import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AddFoodLogScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final String? logId;
  final Map<String, dynamic>? existingData;

  const AddFoodLogScreen({
    super.key,
    required this.userId,
    required this.userName,
    this.logId,
    this.existingData,
  });

  @override
  State<AddFoodLogScreen> createState() => _AddFoodLogScreenState();
}

class _AddFoodLogScreenState extends State<AddFoodLogScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _foodController;
  late TextEditingController _caloriesController;
  late TextEditingController _carbsController;
  late TextEditingController _proteinController;
  late TextEditingController _fatController;

  @override
  void initState() {
    super.initState();

    _foodController =
        TextEditingController(text: widget.existingData?['food'] ?? '');
    _caloriesController = TextEditingController(
        text: widget.existingData?['calories']?.toString() ?? '');
    _carbsController = TextEditingController(
        text: widget.existingData?['carbs']?.toString() ?? '');
    _proteinController = TextEditingController(
        text: widget.existingData?['protein']?.toString() ?? '');
    _fatController = TextEditingController(
        text: widget.existingData?['fat']?.toString() ?? '');
  }

  @override
  void dispose() {
    _foodController.dispose();
    _caloriesController.dispose();
    _carbsController.dispose();
    _proteinController.dispose();
    _fatController.dispose();
    super.dispose();
  }

  Future<void> _saveLog() async {
    if (!_formKey.currentState!.validate()) return;

    final logData = {
      'food': _foodController.text.trim(),
      'calories': int.tryParse(_caloriesController.text) ?? 0,
      'carbs': double.tryParse(_carbsController.text) ?? 0,
      'protein': double.tryParse(_proteinController.text) ?? 0,
      'fat': double.tryParse(_fatController.text) ?? 0,
      'timestamp': FieldValue.serverTimestamp(),
    };

    final logsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .collection('foodLogs');

    if (widget.logId != null) {
      // Update existing log
      await logsRef.doc(widget.logId).update(logData);
    } else {
      // Add new log
      await logsRef.add(logData);
    }

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              widget.logId != null ? 'Food log updated!' : 'Food log added!'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.logId != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Food Log' : 'Add Food Log'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _foodController,
                decoration: const InputDecoration(labelText: 'Food Name'),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Enter food name' : null,
              ),
              TextFormField(
                controller: _caloriesController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Calories (kcal)'),
              ),
              TextFormField(
                controller: _carbsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Carbs (g)'),
              ),
              TextFormField(
                controller: _proteinController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Protein (g)'),
              ),
              TextFormField(
                controller: _fatController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Fat (g)'),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saveLog,
                child: Text(isEditing ? 'Update Log' : 'Add Log'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

