import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_state.dart';
import 'nutrition_service_api.dart';

void main() {
  runApp(const FitnessApp());
}

class FitnessApp extends StatelessWidget {
  const FitnessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.teal,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.grey.shade100,
      ),
      home: const CalorieTrackerHome(),
    );
  }
}

class CalorieTrackerHome extends StatefulWidget {
  const CalorieTrackerHome({super.key});

  @override
  State<CalorieTrackerHome> createState() => _CalorieTrackerHomeState();
}

class _CalorieTrackerHomeState extends State<CalorieTrackerHome> {
  int calorieGoal = 2100;
  int proteinGoal = 150;
  int carbsGoal = 300;
  int fatGoal = 70;
  List<Map<String, dynamic>> foodLog = [];

  double totalCalories = 0;
  double totalProtein = 0;
  double totalCarbs = 0;
  double totalFat = 0;

  bool _isLoading = false;
  String selectedCategory = 'Select Meal Type';
  int? editingIndex;

  // Global Error States
  bool dropdownError = false;
  bool qtyError = false;
  bool nameError = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      calorieGoal = prefs.getInt('calorie_goal') ?? 2500;
      proteinGoal = prefs.getInt('protein_goal') ?? 150;
      carbsGoal = prefs.getInt('carbs_goal') ?? 300;
      fatGoal = prefs.getInt('fat_goal') ?? 70;

