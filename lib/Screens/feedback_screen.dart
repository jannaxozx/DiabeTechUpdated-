import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ── Palette — identical to dashboard ────────────────────────────────────────
const _fb_bg      = Color(0xFFF4F7F5);
const _fb_white   = Color(0xFFFFFFFF);
const _fb_green   = Color(0xFF2C6E49);
const _fb_greenLt = Color(0xFF4A9B6F);
const _fb_greenPal= Color(0xFFE8F5EE);
const _fb_red     = Color(0xFFD64045);
const _fb_redPal  = Color(0xFFFDECEC);
const _fb_amber   = Color(0xFFF09D18);
const _fb_amberPal= Color(0xFFFFF4E0);
const _fb_blue    = Color(0xFF2979C6);
const _fb_bluePal = Color(0xFFE8F0FB);
const _fb_teal    = Color(0xFF0D8A7C);
const _fb_tealPal = Color(0xFFE3F5F3);
const _fb_grey1   = Color(0xFF1A2E22);
const _fb_grey2   = Color(0xFF4D6357);
const _fb_grey3   = Color(0xFF8FA898);
const _fb_grey4   = Color(0xFFD5E2DA);
const _fb_grey5   = Color(0xFFF0F5F2);

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _msgCtrl   = TextEditingController();
  bool  _isSending = false;

  @override
  void initState() {
    super.initState();
    _backfillFeedback();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  // Backfill: copy any existing top-level feedback docs into user subcollection
  // so old feedback (before the dual-write fix) also shows up for the user
  Future<void> _backfillFeedback() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('feedback')
          .where('userId', isEqualTo: user.uid)
          .get();
      for (final doc in snap.docs) {
        final data = doc.data();
        final subRef = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('feedback')
            .doc(doc.id);
        final existing = await subRef.get();
        // Only write if not already there, or if reply changed
        final existingReply = existing.data()?['reply'] ?? '';
        final latestReply   = data['reply'] ?? '';
        if (!existing.exists || existingReply != latestReply) {
          await subRef.set({
            'feedbackId': doc.id,
            'message':    data['message']   ?? '',
            'timestamp':  data['timestamp'],
            'reply':      latestReply,
            'repliedAt':  data['repliedAt'],
          }, SetOptions(merge: true));
        }
      }
    } catch (e) {
      debugPrint('Backfill error: \$e');
    }
  }

  Future<void> _sendFeedback() async {
    final msg = _msgCtrl.text.trim();
    if (msg.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('⚠️ Please write a message before sending.'),
        backgroundColor: _fb_amber,
      ));
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isSending = true);
    try {
      // Fetch user name from Firestore
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final name = doc.data()?['name'] ?? user.displayName ?? 'User';

      // Write to top-level collection (admin reads from here)
      final feedbackRef = await FirebaseFirestore.instance
          .collection('feedback')
          .add({
        'userId':    user.uid,
        'userName':  name,
        'userEmail': user.email ?? '',
        'message':   msg,
        'timestamp': FieldValue.serverTimestamp(),
        'read':      false,
        'reply':     '',
        'repliedAt': null,
      });

      // Mirror to user's own subcollection (user reads from here — no index needed)
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('feedback')
          .doc(feedbackRef.id)   // same doc ID as top-level
          .set({
        'feedbackId': feedbackRef.id,
        'message':    msg,
        'timestamp':  FieldValue.serverTimestamp(),
        'reply':      '',
        'repliedAt':  null,
      });

      _msgCtrl.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✅ Feedback sent! Admin will review it soon.'),
        backgroundColor: _fb_green,
        duration: Duration(seconds: 3),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('❌ Failed to send: $e'),
        backgroundColor: _fb_red,
      ));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: _fb_bg,
      body: Column(children: [
        // ── Gradient header ───────────────────────────────────────────
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF2C6E49), Color(0xFF4A9B6F)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 16, 20),
              child: Row(children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: Colors.white, size: 18),
                ),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Feedback',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.1)),
                      Text('Send a message to admin',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 11)),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ),

        // ── Body ─────────────────────────────────────────────────────
        Expanded(
          child: user == null
              ? const Center(
                  child: Text('Please log in',
                      style: TextStyle(color: _fb_grey3)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // ── Send feedback card ─────────────────────────
                      _card(Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _cardTitle('Send Feedback',
                              Icons.feedback_rounded,
                              _fb_blue, _fb_bluePal),
                          const SizedBox(height: 4),
                          const Text(
                            'Share your thoughts, suggestions, or report issues.',
                            style: TextStyle(
                                fontSize: 11, color: _fb_grey3),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _msgCtrl,
                            maxLines: 5,
                            minLines: 3,
                            enabled: !_isSending,
                            style: const TextStyle(
                                color: _fb_grey1, fontSize: 14),
                            decoration: InputDecoration(
                              hintText:
                                  'Write your message here...',
                              hintStyle: const TextStyle(
                                  color: _fb_grey3, fontSize: 13),
                              filled: true,
                              fillColor:
                                  _isSending ? _fb_grey5 : _fb_white,
                              border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                      color: _fb_grey4)),
                              enabledBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                      color: _fb_grey4)),
                              focusedBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                      color: _fb_green, width: 1.5)),
                              contentPadding: const EdgeInsets.all(14),
                            ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed:
                                  _isSending ? null : _sendFeedback,
                              icon: _isSending
                                  ? const SizedBox(
                                      width: 16, height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white))
                                  : const Icon(Icons.send_rounded,
                                      color: Colors.white, size: 17),
                              label: Text(
                                _isSending ? 'Sending...' : 'Send Feedback',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    _isSending ? _fb_grey4 : _fb_green,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 13),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                            ),
                          ),
                        ],
                      )),
                      const SizedBox(height: 20),

                      // ── My past feedback ───────────────────────────
                      Row(children: [
                        const Expanded(
                          child: Text('My Feedback History',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: _fb_grey1)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: _fb_greenPal,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('Newest first',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: _fb_green,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ]),
                      const SizedBox(height: 10),

                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .doc(user.uid)
                            .collection('feedback')
                            .snapshots(),
                        builder: (context, snap) {
                          if (snap.connectionState ==
                              ConnectionState.waiting)
                            return const Center(
                                child: Padding(
                              padding: EdgeInsets.all(24),
                              child: CircularProgressIndicator(
                                  color: _fb_green),
                            ));

                          if (snap.hasError)
                            return _card(Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.inbox_rounded,
                                        size: 36, color: _fb_grey4),
                                    const SizedBox(height: 10),
                                    const Text('No feedback history yet',
                                        style: TextStyle(
                                            color: _fb_grey3, fontSize: 13)),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'Send a message above to get started.',
                                      style: TextStyle(
                                          color: _fb_grey3, fontSize: 11),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ));

                          // Sort newest first in Dart — no Firestore index needed
                          final docs = [...(snap.data?.docs ?? [])]
                            ..sort((a, b) {
                              final aTs = ((a.data() as Map)['timestamp'] as Timestamp?)?.toDate();
                              final bTs = ((b.data() as Map)['timestamp'] as Timestamp?)?.toDate();
                              if (aTs == null && bTs == null) return 0;
                              if (aTs == null) return 1;
                              if (bTs == null) return -1;
                              return bTs.compareTo(aTs);
                            });
                          if (docs.isEmpty)
                            return _card(const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                    vertical: 24),
                                child: Column(children: [
                                  Icon(Icons.inbox_rounded,
                                      size: 40, color: _fb_grey4),
                                  SizedBox(height: 10),
                                  Text('No feedback sent yet',
                                      style: TextStyle(
                                          color: _fb_grey3,
                                          fontSize: 13)),
                                ]),
                              ),
                            ));

                          return Column(
                            children: docs.map((doc) {
                              final d = doc.data()
                                  as Map<String, dynamic>;
                              final msg  = d['message'] ?? '';
                              final reply= d['reply']   ?? '';
                              final ts   = (d['timestamp'] as Timestamp?)?.toDate();
                              final rTs  = (d['repliedAt'] as Timestamp?)?.toDate();
                              final hasReply = reply.toString().trim().isNotEmpty;

                              // Mark reply as read when user sees it
                              if (hasReply) {
                                WidgetsBinding.instance.addPostFrameCallback(
                                    (_) => _markReplyRead(doc.id));
                              }

                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: _fb_white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: hasReply
                                      ? Border.all(
                                          color: _fb_green.withOpacity(0.3),
                                          width: 1.5)
                                      : null,
                                  boxShadow: [
                                    BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2)),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Header row
                                      Row(children: [
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                              color: _fb_bluePal,
                                              borderRadius:
                                                  BorderRadius.circular(8)),
                                          child: const Icon(
                                              Icons.person_rounded,
                                              color: _fb_blue, size: 14),
                                        ),
                                        const SizedBox(width: 8),
                                        const Text('Your message',
                                            style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: _fb_grey2)),
                                        const Spacer(),
                                        if (ts != null)
                                          Text(_formatDate(ts),
                                              style: const TextStyle(
                                                  fontSize: 10,
                                                  color: _fb_grey3)),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: hasReply
                                                ? _fb_greenPal
                                                : _fb_amberPal,
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            hasReply ? '✅ Replied' : '⏳ Pending',
                                            style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w700,
                                                color: hasReply
                                                    ? _fb_green
                                                    : _fb_amber),
                                          ),
                                        ),
                                      ]),
                                      const SizedBox(height: 10),

                                      // User message bubble
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: _fb_grey5,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Text(msg,
                                            style: const TextStyle(
                                                fontSize: 13,
                                                color: _fb_grey1,
                                                height: 1.5)),
                                      ),

                                      // Admin reply
                                      if (hasReply) ...[
                                        const SizedBox(height: 10),
                                        Divider(height: 1, color: _fb_grey4),
                                        const SizedBox(height: 10),
                                        Row(children: [
                                          Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                                color: _fb_greenPal,
                                                borderRadius:
                                                    BorderRadius.circular(8)),
                                            child: const Icon(
                                                Icons.admin_panel_settings_rounded,
                                                color: _fb_green, size: 14),
                                          ),
                                          const SizedBox(width: 8),
                                          const Text('Admin reply',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: _fb_green)),
                                          const Spacer(),
                                          if (rTs != null)
                                            Text(_formatDate(rTs),
                                                style: const TextStyle(
                                                    fontSize: 10,
                                                    color: _fb_grey3)),
                                        ]),
                                        const SizedBox(height: 8),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: _fb_greenPal,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: Border.all(
                                                color: _fb_green
                                                    .withOpacity(0.25)),
                                          ),
                                          child: Text(reply,
                                              style: const TextStyle(
                                                  fontSize: 13,
                                                  color: _fb_green,
                                                  height: 1.5)),
                                        ),
                                      ],
                                      const SizedBox(height: 10),
                                      Divider(height: 1, color: _fb_grey4),
                                      const SizedBox(height: 8),
                                      // Delete button
                                      SizedBox(
                                        width: double.infinity,
                                        child: OutlinedButton.icon(
                                          onPressed: () =>
                                              _deleteFeedback(doc.id, context),
                                          icon: const Icon(
                                              Icons.delete_outline_rounded,
                                              size: 15),
                                          label: const Text('Delete',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight:
                                                      FontWeight.w600)),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: _fb_red,
                                            side: BorderSide(
                                                color: _fb_red
                                                    .withOpacity(0.5)),
                                            backgroundColor: _fb_redPal,
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    vertical: 8),
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        10)),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
        ),
      ]),
    );
  }

  Widget _card(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _fb_white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2)),
          ],
        ),
        child: child,
      );

  Widget _cardTitle(String label, IconData icon,
      Color color, Color pal) =>
      Row(children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
              color: pal, borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, color: color, size: 15),
        ),
        const SizedBox(width: 10),
        Text(label,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _fb_grey1)),
      ]);

  Future<void> _deleteFeedback(String docId, BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.delete_forever_rounded, color: _fb_red, size: 22),
          SizedBox(width: 8),
          Text('Delete Feedback',
              style: TextStyle(color: _fb_red, fontWeight: FontWeight.w700)),
        ]),
        content: const Text(
          'Delete this feedback message? This cannot be undone.',
          style: TextStyle(color: _fb_grey2, fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: _fb_grey3))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _fb_red, elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      // User only deletes from their own subcollection (they can't touch top-level)
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('feedback')
          .doc(docId)
          .delete();

      // Mark the top-level doc as hidden so admin knows user removed it
      // (uses update — allowed by existing admin write rule via the user's own write path)
      try {
        await FirebaseFirestore.instance
            .collection('feedback')
            .doc(docId)
            .update({'hiddenByUser': true});
      } catch (_) {
        // Silently ignore — admin copy stays, no crash for user
      }

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Feedback deleted'),
          backgroundColor: _fb_green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Failed: $e'), backgroundColor: _fb_red),
      );
    }
  }

  // Mark a reply as seen so the badge clears
  Future<void> _markReplyRead(String docId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('feedback')
          .doc(docId)
          .update({'replyRead': true});
    } catch (_) {}
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m ${dt.hour >= 12 ? 'PM' : 'AM'}';
    }
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }
}