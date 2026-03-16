import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:diabetechapp/Screens/add_food_log_screen.dart';

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
const _purp     = Color(0xFF7B5EA7);
const _purpPal  = Color(0xFFF0EBF8);
const _grey1    = Color(0xFF1A2E22);
const _grey2    = Color(0xFF4D6357);
const _grey3    = Color(0xFF8FA898);
const _grey4    = Color(0xFFD5E2DA);
const _grey5    = Color(0xFFF0F5F2);

class UserFoodLogScreen extends StatelessWidget {
  final String userId;
  final String userName;

  const UserFoodLogScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  // ── Helpers ─────────────────────────────────────────────────────────────

  double _dbl(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;

  String _mealColor(String meal) => meal;

  Color _mealAccent(String meal) {
    switch (meal.toLowerCase()) {
      case 'breakfast': return _amber;
      case 'lunch':     return _teal;
      case 'dinner':    return _blue;
      default:          return _purp;
    }
  }

  Color _mealPal(String meal) {
    switch (meal.toLowerCase()) {
      case 'breakfast': return _amberPal;
      case 'lunch':     return _tealPal;
      case 'dinner':    return _bluePal;
      default:          return _purpPal;
    }
  }

  Color _categoryColor(String cat) =>
      cat == 'Do' ? _green : cat == "Don't" ? _red : _grey3;

  Color _categoryPal(String cat) =>
      cat == 'Do' ? _greenPal : cat == "Don't" ? _redPal : _grey5;

  String _categoryLabel(String cat) =>
      cat == 'Do' ? '✅ Safe' : cat == "Don't" ? '❌ Avoid' : cat;

  // ── Delete log ──────────────────────────────────────────────────────────

  Future<void> _deleteLog(BuildContext context, String logId,
      String foodName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.delete_rounded, color: _red, size: 22),
          SizedBox(width: 8),
          Text('Delete Log',
              style: TextStyle(
                  color: _red, fontWeight: FontWeight.w700)),
        ]),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(
                fontSize: 14, color: _grey2, height: 1.5),
            children: [
              const TextSpan(text: 'Remove '),
              TextSpan(
                  text: '"$foodName"',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: _grey1)),
              const TextSpan(text: ' from the food log?'),
            ],
          ),
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true || !context.mounted) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('foodLogs')
        .doc(logId)
        .delete();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Food log deleted'),
        backgroundColor: _green,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ));
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      // ── Same gradient AppBar as dashboard ────────────────────────────
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              userName,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700),
            ),
            const Text(
              'Food Logs',
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),

      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('foodLogs')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          // ── Loading ──────────────────────────────────────────────────
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: _green));
          }

          // ── Error ────────────────────────────────────────────────────
          if (snapshot.hasError) {
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
                      child: const Icon(Icons.error_outline_rounded,
                          color: _red, size: 32),
                    ),
                    const SizedBox(height: 14),
                    Text('Failed to load logs',
                        style: const TextStyle(
                            color: _grey1,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text('${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: _grey3, fontSize: 12)),
                  ],
                ),
              ),
            );
          }

          final logs = snapshot.data?.docs ?? [];

          // ── Empty state ──────────────────────────────────────────────
          if (logs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                        color: _greenPal, shape: BoxShape.circle),
                    child: const Icon(Icons.restaurant_menu_rounded,
                        color: _green, size: 36),
                  ),
                  const SizedBox(height: 14),
                  const Text('No food logs yet',
                      style: TextStyle(
                          color: _grey1,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  const Text('This user has not logged any meals.',
                      style: TextStyle(color: _grey3, fontSize: 13)),
                ],
              ),
            );
          }

          // ── Group logs by date ───────────────────────────────────────
          final grouped = <String, List<QueryDocumentSnapshot>>{};
          for (final doc in logs) {
            final d    = doc.data() as Map<String, dynamic>? ?? {};
            final ts   = (d['timestamp'] as Timestamp?)?.toDate();
            final key  = ts != null
                ? DateFormat('EEEE, MMM d yyyy').format(ts)
                : 'Unknown Date';
            grouped.putIfAbsent(key, () => []).add(doc);
          }

          // ── Log count summary banner ─────────────────────────────────
          return Column(children: [
            _summaryBanner(logs.length),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: grouped.entries.map((entry) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Date header
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(0, 18, 0, 8),
                        child: Row(children: [
                          Container(
                            width: 4, height: 14,
                            decoration: BoxDecoration(
                                color: _green,
                                borderRadius:
                                    BorderRadius.circular(2)),
                          ),
                          const SizedBox(width: 8),
                          Text(entry.key,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: _grey2,
                                  letterSpacing: 0.3)),
                        ]),
                      ),
                      // Log cards for this date
                      ...entry.value.map((logDoc) {
                        final d = logDoc.data()
                            as Map<String, dynamic>? ?? {};
                        return _logCard(context, logDoc.id, d);
                      }).toList(),
                    ],
                  );
                }).toList(),
              ),
            ),
          ]);
        },
      ),
    );
  }

  // ── Summary banner ──────────────────────────────────────────────────────

  Widget _summaryBanner(int total) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
                color: _greenPal,
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.restaurant_rounded,
                color: _green, size: 18),
          ),
          const SizedBox(width: 12),
          RichText(
            text: TextSpan(
              style: const TextStyle(
                  fontSize: 13, color: _grey2),
              children: [
                TextSpan(
                  text: '$total ',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _green),
                ),
                const TextSpan(text: 'meal log'),
                TextSpan(text: total == 1 ? '' : 's'),
                const TextSpan(text: ' recorded'),
              ],
            ),
          ),
        ]),
      );

  // ── Individual log card ─────────────────────────────────────────────────

  Widget _logCard(BuildContext context, String logId,
      Map<String, dynamic> d) {
    // Data extraction — supports both old and new field names
    final foodName  = (d['foodName'] ?? d['food'] ?? 'Unknown Food')
        .toString();
    final variety   = (d['variety']  ?? '').toString();
    final mealType  = (d['mealType'] ?? '').toString();
    final category  = (d['category'] ?? '').toString();
    final portion   = (d['portionLabel'] ?? '').toString();
    final ts        = (d['timestamp'] as Timestamp?)?.toDate();
    final timeStr   = ts != null
        ? DateFormat('h:mm a').format(ts)
        : '';

    // Nutrition — nested map (new) or flat fields (old)
    final nutMap = d['nutrition'] as Map<String, dynamic>?;
    final cal  = nutMap != null ? _dbl(nutMap['calories'])
        : _dbl(d['calories']);
    final carbs = nutMap != null ? _dbl(nutMap['carbs'])
        : _dbl(d['carbs']);
    final prot  = nutMap != null ? _dbl(nutMap['protein'])
        : _dbl(d['protein']);
    final fat   = nutMap != null ? _dbl(nutMap['fat'])
        : _dbl(d['fat']);

    final mealC = mealType.isNotEmpty
        ? _mealAccent(mealType) : _purp;
    final mealP = mealType.isNotEmpty
        ? _mealPal(mealType) : _purpPal;
    final catC  = _categoryColor(category);
    final catP  = _categoryPal(category);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(children: [
        // ── Top section ───────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Meal type icon
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: mealP,
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(
                  _mealIcon(mealType),
                  color: mealC,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Food name + variety
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          variety.isNotEmpty
                              ? '$foodName ($variety)' : foodName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: _grey1),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  // Badges row
                  Wrap(spacing: 5, runSpacing: 4, children: [
                    if (mealType.isNotEmpty)
                      _badge(mealType, mealC, mealP),
                    if (category.isNotEmpty)
                      _badge(_categoryLabel(category), catC, catP),
                    if (portion.isNotEmpty)
                      _badge(portion, _grey2, _grey5),
                  ]),
                ],
              )),
              // Time + menu
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (timeStr.isNotEmpty)
                    Text(timeStr,
                        style: const TextStyle(
                            fontSize: 11, color: _grey3)),
                  const SizedBox(height: 4),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded,
                        color: _grey3, size: 20),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    onSelected: (value) {
                      if (value == 'delete') {
                        _deleteLog(context, logId, foodName);
                      } else if (value == 'edit') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AddFoodLogScreen(
                              userId: userId,
                              userName: userName,
                              logId: logId,
                              existingData: d,
                            ),
                          ),
                        );
                      }
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                                color: _amberPal,
                                borderRadius:
                                    BorderRadius.circular(7)),
                            child: const Icon(
                                Icons.edit_rounded,
                                size: 14, color: _amber),
                          ),
                          const SizedBox(width: 10),
                          const Text('Edit Log'),
                        ]),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                                color: _redPal,
                                borderRadius:
                                    BorderRadius.circular(7)),
                            child: const Icon(
                                Icons.delete_rounded,
                                size: 14, color: _red),
                          ),
                          const SizedBox(width: 10),
                          const Text('Delete',
                              style: TextStyle(color: _red)),
                        ]),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),

        // ── Nutrition chips ───────────────────────────────────────────
        if (cal > 0 || carbs > 0 || prot > 0 || fat > 0)
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: _grey4)),
            ),
            child: Row(children: [
              if (cal > 0)
                Expanded(child: _nutChip(
                    '🔥', cal.toStringAsFixed(0), 'kcal',
                    _amber, _amberPal)),
              if (carbs > 0)
                Expanded(child: _nutChip(
                    '🌾', carbs.toStringAsFixed(1), 'g carbs',
                    _blue, _bluePal)),
              if (prot > 0)
                Expanded(child: _nutChip(
                    '💪', prot.toStringAsFixed(1), 'g protein',
                    _green, _greenPal)),
              if (fat > 0)
                Expanded(child: _nutChip(
                    '🫙', fat.toStringAsFixed(1), 'g fat',
                    _teal, _tealPal)),
            ]),
          ),
      ]),
    );
  }

  // ── Sub-widgets ─────────────────────────────────────────────────────────

  Widget _badge(String label, Color color, Color pal) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: pal,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color)),
      );

  Widget _nutChip(String emoji, String value, String unit,
      Color color, Color pal) =>
      Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(
            horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
            color: pal, borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: color,
                  height: 1.0)),
          Text(unit,
              style: const TextStyle(
                  fontSize: 9, color: _grey3)),
        ]),
      );

  IconData _mealIcon(String meal) {
    switch (meal.toLowerCase()) {
      case 'breakfast': return Icons.wb_sunny_rounded;
      case 'lunch':     return Icons.wb_cloudy_rounded;
      case 'dinner':    return Icons.nights_stay_rounded;
      default:          return Icons.restaurant_rounded;
    }
  }
}