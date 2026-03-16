import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ── Palette (matches admin_dashboard) ────────────────────────────────────────
const _bg       = Color(0xFFF4F7F5);
const _white    = Color(0xFFFFFFFF);
const _green    = Color(0xFF2C6E49);
const _greenLt  = Color(0xFF4A9B6F);
const _greenPal = Color(0xFFE8F5EE);
const _red      = Color(0xFFD64045);
const _redPal   = Color(0xFFFDECEC);
const _amber    = Color(0xFFF09D18);
const _amberPal = Color(0xFFFFF4E0);
const _blue     = Color(0xFF2979C6);
const _bluePal  = Color(0xFFE8F0FB);
const _teal     = Color(0xFF0D8A7C);
const _tealPal  = Color(0xFFE3F5F3);
const _grey1    = Color(0xFF1A2E22);
const _grey2    = Color(0xFF4D6357);
const _grey3    = Color(0xFF8FA898);
const _grey4    = Color(0xFFD5E2DA);
const _grey5    = Color(0xFFF0F5F2);

class AdminFoodDetailScreen extends StatelessWidget {
  final String foodId;
  const AdminFoodDetailScreen({Key? key, required this.foodId})
      : super(key: key);

  // ── Helpers ────────────────────────────────────────────────────────────
  double _dbl(dynamic v) =>
      double.tryParse(v?.toString() ?? '') ?? 0;

  Color _hexColor(String hex) {
    try {
      final h = hex.replaceAll('#', '').trim();
      if (h.length == 6) return Color(int.parse('FF$h', radix: 16));
    } catch (_) {}
    return _grey3;
  }