      final List<String>? savedList = prefs.getStringList('food_log_${AppState.dateKey}');
      if (savedList != null) {
        foodLog = savedList.map((item) => jsonDecode(item) as Map<String, dynamic>).toList();
      } else {
        foodLog = [];
      }
      _calculateTotals();
    });
  }

  void _calculateTotals() {
    totalCalories = 0; totalProtein = 0; totalCarbs = 0; totalFat = 0;
    for (var item in foodLog) {
      totalCalories += item['calories'] ?? 0;
      totalProtein += item['protein'] ?? 0;
      totalCarbs += item['carbs'] ?? 0;
      totalFat += item['fat'] ?? 0;
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> listToSave = foodLog.map((item) => jsonEncode(item)).toList();
    await prefs.setStringList('food_log_${AppState.dateKey}', listToSave);
  }

  Future<void> _deleteItem(int index) async {
    setState(() { foodLog.removeAt(index); _calculateTotals(); });
    await _saveData();
  }

  // UPDATED PROCESS LOGIC
  Future<void> _processNutrition(Function modalSetState) async {
    modalSetState(() {
      dropdownError = selectedCategory == 'Select Meal Type';
      qtyError = AppState.qtyController.text.isEmpty;
      nameError = AppState.nameController.text.isEmpty;
    });

    if (dropdownError || qtyError || nameError) return;

    Navigator.pop(context);
    setState(() => _isLoading = true);

    String rawQty = AppState.qtyController.text.trim();
    String finalQty = double.tryParse(rawQty) != null ? "${rawQty}g" : rawQty;
    String query = "$finalQty ${AppState.nameController.text}";

    try {
      final item = await NutritionServiceApi.fetchNutrition(query);
      if (item != null) {
        setState(() {
          Map<String, dynamic> newEntry = {
            'name': item['name'],
            'category': selectedCategory,
            'qty': finalQty,
            'calories': (item['calories'] as num).toDouble(),
            'protein': (item['protein_g'] as num).toDouble(),
            'carbs': (item['carbohydrates_total_g'] as num).toDouble(),
            'fat': (item['fat_total_g'] as num).toDouble()
          };
          if (editingIndex != null) { foodLog[editingIndex!] = newEntry; } 
          else { foodLog.insert(0, newEntry); }
          _calculateTotals();
        });
        await _saveData();
        AppState.clearFoodInputs();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    } finally {
      setState(() { _isLoading = false; editingIndex = null; });
    }
  }

  void _editItem(int index) {
    var item = foodLog[index];
    setState(() {
      editingIndex = index;
      selectedCategory = item['category'];
      AppState.nameController.text = item['name'];
      AppState.qtyController.text = item['qty'].toString().replaceAll('g', '');
      dropdownError = false; qtyError = false; nameError = false;
    });
    _showAddFoodPanel(isEditing: true);
  }

  void _showAddFoodPanel({bool isEditing = false}) {
    if (!isEditing) {
      setState(() {
        selectedCategory = 'Select Meal Type';
        editingIndex = null;
        dropdownError = false; qtyError = false; nameError = false;
        AppState.clearFoodInputs();
      });
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(isEditing ? "Edit Meal" : "Add New Meal", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 15),
              
              // 1. Dropdown
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: dropdownError ? Colors.red : Colors.teal.shade100, width: dropdownError ? 2 : 1),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedCategory,
                    isExpanded: true,
                    items: ["Select Meal Type", "Breakfast", "Lunch", "Dinner"].map((value) {
                      return DropdownMenuItem<String>(value: value, child: Text(value, style: TextStyle(color: value == "Select Meal Type" ? Colors.grey : Colors.black)));
                    }).toList(),
                    onChanged: (val) {
                      setModalState(() { selectedCategory = val!; dropdownError = false; });
                      setState(() { selectedCategory = val!; });
                    },
                  ),
                ),
              ),
              if (dropdownError) const Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.only(left: 5, top: 5), child: Text("Selection required", style: TextStyle(color: Colors.red, fontSize: 12)))),
              
              const SizedBox(height: 15),

              // 2. Qty
              TextField(
                controller: AppState.qtyController,
                keyboardType: TextInputType.number,
                onChanged: (val) => setModalState(() => qtyError = val.isEmpty),
                decoration: InputDecoration(
                  labelText: 'Qty (g)',
                  errorText: qtyError ? "Enter quantity" : null,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),

              // 3. Name
              TextField(
                controller: AppState.nameController,
                onChanged: (val) => setModalState(() => nameError = val.isEmpty),
                decoration: InputDecoration(
                  labelText: 'Food Name',
                  errorText: nameError ? "Enter food name" : null,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),

              // 4. Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: selectedCategory == 'Select Meal Type' ? Colors.grey.shade400 : Colors.teal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                  ),
                  onPressed: () => _processNutrition(setModalState), 
                  child: Text(isEditing ? "UPDATE MEAL" : "TRACK IT", style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ... REST OF YOUR BUILD METHOD (Same as before)
  @override
  Widget build(BuildContext context) {
    int remaining = calorieGoal - totalCalories.toInt();
    double progress = calorieGoal > 0 ? totalCalories / calorieGoal : 0;
    if (progress > 1.0) progress = 1.0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.settings, color: Colors.teal), onPressed: _showGoalsMenu),
        title: GestureDetector(
          onTap: () async {
            DateTime? picked = await showDatePicker(context: context, initialDate: AppState.selectedDate, firstDate: DateTime(2023), lastDate: DateTime.now());
            if (picked != null) { setState(() => AppState.selectedDate = picked); _loadData(); }
          },
          child: Column(children: [
            Text("${AppState.selectedDate.month}/${AppState.selectedDate.day}/${AppState.selectedDate.year}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black)),
            const Text("Tap to change date", style: TextStyle(fontSize: 10, color: Colors.grey)),
          ]),
        ),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.chevron_left, color: Colors.teal), onPressed: () { setState(() => AppState.selectedDate = AppState.selectedDate.subtract(const Duration(days: 1))); _loadData(); }),
          IconButton(icon: const Icon(Icons.chevron_right, color: Colors.teal), onPressed: AppState.selectedDate.day == DateTime.now().day && AppState.selectedDate.month == DateTime.now().month ? null : () { setState(() => AppState.selectedDate = AppState.selectedDate.add(const Duration(days: 1))); _loadData(); }),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 30),
        child: FloatingActionButton.extended(
          onPressed: () => _showAddFoodPanel(),
          backgroundColor: Colors.teal,
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text("Add Food", style: TextStyle(color: Colors.white)),
        ),
      ),
      body: Column(
        children: [
          if (_isLoading) const LinearProgressIndicator(),
          Container(
            padding: const EdgeInsets.all(20), margin: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.grey.shade200, blurRadius: 10)]),
            child: Row(children: [
              Stack(alignment: Alignment.center, children: [
                SizedBox(width: 100, height: 100, child: CircularProgressIndicator(value: progress, strokeWidth: 10, backgroundColor: Colors.grey.shade200, color: remaining < 0 ? Colors.red : Colors.teal)),
                Column(mainAxisSize: MainAxisSize.min, children: [Text("$remaining", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), const Text("kcal left", style: TextStyle(fontSize: 10, color: Colors.grey))])
              ]),
              const SizedBox(width: 20),
              Expanded(child: Column(children: [
                _buildMacroRow("Protein", totalProtein, proteinGoal, Colors.blue),
                const SizedBox(height: 12),
                _buildMacroRow("Carbs", totalCarbs, carbsGoal, Colors.orange),
                const SizedBox(height: 12),
                _buildMacroRow("Fat", totalFat, fatGoal, Colors.red),
              ]))
            ]),
          ),
          Expanded(
            child: foodLog.isEmpty
                ? const Center(child: Text("No meals recorded for this day"))
                : ListView(padding: const EdgeInsets.symmetric(horizontal: 15), children: [
                    _buildMealSection("Breakfast"),
                    _buildMealSection("Lunch"),
                    _buildMealSection("Dinner"),
                    const SizedBox(height: 100),
                  ]),
          ),
          Text("Developed by: Argil", style: TextStyle(color: Colors.grey.shade400, fontStyle: FontStyle.italic)),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  void _showGoalsMenu() {
    AppState.calGoalController.text = calorieGoal.toString();
    AppState.proGoalController.text = proteinGoal.toString();
    AppState.carbGoalController.text = carbsGoal.toString();
    AppState.fatGoalController.text = fatGoal.toString();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Set Goals"),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: AppState.calGoalController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Calories')),
          TextField(controller: AppState.proGoalController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Protein')),
          TextField(controller: AppState.carbGoalController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Carbs')),
          TextField(controller: AppState.fatGoalController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Fat')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(onPressed: () async {
            final prefs = await SharedPreferences.getInstance();
            setState(() {
              calorieGoal = int.tryParse(AppState.calGoalController.text) ?? 2100;
              proteinGoal = int.tryParse(AppState.proGoalController.text) ?? 150;
              carbsGoal = int.tryParse(AppState.carbGoalController.text) ?? 300;
              fatGoal = int.tryParse(AppState.fatGoalController.text) ?? 70;
            });
            await prefs.setInt('calorie_goal', calorieGoal);
            await prefs.setInt('protein_goal', proteinGoal);
            await prefs.setInt('carbs_goal', carbsGoal);
            await prefs.setInt('fat_goal', fatGoal);
            Navigator.pop(context);
          }, child: const Text("Save"))
        ],
      ),
    );
  }

  Widget _buildMealSection(String category) {
    final items = foodLog.where((item) => item['category'] == category).toList();
    double sectionCalories = items.fold(0, (sum, item) => sum + (item['calories'] ?? 0));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 5), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(category.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 14)),
        Text("${sectionCalories.toInt()} kcal", style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey.shade700, fontSize: 13)),
      ])),
      Container(
        width: double.infinity,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]),
        child: items.isEmpty
            ? const Padding(padding: EdgeInsets.all(20), child: Text("Empty", style: TextStyle(color: Colors.grey, fontSize: 12)))
            : Column(children: items.asMap().entries.map((entry) {
                int idx = entry.key; var food = entry.value; int originalIndex = foodLog.indexOf(food);
                return Column(children: [
                  Padding(padding: const EdgeInsets.all(12), child: Row(children: [
                    Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.teal.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.restaurant, color: Colors.teal, size: 20)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text("${food['name'].toString().toUpperCase()} (${food['qty']})", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 4),
                      Text("${food['calories']} kcal | P: ${food['protein']}g | C: ${food['carbs'] ?? 0}g | F: ${food['fat'] ?? 0}g", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    ])),
                    IconButton(icon: const Icon(Icons.edit_outlined, color: Colors.blueAccent, size: 20), onPressed: () => _editItem(originalIndex)),
                    IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20), onPressed: () => _deleteItem(originalIndex)),
                  ])),
                  if (idx < items.length - 1) Divider(height: 1, thickness: 1, color: Colors.grey.shade100, indent: 20, endIndent: 20),
                ]);
              }).toList()),
      ),
      const SizedBox(height: 10),
    ]);
  }

  Widget _buildMacroRow(String label, double current, int goal, Color color) {
    double progress = goal > 0 ? current / goal : 0.0;
    if (progress > 1.0) progress = 1.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(fontWeight: FontWeight.bold)), Text("${current.toInt()}g / ${goal}g")]),
      LinearProgressIndicator(value: progress, color: color, backgroundColor: color.withOpacity(0.1)),
    ]);
  }
}