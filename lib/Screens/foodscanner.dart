import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

class FoodScannerScreen extends StatefulWidget {
  const FoodScannerScreen({Key? key}) : super(key: key);

  @override
  State<FoodScannerScreen> createState() => _FoodScannerScreenState();
}

class _FoodScannerScreenState extends State<FoodScannerScreen> {
  File?   _capturedImage;
  bool    _isLoading      = false;
  String  _loadingMessage = '';
  String  _detectedFood   = '';
  Map<String, dynamic>? _matchedFoodRule;
  String  _category           = 'unknown';
  String  _userDiabetesType   = '';
  List<Map<String, dynamic>> _allFoodDocs = [];

  final ImagePicker _picker = ImagePicker();

  // ── Replace with your working Gemini API key ──────────────────────────
  static const String _geminiApiKey = 'AIzaSyAxc-rFx1kj8QS5JPQjN1eOALnLbK8JhUE';
  static const String _geminiModel  = 'gemini-1.5-flash';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  // ── Load user type + all food rules at startup ────────────────────────
  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Load in parallel
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
        FirebaseFirestore.instance.collection('food_rules').get(),
      ]);

      final userDoc  = results[0] as DocumentSnapshot;
      final foodSnap = results[1] as QuerySnapshot;

      if (mounted) {
        setState(() {
          _userDiabetesType = (userDoc.data() as Map?)?['diabetesType']?.toString() ?? '';
          _allFoodDocs = foodSnap.docs
              .map((d) => Map<String, dynamic>.from(d.data() as Map))
              .toList();
        });
      }
      debugPrint('Loaded ${_allFoodDocs.length} food rules, type: $_userDiabetesType');
    } catch (e) {
      debugPrint('Load user data error: $e');
    }
  }

  // ── Main scan flow ────────────────────────────────────────────────────
  Future<void> _scanImage() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1024,
      );
      if (picked == null) return;

      if (!mounted) return;
      setState(() {
        _capturedImage   = File(picked.path);
        _isLoading       = true;
        _loadingMessage  = 'Identifying your food...';
        _detectedFood    = '';
        _matchedFoodRule = null;
        _category        = 'unknown';
      });

      // Step 1 — Ask Gemini to identify the food
      final foodName = await _identifyWithGemini(
        picked.path,
        _allFoodDocs.map((d) => (d['name'] ?? '').toString().trim()).where((n) => n.isNotEmpty).toList(),
      );

      if (foodName == null || foodName.trim().isEmpty) {
        _showError('Could not identify the food in the photo.\n\nTips:\n• Fill the frame with the food\n• Use good lighting\n• Hold the camera steady');
        return;
      }

      debugPrint('Gemini result: "$foodName"');

      if (!mounted) return;
      setState(() {
        _detectedFood   = foodName.trim();
        _loadingMessage = 'Checking food database...';
      });

      // Step 2 — Match against local food rules
      _matchFoodLocally(_detectedFood);

      // Step 3 — Save to history
      await _saveHistory();

      if (mounted) setState(() => _isLoading = false);

    } catch (e) {
      debugPrint('Scan error: $e');
      _showError('Something went wrong: $e');
    }
  }

  // ── Gemini Vision API call ────────────────────────────────────────────
  Future<String?> _identifyWithGemini(String imagePath, List<String> knownFoods) async {
    try {
      final bytes  = await File(imagePath).readAsBytes();
      final b64    = base64Encode(bytes);

      // Build hint string — send known food names so Gemini can match exactly
      final hint = knownFoods.isNotEmpty
          ? '\n\nFOOD DATABASE (use exact name if food matches):\n${knownFoods.take(80).join(', ')}'
          : '';

      final prompt =
          'Identify the food in this image.\n'
          'Reply with ONLY this JSON — no extra text, no markdown:\n'
          '{"food":"food name","confidence":"high"}\n'
          'Rules:\n'
          '- food name must be lowercase\n'
          '- be specific (e.g. "white rice", "fried chicken", "ampalaya")\n'
          '- if no food is visible reply: {"food":"","confidence":"none"}\n'
          '- if the food matches something in the database list below, use that EXACT name'
          '$hint';

      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/'
        '$_geminiModel:generateContent?key=$_geminiApiKey',
      );

      debugPrint('Calling Gemini...');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {
                  'inline_data': {
                    'mime_type': 'image/jpeg',
                    'data': b64,
                  }
                },
                {'text': prompt},
              ]
            }
          ],
          'generationConfig': {
            'maxOutputTokens': 100,
            'temperature': 0.05,  // very low = more deterministic
            'topP': 0.9,
            'topK': 5,
          },
          'safetySettings': [
            {'category': 'HARM_CATEGORY_DANGEROUS_CONTENT', 'threshold': 'BLOCK_NONE'},
          ],
        }),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw Exception('Request timed out. Check your internet connection.'),
      );

      debugPrint('Gemini HTTP status: ${response.statusCode}');

      if (response.statusCode != 200) {
        // Parse the error message from Gemini
        try {
          final err = jsonDecode(response.body);
          final msg = err['error']?['message'] ?? 'Unknown API error';
          debugPrint('Gemini API error: $msg');
          _showError('AI service error: $msg\n\nCheck your API key and try again.');
        } catch (_) {
          _showError('AI service returned HTTP ${response.statusCode}.\nCheck your API key.');
        }
        return null;
      }

      // Parse response body
      final decoded  = jsonDecode(response.body) as Map<String, dynamic>;
      final rawText  = _extractGeminiText(decoded);

      debugPrint('Gemini raw text: "$rawText"');

      if (rawText == null || rawText.trim().isEmpty) {
        debugPrint('Empty Gemini response');
        return null;
      }

      // Parse food name from the returned text
      return _parseFoodName(rawText);

    } catch (e) {
      debugPrint('Gemini exception: $e');
      if (e.toString().contains('timed out')) {
        _showError('Request timed out.\nCheck your internet and try again.');
      } else if (e.toString().contains('SocketException')) {
        _showError('No internet connection.\nPlease check your network.');
      } else {
        _showError('AI error: $e');
      }
      return null;
    }
  }

  // ── Extract text from Gemini response safely ──────────────────────────
  String? _extractGeminiText(Map<String, dynamic> decoded) {
    try {
      final candidates = decoded['candidates'];
      if (candidates == null || (candidates as List).isEmpty) return null;

      final content = candidates[0]?['content'];
      if (content == null) return null;

      final parts = content['parts'];
      if (parts == null || (parts as List).isEmpty) return null;

      return parts[0]?['text']?.toString();
    } catch (_) {
      return null;
    }
  }

  // ── Parse food name from Gemini text (JSON or plain) ──────────────────
  String? _parseFoodName(String raw) {
    final text = raw.trim();

    // ── Try JSON extraction first ─────────────────────────────────────
    try {
      // Remove markdown code fences if present
      String cleaned = text
          .replaceAll(RegExp(r'```json', caseSensitive: false), '')
          .replaceAll('```', '')
          .trim();

      // Use dotAll regex to capture multi-line JSON objects
      final jsonMatch = RegExp(r'\{.+?\}', dotAll: true).firstMatch(cleaned);
      if (jsonMatch != null) {
        final obj = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
        final food = (obj['food'] as String?)?.trim().toLowerCase() ?? '';
        if (food.isNotEmpty) {
          debugPrint('JSON parsed: "$food"');
          return food;
        }
        // Explicit empty = no food detected
        if (obj.containsKey('food') && food.isEmpty) return null;
      }
    } catch (e) {
      debugPrint('JSON parse attempt failed: $e');
    }

    // ── Fallback: plain text heuristics ──────────────────────────────
    final lower = text.toLowerCase();

    // Detect "no food" responses
    for (final phrase in [
      'no food', 'not food', 'no visible food', 'cannot identify',
      'unable to identify', 'not a food item', 'no food item',
    ]) {
      if (lower.contains(phrase)) {
        debugPrint('No-food phrase detected: "$phrase"');
        return null;
      }
    }

    // Try common phrase patterns
    final patterns = [
      RegExp(r'"food"\s*:\s*"([^"]{2,40})"'),
      RegExp(r'(?:is|shows?|contains?|identified as|appears? to be|food is)\s+(?:a |an |the )?([a-z][a-z\s\-]{1,35})', caseSensitive: false),
      RegExp(r'(?:food|dish|item):\s*([a-z][a-z\s\-]{1,35})', caseSensitive: false),
    ];

    for (final p in patterns) {
      final m = p.firstMatch(lower);
      if (m != null) {
        final food = m.group(1)?.trim().toLowerCase() ?? '';
        if (food.length > 2) {
          debugPrint('Pattern extracted: "$food"');
          return food;
        }
      }
    }

    // Last resort: if entire response is short and looks like a food name
    if (lower.length <= 40 && !lower.contains('{') && !lower.contains('\n')) {
      final cleaned = lower.replaceAll(RegExp(r'[^a-z\s\-]'), '').trim();
      if (cleaned.length > 2) {
        debugPrint('Using raw text as food: "$cleaned"');
        return cleaned;
      }
    }

    debugPrint('Could not extract food name from: "$raw"');
    return null;
  }

  // ── Fuzzy match food name against local food_rules docs ───────────────
  void _matchFoodLocally(String foodName) {
    final lower    = foodName.toLowerCase().trim();
    final variants = _buildVariants(lower);

    debugPrint('Matching "$lower" — variants: $variants');

    Map<String, dynamic>? best;
    String bestCat = 'unknown';
    int    bestScore = 0;

    for (final doc in _allFoodDocs) {
      final name     = (doc['name']      ?? '').toString().toLowerCase().trim();
      final nameLow  = (doc['nameLower'] ?? name).toString().toLowerCase().trim();
      final type     = (doc['diabetesType'] ?? '').toString();
      final cat      = (doc['category']  ?? '').toString();
      final keywords = (doc['searchKeywords'] as List? ?? [])
          .map((e) => e.toString().toLowerCase())
          .toList();

      int score = _computeScore(variants, name, nameLow, keywords);
      if (score == 0) continue;

      // Boost for matching diabetes type
      if (_userDiabetesType.isNotEmpty && type == _userDiabetesType) score += 30;

      debugPrint('  "$name" → $score');

      if (score > bestScore) {
        bestScore = score;
        best      = doc;
        bestCat   = cat;
      }
    }

    debugPrint('Best: "${best?['name']}" score=$bestScore');

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

  int _computeScore(List<String> variants, String name, String nameLow, List<String> keywords) {
    int best = 0;
    for (final v in variants) {
      if (v.isEmpty) continue;

      // Exact
      if (name == v || nameLow == v) return 100;

      // Contains
      if (name.contains(v) || nameLow.contains(v)) best = _mx(best, 70);
      else if (v.contains(name) || v.contains(nameLow)) best = _mx(best, 65);

      // Keywords
      for (final kw in keywords) {
        if (kw == v || kw.contains(v) || v.contains(kw)) {
          best = _mx(best, 60);
          break;
        }
      }

      // Word overlap
      final vW = v.split(' ').where((w) => w.length > 2).toSet();
      final dW = name.split(' ').where((w) => w.length > 2).toSet();
      final common = vW.intersection(dW).length;
      if (common > 0) best = _mx(best, common * 22);
    }
    return best;
  }

  int _mx(int a, int b) => a > b ? a : b;

  // ── Filipino / English food alias table ──────────────────────────────
  List<String> _buildVariants(String food) {
    final s = <String>{food};
    s.addAll(food.split(' ').where((w) => w.length > 2));

    const map = <String, List<String>>{
      // Legumes
      'mung beans':      ['monggo', 'mungo', 'munggo', 'mung bean'],
      'monggo':          ['mung beans', 'mungo', 'munggo', 'mung bean'],
      'mungo':           ['mung beans', 'monggo', 'munggo'],
      'munggo':          ['mung beans', 'monggo', 'mungo'],
      // Vegetables
      'ampalaya':        ['bitter gourd', 'bitter melon', 'amargoso'],
      'bitter gourd':    ['ampalaya', 'bitter melon'],
      'bitter melon':    ['ampalaya', 'bitter gourd'],
      'sitaw':           ['string beans', 'long beans', 'yard long beans'],
      'string beans':    ['sitaw', 'long beans'],
      'talong':          ['eggplant', 'aubergine'],
      'eggplant':        ['talong'],
      'kangkong':        ['water spinach', 'swamp cabbage'],
      'water spinach':   ['kangkong'],
      'kalabasa':        ['squash', 'pumpkin'],
      'squash':          ['kalabasa', 'pumpkin'],
      'pumpkin':         ['kalabasa', 'squash'],
      'camote':          ['sweet potato', 'kamote', 'yam'],
      'kamote':          ['sweet potato', 'camote', 'yam'],
      'sweet potato':    ['camote', 'kamote'],
      'gabi':            ['taro', 'taro root'],
      'taro':            ['gabi'],
      'pechay':          ['bok choy', 'pak choi', 'chinese cabbage'],
      'bok choy':        ['pechay', 'pak choi'],
      'malunggay':       ['moringa', 'drumstick leaves'],
      'moringa':         ['malunggay'],
      'saluyot':         ['jute leaves', 'jute mallow'],
      'okra':            ['lady finger', 'ladies finger'],
      'pipino':          ['cucumber'],
      'cucumber':        ['pipino'],
      'kamatis':         ['tomato'],
      'tomato':          ['kamatis'],
      'repolyo':         ['cabbage'],
      'cabbage':         ['repolyo'],
      'karot':           ['carrot'],
      'carrot':          ['karot'],
      // Fruits
      'saging':          ['banana', 'plantain'],
      'banana':          ['saging'],
      'mangga':          ['mango'],
      'mango':           ['mangga'],
      'bayabas':         ['guava'],
      'guava':           ['bayabas'],
      'langka':          ['jackfruit'],
      'jackfruit':       ['langka'],
      'pinya':           ['pineapple'],
      'pineapple':       ['pinya'],
      'pakwan':          ['watermelon'],
      'watermelon':      ['pakwan'],
      'abukado':         ['avocado'],
      'avocado':         ['abukado'],
      // Rice
      'kanin':           ['white rice', 'rice', 'plain rice'],
      'white rice':      ['rice', 'kanin', 'plain rice', 'steamed rice'],
      'rice':            ['white rice', 'kanin', 'plain rice'],
      'brown rice':      ['rice', 'whole grain rice'],
      'sinangag':        ['garlic rice', 'fried rice'],
      'garlic rice':     ['sinangag', 'fried rice'],
      'lugaw':           ['congee', 'rice porridge', 'porridge'],
      'congee':          ['lugaw', 'porridge', 'rice porridge'],
      'oats':            ['oatmeal', 'rolled oats'],
      'oatmeal':         ['oats', 'rolled oats'],
      // Meat
      'manok':           ['chicken', 'fried chicken', 'grilled chicken'],
      'chicken':         ['manok', 'fried chicken', 'grilled chicken'],
      'fried chicken':   ['chicken', 'manok'],
      'grilled chicken': ['chicken', 'manok'],
      'baboy':           ['pork', 'lechon', 'liempo'],
      'pork':            ['baboy', 'liempo', 'lechon'],
      'liempo':          ['pork belly', 'pork', 'baboy'],
      'lechon':          ['roast pork', 'pork', 'baboy'],
      'baka':            ['beef'],
      'beef':            ['baka'],
      // Fish
      'isda':            ['fish', 'tilapia', 'bangus'],
      'fish':            ['isda', 'tilapia', 'bangus', 'galunggong'],
      'bangus':          ['milkfish', 'fish', 'isda'],
      'milkfish':        ['bangus', 'fish'],
      'tilapia':         ['fish', 'isda'],
      'galunggong':      ['fish', 'isda', 'mackerel scad'],
      'sardinas':        ['sardines', 'canned fish'],
      'sardines':        ['sardinas'],
      'hipon':           ['shrimp', 'prawns'],
      'shrimp':          ['hipon', 'prawns'],
      'pusit':           ['squid'],
      'squid':           ['pusit'],
      // Eggs & tofu
      'itlog':           ['egg', 'eggs', 'boiled egg', 'fried egg'],
      'egg':             ['itlog', 'eggs', 'boiled egg'],
      'eggs':            ['itlog', 'egg'],
      'boiled egg':      ['itlog', 'egg'],
      'tokwa':           ['tofu', 'bean curd'],
      'tofu':            ['tokwa', 'bean curd'],
      'taho':            ['soft tofu', 'silken tofu', 'tofu'],
      // Common dishes
      'adobo':           ['chicken adobo', 'pork adobo', 'adobong manok'],
      'sinigang':        ['pork sinigang', 'sinigang na baboy', 'sinigang na isda'],
      'tinola':          ['chicken tinola', 'tinolang manok'],
      'pinakbet':        ['pakbet', 'mixed vegetables'],
      'pakbet':          ['pinakbet'],
      'pancit':          ['noodles', 'bihon', 'canton', 'pancit canton'],
      'noodles':         ['pancit', 'bihon', 'canton'],
      'pandesal':        ['bread', 'pan de sal'],
      'bread':           ['pandesal', 'tinapay'],
      'mais':            ['corn'],
      'corn':            ['mais'],
    };

    // Direct lookup
    if (map.containsKey(food)) s.addAll(map[food]!);

    // Partial match — if food name contains a key
    for (final entry in map.entries) {
      if (food != entry.key &&
          (food.contains(entry.key) || entry.key.contains(food))) {
        s.addAll(entry.value);
        s.add(entry.key);
      }
    }

    return s.toList();
  }

  String _normCat(String c) {
    final l = c.toLowerCase();
    if (l == 'do')    return 'do';
    if (l == "don't") return 'dont';
    return 'unknown';
  }

  Future<void> _saveHistory() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await FirebaseFirestore.instance
          .collection('users').doc(user.uid)
          .collection('scanned_foods')
          .add({
        'food':      _detectedFood,
        'category':  _category,
        'ruleData':  _matchedFoodRule,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Save history error: $e');
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
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2C6E49)),
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

  // ═══════════════════════════════════════════════════════════════════════
  // UI
  // ═══════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FDF9),
      appBar: AppBar(
        // ── Renamed from "AI Food Scanner" to "Food Scan" ──
        title: const Text('Food Scan',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF2C6E49),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_userDiabetesType.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('$_userDiabetesType Diabetes',
                      style: const TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          // Background image or placeholder
          if (_capturedImage != null)
            Positioned.fill(child: Image.file(_capturedImage!, fit: BoxFit.cover))
          else
            _buildPlaceholder(),

          // Dim overlay when image is shown
          if (_capturedImage != null)
            Container(color: const Color.fromRGBO(0, 0, 0, 0.45)),

          // Center content
          Center(
            child: _isLoading
                ? _buildLoadingCard()
                : _detectedFood.isNotEmpty
                    ? _buildResultCard()
                    : const SizedBox.shrink(),
          ),

          // Bottom buttons
          Positioned(
            bottom: 40, left: 0, right: 0,
            child: Column(
              children: [
                if (_detectedFood.isNotEmpty && !_isLoading) ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    icon: const Icon(Icons.clear, size: 20, color: Colors.white),
                    label: const Text('Clear', style: TextStyle(color: Colors.white, fontSize: 14)),
                    onPressed: () => setState(() {
                      _capturedImage   = null;
                      _detectedFood    = '';
                      _matchedFoodRule = null;
                      _category        = 'unknown';
                    }),
                  ),
                  const SizedBox(height: 10),
                ],
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2C6E49),
                    padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  icon: const Icon(Icons.camera_alt, size: 28, color: Colors.white),
                  label: Text(
                    _detectedFood.isEmpty ? 'Scan Food' : 'Scan Again',
                    style: const TextStyle(fontSize: 18, color: Colors.white),
                  ),
                  onPressed: _isLoading ? null : _scanImage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Placeholder — NO chips ─────────────────────────────────────────────
  Widget _buildPlaceholder() {
    return Positioned.fill(
      child: Container(
        color: Colors.grey.shade100,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: const Color(0xFF2C6E49).withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.camera_alt,
                  size: 80, color: const Color(0xFF2C6E49).withOpacity(0.5)),
            ),
            const SizedBox(height: 24),
            // ── Changed from "AI Food Scanner" to "Food Scan" ──
            const Text('Food Scan',
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2C6E49))),
            const SizedBox(height: 10),
            Text(
              'Take a photo of your food\nto check if it\'s safe for your diabetes',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15, color: Colors.grey.shade600, height: 1.6),
            ),
            // ── Chips removed as requested ──
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
          color: Colors.black87, borderRadius: BorderRadius.circular(20)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Color(0xFF4CAF50)),
          const SizedBox(height: 16),
          Text(_loadingMessage,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildResultCard() {
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 80, 16, 110),
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: catColor.withOpacity(0.7), width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [

              // ── Food name + status badge ──────────────────────────────
              Row(children: [
                Expanded(
                  child: Text(_cap(_detectedFood),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
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
                    Icon(catIcon, color: catColor, size: 15),
                    const SizedBox(width: 4),
                    Text(catLabel,
                        style: TextStyle(
                            color: catColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 11)),
                  ]),
                ),
              ]),

              const SizedBox(height: 14),

              // ── Nutrition info ────────────────────────────────────────
              if (rule != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
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
                              fontSize: 10,
                              letterSpacing: 1.2)),
                      const SizedBox(height: 10),
                      if ((rule['name'] ?? '').toString().isNotEmpty)
                        _row(Icons.label_outline, 'Food',
                            _cap(rule['name'].toString())),
                      if ((rule['portionSize'] ?? '').toString().isNotEmpty)
                        _row(Icons.scale, 'Portion',
                            rule['portionSize'].toString()),
                      if (_num(rule['calories']) > 0)
                        _row(Icons.local_fire_department, 'Calories',
                            '${rule['calories']} kcal'),
                      if (_num(rule['carbs']) > 0)
                        _row(Icons.bubble_chart, 'Carbs',
                            '${rule['carbs']} g'),
                      if (_num(rule['protein']) > 0)
                        _row(Icons.fitness_center, 'Protein',
                            '${rule['protein']} g'),
                      if (_num(rule['fat']) > 0)
                        _row(Icons.opacity, 'Fat', '${rule['fat']} g'),
                      if (_num(rule['sugar']) > 0)
                        _row(Icons.water_drop, 'Sugar',
                            '${rule['sugar']} g'),
                      if ((rule['diabetesType'] ?? '').toString().isNotEmpty) ...[
                        const Divider(color: Colors.white12, height: 18),
                        Text('For: ${rule['diabetesType']} Diabetes',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 12)),
                      ],
                    ],
                  ),
                ),
              ] else ...[
                // Food not in database
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.withOpacity(0.4)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.info_outline,
                        color: Colors.orange, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '"${_cap(_detectedFood)}" is not in your database yet.\nAsk your admin to add it.',
                        style: const TextStyle(
                            color: Colors.orange, fontSize: 13, height: 1.4),
                      ),
                    ),
                  ]),
                ),
              ],

              const SizedBox(height: 14),

              // ── Recommendation banner ─────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
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

              if (_userDiabetesType.isNotEmpty) ...[
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Your profile: $_userDiabetesType Diabetes',
                    style: const TextStyle(color: Colors.white30, fontSize: 11),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(IconData icon, String label, String val) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Icon(icon, color: Colors.white38, size: 14),
          const SizedBox(width: 6),
          Text('$label: ',
              style: const TextStyle(color: Colors.white54, fontSize: 13)),
          Expanded(
            child: Text(val,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis),
          ),
        ]),
      );

  double _num(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;
}