  // ── Delete ────────────────────────────────────────────────────────────
  Future<void> _deleteFood(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.delete_rounded, color: _red, size: 20),
          SizedBox(width: 8),
          Text('Delete Food',
              style: TextStyle(
                  color: _red,
                  fontWeight: FontWeight.w700,
                  fontSize: 16)),
        ]),
        content: const Text(
          'Are you sure you want to delete this food item?\nThis cannot be undone.',
          style: TextStyle(fontSize: 13, color: _grey2, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: _grey3)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _red,
              foregroundColor: _white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true || !context.mounted) return;

    try {
      await FirebaseFirestore.instance
          .collection('food_rules')
          .doc(foodId)
          .delete();
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Food deleted successfully'),
          backgroundColor: _green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: _red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ));
      }
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_green, _greenLt],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 4,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Food Details',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
            Text('Food rule information',
                style: TextStyle(
                    color: Colors.white70, fontSize: 11)),
          ],
        ),
        actions: [
          InkWell(
            onTap: () => _deleteFood(context),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              margin: const EdgeInsets.only(right: 14),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.delete_rounded,
                  color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance
            .collection('food_rules')
            .doc(foodId)
            .get(),
        builder: (context, snap) {
          // Loading
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: _green));
          }
          // Not found
          if (!snap.hasData || !snap.data!.exists) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: _redPal, shape: BoxShape.circle),
                      child: const Icon(Icons.search_off_rounded,
                          color: _red, size: 32),
                    ),
                    const SizedBox(height: 14),
                    const Text('Food not found',
                        style: TextStyle(
                            color: _grey1,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    const Text('This item may have been deleted.',
                        style: TextStyle(
                            color: _grey3, fontSize: 12)),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 14),
                      label: const Text('Go Back'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        foregroundColor: _white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // Data
          final data     = snap.data!.data() as Map<String, dynamic>;
          final name     = (data['name']        ?? 'Unknown').toString();
          final category = (data['category']    ?? '').toString();
          final dtType   = (data['diabetesType'] ?? 'Mild').toString();
          final portion  = (data['portionSize'] ?? 'N/A').toString();
          final imageUrl = (data['imageUrl'] ?? data['imagePath'] ?? '').toString();
          final variety  = (data['variety']     ?? '').toString();
          final varColor = (data['varietyColor']?? '').toString();
          final cal   = _dbl(data['calories']);
          final carbs = _dbl(data['carbs']);
          final prot  = _dbl(data['protein']);
          final fat   = _dbl(data['fat']);

          final isGood = category == 'Do';
          final catC   = isGood ? _green : _red;
          final catPal = isGood ? _greenPal : _redPal;
          final dtC    = dtType == 'Severe' ? _red : _green;
          final dtPal  = dtType == 'Severe' ? _redPal : _greenPal;
          final total  = carbs + prot + fat;

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Header card: image + name + badges ────────────────
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Image
                      Container(
                        width: 64, height: 64,
                        decoration: BoxDecoration(
                          color: catPal,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: catC.withOpacity(0.2),
                              width: 1.5),
                        ),
                        child: imageUrl.isNotEmpty
                            ? ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(13),
                                child: Image.network(
                                  imageUrl,
                                  width: 64, height: 64,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      Icon(
                                          Icons
                                              .restaurant_rounded,
                                          size: 28,
                                          color: catC),
                                ))
                            : Icon(Icons.restaurant_rounded,
                                size: 28, color: catC),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: _grey1),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                            if (variety.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                if (varColor.isNotEmpty)
                                  Container(
                                    width: 8, height: 8,
                                    margin: const EdgeInsets.only(
                                        right: 4),
                                    decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color:
                                            _hexColor(varColor)),
                                  ),
                                Text(variety,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: _grey2,
                                        fontWeight:
                                            FontWeight.w500)),
                              ]),
                            ],
                            const SizedBox(height: 7),
                            Wrap(
                                spacing: 5,
                                runSpacing: 4,
                                children: [
                              _badge(
                                  isGood
                                      ? '✅ Recommended'
                                      : '❌ Avoid',
                                  catC,
                                  catPal),
                              _badge(
                                  '${dtType == 'Severe' ? '🔴' : '🟢'} $dtType',
                                  dtC,
                                  dtPal),
                            ]),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ── Nutrition per 100g ────────────────────────────────
                _sectionLabel('Nutrition per 100g'),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _nutChip(
                      '🔥', cal.toStringAsFixed(0), 'kcal',
                      _amber, _amberPal)),
                  const SizedBox(width: 8),
                  Expanded(child: _nutChip(
                      '🌾', carbs.toStringAsFixed(1), 'carbs',
                      _blue, _bluePal)),
                  const SizedBox(width: 8),
                  Expanded(child: _nutChip(
                      '💪', prot.toStringAsFixed(1), 'protein',
                      _green, _greenPal)),
                  const SizedBox(width: 8),
                  Expanded(child: _nutChip(
                      '🫙', fat.toStringAsFixed(1), 'fat',
                      _teal, _tealPal)),
                ]),
                const SizedBox(height: 14),

                // ── Food info rows ────────────────────────────────────
                _sectionLabel('Food Information'),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: _white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Column(children: [
                    _infoRow(Icons.scale_rounded,
                        _blue, 'Portion Size', portion),
                    Divider(height: 1, color: _grey4),
                    _infoRow(Icons.restaurant_menu_rounded,
                        catC, 'Category',
                        isGood
                            ? 'Recommended (Do)'
                            : "Avoid (Don't)"),
                    Divider(height: 1, color: _grey4),
                    _infoRow(Icons.health_and_safety_rounded,
                        dtC, 'Diabetes Type',
                        '$dtType Diabetes'),
                  ]),
                ),
                const SizedBox(height: 14),

                // ── Macro breakdown ───────────────────────────────────
                _sectionLabel('Macronutrient Breakdown'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Column(children: [
                    // Segmented bar
                    if (total > 0) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          height: 10,
                          child: Row(children: [
                            if (carbs > 0)
                              Flexible(
                                flex: (carbs * 100).toInt(),
                                child: Container(color: _blue),
                              ),
                            if (prot > 0)
                              Flexible(
                                flex: (prot * 100).toInt(),
                                child: Container(color: _green),
                              ),
                            if (fat > 0)
                              Flexible(
                                flex: (fat * 100).toInt(),
                                child: Container(color: _teal),
                              ),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Legend
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceAround,
                        children: [
                          _macroLegend('Carbs',   carbs, _blue),
                          _macroLegend('Protein', prot,  _green),
                          _macroLegend('Fat',     fat,   _teal),
                        ],
                      ),
                      Divider(height: 18, color: _grey4),
                    ],
                    _summaryRow('Total Macros',
                        '${total.toStringAsFixed(1)} g'),
                    const SizedBox(height: 6),
                    _summaryRow('Calories per 100g',
                        '${cal.toStringAsFixed(0)} kcal'),
                  ]),
                ),
                const SizedBox(height: 16),

                // ── Delete button ─────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _deleteFood(context),
                    icon: const Icon(Icons.delete_rounded,
                        size: 16),
                    label: const Text('Delete This Food',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _red,
                      side: const BorderSide(color: _red),
                      padding: const EdgeInsets.symmetric(
                          vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Component widgets ────────────────────────────────────────────────────

  Widget _sectionLabel(String text) => Text(text,
      style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: _grey1));

  Widget _badge(String label, Color color, Color pal) =>
      Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: pal,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.22)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color)),
      );

  Widget _nutChip(String emoji, String value, String unit,
      Color color, Color pal) =>
      Container(
        padding: const EdgeInsets.symmetric(
            vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: pal,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.15)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji,
                style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 3),
            Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: color,
                    height: 1.0)),
            Text(unit,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 9, color: _grey3)),
          ],
        ),
      );

  Widget _infoRow(IconData icon, Color color, String label,
      String value) =>
      Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 11),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
                color: color.withOpacity(0.09),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 15),
          ),
          const SizedBox(width: 12),
          Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  color: _grey2,
                  fontWeight: FontWeight.w500)),
          const Spacer(),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _grey1)),
          ),
        ]),
      );

  Widget _summaryRow(String label, String value) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: _grey2)),
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _grey1)),
        ],
      );

  Widget _macroLegend(String label, double val, Color color) =>
      Column(children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 8, height: 8,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: _grey2)),
        ]),
        const SizedBox(height: 2),
        Text('${val.toStringAsFixed(1)}g',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color)),
      ]);
}