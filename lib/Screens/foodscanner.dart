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
  File? _capturedImage;
  bool _isLoading = false;
  String _loadingMessage = '';

  String _detectedFood = '';
  Map<String, dynamic>? _matchedFoodRule;
  String _category = 'unknown';
  String _userDiabetesType = '';

  final ImagePicker _picker = ImagePicker();

  static const String _geminiApiKey = 'AIzaSyAxc-rFx1kj8QS5JPQjN1eOALnLbK8JhUE';
  static const String _geminiModel  = 'gemini-1.5-flash';

  @override
  void initState() {
    super.initState();
    _loadUserDiabetesType();
  }

  Future<void> _loadUserDiabetesType() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      setState(() {
        _userDiabetesType = (doc.data()?['diabetesType'] ?? '').toString();
      });
    } catch (_) {}
  }

  Future<void> _scanImage() async {
    try {
      final pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1024,
      );
      if (pickedFile == null) return;

      setState(() {
        _capturedImage   = File(pickedFile.path);
        _isLoading       = true;
        _loadingMessage  = '🤖 AI is identifying your food...';
        _detectedFood    = '';
        _matchedFoodRule = null;
        _category        = 'unknown';
      });

      final foodName = await _identifyFoodWithGemini(pickedFile.path);
      if (foodName == null || foodName.isEmpty) {
        _showError('Could not identify food. Please try again with a clearer photo.');
        return;
      }

      setState(() {
        _detectedFood   = foodName;
        _loadingMessage = '🔍 Checking your food database...';
      });

      await _lookupFoodInFirestore(foodName);
      await _saveScanHistory();

      setState(() => _isLoading = false);
    } catch (e) {
      _showError('Error: $e');
    }
  }

  // ── Gemini Vision: identify food name (robust parsing) ────────────────
  Future<String?> _identifyFoodWithGemini(String imagePath) async {
    try {
      final imageBytes  = await File(imagePath).readAsBytes();
      final base64Image = base64Encode(imageBytes);

      // Simpler prompt — less likely to confuse the model
      const prompt = '''
Look at this image and identify the food item shown.

Respond with ONLY a single JSON object like this:
{"food": "avocado", "is_food": true}

If there is no food in the image, respond:
{"food": "", "is_food": false}

Rules:
- Use simple, common food names in lowercase (e.g. "white rice", "fried chicken", "avocado", "apple")
- If multiple foods are visible, name the most prominent one
- Do NOT include any explanation, markdown, or extra text — only the JSON object
''';

      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$_geminiModel:generateContent?key=$_geminiApiKey',
      );

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
                    'data': base64Image,
                  },
                },
                {'text': prompt},
              ],
            }
          ],
          'generationConfig': {
            'maxOutputTokens': 150,
            'temperature': 0.1,
          },
        }),
      );

      if (response.statusCode != 200) {
        debugPrint('Gemini HTTP error ${response.statusCode}: ${response.body}');
        return null;
      }

      final decoded = jsonDecode(response.body);
      final text = decoded['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;

      if (text == null || text.trim().isEmpty) {
        debugPrint('Gemini returned empty text');
        return null;
      }

      debugPrint('Gemini raw response: $text');

      // Try JSON parse first
      final foodName = _parseGeminiResponse(text);
      if (foodName != null && foodName.isNotEmpty) return foodName;

      // Fallback: extract food name from plain text response
      return _extractFoodNameFromText(text);

    } catch (e) {
      debugPrint('Gemini error: $e');
      return null;
    }
  }

  /// Tries to parse a JSON response from Gemini
  String? _parseGeminiResponse(String text) {
    try {
      // Strip markdown fences if present
      String cleaned = text
          .trim()
          .replaceAll(RegExp(r'```json\s*', multiLine: true), '')
          .replaceAll(RegExp(r'```\s*',      multiLine: true), '')
          .trim();

      // Find the first JSON object in the response
      final jsonMatch = RegExp(r'\{[^}]+\}').firstMatch(cleaned);
      if (jsonMatch == null) return null;

      final parsed = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;

      if (parsed['is_food'] == false) {
        debugPrint('Gemini: no food detected');
        return null;
      }

      final food = (parsed['food'] as String?)?.trim().toLowerCase();
      if (food == null || food.isEmpty) return null;

      debugPrint('Parsed food from JSON: $food');
      return food;
    } catch (e) {
      debugPrint('JSON parse failed: $e');
      return null;
    }
  }

  /// Fallback: if Gemini returns plain text instead of JSON, extract food name
  String? _extractFoodNameFromText(String text) {
    final lower = text.toLowerCase().trim();

    // If it says "no food" or similar, return null
    final noFoodPhrases = ['no food', 'not food', 'cannot identify', 'unable to identify', 'not a food'];
    for (final phrase in noFoodPhrases) {
      if (lower.contains(phrase)) return null;
    }

    // Try to extract from patterns like: "The food is avocado" / "This is avocado" / "avocado"
    final patterns = [
      RegExp(r'(?:food is|this is|shows?|contains?|identified as|appears? to be)\s+(?:a |an |the )?([a-z][a-z\s]{1,30})', caseSensitive: false),
      RegExp(r'"food"\s*:\s*"([^"]+)"'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(lower);
      if (match != null) {
        final food = match.group(1)?.trim().toLowerCase();
        if (food != null && food.isNotEmpty) {
          debugPrint('Extracted food from text: $food');
          return food;
        }
      }
    }

    // Last resort: if the response is short and looks like a food name, use it
    if (lower.length < 40 && !lower.contains('{') && !lower.contains('\n')) {
      final cleaned = lower.replaceAll(RegExp(r'[^a-z\s]'), '').trim();
      if (cleaned.isNotEmpty) {
        debugPrint('Using raw text as food name: $cleaned');
        return cleaned;
      }
    }

    debugPrint('Could not extract food name from text: $text');
    return null;
  }

  // ── Look up food in Firestore ─────────────────────────────────────────
  Future<void> _lookupFoodInFirestore(String foodName) async {
    try {
      final foodLower = foodName.toLowerCase().trim();
      final foodWords = foodLower.split(' ').where((w) => w.length > 1).toList();

      final allDocs = await FirebaseFirestore.instance
          .collection('food_rules')
          .get();

      if (allDocs.docs.isEmpty) {
        setState(() => _category = 'unknown');
        return;
      }

      Map<String, dynamic>? bestMatch;
      String bestCategory = 'unknown';
      int bestScore = 0;

      for (final doc in allDocs.docs) {
        final data    = doc.data();
        final docName = (data['name'] ?? '').toString().toLowerCase().trim();
        final docType = (data['diabetesType'] ?? '').toString();
        final docCat  = (data['category'] ?? '').toString();

        int score = 0;

        if (docName == foodLower) {
          score = 100;
        } else if (docName.contains(foodLower) || foodLower.contains(docName)) {
          score = 60;
        } else {
          final docWords = docName.split(' ').toSet();
          final common = foodWords
              .where((w) => w.length > 2 && docWords.contains(w))
              .length;
          if (common > 0) score = common * 20;
        }

        if (score == 0) continue;

        // Boost score for matching user's diabetes type
        if (_userDiabetesType.isNotEmpty && docType == _userDiabetesType) {
          score += 30;
        }

        if (score > bestScore) {
          bestScore    = score;
          bestMatch    = data;
          bestCategory = docCat;
        }
      }

      setState(() {
        if (bestMatch != null && bestScore >= 20) {
          _matchedFoodRule = bestMatch;
          _category        = _normalizeCategory(bestCategory);
        } else {
          _matchedFoodRule = null;
          _category        = 'unknown';
        }
      });
    } catch (e) {
      debugPrint('Firestore lookup error: $e');
    }
  }

  String _normalizeCategory(String cat) {
    final c = cat.toLowerCase();
    if (c == 'do')    return 'do';
    if (c == "don't") return 'dont';
    return 'unknown';
  }

  Future<void> _saveScanHistory() async {
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
      debugPrint('Save history error: $e');
    }
  }

  void _showError(String message) {
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 12),
            const Text('Tips for better results:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            const Text('• Make sure the food fills most of the frame', style: TextStyle(fontSize: 12)),
            const Text('• Use good lighting', style: TextStyle(fontSize: 12)),
            const Text('• Avoid blurry photos', style: TextStyle(fontSize: 12)),
            const Text('• Try holding the camera closer', style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2C6E49)),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Try Again', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String _capitalize(String text) => text
      .split(' ')
      .map((w) => w.isNotEmpty ? w[0].toUpperCase() + w.substring(1) : '')
      .join(' ');

  // ── UI ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FDF9),
      appBar: AppBar(
        title: const Text('AI Food Scanner', style: TextStyle(color: Colors.white)),
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
            bottom: 40,
            left: 0,
            right: 0,
            child: Column(
              children: [
                if (_detectedFood.isNotEmpty && !_isLoading)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      icon: const Icon(Icons.clear, size: 20, color: Colors.white),
                      label: const Text('Clear Result', style: TextStyle(fontSize: 14, color: Colors.white)),
                      onPressed: () {
                        setState(() {
                          _capturedImage   = null;
                          _detectedFood    = '';
                          _matchedFoodRule = null;
                          _category        = 'unknown';
                        });
                      },
                    ),
                  ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2C6E49),
                    padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  icon: const Icon(Icons.camera_alt, size: 28, color: Colors.white),
                  label: Text(
                    _detectedFood.isEmpty ? 'Scan Food' : 'Scan New Food',
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
              child: Icon(Icons.camera_alt, size: 80, color: const Color(0xFF2C6E49).withOpacity(0.5)),
            ),
            const SizedBox(height: 24),
            const Text('AI Food Scanner',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF2C6E49))),
            const SizedBox(height: 8),
            Text(
              'Take a photo of your food\nand see if it\'s safe for your diabetes',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600, height: 1.5),
            ),
            const SizedBox(height: 28),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _chip('🤖 AI Identifies Food'),
                _chip('📋 Your Database'),
                _chip('✅ Safe  /  ⚠️ Avoid'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label) => Chip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        backgroundColor: const Color(0xFF2C6E49).withOpacity(0.08),
        side: BorderSide(color: const Color(0xFF2C6E49).withOpacity(0.3)),
      );

  Widget _buildLoadingCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20)),
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
        catLabel = '✅ Safe to Eat';
        break;
      case 'dont':
        catColor = Colors.red;
        catIcon  = Icons.cancel;
        catLabel = '⚠️ Avoid This Food';
        break;
      default:
        catColor = Colors.orange;
        catIcon  = Icons.help_outline;
        catLabel = 'Not in Database';
    }

    final rule = _matchedFoodRule;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 80, 16, 100),
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

              Row(children: [
                Expanded(
                  child: Text(
                    _capitalize(_detectedFood),
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: catColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: catColor),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(catIcon, color: catColor, size: 15),
                    const SizedBox(width: 4),
                    Text(catLabel, style: TextStyle(color: catColor, fontWeight: FontWeight.bold, fontSize: 11)),
                  ]),
                ),
              ]),

              const SizedBox(height: 14),

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
                      Row(children: const [
                        Icon(Icons.storage, color: Colors.white38, size: 13),
                        SizedBox(width: 5),
                        Text('FROM YOUR DATABASE',
                            style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1.2)),
                      ]),
                      const SizedBox(height: 10),
                      if ((rule['portionSize'] ?? '').toString().isNotEmpty)
                        _row(Icons.scale, 'Portion', '${rule['portionSize']}'),
                      if (_toDouble(rule['calories']) > 0)
                        _row(Icons.local_fire_department, 'Calories', '${rule['calories']} kcal'),
                      if (_toDouble(rule['carbs']) > 0)
                        _row(Icons.bubble_chart, 'Carbs', '${rule['carbs']} g'),
                      if (_toDouble(rule['protein']) > 0)
                        _row(Icons.fitness_center, 'Protein', '${rule['protein']} g'),
                      if (_toDouble(rule['fat']) > 0)
                        _row(Icons.opacity, 'Fat', '${rule['fat']} g'),
                      if (_toDouble(rule['sugar']) > 0)
                        _row(Icons.water_drop, 'Sugar', '${rule['sugar']} g'),
                      if ((rule['diabetesType'] ?? '').toString().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(children: [
                          const Icon(Icons.monitor_heart, color: Colors.white30, size: 13),
                          const SizedBox(width: 5),
                          Text('Rule applies to: ${rule['diabetesType']} Diabetes',
                              style: const TextStyle(color: Colors.white38, fontSize: 12)),
                        ]),
                      ],
                    ],
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.withOpacity(0.35)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.info_outline, color: Colors.orange, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '"${_capitalize(_detectedFood)}" is not in your food database yet. Ask your admin to add it.',
                        style: const TextStyle(color: Colors.orange, fontSize: 13),
                      ),
                    ),
                  ]),
                ),
              ],

              const SizedBox(height: 14),

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
                      ? '✅ Recommended for diabetics${_userDiabetesType.isNotEmpty ? ' with $_userDiabetesType diabetes' : ''}.'
                      : _category == 'dont'
                          ? '⚠️ Should be avoided${_userDiabetesType.isNotEmpty ? ' for $_userDiabetesType diabetes' : ' by diabetics'}.'
                          : 'ℹ️ No rule found. Check with your doctor.',
                  style: TextStyle(color: catColor, fontWeight: FontWeight.bold, fontSize: 13, height: 1.4),
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

  Widget _row(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(icon, color: Colors.white38, size: 14),
        const SizedBox(width: 6),
        Text('$label: ', style: const TextStyle(color: Colors.white54, fontSize: 13)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  double _toDouble(dynamic val) => double.tryParse(val?.toString() ?? '') ?? 0;
}