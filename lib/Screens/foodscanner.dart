import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

class FoodScannerScreen extends StatefulWidget {
  const FoodScannerScreen({Key? key}) : super(key: key);

  @override
  State<FoodScannerScreen> createState() => _FoodScannerScreenState();
}

class _FoodScannerScreenState extends State<FoodScannerScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _isCameraReady     = false;
  bool _cameraPermDenied  = false;
  bool _isLoading         = false;
  bool _flashOn           = false;
  bool _showResult        = false;
  String _loadingMessage  = '';

  String _detectedFood    = '';
  Map<String, dynamic>? _matchedFoodRule;
  String _category        = 'unknown';
  String _userDiabetesType = '';
  List<Map<String, dynamic>> _allFoodDocs = [];

  static const String _geminiApiKey = 'AIzaSyBsEWZ-oIgSbEnHp-uCxWJZL3k7yO59Cws';
  static const String _geminiModel  = 'gemini-1.5-flash';

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
    super.dispose();
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

  // ── Request camera permission then init ───────────────────────────────
  Future<void> _requestCameraAndInit() async {
    final status = await Permission.camera.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      setState(() => _cameraPermDenied = true);
      return;
    }
    await _initCamera();
  }

  // ── Init live camera ──────────────────────────────────────────────────
  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      // Dispose any old controller first
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
        _isCameraReady    = true;
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
      if (user == null) return;

      final results = await Future.wait([
        FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
        FirebaseFirestore.instance.collection('food_rules').get(),
      ]);

      final userDoc  = results[0] as DocumentSnapshot;
      final foodSnap = results[1] as QuerySnapshot;

      if (!mounted) return;
      setState(() {
        _userDiabetesType = (userDoc.data() as Map?)?['diabetesType']?.toString() ?? '';
        _allFoodDocs = foodSnap.docs
            .map((d) => Map<String, dynamic>.from(d.data() as Map))
            .toList();
      });
      debugPrint('Loaded ${_allFoodDocs.length} food rules');
    } catch (e) {
      debugPrint('Load user data error: $e');
    }
  }

  // ── Toggle flash ──────────────────────────────────────────────────────
  Future<void> _toggleFlash() async {
    if (_cameraController == null || !_isCameraReady) return;
    try {
      _flashOn = !_flashOn;
      await _cameraController!
          .setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
      setState(() {});
    } catch (e) {
      debugPrint('Flash error: $e');
    }
  }

  // ── Capture and scan ──────────────────────────────────────────────────
  Future<void> _captureAndScan() async {
    final ctrl = _cameraController;
    if (ctrl == null || !_isCameraReady || _isLoading) return;

    try {
      // Turn off torch briefly to avoid overexposure
      if (_flashOn) await ctrl.setFlashMode(FlashMode.off);

      final xFile = await ctrl.takePicture();

      if (_flashOn) await ctrl.setFlashMode(FlashMode.torch);

      if (!mounted) return;
      setState(() {
        _isLoading      = true;
        _loadingMessage = 'Identifying your food...';
        _showResult     = false;
        _detectedFood   = '';
        _matchedFoodRule = null;
        _category       = 'unknown';
      });

      final knownFoods = _allFoodDocs
          .map((d) => (d['name'] ?? '').toString().trim())
          .where((n) => n.isNotEmpty)
          .toList();

      final foodName = await _identifyWithGemini(xFile.path, knownFoods);

      if (!mounted) return;

      if (foodName == null || foodName.trim().isEmpty) {
        setState(() => _isLoading = false);
        _showError(
          'Could not identify the food.\n\n'
          'Tips:\n'
          '• Point directly at the food\n'
          '• Make sure food fills the scan frame\n'
          '• Use better lighting or turn on flash\n'
          '• Hold the phone steady',
        );
        return;
      }

      debugPrint('Identified: "$foodName"');

      setState(() {
        _detectedFood   = foodName.trim();
        _loadingMessage = 'Checking food database...';
      });

      _matchFoodLocally(_detectedFood);
      await _saveHistory();

      if (!mounted) return;
      setState(() {
        _isLoading  = false;
        _showResult = true;
      });
    } catch (e) {
      debugPrint('Capture error: $e');
      _showError('Something went wrong: $e');
    }
  }

  // ── Gemini Vision API ─────────────────────────────────────────────────
  Future<String?> _identifyWithGemini(
      String imagePath, List<String> knownFoods) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final b64   = base64Encode(bytes);

      final hint = knownFoods.isNotEmpty
          ? '\n\nFOOD DATABASE — if food matches any of these, return that EXACT name:\n${knownFoods.take(80).join(', ')}'
          : '';

      final prompt =
          'Identify the food in this image.\n'
          'Reply with ONLY this JSON — no extra text, no markdown:\n'
          '{"food":"food name here","confidence":"high"}\n'
          'Rules:\n'
          '- food name must be lowercase\n'
          '- be specific (e.g. "white rice", "ampalaya", "fried chicken")\n'
          '- if no food is visible reply: {"food":"","confidence":"none"}\n'
          '- if the food matches something in the database, use that EXACT name'
          '$hint';

      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1/models/'
        '$_geminiModel:generateContent?key=$_geminiApiKey',
      );

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'inline_data': {'mime_type': 'image/jpeg', 'data': b64}},
                {'text': prompt},
              ]
            }
          ],
          'generationConfig': {
            'maxOutputTokens': 100,
            'temperature': 0.05,
            'topP': 0.9,
            'topK': 5,
          },
        }),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () =>
            throw Exception('Request timed out. Check your internet.'),
      );

      debugPrint('Gemini status: ${response.statusCode}');

      if (response.statusCode != 200) {
        try {
          final err = jsonDecode(response.body);
          final msg = err['error']?['message'] ?? 'API error';
          _showError('AI error: $msg\n\nCheck your API key.');
        } catch (_) {
          _showError('AI service error ${response.statusCode}.');
        }
        return null;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final text    = _geminiText(decoded);
      debugPrint('Gemini text: "$text"');

      if (text == null || text.trim().isEmpty) return null;
      return _parseFoodName(text);
    } catch (e) {
      debugPrint('Gemini error: $e');
      if (e.toString().contains('timed out')) {
        _showError('Request timed out.\nCheck your internet connection.');
      } else if (e.toString().contains('SocketException')) {
        _showError('No internet connection.');
      } else {
        _showError('AI error: $e');
      }
      return null;
    }
  }

  String? _geminiText(Map<String, dynamic> d) {
    try {
      return (d['candidates'] as List?)
          ?[0]?['content']?['parts']?[0]?['text']
          ?.toString();
    } catch (_) {
      return null;
    }
  }

  String? _parseFoodName(String raw) {
    final text = raw.trim();
    // Try JSON
    try {
      final cleaned = text
          .replaceAll(RegExp(r'```json', caseSensitive: false), '')
          .replaceAll('```', '')
          .trim();
      final m = RegExp(r'\{.+?\}', dotAll: true).firstMatch(cleaned);
      if (m != null) {
        final obj  = jsonDecode(m.group(0)!) as Map<String, dynamic>;
        final food = (obj['food'] as String?)?.trim().toLowerCase() ?? '';
        if (food.isNotEmpty) return food;
        if (obj.containsKey('food')) return null;
      }
    } catch (_) {}

    // No-food phrases
    final lower = text.toLowerCase();
    for (final p in [
      'no food', 'not food', 'cannot identify', 'unable to identify',
      'no visible food', 'no food item',
    ]) {
      if (lower.contains(p)) return null;
    }

    // Pattern fallbacks
    for (final r in [
      RegExp(r'"food"\s*:\s*"([^"]{2,40})"'),
      RegExp(r'(?:is|shows?|identified as|appears? to be)\s+(?:a |an |the )?([a-z][a-z\s\-]{1,35})',
          caseSensitive: false),
    ]) {
      final m = r.firstMatch(lower);
      if (m != null) {
        final f = m.group(1)?.trim().toLowerCase() ?? '';
        if (f.length > 2) return f;
      }
    }

    // Raw text as last resort
    if (lower.length <= 40 && !lower.contains('{') && !lower.contains('\n')) {
      final c = lower.replaceAll(RegExp(r'[^a-z\s\-]'), '').trim();
      if (c.length > 2) return c;
    }
    return null;
  }

  // ── Fuzzy match against Firestore food rules ──────────────────────────
  void _matchFoodLocally(String foodName) {
    final lower    = foodName.toLowerCase().trim();
    final variants = _buildVariants(lower);

    Map<String, dynamic>? best;
    String bestCat   = 'unknown';
    int    bestScore = 0;

    for (final doc in _allFoodDocs) {
      final name    = (doc['name']      ?? '').toString().toLowerCase().trim();
      final nameLow = (doc['nameLower'] ?? name).toString().toLowerCase().trim();
      final type    = (doc['diabetesType'] ?? '').toString();
      final cat     = (doc['category']  ?? '').toString();
      final kws     = (doc['searchKeywords'] as List? ?? [])
          .map((e) => e.toString().toLowerCase())
          .toList();

      int score = _computeScore(variants, name, nameLow, kws);
      if (score == 0) continue;
      if (_userDiabetesType.isNotEmpty && type == _userDiabetesType) score += 30;

      if (score > bestScore) {
        bestScore = score;
        best      = doc;
        bestCat   = cat;
      }
    }

    debugPrint('Best match: "${best?['name']}" score=$bestScore');

    setState(() {
      if (best != null && bestScore >= 15) {
        _matchedFoodRule = best;
        _category        = _normCat(bestCat);
      } else {
        _matchedFoodRule = null;
        _category        = 'unknown';
      }
    });
  }

  int _computeScore(
      List<String> vs, String name, String nameLow, List<String> kws) {
    int best = 0;
    for (final v in vs) {
      if (v.isEmpty) continue;
      if (name == v || nameLow == v) return 100;
      if (name.contains(v) || nameLow.contains(v)) best = _mx(best, 70);
      else if (v.contains(name) || v.contains(nameLow)) best = _mx(best, 65);
      for (final kw in kws) {
        if (kw == v || kw.contains(v) || v.contains(kw)) {
          best = _mx(best, 60);
          break;
        }
      }
      final vW = v.split(' ').where((w) => w.length > 2).toSet();
      final dW = name.split(' ').where((w) => w.length > 2).toSet();
      final c  = vW.intersection(dW).length;
      if (c > 0) best = _mx(best, c * 22);
    }
    return best;
  }

  int _mx(int a, int b) => a > b ? a : b;

  List<String> _buildVariants(String food) {
    final s = <String>{food};
    s.addAll(food.split(' ').where((w) => w.length > 2));

    const map = <String, List<String>>{
      'mung beans':    ['monggo','mungo','munggo','mung bean'],
      'monggo':        ['mung beans','mungo','munggo','mung bean'],
      'mungo':         ['mung beans','monggo','munggo'],
      'munggo':        ['mung beans','monggo','mungo'],
      'ampalaya':      ['bitter gourd','bitter melon','amargoso'],
      'bitter gourd':  ['ampalaya','bitter melon'],
      'bitter melon':  ['ampalaya','bitter gourd'],
      'sitaw':         ['string beans','long beans','yard long beans'],
      'string beans':  ['sitaw','long beans'],
      'talong':        ['eggplant','aubergine'],
      'eggplant':      ['talong'],
      'kangkong':      ['water spinach','swamp cabbage'],
      'water spinach': ['kangkong'],
      'kalabasa':      ['squash','pumpkin'],
      'squash':        ['kalabasa','pumpkin'],
      'camote':        ['sweet potato','kamote','yam'],
      'kamote':        ['sweet potato','camote','yam'],
      'sweet potato':  ['camote','kamote'],
      'gabi':          ['taro','taro root'],
      'taro':          ['gabi'],
      'pechay':        ['bok choy','pak choi','chinese cabbage'],
      'bok choy':      ['pechay','pak choi'],
      'malunggay':     ['moringa','drumstick leaves'],
      'moringa':       ['malunggay'],
      'okra':          ['lady finger','ladies finger'],
      'pipino':        ['cucumber'],
      'cucumber':      ['pipino'],
      'kamatis':       ['tomato'],
      'tomato':        ['kamatis'],
      'repolyo':       ['cabbage'],
      'cabbage':       ['repolyo'],
      'saging':        ['banana','plantain'],
      'banana':        ['saging'],
      'mangga':        ['mango'],
      'mango':         ['mangga'],
      'langka':        ['jackfruit'],
      'jackfruit':     ['langka'],
      'pinya':         ['pineapple'],
      'pineapple':     ['pinya'],
      'pakwan':        ['watermelon'],
      'watermelon':    ['pakwan'],
      'avocado':       ['abukado'],
      'abukado':       ['avocado'],
      'kanin':         ['white rice','rice','plain rice'],
      'white rice':    ['rice','kanin','plain rice','steamed rice'],
      'rice':          ['white rice','kanin','plain rice'],
      'brown rice':    ['rice','whole grain rice'],
      'sinangag':      ['garlic rice','fried rice'],
      'garlic rice':   ['sinangag','fried rice'],
      'lugaw':         ['congee','rice porridge','porridge'],
      'congee':        ['lugaw','porridge'],
      'oats':          ['oatmeal','rolled oats'],
      'oatmeal':       ['oats','rolled oats'],
      'manok':         ['chicken','fried chicken','grilled chicken'],
      'chicken':       ['manok','fried chicken','grilled chicken'],
      'fried chicken': ['chicken','manok'],
      'baboy':         ['pork','lechon','liempo'],
      'pork':          ['baboy','liempo','lechon'],
      'liempo':        ['pork belly','pork','baboy'],
      'lechon':        ['roast pork','pork','baboy'],
      'baka':          ['beef'],
      'beef':          ['baka'],
      'isda':          ['fish','tilapia','bangus'],
      'fish':          ['isda','tilapia','bangus','galunggong'],
      'bangus':        ['milkfish','fish','isda'],
      'milkfish':      ['bangus','fish'],
      'tilapia':       ['fish','isda'],
      'galunggong':    ['fish','isda','mackerel scad'],
      'sardinas':      ['sardines','canned fish'],
      'sardines':      ['sardinas'],
      'hipon':         ['shrimp','prawns'],
      'shrimp':        ['hipon','prawns'],
      'pusit':         ['squid'],
      'squid':         ['pusit'],
      'itlog':         ['egg','eggs','boiled egg','fried egg'],
      'egg':           ['itlog','eggs','boiled egg'],
      'eggs':          ['itlog','egg'],
      'tokwa':         ['tofu','bean curd'],
      'tofu':          ['tokwa','bean curd'],
      'adobo':         ['chicken adobo','pork adobo','adobong manok'],
      'sinigang':      ['pork sinigang','sinigang na baboy'],
      'tinola':        ['chicken tinola','tinolang manok'],
      'pinakbet':      ['pakbet','mixed vegetables'],
      'pakbet':        ['pinakbet'],
      'pancit':        ['noodles','bihon','canton'],
      'noodles':       ['pancit','bihon','canton'],
      'pandesal':      ['bread','pan de sal'],
      'bread':         ['pandesal','tinapay'],
      'mais':          ['corn'],
      'corn':          ['mais'],
    };

    if (map.containsKey(food)) s.addAll(map[food]!);
    for (final e in map.entries) {
      if (food != e.key &&
          (food.contains(e.key) || e.key.contains(food))) {
        s.addAll(e.value);
        s.add(e.key);
      }
    }
    return s.toList();
  }

  String _normCat(String c) {
    if (c.toLowerCase() == 'do')    return 'do';
    if (c.toLowerCase() == "don't") return 'dont';
    return 'unknown';
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
        'food':      _detectedFood,
        'category':  _category,
        'ruleData':  _matchedFoodRule,
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
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange),
          SizedBox(width: 8),
          Text('Scan Failed'),
        ]),
        content: Text(msg),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2C6E49)),
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

          // ── 1. Camera preview or fallback ─────────────────────────────
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
                    Text('Starting camera...',
                        style: TextStyle(color: Colors.white, fontSize: 15)),
                  ],
                ),
              ),
            ),

          // ── 2. Scanner overlay (only when camera is live) ─────────────
          if (_isCameraReady && !_cameraPermDenied)
            _buildScanOverlay(context),

          // ── 3. Top bar ────────────────────────────────────────────────
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    _topBtn(Icons.arrow_back, () => Navigator.pop(context)),
                    const SizedBox(width: 12),
                    const Text('Food Scan',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (_userDiabetesType.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('$_userDiabetesType Diabetes',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11)),
                      ),
                      const SizedBox(width: 8),
                    ],
                    // Flash button
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

          // ── 4. Loading overlay ────────────────────────────────────────
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
                          color: const Color(0xFF4CAF50), width: 1.5),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(
                            color: Color(0xFF4CAF50)),
                        const SizedBox(height: 16),
                        Text(_loadingMessage,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 15),
                            textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── 5. Result panel (bottom sheet style) ─────────────────────
          if (_showResult && !_isLoading)
            Positioned(
                bottom: 0, left: 0, right: 0,
                child: _buildResultPanel()),

          // ── 6. Scan button + hint (only when no result) ───────────────
          if (!_showResult && !_isLoading && _isCameraReady)
            Positioned(
              bottom: 48, left: 0, right: 0,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
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
                            color:
                                const Color(0xFF2C6E49).withOpacity(0.6),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.center_focus_strong,
                          color: Colors.white, size: 36),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Top icon button ───────────────────────────────────────────────────
  Widget _topBtn(IconData icon, VoidCallback onTap, {bool active = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: active
              ? Colors.yellow.withOpacity(0.25)
              : Colors.black45,
          borderRadius: BorderRadius.circular(10),
          border: active
              ? Border.all(color: Colors.yellow, width: 1.5)
              : null,
        ),
        child: Icon(icon,
            color: active ? Colors.yellow : Colors.white, size: 22),
      ),
    );
  }

  // ── Permission denied screen ──────────────────────────────────────────
  Widget _buildPermissionDenied() {
    return Positioned.fill(
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
                const Text('Camera Permission Required',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Text(
                  'Please allow camera access to use the food scanner.',
                  style:
                      TextStyle(color: Colors.white54, fontSize: 14, height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2C6E49),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => openAppSettings(),
                  child: const Text('Open Settings',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Scanner frame overlay ─────────────────────────────────────────────
  Widget _buildScanOverlay(BuildContext context) {
    final size       = MediaQuery.of(context).size;
    final frameSize  = size.width * 0.72;
    final frameLeft  = (size.width - frameSize) / 2;
    final frameTop   = (size.height - frameSize) / 2 - 50;

    return Stack(
      children: [
        // Dark mask — top
        Positioned(
            top: 0, left: 0, right: 0, height: frameTop,
            child: Container(color: Colors.black54)),
        // Dark mask — left
        Positioned(
            top: frameTop, left: 0, width: frameLeft, height: frameSize,
            child: Container(color: Colors.black54)),
        // Dark mask — right
        Positioned(
            top: frameTop, right: 0, width: frameLeft, height: frameSize,
            child: Container(color: Colors.black54)),
        // Dark mask — bottom
        Positioned(
            top: frameTop + frameSize, left: 0, right: 0, bottom: 0,
            child: Container(color: Colors.black54)),

        // Corner brackets
        Positioned(top: frameTop,              left: frameLeft,
            child: _corner(true,  true)),
        Positioned(top: frameTop,              right: frameLeft,
            child: _corner(true,  false)),
        Positioned(top: frameTop + frameSize - 32, left: frameLeft,
            child: _corner(false, true)),
        Positioned(top: frameTop + frameSize - 32, right: frameLeft,
            child: _corner(false, false)),

        // Animated scan line
        if (!_isLoading && !_showResult)
          _ScanLine(
              frameTop: frameTop,
              frameSize: frameSize,
              frameLeft: frameLeft),
      ],
    );
  }

  Widget _corner(bool top, bool left) {
    return SizedBox(
      width: 32, height: 32,
      child: CustomPaint(
        painter: _CornerPainter(
            color: const Color(0xFF4CAF50),
            strokeWidth: 4,
            top: top,
            left: left),
      ),
    );
  }

  // ── Result panel ──────────────────────────────────────────────────────
  Widget _buildResultPanel() {
    Color    catColor;
    IconData catIcon;
    String   catLabel;

    switch (_category) {
      case 'do':
        catColor = Colors.green;
        catIcon  = Icons.check_circle;
        catLabel = 'Safe to Eat';
        break;
      case 'dont':
        catColor = Colors.red;
        catIcon  = Icons.cancel;
        catLabel = 'Avoid This Food';
        break;
      default:
        catColor = Colors.orange;
        catIcon  = Icons.help_outline;
        catLabel = 'Not in Database';
    }

    final rule = _matchedFoodRule;

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
          // Drag handle
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Food name + badge
          Row(children: [
            Expanded(
              child: Text(_cap(_detectedFood),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: catColor.withOpacity(0.18),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: catColor),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(catIcon, color: catColor, size: 14),
                const SizedBox(width: 4),
                Text(catLabel,
                    style: TextStyle(
                        color: catColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ]),
            ),
          ]),

          const SizedBox(height: 12),

          // Nutrition chips or not-in-db notice
          if (rule != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('NUTRITION INFO',
                      style: TextStyle(
                          color: Colors.white38,
                          fontSize: 9,
                          letterSpacing: 1.2)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    if (_num(rule['calories']) > 0)
                      _chip('Cal', '${rule['calories']} kcal', Colors.orange),
                    if (_num(rule['carbs']) > 0)
                      _chip('Carbs', '${rule['carbs']}g', Colors.blue),
                    if (_num(rule['protein']) > 0)
                      _chip('Protein', '${rule['protein']}g', Colors.purple),
                    if (_num(rule['fat']) > 0)
                      _chip('Fat', '${rule['fat']}g', Colors.brown),
                    if (_num(rule['sugar']) > 0)
                      _chip('Sugar', '${rule['sugar']}g', Colors.red),
                  ]),
                  if ((rule['portionSize'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('Portion: ${rule['portionSize']}',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11)),
                  ],
                  if ((rule['diabetesType'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('For: ${rule['diabetesType']} Diabetes',
                        style: const TextStyle(
                            color: Colors.white30, fontSize: 11)),
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
              child: Row(children: [
                const Icon(Icons.info_outline, color: Colors.orange, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '"${_cap(_detectedFood)}" is not in your database yet.\nAsk your admin to add it.',
                    style: const TextStyle(
                        color: Colors.orange, fontSize: 12, height: 1.4),
                  ),
                ),
              ]),
            ),
          ],

          const SizedBox(height: 12),

          // Recommendation banner
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
                  height: 1.4),
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: 14),

          // Scan again
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2C6E49),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.center_focus_strong,
                  color: Colors.white, size: 20),
              label: const Text('Scan Again',
                  style: TextStyle(color: Colors.white, fontSize: 16)),
              onPressed: () => setState(() {
                _showResult      = false;
                _detectedFood    = '';
                _matchedFoodRule = null;
                _category        = 'unknown';
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text('$label: $value',
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
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
  late Animation<double>    _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _anim = Tween(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
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
          right: MediaQuery.of(context).size.width -
              widget.frameLeft -
              widget.frameSize +
              4,
          child: Container(
            height: 2.5,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                Colors.transparent,
                const Color(0xFF4CAF50).withOpacity(0.8),
                const Color(0xFF4CAF50),
                const Color(0xFF4CAF50).withOpacity(0.8),
                Colors.transparent,
              ]),
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
  final Color  color;
  final double strokeWidth;
  final bool   top;
  final bool   left;

  const _CornerPainter({
    required this.color,
    required this.strokeWidth,
    required this.top,
    required this.left,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color       = color
      ..strokeWidth = strokeWidth
      ..style       = PaintingStyle.stroke
      ..strokeCap   = StrokeCap.round;

    final path = Path();
    final w = size.width;
    final h = size.height;

    if (top && left) {
      path.moveTo(0, h); path.lineTo(0, 0); path.lineTo(w, 0);
    } else if (top && !left) {
      path.moveTo(0, 0); path.lineTo(w, 0); path.lineTo(w, h);
    } else if (!top && left) {
      path.moveTo(0, 0); path.lineTo(0, h); path.lineTo(w, h);
    } else {
      path.moveTo(0, h); path.lineTo(w, h); path.lineTo(w, 0);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CornerPainter o) =>
      o.color != color || o.strokeWidth != strokeWidth;
}