import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ── Palette ────────────────────────────────────────────────────────────────
const _bg = Color(0xFFF4F7F5); // soft off-white background
const _white = Color(0xFFFFFFFF);
const _green = Color(0xFF2C6E49); // primary brand green
const _greenLt = Color(0xFF4A9B6F);
const _greenPal = Color(0xFFE8F5EE); // green tint bg
const _red = Color(0xFFD64045);
const _redPal = Color(0xFFFDECEC);
const _amber = Color(0xFFF09D18);
const _amberPal = Color(0xFFFFF4E0);
const _blue = Color(0xFF2979C6);
const _bluePal = Color(0xFFE8F0FB);
const _teal = Color(0xFF0D8A7C);
const _tealPal = Color(0xFFE3F5F3);
const _grey1 = Color(0xFF1A2E22); // heading text
const _grey2 = Color(0xFF4D6357); // body text
const _grey3 = Color(0xFF8FA898); // muted text
const _grey4 = Color(0xFFD5E2DA); // dividers / borders
const _grey5 = Color(0xFFF0F5F2); // subtle chip bg

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({Key? key}) : super(key: key);

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  bool _loading = true;
  String? _error;

  // ── Data ───────────────────────────────────────────────────────────────
  int _totalUsers = 0, _mildUsers = 0, _severeUsers = 0, _otherUsers = 0;
  Map<String, int> _activityDist = {};

  int _totalFoods = 0, _doFoods = 0, _dontFoods = 0;
  int _mildFoods = 0, _severeFoods = 0;

  int _totalLogs = 0;
  double _avgCal = 0, _avgCarbs = 0, _avgProtein = 0, _avgFat = 0;
  Map<String, int> _mealTypeDist = {};
  Map<String, int> _topFoodsLogged = {};
  Map<String, int> _logsPerDay = {};

  int _totalScans = 0, _safeScans = 0, _avoidScans = 0, _unknownScans = 0;
  Map<String, int> _topFoodsScanned = {};
  Map<String, int> _scansPerDay = {};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _fetchAll();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // ── Master fetch ───────────────────────────────────────────────────────
  Future<void> _fetchAll() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Future.wait([_fUsers(), _fFoods(), _fLogs(), _fScans()]);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fUsers() async {
    final s =
        await FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'user')
            .get();
    int mild = 0, severe = 0, other = 0;
    final act = <String, int>{};
    for (final doc in s.docs) {
      final d = doc.data() as Map<String, dynamic>? ?? {};
      final dt = (d['diabetesType'] ?? '').toString();
      if (dt == 'Mild')
        mild++;
      else if (dt == 'Severe')
        severe++;
      else
        other++;
      final al = (d['activityLevel'] ?? 'Not Set').toString();
      act[al] = (act[al] ?? 0) + 1;
    }
    if (mounted)
      setState(() {
        _totalUsers = s.docs.length;
        _mildUsers = mild;
        _severeUsers = severe;
        _otherUsers = other;
        _activityDist = act;
      });
  }

  Future<void> _fFoods() async {
    final s = await FirebaseFirestore.instance.collection('food_rules').get();
    int doC = 0, dontC = 0, mildC = 0, sevC = 0;

    for (final doc in s.docs) {
      final d = doc.data() as Map<String, dynamic>? ?? {};

      // BACKWARD COMPATIBLE: Check both old and new structure

      // Check suitableFor array (NEW) or diabetesType string (OLD)
      final suitableFor = (d['suitableFor'] as List?)?.cast<String>() ?? [];
      if (suitableFor.isNotEmpty) {
        // NEW STRUCTURE
        if (suitableFor.contains('Mild')) mildC++;
        if (suitableFor.contains('Severe')) sevC++;
      } else {
        // OLD STRUCTURE
        final dt = (d['diabetesType'] ?? '').toString();
        if (dt == 'Mild')
          mildC++;
        else if (dt == 'Severe')
          sevC++;
      }

      // Check categories map (NEW) or category string (OLD)
      final categories = d['categories'] as Map<String, dynamic>? ?? {};
      if (categories.isNotEmpty) {
        // NEW STRUCTURE - count if ANY type has Do/Don't
        bool hasDo = false;
        bool hasDont = false;
        for (var cat in categories.values) {
          if (cat == 'Do') hasDo = true;
          if (cat == "Don't") hasDont = true;
        }
        if (hasDo) doC++;
        if (hasDont) dontC++;
      } else {
        // OLD STRUCTURE
        final cat = (d['category'] ?? '').toString();
        if (cat == 'Do')
          doC++;
        else if (cat == "Don't")
          dontC++;
      }
    }

    if (mounted)
      setState(() {
        _totalFoods = s.docs.length;
        _doFoods = doC;
        _dontFoods = dontC;
        _mildFoods = mildC;
        _severeFoods = sevC;
      });
  }

  Future<void> _fLogs() async {
    final s =
        await FirebaseFirestore.instance
            .collectionGroup('foodLogs')
            .limit(500)
            .get();
    double tCal = 0, tCarbs = 0, tProt = 0, tFat = 0;
    final meal = <String, int>{}, food = <String, int>{}, day = <String, int>{};
    final now = DateTime.now();
    final week = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 6));
    for (int i = 0; i < 7; i++) day[_dk(week.add(Duration(days: i)))] = 0;
    for (final doc in s.docs) {
      final d = doc.data() as Map<String, dynamic>? ?? {};
      final n = (d['nutrition'] as Map<String, dynamic>?) ?? {};
      tCal += _dbl(n['calories']);
      tCarbs += _dbl(n['carbs']);
      tProt += _dbl(n['protein']);
      tFat += _dbl(n['fat']);
      final mt = (d['mealType'] ?? 'Other').toString();
      meal[mt] = (meal[mt] ?? 0) + 1;
      final fn = (d['foodName'] ?? 'Unknown').toString();
      food[fn] = (food[fn] ?? 0) + 1;
      final ts = (d['timestamp'] as Timestamp?)?.toDate();
      if (ts != null && !ts.isBefore(week)) {
        final k = _dk(ts);
        day[k] = (day[k] ?? 0) + 1;
      }
    }
    final top5 = Map.fromEntries(
      (food.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(
        5,
      ),
    );
    final c = s.docs.length;
    if (mounted)
      setState(() {
        _totalLogs = c;
        _avgCal = c > 0 ? tCal / c : 0;
        _avgCarbs = c > 0 ? tCarbs / c : 0;
        _avgProtein = c > 0 ? tProt / c : 0;
        _avgFat = c > 0 ? tFat / c : 0;
        _mealTypeDist = meal;
        _topFoodsLogged = top5;
        _logsPerDay = day;
      });
  }

  Future<void> _fScans() async {
    final s =
        await FirebaseFirestore.instance
            .collectionGroup('scanned_foods')
            .limit(500)
            .get();
    int safe = 0, avoid = 0, unk = 0;
    final food = <String, int>{}, day = <String, int>{};
    final now = DateTime.now();
    final week = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 6));
    for (int i = 0; i < 7; i++) day[_dk(week.add(Duration(days: i)))] = 0;
    for (final doc in s.docs) {
      final d = doc.data() as Map<String, dynamic>? ?? {};
      final cat = (d['category'] ?? 'unknown').toString();
      if (cat == 'do')
        safe++;
      else if (cat == 'dont')
        avoid++;
      else
        unk++;
      final fn = (d['food'] ?? d['foodName'] ?? '').toString().trim();
      if (fn.isNotEmpty && fn.toLowerCase() != 'unknown')
        food[fn] = (food[fn] ?? 0) + 1;
      final ts = (d['timestamp'] as Timestamp?)?.toDate();
      if (ts != null && !ts.isBefore(week)) {
        final k = _dk(ts);
        day[k] = (day[k] ?? 0) + 1;
      }
    }
    final top5 = Map.fromEntries(
      (food.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(
        5,
      ),
    );
    if (mounted)
      setState(() {
        _totalScans = s.docs.length;
        _safeScans = safe;
        _avoidScans = avoid;
        _unknownScans = unk;
        _topFoodsScanned = top5;
        _scansPerDay = day;
      });
  }

  // ── Util ───────────────────────────────────────────────────────────────
  double _dbl(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;
  String _dk(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  String _pct(int n, int t) =>
      t > 0 ? '${(n / t * 100).toStringAsFixed(1)}%' : '0%';
  String _cap(String t) => t
      .split(' ')
      .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
      .join(' ');

  // ═══════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          _header(),
          Expanded(
            child:
                _loading
                    ? const Center(
                      child: CircularProgressIndicator(color: _green),
                    )
                    : _error != null
                    ? _errorView()
                    : TabBarView(
                      controller: _tabs,
                      children: [
                        _usersTab(),
                        _foodsTab(),
                        _logsTab(),
                        _scansTab(),
                      ],
                    ),
          ),
        ],
      ),
    );
  }

  // ── Header with gradient ───────────────────────────────────────────────
  Widget _header() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2C6E49), Color(0xFF4A9B6F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
              child: Row(
                children: [
                  const Icon(
                    Icons.bar_chart_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Analytics & Reports',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.1,
                          ),
                        ),
                        Text(
                          'DiabeTech Admin Dashboard',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  _loading
                      ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                      : InkWell(
                        onTap: _fetchAll,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.refresh_rounded,
                            color: Colors.white,
                            size: 17,
                          ),
                        ),
                      ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TabBar(
              controller: _tabs,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              indicatorSize: TabBarIndicatorSize.label,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              labelStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              tabs: const [
                Tab(
                  icon: Icon(Icons.people_alt_rounded, size: 17),
                  text: 'Users',
                ),
                Tab(
                  icon: Icon(Icons.restaurant_menu_rounded, size: 17),
                  text: 'Foods',
                ),
                Tab(
                  icon: Icon(Icons.edit_note_rounded, size: 17),
                  text: 'Logs',
                ),
                Tab(
                  icon: Icon(Icons.qr_code_scanner_rounded, size: 17),
                  text: 'Scans',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Error ──────────────────────────────────────────────────────────────
  Widget _errorView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: _redPal, shape: BoxShape.circle),
            child: const Icon(
              Icons.error_outline_rounded,
              color: _red,
              size: 36,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Failed to load reports',
            style: TextStyle(
              color: _grey1,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _grey3, fontSize: 12),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _fetchAll,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Try Again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    ),
  );

  // ═══════════════════════════════════════════════════════════════════════
  // TAB 1 — USERS
  // ═══════════════════════════════════════════════════════════════════════
  Widget _usersTab() => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // KPI row
        Row(
          children: [
            Expanded(
              child: _kpi(
                'Total Users',
                '$_totalUsers',
                Icons.people_alt_rounded,
                _blue,
                _bluePal,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _kpi(
                'Mild',
                '$_mildUsers',
                Icons.health_and_safety_rounded,
                _green,
                _greenPal,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _kpi(
                'Severe',
                '$_severeUsers',
                Icons.warning_amber_rounded,
                _red,
                _redPal,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        _sectionLabel('Diabetes Type Distribution'),
        const SizedBox(height: 10),
        _card(
          Column(
            children: [
              _hBar('Mild', _mildUsers, _totalUsers, _green),
              const SizedBox(height: 16),
              _hBar('Severe', _severeUsers, _totalUsers, _red),
              if (_otherUsers > 0) ...[
                const SizedBox(height: 16),
                _hBar('Not Set', _otherUsers, _totalUsers, _grey3),
              ],
              const SizedBox(height: 14),
              _legendRow([
                _dot(_green, 'Mild  ${_pct(_mildUsers, _totalUsers)}'),
                _dot(_red, 'Severe ${_pct(_severeUsers, _totalUsers)}'),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 20),

        _sectionLabel('Activity Level Distribution'),
        const SizedBox(height: 10),
        _card(
          _activityDist.isEmpty
              ? _empty()
              : Column(
                children: [
                  ..._activityDist.entries
                      .map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _hBar(
                            e.key,
                            e.value,
                            _totalUsers,
                            _actColor(e.key),
                          ),
                        ),
                      )
                      .toList(),
                ],
              ),
        ),
        const SizedBox(height: 8),
      ],
    ),
  );

  // ═══════════════════════════════════════════════════════════════════════
  // TAB 2 — FOODS
  // ═══════════════════════════════════════════════════════════════════════
  Widget _foodsTab() => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _kpi(
                'Total',
                '$_totalFoods',
                Icons.restaurant_menu_rounded,
                _teal,
                _tealPal,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _kpi(
                'Safe',
                '$_doFoods',
                Icons.check_circle_rounded,
                _green,
                _greenPal,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _kpi(
                'Avoid',
                '$_dontFoods',
                Icons.cancel_rounded,
                _red,
                _redPal,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        _sectionLabel('Category Distribution'),
        const SizedBox(height: 10),
        _card(
          Column(
            children: [
              _hBar('Recommended (Do)', _doFoods, _totalFoods, _green),
              const SizedBox(height: 16),
              _hBar("Avoid (Don't)", _dontFoods, _totalFoods, _red),
              const SizedBox(height: 14),
              _legendRow([
                _dot(_green, 'Do   ${_pct(_doFoods, _totalFoods)}'),
                _dot(_red, "Don't ${_pct(_dontFoods, _totalFoods)}"),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 20),

        _sectionLabel('Coverage by Diabetes Type'),
        const SizedBox(height: 10),
        _card(
          Column(
            children: [
              _hBar('Mild Diabetes', _mildFoods, _totalFoods, _green),
              const SizedBox(height: 16),
              _hBar('Severe Diabetes', _severeFoods, _totalFoods, _red),
              const SizedBox(height: 14),
              _legendRow([
                _dot(_green, 'Mild   ${_pct(_mildFoods, _totalFoods)}'),
                _dot(_red, 'Severe ${_pct(_severeFoods, _totalFoods)}'),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 20),

        _sectionLabel('Database Summary'),
        const SizedBox(height: 10),
        _card(
          Column(
            children: [
              _sRow(
                Icons.restaurant_menu_rounded,
                _teal,
                'Total food items',
                '$_totalFoods',
              ),
              _divider(),
              _sRow(
                Icons.check_circle_rounded,
                _green,
                'Recommended foods',
                '$_doFoods',
              ),
              _divider(),
              _sRow(
                Icons.cancel_rounded,
                _red,
                'Foods to avoid',
                '$_dontFoods',
              ),
              _divider(),
              _sRow(
                Icons.health_and_safety_rounded,
                _green,
                'Mild coverage',
                '$_mildFoods items',
              ),
              _divider(),
              _sRow(
                Icons.warning_amber_rounded,
                _red,
                'Severe coverage',
                '$_severeFoods items',
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    ),
  );

  // ═══════════════════════════════════════════════════════════════════════
  // TAB 3 — LOGS
  // ═══════════════════════════════════════════════════════════════════════
  Widget _logsTab() {
    final days = _logsPerDay.keys.toList()..sort();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero total
          _totalBanner(
            _totalLogs,
            'Total Meal Logs',
            Icons.edit_note_rounded,
            _green,
            _greenPal,
          ),
          const SizedBox(height: 20),

          _sectionLabel('Average Nutrition Per Log'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _nutCard(
                  'Calories',
                  _avgCal.toStringAsFixed(0),
                  'kcal',
                  Icons.local_fire_department_rounded,
                  _amber,
                  _amberPal,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _nutCard(
                  'Carbs',
                  _avgCarbs.toStringAsFixed(1),
                  'g',
                  Icons.grain_rounded,
                  _blue,
                  _bluePal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _nutCard(
                  'Protein',
                  _avgProtein.toStringAsFixed(1),
                  'g',
                  Icons.fitness_center_rounded,
                  _green,
                  _greenPal,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _nutCard(
                  'Fat',
                  _avgFat.toStringAsFixed(1),
                  'g',
                  Icons.opacity_rounded,
                  _red,
                  _redPal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          _sectionLabel('Meal Type Breakdown'),
          const SizedBox(height: 10),
          _card(
            _mealTypeDist.isEmpty
                ? _empty()
                : Column(
                  children: [
                    ..._mealTypeDist.entries
                        .map(
                          (e) => Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _hBar(
                              e.key,
                              e.value,
                              _totalLogs,
                              _mealColor(e.key),
                            ),
                          ),
                        )
                        .toList(),
                  ],
                ),
          ),
          const SizedBox(height: 20),

          _sectionLabel('Top 5 Most Logged Foods'),
          const SizedBox(height: 10),
          _card(
            _topFoodsLogged.isEmpty
                ? _empty()
                : Column(
                  children: () {
                    final e = _topFoodsLogged.entries.toList();
                    return List.generate(
                      e.length,
                      (i) => _rankRow(
                        i + 1,
                        e[i].key,
                        e[i].value,
                        _totalLogs,
                        _amber,
                      ),
                    );
                  }(),
                ),
          ),
          const SizedBox(height: 20),

          _sectionLabel('Activity — Last 7 Days'),
          const SizedBox(height: 10),
          _card(days.isEmpty ? _empty() : _barChart(days, _logsPerDay, _green)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TAB 4 — SCANS
  // ═══════════════════════════════════════════════════════════════════════
  Widget _scansTab() {
    final days = _scansPerDay.keys.toList()..sort();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _kpi(
                  'Total',
                  '${_safeScans + _avoidScans}',
                  Icons.qr_code_scanner_rounded,
                  _teal,
                  _tealPal,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _kpi(
                  'Safe',
                  '$_safeScans',
                  Icons.check_circle_rounded,
                  _green,
                  _greenPal,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _kpi(
                  'Avoided',
                  '$_avoidScans',
                  Icons.cancel_rounded,
                  _red,
                  _redPal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          _sectionLabel('Scan Result Breakdown'),
          const SizedBox(height: 10),
          _card(
            Column(
              children: [
                _hBar(
                  'Safe (Do)',
                  _safeScans,
                  _safeScans + _avoidScans,
                  _green,
                ),
                const SizedBox(height: 16),
                _hBar(
                  "Avoid (Don't)",
                  _avoidScans,
                  _safeScans + _avoidScans,
                  _red,
                ),
                const SizedBox(height: 14),
                _legendRow([
                  _dot(
                    _green,
                    'Safe    ${_pct(_safeScans, _safeScans + _avoidScans)}',
                  ),
                  _dot(
                    _red,
                    'Avoid   ${_pct(_avoidScans, _safeScans + _avoidScans)}',
                  ),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 20),

          _sectionLabel('Top 5 Most Scanned Foods'),
          const SizedBox(height: 10),
          _card(() {
            final filtered =
                _topFoodsScanned.entries
                    .where((e) => e.key.toLowerCase() != 'unknown')
                    .toList();
            if (filtered.isEmpty) return _empty();
            return Column(
              children: List.generate(
                filtered.length,
                (i) => _rankRow(
                  i + 1,
                  filtered[i].key,
                  filtered[i].value,
                  _safeScans + _avoidScans,
                  _teal,
                ),
              ),
            );
          }()),
          const SizedBox(height: 20),

          _sectionLabel('Activity — Last 7 Days'),
          const SizedBox(height: 10),
          _card(days.isEmpty ? _empty() : _barChart(days, _scansPerDay, _teal)),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SHARED COMPONENTS
  // ═══════════════════════════════════════════════════════════════════════

  /// Section label
  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(
      color: _grey1,
      fontSize: 15,
      fontWeight: FontWeight.w700,
    ),
  );

  /// White card
  Widget _card(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: _white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: child,
  );

  /// KPI stat card
  Widget _kpi(
    String label,
    String value,
    IconData icon,
    Color color,
    Color palColor,
  ) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: palColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(height: 10),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(
            color: _grey3,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ),
  );

  /// Hero total banner (Logs tab)
  Widget _totalBanner(
    int total,
    String label,
    IconData icon,
    Color color,
    Color palColor,
  ) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: _white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: palColor,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$total',
              style: TextStyle(
                color: color,
                fontSize: 36,
                fontWeight: FontWeight.w800,
                height: 1.0,
              ),
            ),
            Text(label, style: const TextStyle(color: _grey3, fontSize: 13)),
          ],
        ),
      ],
    ),
  );

  /// Nutrition avg card
  Widget _nutCard(
    String label,
    String value,
    String unit,
    IconData icon,
    Color color,
    Color palColor,
  ) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: palColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 3, bottom: 1),
                  child: Text(
                    unit,
                    style: const TextStyle(color: _grey3, fontSize: 11),
                  ),
                ),
              ],
            ),
            Text(
              'Avg $label',
              style: const TextStyle(color: _grey3, fontSize: 11),
            ),
          ],
        ),
      ],
    ),
  );

  /// Horizontal bar
  Widget _hBar(String label, int value, int total, Color color) {
    final pct = (total > 0 ? value / total : 0.0).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: _grey1,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$value',
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _pct(value, total),
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Stack(
          children: [
            Container(
              height: 8,
              decoration: BoxDecoration(
                color: _grey4,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            FractionallySizedBox(
              widthFactor: pct,
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Rank row — top foods leaderboard
  Widget _rankRow(int rank, String name, int count, int total, Color color) {
    final medals = {1: '🥇', 2: '🥈', 3: '🥉'};
    final pct = (total > 0 ? count / total : 0.0).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              medals[rank] ?? '$rank.',
              style: const TextStyle(fontSize: 17),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _cap(name),
                  style: const TextStyle(
                    color: _grey1,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 5),
                Stack(
                  children: [
                    Container(
                      height: 5,
                      decoration: BoxDecoration(
                        color: _grey4,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: pct,
                      child: Container(
                        height: 5,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$count',
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                _pct(count, total),
                style: const TextStyle(color: _grey3, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Bar chart — last 7 days
  Widget _barChart(List<String> days, Map<String, int> data, Color color) {
    final maxVal = data.values.fold(0, (a, b) => a > b ? a : b).toDouble();
    return Column(
      children: [
        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children:
                days.map((day) {
                  final val = (data[day] ?? 0).toDouble();
                  final barH = maxVal > 0 ? (val / maxVal) * 90 : 0.0;
                  final isMax = val > 0 && val == maxVal;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (val > 0)
                            Text(
                              '${val.toInt()}',
                              style: TextStyle(
                                fontSize: 9,
                                color: isMax ? color : _grey3,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          const SizedBox(height: 4),
                          Container(
                            height: barH > 0 ? barH : 6,
                            decoration: BoxDecoration(
                              color:
                                  barH > 0
                                      ? (isMax
                                          ? color
                                          : color.withOpacity(0.35))
                                      : _grey4,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children:
              days
                  .map(
                    (day) => Expanded(
                      child: Text(
                        day,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 9, color: _grey3),
                      ),
                    ),
                  )
                  .toList(),
        ),
      ],
    );
  }

  /// Summary stat row
  Widget _sRow(IconData icon, Color color, String label, String value) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: _grey2, fontSize: 13),
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                color: _grey1,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );

  Widget _divider() => Divider(height: 1, color: _grey4);

  Widget _legendRow(List<Widget> items) =>
      Wrap(spacing: 18, runSpacing: 8, children: items);

  Widget _dot(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 11, color: _grey2)),
    ],
  );

  Widget _empty() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 20),
    child: Center(
      child: Text(
        'No data available yet',
        style: TextStyle(color: _grey3, fontSize: 13),
      ),
    ),
  );

  Color _actColor(String level) {
    switch (level) {
      case 'Sedentary':
        return _grey3;
      case 'Light':
        return _green;
      case 'Very Active':
        return _red;
      default:
        return _grey2;
    }
  }

  Color _mealColor(String meal) {
    switch (meal) {
      case 'Breakfast':
        return _amber;
      case 'Lunch':
        return _teal;
      case 'Dinner':
        return _blue;
      default:
        return _grey3;
    }
  }
}
