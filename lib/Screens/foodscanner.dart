import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../health/nutrition_calculator.dart';
import '../config.dart';

class FoodScannerScreen extends StatefulWidget {
  const FoodScannerScreen({Key? key}) : super(key: key);

  @override
  State<FoodScannerScreen> createState() => _FoodScannerScreenState();
}

class _FoodScannerScreenState extends State<FoodScannerScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _isCameraReady = false;
  bool _cameraPermDenied = false;
  bool _isLoading = false;
  bool _flashOn = false;
  bool _showResult = false;
  String _loadingMessage = '';

  String _detectedFood = '';
  Map<String, dynamic>? _matchedFoodRule;
  String _category = 'unknown';
  String _userDiabetesType = '';
  double? _userHeight;
  double? _userWeight;
  String _userActivityLevel = 'Light';
  PersonalizedNutrition? _personalizedNutrition;
  List<Map<String, dynamic>> _allFoodDocs = [];
  String? _capturedImagePath;

  static const String _geminiApiKey = geminiApiKey;

  // Fallback models in case primary model has quota issues
  static const List<String> _fallbackModels = [
    'gemini-2.0-flash',
    'gemini-2.5-flash',
    'gemini-2.0-flash-lite',
  ];

  // Rate limiting to prevent quota exhaustion
  DateTime? _lastScanTime;
  static const Duration _minScanInterval = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserData();
    _requestCameraAndInit();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _cleanupImage();
    super.dispose();
  }

  void _cleanupImage() {
    if (_capturedImagePath != null) {
      try {
        final f = File(_capturedImagePath!);
        if (f.existsSync()) f.deleteSync();
        debugPrint('🗑️ Cleaned up image: $_capturedImagePath');
      } catch (e) {
        debugPrint('Cleanup error: $e');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _cameraController;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      ctrl.dispose();
      setState(() => _isCameraReady = false);
    } else if (state == AppLifecycleState.resumed) {
      _requestCameraAndInit();
    }
  }

  Future<void> _requestCameraAndInit() async {
    final status = await Permission.camera.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      setState(() => _cameraPermDenied = true);
      return;
    }
    await _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      await _cameraController?.dispose();
      final ctrl = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await ctrl.initialize();
      await ctrl.setFlashMode(FlashMode.off);
      if (!mounted) return;
      setState(() {
        _cameraController = ctrl;
        _isCameraReady = true;
        _cameraPermDenied = false;
      });
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  // ── Load user profile + food rules ───────────────────────────────────
  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('⚠️ No user logged in');
        return;
      }
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
        FirebaseFirestore.instance.collection('food_rules').get(),
      ]);
      final userDoc = results[0] as DocumentSnapshot;
      final foodSnap = results[1] as QuerySnapshot;
      if (!mounted) return;
      final userData = userDoc.data() as Map?;
      setState(() {
        _userDiabetesType = userData?['diabetesType']?.toString() ?? '';
        _userHeight = _num(userData?['height']);
        _userWeight = _num(userData?['weight']);
        _userActivityLevel = userData?['activityLevel']?.toString() ?? 'Light';
        _allFoodDocs =
            foodSnap.docs
                .map((d) => Map<String, dynamic>.from(d.data() as Map))
                .toList();
      });
      debugPrint(
        'Profile → DT:$_userDiabetesType H:$_userHeight W:$_userWeight A:$_userActivityLevel',
      );
      debugPrint('Loaded ${_allFoodDocs.length} food rules');
      if (_allFoodDocs.isEmpty) debugPrint('⚠️ No food rules found!');
    } catch (e) {
      debugPrint('Load user data error: $e');
      if (e.toString().contains('permission-denied'))
        debugPrint('⚠️ Firestore permission denied');
    }
  }

  Future<void> _toggleFlash() async {
    if (_cameraController == null || !_isCameraReady) return;
    try {
      _flashOn = !_flashOn;
      await _cameraController!.setFlashMode(
        _flashOn ? FlashMode.torch : FlashMode.off,
      );
      setState(() {});
    } catch (e) {
      debugPrint('Flash error: $e');
    }
  }

  Future<void> _captureAndScan() async {
    final ctrl = _cameraController;
    if (ctrl == null || !_isCameraReady || _isLoading) return;

    // Rate limiting check
    if (_lastScanTime != null) {
      final timeSinceLastScan = DateTime.now().difference(_lastScanTime!);
      if (timeSinceLastScan < _minScanInterval) {
        final waitSeconds = (_minScanInterval - timeSinceLastScan).inSeconds;
        _showError(
          'Please wait $waitSeconds seconds before scanning again.\n\n'
          'This helps prevent API quota exhaustion.',
        );
        return;
      }
    }

    _lastScanTime = DateTime.now();

    try {
      if (_flashOn) await ctrl.setFlashMode(FlashMode.off);
      final xFile = await ctrl.takePicture();
      if (_flashOn) await ctrl.setFlashMode(FlashMode.torch);
      if (!mounted) return;
      setState(() {
        _isLoading = true;
        _loadingMessage = 'Identifying your food...';
        _showResult = false;
        _detectedFood = '';
        _matchedFoodRule = null;
        _category = 'unknown';
        _personalizedNutrition = null;
        _capturedImagePath = xFile.path;
      });
      debugPrint('📸 Captured: ${xFile.path}');
      final knownFoods =
          _allFoodDocs
              .map((d) => (d['name'] ?? '').toString().trim())
              .where((n) => n.isNotEmpty)
              .toList();
      final foodName = await _identifyWithGemini(xFile.path, knownFoods);
      if (!mounted) return;
      if (foodName == null || foodName.trim().isEmpty) {
        setState(() => _isLoading = false);
        _showError(
          'Could not identify the food.\n\nTips:\n'
          '• Point directly at the food\n'
          '• Make sure food fills the scan frame\n'
          '• Use better lighting or turn on flash\n'
          '• Hold the phone steady',
        );
        return;
      }
      debugPrint('Identified: "$foodName"');
      if (_allFoodDocs.isEmpty) {
        debugPrint('⚠️ Cannot match: Food database is empty or still loading.');
        _showError(
          'Scanning works, but your food database is still loading.\n\n'
          'Please wait a few seconds and try again.',
        );
        return;
      }
      setState(() {
        _detectedFood = foodName.trim();
        _loadingMessage = 'Matching with database...';
      });
      _matchFoodLocally(_detectedFood);
      await _saveHistory();
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _showResult = true;
      });
    } catch (e) {
      debugPrint('Capture error: $e');
      _showError('Something went wrong: $e');
      // The image cleanup is now handled in dispose() or when Scan Again is tapped
      // to ensure the user can see the image in the results panel.
    }
  }

  // ── Gemini Vision API ─────────────────────────────────────────────────
  Future<String?> _identifyWithGemini(
    String imagePath,
    List<String> knownFoods,
  ) async {
    // Try each model in the fallback list
    for (int i = 0; i < _fallbackModels.length; i++) {
      final modelToTry = _fallbackModels[i];
      debugPrint(
        '🔄 Trying model: $modelToTry (attempt ${i + 1}/${_fallbackModels.length})',
      );

      final result = await _tryGeminiModel(imagePath, knownFoods, modelToTry);

      if (result != null) {
        debugPrint('✅ Success with model: $modelToTry');
        return result;
      }

      // If not the last model, continue to next
      if (i < _fallbackModels.length - 1) {
        debugPrint('⚠️ Model $modelToTry failed, trying next...');
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    // All models failed
    debugPrint('❌ All models failed');
    return null;
  }

  Future<String?> _tryGeminiModel(
    String imagePath,
    List<String> knownFoods,
    String modelName,
  ) async {
    try {
      // Compress image to reduce size and improve upload speed
      var bytes = await File(imagePath).readAsBytes();

      // If image is too large (>1MB), it might cause connection issues
      if (bytes.length > 1024 * 1024) {
        debugPrint(
          'Image too large (${(bytes.length / 1024).toStringAsFixed(0)}KB), compressing...',
        );
        // Simple resize by re-encoding with lower quality would go here
        // For now, just warn if it's large
      }

      final b64 = base64Encode(bytes);

      final prompt =
          'Identify the food in this image.\n'
          'Reply with ONLY this JSON — no extra text, no markdown:\n'
          '{"food":"food name here","confidence":"high"}\n'
          'Rules:\n'
          '- food name must be lowercase\n'
          '- be specific (e.g. "white rice", "ampalaya", "fried chicken")\n'
          '- if no food is visible reply: {"food":"","confidence":"none"}\n'
          '- if the food matches something in the database, use that EXACT name'
          '${knownFoods.isNotEmpty ? '\n\nFOOD DATABASE (Use these exact names if they match):\n${knownFoods.take(50).join(', ')}' : ''}';

      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/'
        '$modelName:generateContent?key=$_geminiApiKey',
      );

      debugPrint('🔍 Calling Gemini API...');
      debugPrint('Model: $modelName');
      debugPrint(
        'URL: ${url.toString().replaceAll(_geminiApiKey, 'API_KEY_HIDDEN')}',
      );

      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {
                      'inline_data': {'mime_type': 'image/jpeg', 'data': b64},
                    },
                    {'text': prompt},
                  ],
                },
              ],
              'generationConfig': {
                'maxOutputTokens': 200,
                'temperature': 0.1,
                'topP': 0.95,
              },
            }),
          )
          .timeout(
            const Duration(seconds: 45),
            onTimeout:
                () =>
                    throw Exception('Request timed out. Check your internet.'),
          );

      debugPrint('Gemini status: ${response.statusCode}');
      debugPrint('Response body: ${response.body}');

      if (response.statusCode != 200) {
        try {
          final err = jsonDecode(response.body);
          final msg = err['error']?['message']?.toString() ?? '';
          debugPrint('Error message: $msg');

          // For quota errors, return null to try next model
          if (msg.contains('quota')) {
            debugPrint(
              '⚠️ Quota exhausted for $modelName, will try fallback...',
            );
            return null;
          }

          // For other errors, show message and return null
          String userMsg = 'AI Service Error (${response.statusCode})';
          if (msg.contains('API key not valid') ||
              msg.contains('API key expired')) {
            userMsg =
                'API Key Expired or Invalid!\n\nPlease get a new API key from:\nhttps://aistudio.google.com/apikey\n\nThen update lib/config.dart';
            _showError(userMsg);
          } else if (msg.contains('not found')) {
            debugPrint('Model $modelName not found, trying next...');
            return null; // Try next model
          } else if (msg.contains('leaked')) {
            userMsg =
                'API Key Compromised!\n\nYour API key was reported as leaked.\nPlease get a new one from:\nhttps://aistudio.google.com/apikey';
            _showError(userMsg);
          } else if (msg.isNotEmpty) {
            userMsg = 'AI error: $msg';
            _showError(userMsg);
          }
        } catch (e) {
          debugPrint('Error parsing response: $e');
        }
        return null;
      }

      Map<String, dynamic> decoded;
      try {
        decoded = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('JSON parse error: $e');
        _showError('AI returned an unexpected response format.');
        return null;
      }

      final text = _geminiText(decoded);
      debugPrint('Gemini text: "$text"');
      if (text == null || text.trim().isEmpty) return null;
      return _parseFoodName(text);
    } catch (e) {
      debugPrint('Gemini error: $e');
      if (e.toString().contains('timed out'))
        _showError('Request timed out.\nCheck your internet connection.');
      else if (e.toString().contains('SocketException'))
        _showError('No internet connection.');
      else
        _showError('AI error: $e');
      return null;
    }
  }

  String? _geminiText(Map<String, dynamic> d) {
    try {
      return (d['candidates'] as List?)?[0]?['content']?['parts']?[0]?['text']
          ?.toString();
    } catch (_) {
      return null;
    }
  }

  String? _parseFoodName(String raw) {
    final text = raw.trim();
    try {
      final cleaned =
          text
              .replaceAll(RegExp(r'```json', caseSensitive: false), '')
              .replaceAll('```', '')
              .trim();
      final m = RegExp(r'\{.+?\}', dotAll: true).firstMatch(cleaned);
      if (m != null) {
        final obj = jsonDecode(m.group(0)!) as Map<String, dynamic>;
        final food = (obj['food'] as String?)?.trim().toLowerCase() ?? '';
        if (food.isNotEmpty) return food;
        if (obj.containsKey('food')) return null;
      }
    } catch (_) {}
    final lower = text.toLowerCase();
    for (final p in [
      'no food',
      'not food',
      'cannot identify',
      'unable to identify',
      'no visible food',
      'no food item',
    ]) {
      if (lower.contains(p)) return null;
    }
    for (final r in [
      RegExp(r'"food"\s*:\s*"([^"]{2,40})"'),
      RegExp(
        r'(?:is|shows?|identified as|appears? to be)\s+(?:a |an |the )?([a-z][a-z\s\-]{1,35})',
        caseSensitive: false,
      ),
    ]) {
      final m = r.firstMatch(lower);
      if (m != null) {
        final f = m.group(1)?.trim().toLowerCase() ?? '';
        if (f.length > 2) return f;
      }
    }
    if (lower.length <= 40 && !lower.contains('{') && !lower.contains('\n')) {
      final c = lower.replaceAll(RegExp(r'[^a-z\s\-]'), '').trim();
      if (c.length > 2) return c;
    }
    return null;
  }

  // ── Fuzzy match + personalized nutrition ─────────────────────────────
  void _matchFoodLocally(String foodName) {
    final lower = foodName.toLowerCase().trim();
    final variants = _buildVariants(lower);
    Map<String, dynamic>? best;
    int bestScore = 0;

    for (final doc in _allFoodDocs) {
      final name = (doc['name'] ?? '').toString().toLowerCase().trim();
      final nameLow =
          (doc['nameLower'] ?? name).toString().toLowerCase().trim();

      // BACKWARD COMPATIBLE: Check both old and new structure
      String type = '';
      final suitableFor = (doc['suitableFor'] as List?)?.cast<String>() ?? [];
      if (suitableFor.isNotEmpty) {
        // NEW STRUCTURE: check if user's diabetes type is in suitableFor array
        type = suitableFor.contains(_userDiabetesType) ? _userDiabetesType : '';
      } else {
        // OLD STRUCTURE: use diabetesType field
        type = (doc['diabetesType'] ?? '').toString();
      }

      final kws =
          (doc['searchKeywords'] as List? ?? [])
              .map((e) => e.toString().toLowerCase())
              .toList();
      int score = _computeScore(variants, name, nameLow, kws);
      if (score == 0) continue;
      if (_userDiabetesType.isNotEmpty && type == _userDiabetesType)
        score += 30;
      if (score > bestScore) {
        bestScore = score;
        best = doc;
      }
    }

    debugPrint('Best match: "${best?['name']}" score=$bestScore');

    PersonalizedNutrition? pn;
    String category = 'unknown';

    if (best != null && bestScore >= 15) {
      // AUTO-DETERMINE category based on carbs and user's diabetes type
      final carbs = _num(best['carbs']);
      category = FoodCategoryHelper.determineCategory(carbs, _userDiabetesType);

      debugPrint(
        'Auto-determined category: $category (carbs: ${carbs}g, type: $_userDiabetesType)',
      );

      pn = NutritionCalculator.calculate(
        heightCm: _userHeight,
        weightKg: _userWeight,
        activityLevel: _userActivityLevel,
        diabetesType: _userDiabetesType,
        calories100g: _num(best['calories']),
        carbs100g: carbs,
        protein100g: _num(best['protein']),
        fat100g: _num(best['fat']),
      );
    }

    setState(() {
      _matchedFoodRule = best != null && bestScore >= 15 ? best : null;
      _category = category;
      _personalizedNutrition = pn;
    });
  }

  int _computeScore(
    List<String> vs,
    String name,
    String nameLow,
    List<String> kws,
  ) {
    int best = 0;
    for (final v in vs) {
      if (v.isEmpty) continue;
      if (name == v || nameLow == v) return 100;
      if (name.contains(v) || nameLow.contains(v))
        best = _mx(best, 70);
      else if (v.contains(name) || v.contains(nameLow))
        best = _mx(best, 65);
      for (final kw in kws) {
        if (kw == v || kw.contains(v) || v.contains(kw)) {
          best = _mx(best, 60);
          break;
        }
      }
      final vW = v.split(' ').where((w) => w.length > 2).toSet();
      final dW = name.split(' ').where((w) => w.length > 2).toSet();
      final c = vW.intersection(dW).length;
      if (c > 0) best = _mx(best, c * 22);
    }
    return best;
  }

  int _mx(int a, int b) => a > b ? a : b;

  List<String> _buildVariants(String food) {
    final s = <String>{food};
    s.addAll(food.split(' ').where((w) => w.length > 2));
    const map = <String, List<String>>{
      'mung beans': ['monggo', 'mungo', 'munggo', 'mung bean'],
      'monggo': ['mung beans', 'mungo', 'munggo', 'mung bean'],
      'mungo': ['mung beans', 'monggo', 'munggo'],
      'munggo': ['mung beans', 'monggo', 'mungo'],
      'ampalaya': ['bitter gourd', 'bitter melon', 'amargoso'],
      'bitter gourd': ['ampalaya', 'bitter melon'],
      'bitter melon': ['ampalaya', 'bitter gourd'],
      'sitaw': ['string beans', 'long beans', 'yard long beans'],
      'string beans': ['sitaw', 'long beans'],
      'talong': ['eggplant', 'aubergine'],
      'eggplant': ['talong'],
      'kangkong': ['water spinach', 'swamp cabbage'],
      'water spinach': ['kangkong'],
      'kalabasa': ['squash', 'pumpkin'],
      'squash': ['kalabasa', 'pumpkin'],
      'camote': ['sweet potato', 'kamote', 'yam'],
      'kamote': ['sweet potato', 'camote', 'yam'],
      'sweet potato': ['camote', 'kamote'],
      'gabi': ['taro', 'taro root'],
      'taro': ['gabi'],
      'pechay': ['bok choy', 'pak choi', 'chinese cabbage'],
      'bok choy': ['pechay', 'pak choi'],
      'malunggay': ['moringa', 'drumstick leaves'],
      'moringa': ['malunggay'],
      'okra': ['lady finger', 'ladies finger'],
      'pipino': ['cucumber'],
      'cucumber': ['pipino'],
      'kamatis': ['tomato'],
      'tomato': ['kamatis'],
      'repolyo': ['cabbage'],
      'cabbage': ['repolyo'],
      'saging': ['banana', 'plantain'],
      'banana': ['saging'],
      'mangga': ['mango'],
      'mango': ['mangga'],
      'langka': ['jackfruit'],
      'jackfruit': ['langka'],
      'pinya': ['pineapple'],
      'pineapple': ['pinya'],
      'pakwan': ['watermelon'],
      'watermelon': ['pakwan'],
      'avocado': ['abukado'],
      'abukado': ['avocado'],
      // Apple variants (different colors have different carb content)
      'apple': ['red apple', 'green apple'],
      'red apple': ['apple', 'fuji apple', 'gala apple'],
      'green apple': ['apple', 'granny smith', 'granny smith apple'],
      'kanin': ['white rice', 'rice', 'plain rice'],
      'white rice': ['rice', 'kanin', 'plain rice', 'steamed rice'],
      'rice': ['white rice', 'kanin', 'plain rice'],
      'brown rice': ['rice', 'whole grain rice'],
      'sinangag': ['garlic rice', 'fried rice'],
      'garlic rice': ['sinangag', 'fried rice'],
      'lugaw': ['congee', 'rice porridge', 'porridge'],
      'congee': ['lugaw', 'porridge'],
      'oats': ['oatmeal', 'rolled oats'],
      'oatmeal': ['oats', 'rolled oats'],
      'manok': ['chicken', 'fried chicken', 'grilled chicken'],
      'chicken': ['manok', 'fried chicken', 'grilled chicken'],
      'fried chicken': ['chicken', 'manok'],
      'baboy': ['pork', 'lechon', 'liempo'],
      'pork': ['baboy', 'liempo', 'lechon'],
      'liempo': ['pork belly', 'pork', 'baboy'],
      'lechon': ['roast pork', 'pork', 'baboy'],
      'baka': ['beef'],
      'beef': ['baka'],
      'isda': ['fish', 'tilapia', 'bangus'],
      'fish': ['isda', 'tilapia', 'bangus', 'galunggong'],
      'bangus': ['milkfish', 'fish', 'isda'],
      'milkfish': ['bangus', 'fish'],
      'tilapia': ['fish', 'isda'],
      'galunggong': ['fish', 'isda', 'mackerel scad'],
      'sardinas': ['sardines', 'canned fish'],
      'sardines': ['sardinas'],
      'hipon': ['shrimp', 'prawns'],
      'shrimp': ['hipon', 'prawns'],
      'pusit': ['squid'],
      'squid': ['pusit'],
      'itlog': ['egg', 'eggs', 'boiled egg', 'fried egg'],
      'egg': ['itlog', 'eggs', 'boiled egg'],
      'eggs': ['itlog', 'egg'],
      'tokwa': ['tofu', 'bean curd'],
      'tofu': ['tokwa', 'bean curd'],
      'adobo': ['chicken adobo', 'pork adobo', 'adobong manok'],
      'sinigang': ['pork sinigang', 'sinigang na baboy'],
      'tinola': ['chicken tinola', 'tinolang manok'],
      'pinakbet': ['pakbet', 'mixed vegetables'],
      'pakbet': ['pinakbet'],
      'pancit': ['noodles', 'bihon', 'canton'],
      'noodles': ['pancit', 'bihon', 'canton'],
      'pandesal': ['bread', 'pan de sal'],
      'bread': ['pandesal', 'tinapay'],
      'mais': ['corn'],
      'corn': ['mais'],
    };
    if (map.containsKey(food)) s.addAll(map[food]!);
    for (final e in map.entries) {
      if (food != e.key && (food.contains(e.key) || e.key.contains(food))) {
        s.addAll(e.value);
        s.add(e.key);
      }
    }
    return s.toList();
  }

  Future<void> _saveHistory() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('scanned_foods')
          .add({
            'food': _detectedFood,
            'category': _category,
            'ruleData': _matchedFoodRule,
            'timestamp': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      debugPrint('Save error: $e');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    setState(() => _isLoading = false);
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange),
                SizedBox(width: 8),
                Text('Scan Failed'),
              ],
            ),
            content: Text(msg),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2C6E49),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
    );
  }

  String _cap(String t) => t
      .split(' ')
      .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
      .join(' ');

  double _num(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;

  // ════════════════════════════════════════════════════════════════════════
  // UI
  // ════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_cameraPermDenied)
            _buildPermissionDenied()
          else if (_isCameraReady && _cameraController != null)
            Positioned.fill(child: CameraPreview(_cameraController!))
          else
            const Positioned.fill(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF4CAF50)),
                    SizedBox(height: 16),
                    Text(
                      'Starting camera...',
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),

          if (_isCameraReady && !_cameraPermDenied) _buildScanFrame(),

          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    _topBtn(Icons.arrow_back, () => Navigator.pop(context)),
                    const SizedBox(width: 12),
                    const Text(
                      'Food Scan',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (_userDiabetesType.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$_userDiabetesType Diabetes',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    _topBtn(
                      _flashOn ? Icons.flash_on : Icons.flash_off,
                      _toggleFlash,
                      active: _flashOn,
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 48),
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF4CAF50),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(
                          color: Color(0xFF4CAF50),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _loadingMessage,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          if (_showResult && !_isLoading)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildResultPanel(),
            ),

          if (!_showResult && !_isLoading && _isCameraReady)
            Positioned(
              bottom: 48,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Point at food and tap Scan',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: _captureAndScan,
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF2C6E49),
                        border: Border.all(color: Colors.white, width: 3.5),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF2C6E49).withOpacity(0.6),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.center_focus_strong,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _topBtn(
    IconData icon,
    VoidCallback onTap, {
    bool active = false,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: active ? Colors.yellow.withOpacity(0.25) : Colors.black45,
        borderRadius: BorderRadius.circular(10),
        border: active ? Border.all(color: Colors.yellow, width: 1.5) : null,
      ),
      child: Icon(icon, color: active ? Colors.yellow : Colors.white, size: 22),
    ),
  );

  Widget _buildPermissionDenied() => Positioned.fill(
    child: Container(
      color: const Color(0xFF1A1A1A),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.camera_alt, color: Colors.white30, size: 72),
              const SizedBox(height: 20),
              const Text(
                'Camera Permission Required',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Food scanner needs camera access to identify your meals.',
                style: TextStyle(color: Colors.white60, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => openAppSettings(),
                icon: const Icon(Icons.settings, color: Colors.white),
                label: const Text(
                  'Open Settings',
                  style: TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2C6E49),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _buildScanFrame() {
    final size = MediaQuery.of(context).size;
    final frameSize = size.width * 0.65;
    final frameTop = size.height * 0.25;
    final frameLeft = (size.width - frameSize) / 2;
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: frameTop,
          child: Container(color: Colors.black54),
        ),
        Positioned(
          top: frameTop,
          left: 0,
          width: frameLeft,
          height: frameSize,
          child: Container(color: Colors.black54),
        ),
        Positioned(
          top: frameTop,
          right: 0,
          width: frameLeft,
          height: frameSize,
          child: Container(color: Colors.black54),
        ),
        Positioned(
          top: frameTop + frameSize,
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(color: Colors.black54),
        ),
        Positioned(top: frameTop, left: frameLeft, child: _corner(true, true)),
        Positioned(
          top: frameTop,
          right: frameLeft,
          child: _corner(true, false),
        ),
        Positioned(
          top: frameTop + frameSize - 32,
          left: frameLeft,
          child: _corner(false, true),
        ),
        Positioned(
          top: frameTop + frameSize - 32,
          right: frameLeft,
          child: _corner(false, false),
        ),
        if (!_isLoading && !_showResult)
          _ScanLine(
            frameTop: frameTop,
            frameSize: frameSize,
            frameLeft: frameLeft,
          ),
      ],
    );
  }

  Widget _corner(bool top, bool left) => SizedBox(
    width: 32,
    height: 32,
    child: CustomPaint(
      painter: _CornerPainter(
        color: const Color(0xFF4CAF50),
        strokeWidth: 4,
        top: top,
        left: left,
      ),
    ),
  );

  Widget _buildResultPanel() {
    Color catColor;
    IconData catIcon;
    String catLabel;
    switch (_category) {
      case 'do':
        catColor = Colors.green;
        catIcon = Icons.check_circle;
        catLabel = 'Safe to Eat';
        break;
      case 'dont':
        catColor = Colors.red;
        catIcon = Icons.cancel;
        catLabel = 'Avoid This Food';
        break;
      default:
        // Remove "Not in Database" badge - just don't show category badge
        catColor = Colors.grey;
        catIcon = Icons.restaurant;
        catLabel = ''; // Empty label - won't display
    }
    final rule = _matchedFoodRule;
    final pn = _personalizedNutrition;
    final isPers = pn?.isPersonalized == true;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: catColor.withOpacity(0.5), width: 1.5),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 14),

          if (_capturedImagePath != null)
            Center(
              child: Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: catColor.withOpacity(0.3),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.file(
                    File(_capturedImagePath!),
                    width: 140,
                    height: 140,
                    fit: BoxFit.cover,
                    errorBuilder:
                        (_, __, ___) => Container(
                          width: 140,
                          height: 140,
                          color: Colors.grey[800],
                          child: const Icon(
                            Icons.broken_image,
                            color: Colors.white54,
                            size: 40,
                          ),
                        ),
                  ),
                ),
              ),
            ),

          Row(
            children: [
              Expanded(
                child: Text(
                  _cap(_detectedFood),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Only show category badge if label is not empty
              if (catLabel.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: catColor.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: catColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(catIcon, color: catColor, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        catLabel,
                        style: TextStyle(
                          color: catColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          if (rule != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF2C6E49).withOpacity(0.18),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFF4CAF50).withOpacity(0.6),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2C6E49).withOpacity(0.35),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isPers ? Icons.auto_awesome_rounded : Icons.scale_rounded,
                      color: const Color(0xFF4CAF50),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isPers
                              ? 'YOUR PERSONALIZED PORTION'
                              : 'RECOMMENDED PORTION',
                          style: const TextStyle(
                            color: Color(0xFF4CAF50),
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isPers
                              ? _gramsToHumanPortion(pn!.grams, _detectedFood)
                              : '—',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                        ),
                        if (isPers) ...[
                          const SizedBox(height: 3),
                          Text(
                            '≈ ${pn!.grams.toInt()}g · Calculated for your profile',
                            style: const TextStyle(
                              color: Color(0xFF4CAF50),
                              fontSize: 9,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if ((rule['diabetesType'] ?? '').toString().isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2C6E49).withOpacity(0.3),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF4CAF50).withOpacity(0.4),
                        ),
                      ),
                      child: Text(
                        '${rule['diabetesType']}\nDiabetes',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF4CAF50),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        isPers
                            ? 'NUTRITION FOR YOUR PORTION'
                            : 'NUTRITION INFO (per 100g)',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 9,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const Spacer(),
                      if (isPers)
                        const Text(
                          '✨ personalized',
                          style: TextStyle(
                            color: Color(0xFF4CAF50),
                            fontSize: 9,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if ((isPers ? pn!.calories : _num(rule['calories'])) > 0)
                        _chip(
                          'Cal',
                          '${(isPers ? pn!.calories : _num(rule['calories'])).toStringAsFixed(0)} kcal',
                          Colors.orange,
                        ),
                      if ((isPers ? pn!.carbs : _num(rule['carbs'])) > 0)
                        _chip(
                          'Carbs',
                          '${(isPers ? pn!.carbs : _num(rule['carbs'])).toStringAsFixed(1)}g',
                          Colors.blue,
                        ),
                      if ((isPers ? pn!.protein : _num(rule['protein'])) > 0)
                        _chip(
                          'Protein',
                          '${(isPers ? pn!.protein : _num(rule['protein'])).toStringAsFixed(1)}g',
                          Colors.purple,
                        ),
                      if ((isPers ? pn!.fat : _num(rule['fat'])) > 0)
                        _chip(
                          'Fat',
                          '${(isPers ? pn!.fat : _num(rule['fat'])).toStringAsFixed(1)}g',
                          Colors.redAccent,
                        ),
                    ],
                  ),
                  if (isPers) ...[
                    const SizedBox(height: 8),
                    const Divider(height: 1, color: Colors.white12),
                    const SizedBox(height: 6),
                    Text(
                      'Per 100g: ${_num(rule['calories']).toStringAsFixed(0)} kcal  '
                      '${_num(rule['carbs']).toStringAsFixed(1)}g carbs  '
                      '${_num(rule['protein']).toStringAsFixed(1)}g protein  '
                      '${_num(rule['fat']).toStringAsFixed(1)}g fat',
                      style: const TextStyle(
                        color: Colors.white24,
                        fontSize: 9,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: Colors.orange,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '"${_cap(_detectedFood)}" is not in your database yet.\nAsk your admin to add it.',
                      style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            decoration: BoxDecoration(
              color: catColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: catColor.withOpacity(0.4)),
            ),
            child: Text(
              _category == 'do'
                  ? 'Recommended for diabetics${_userDiabetesType.isNotEmpty ? ' with $_userDiabetesType diabetes' : ''}.'
                  : _category == 'dont'
                  ? 'Should be avoided${_userDiabetesType.isNotEmpty ? ' for $_userDiabetesType diabetes' : ' by diabetics'}.'
                  : 'Not found in database. Consult your doctor.',
              style: TextStyle(
                color: catColor,
                fontWeight: FontWeight.bold,
                fontSize: 13,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2C6E49),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(
                Icons.center_focus_strong,
                color: Colors.white,
                size: 20,
              ),
              label: const Text(
                'Scan Again',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              onPressed: () {
                _cleanupImage();
                setState(() {
                  _showResult = false;
                  _detectedFood = '';
                  _matchedFoodRule = null;
                  _category = 'unknown';
                  _capturedImagePath = null;
                  _personalizedNutrition = null;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  String _gramsToHumanPortion(double grams, String foodName) {
    final lower = foodName.toLowerCase();
    final g = grams.round();

    String fraction(double count) {
      final whole = count.floor();
      final rem = count - whole;
      if (whole == 0 && rem >= 0.35) return '½';
      if (rem >= 0.65) return '${whole + 1}';
      if (rem >= 0.35) return '$whole½';
      return '${whole < 1 ? 1 : whole}';
    }

    String natural(double unitGrams, String noun, String size) {
      final count = grams / unitGrams;
      final frac = fraction(count);
      final plural = (count >= 1.75) ? 's' : '';
      return '$frac $size $noun$plural (≈${g}g)';
    }

    String sliced(double sliceG, String noun, String thickness) {
      final count = grams / sliceG;
      final frac = fraction(count);
      final plural = (count >= 1.75) ? 's' : '';
      return '$frac $thickness slice$plural $noun (≈${g}g)';
    }

    if (lower.contains('apple'))
      return natural(
        120,
        'apple',
        grams < 80
            ? 'small'
            : grams < 160
            ? 'medium'
            : 'large',
      );
    if (lower.contains('banana') || lower.contains('saging'))
      return natural(
        90,
        'banana',
        grams < 70
            ? 'small'
            : grams < 120
            ? 'medium'
            : 'large',
      );
    if (lower.contains('mango') || lower.contains('mangga'))
      return natural(
        200,
        'mango',
        grams < 150
            ? 'small'
            : grams < 280
            ? 'medium'
            : 'large',
      );
    if (lower.contains('watermelon') || lower.contains('pakwan'))
      return sliced(150, 'watermelon', grams < 100 ? 'thin' : 'thick');
    if (lower.contains('pineapple') || lower.contains('pinya'))
      return sliced(80, 'pineapple', grams < 60 ? 'thin' : 'medium');
    if (lower.contains('papaya'))
      return sliced(120, 'papaya', grams < 80 ? 'thin' : 'medium');
    if (lower.contains('avocado') || lower.contains('abukado'))
      return natural(150, 'avocado', grams < 100 ? 'small' : 'medium');
    if (lower.contains('jackfruit') || lower.contains('langka'))
      return natural(60, 'piece', grams < 60 ? 'small' : 'medium');
    if (lower.contains('corn') || lower.contains('mais'))
      return natural(150, 'ear of corn', grams < 100 ? 'small' : 'medium');
    if (lower.contains('grapes') || lower.contains('ubas'))
      return natural(5, 'grape', 'small');
    if (lower.contains('ampalaya') || lower.contains('bitter'))
      return natural(
        60,
        'piece',
        grams < 50
            ? 'small'
            : grams < 100
            ? 'medium'
            : 'large',
      );
    if (lower.contains('talong') || lower.contains('eggplant'))
      return natural(
        80,
        'piece',
        grams < 60
            ? 'small'
            : grams < 120
            ? 'medium'
            : 'large',
      );
    if (lower.contains('kalabasa') || lower.contains('squash'))
      return sliced(80, 'squash', grams < 60 ? 'thin' : 'thick');
    if (lower.contains('cucumber') || lower.contains('pipino'))
      return natural(100, 'cucumber', grams < 80 ? 'small' : 'medium');
    if (lower.contains('tomato') || lower.contains('kamatis'))
      return natural(
        80,
        'tomato',
        grams < 60
            ? 'small'
            : grams < 120
            ? 'medium'
            : 'large',
      );
    if (lower.contains('okra')) return natural(15, 'piece okra', 'small');
    if (lower.contains('sitaw') || lower.contains('string bean'))
      return natural(20, 'stalk', 'long');
    if (lower.contains('kangkong') ||
        lower.contains('pechay') ||
        lower.contains('cabbage') ||
        lower.contains('repolyo') ||
        lower.contains('malunggay'))
      return natural(50, 'handful', grams < 50 ? 'small' : 'medium');
    if (lower.contains('camote') ||
        lower.contains('kamote') ||
        lower.contains('sweet potato'))
      return natural(
        130,
        'camote',
        grams < 100
            ? 'small'
            : grams < 180
            ? 'medium'
            : 'large',
      );
    if (lower.contains('gabi') || lower.contains('taro'))
      return natural(80, 'piece', grams < 60 ? 'small' : 'medium');
    if (lower.contains('potato'))
      return natural(
        150,
        'potato',
        grams < 100
            ? 'small'
            : grams < 200
            ? 'medium'
            : 'large',
      );
    if (lower.contains('bangus') || lower.contains('milkfish'))
      return sliced(120, 'bangus', grams < 80 ? 'thin' : 'medium');
    if (lower.contains('tilapia'))
      return natural(200, 'tilapia', grams < 150 ? 'small' : 'medium');
    if (lower.contains('galunggong') || lower.contains('mackerel'))
      return natural(80, 'galunggong', grams < 60 ? 'small' : 'medium');
    if (lower.contains('sardine') || lower.contains('sardinas'))
      return natural(30, 'sardine', 'small');
    if (lower.contains('shrimp') ||
        lower.contains('hipon') ||
        lower.contains('prawn'))
      return natural(15, 'piece shrimp', 'medium');
    if (lower.contains('squid') || lower.contains('pusit'))
      return natural(80, 'piece squid', grams < 60 ? 'small' : 'medium');
    if (lower.contains('fish') || lower.contains('isda'))
      return sliced(100, 'fish', grams < 80 ? 'thin' : 'medium');
    if (lower.contains('egg') || lower.contains('itlog'))
      return natural(
        55,
        'egg',
        grams < 45
            ? 'small'
            : grams < 65
            ? 'medium'
            : 'large',
      );
    if (lower.contains('fried chicken') || lower.contains('grilled chicken'))
      return natural(130, 'piece chicken', grams < 100 ? 'small' : 'medium');
    if (lower.contains('chicken') || lower.contains('manok'))
      return sliced(90, 'chicken', grams < 70 ? 'thin' : 'medium');
    if (lower.contains('liempo') || lower.contains('pork belly'))
      return sliced(80, 'liempo', grams < 60 ? 'thin' : 'thick');
    if (lower.contains('lechon'))
      return sliced(90, 'lechon', grams < 70 ? 'thin' : 'medium');
    if (lower.contains('pork') || lower.contains('baboy'))
      return sliced(90, 'pork', grams < 70 ? 'thin' : 'medium');
    if (lower.contains('beef') || lower.contains('baka'))
      return sliced(90, 'beef', grams < 70 ? 'thin' : 'medium');
    if (lower.contains('tofu') || lower.contains('tokwa'))
      return sliced(80, 'tofu', grams < 60 ? 'thin' : 'medium');
    if (lower.contains('monggo') || lower.contains('mung'))
      return natural(200, 'bowl', grams < 150 ? 'small' : 'medium');
    if (lower.contains('pandesal'))
      return natural(
        40,
        'pandesal',
        grams < 35
            ? 'small'
            : grams < 55
            ? 'medium'
            : 'large',
      );
    if (lower.contains('bread') || lower.contains('toast'))
      return natural(30, 'slice bread', grams < 30 ? 'thin' : 'regular');
    if (lower.contains('bibingka') ||
        lower.contains('puto') ||
        lower.contains('kutsinta') ||
        lower.contains('kakanin'))
      return natural(60, 'piece', grams < 50 ? 'small' : 'medium');
    if (lower.contains('cake') ||
        lower.contains('pie') ||
        lower.contains('pizza') ||
        lower.contains('lasagna'))
      return sliced(
        90,
        lower.contains('pizza') ? 'pizza' : 'cake',
        grams < 70 ? 'thin' : 'medium',
      );
    if (lower.contains('rice') ||
        lower.contains('kanin') ||
        lower.contains('sinangag') ||
        lower.contains('garlic rice'))
      return natural(
        120,
        'scoop of rice',
        grams < 100
            ? 'small'
            : grams < 180
            ? 'medium'
            : 'large',
      );
    if (lower.contains('lugaw') || lower.contains('congee'))
      return natural(200, 'bowl of lugaw', grams < 150 ? 'small' : 'medium');
    if (lower.contains('oat') || lower.contains('cereal'))
      return natural(80, 'bowl of oats', grams < 70 ? 'small' : 'medium');
    if (lower.contains('pancit') ||
        lower.contains('noodle') ||
        lower.contains('bihon') ||
        lower.contains('canton'))
      return natural(
        150,
        'serving of pancit',
        grams < 120 ? 'small' : 'medium',
      );
    if (lower.contains('adobo'))
      return natural(100, 'piece adobo', grams < 80 ? 'small' : 'medium');
    if (lower.contains('sinigang') || lower.contains('tinola'))
      return natural(200, 'bowl', grams < 160 ? 'small' : 'medium');
    if (lower.contains('pinakbet') || lower.contains('pakbet'))
      return natural(100, 'scoop', grams < 80 ? 'small' : 'medium');
    if (lower.contains('menudo') || lower.contains('mechado'))
      return natural(100, 'scoop', grams < 80 ? 'small' : 'medium');

    final size =
        grams < 80
            ? 'small'
            : grams < 160
            ? 'medium'
            : 'large';
    return natural(100, 'piece', size);
  }

  Widget _chip(String label, String value, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Text(
      '$label: $value',
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
    ),
  );
}

// ── Animated scan line ────────────────────────────────────────────────────
class _ScanLine extends StatefulWidget {
  final double frameTop;
  final double frameSize;
  final double frameLeft;
  const _ScanLine({
    required this.frameTop,
    required this.frameSize,
    required this.frameLeft,
  });
  @override
  State<_ScanLine> createState() => _ScanLineState();
}

class _ScanLineState extends State<_ScanLine>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _anim = Tween(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final y = widget.frameTop + _anim.value * widget.frameSize;
        return Positioned(
          top: y,
          left: widget.frameLeft + 4,
          right:
              MediaQuery.of(context).size.width -
              widget.frameLeft -
              widget.frameSize +
              4,
          child: Container(
            height: 2.5,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  const Color(0xFF4CAF50).withOpacity(0.8),
                  const Color(0xFF4CAF50),
                  const Color(0xFF4CAF50).withOpacity(0.8),
                  Colors.transparent,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4CAF50).withOpacity(0.6),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Corner bracket painter ────────────────────────────────────────────────
class _CornerPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final bool top;
  final bool left;
  const _CornerPainter({
    required this.color,
    required this.strokeWidth,
    required this.top,
    required this.left,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = strokeWidth
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
    final path = Path();
    final w = size.width;
    final h = size.height;
    if (top && left) {
      path.moveTo(0, h);
      path.lineTo(0, 0);
      path.lineTo(w, 0);
    } else if (top && !left) {
      path.moveTo(0, 0);
      path.lineTo(w, 0);
      path.lineTo(w, h);
    } else if (!top && left) {
      path.moveTo(0, 0);
      path.lineTo(0, h);
      path.lineTo(w, h);
    } else {
      path.moveTo(0, h);
      path.lineTo(w, h);
      path.lineTo(w, 0);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CornerPainter o) =>
      o.color != color || o.strokeWidth != strokeWidth;
}
