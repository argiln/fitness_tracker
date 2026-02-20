import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_state.dart';
import 'nutrition_service_api.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

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

  double totalCalories = 0.0;
  double totalProtein = 0.0;
  double totalCarbs = 0.0;
  double totalFat = 0.0;

  bool _isLoading = false;
  bool _isAiLoading = false; // Fixed: Used for the AI spinner
  bool isManualMode = false;
  String selectedCategory = 'Select Meal Type';
  int? editingIndex;

  bool dropdownError = false;
  bool qtyError = false;
  bool nameError = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // --- AI LOGIC ---
  Future<void> _analyzeWithGemini(String input, Function setModalState) async {
    if (input.isEmpty) return;

    final model = GenerativeModel(
      model: 'gemini-1.5-flash', 
      apiKey: 'AIzaSyCNNfiSwj4KH5fK3tIB7rSL6VUxjXKN_rQ'
    );

    final prompt = "Provide the nutritional info for '$input'. "
        "Return ONLY 4 numbers separated by commas: calories, protein, carbs, fat. "
        "Example: 250, 30, 5, 12. If unknown, return 0, 0, 0, 0.";

    try {
      setModalState(() => _isAiLoading = true);
      
      final content = [Content.text(prompt)];
      final response = await model.generateContent(content);
      final text = response.text?.trim() ?? "";

      List<String> parts = text.split(',');
      if (parts.length == 4) {
        setModalState(() {
          isManualMode = true; 
          AppState.calGoalController.text = parts[0].trim();
          AppState.proGoalController.text = parts[1].trim();
          AppState.carbGoalController.text = parts[2].trim();
          AppState.fatGoalController.text = parts[3].trim();
        });
      }
    } catch (e) {
      _showError("AI Search failed. Check internet or API key.");
    } finally {
      setModalState(() => _isAiLoading = false);
    }
  }

  // --- DATA PERSISTENCE ---
  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      calorieGoal = prefs.getInt('calorie_goal') ?? 2100;
      proteinGoal = prefs.getInt('protein_goal') ?? 150;
      carbsGoal = prefs.getInt('carbs_goal') ?? 300;
      fatGoal = prefs.getInt('fat_goal') ?? 70;

      final List<String>? savedList = prefs.getStringList('food_log_${AppState.dateKey}');
      foodLog = savedList != null 
          ? savedList.map((item) => jsonDecode(item) as Map<String, dynamic>).toList() 
          : [];
      _calculateTotals();
    });
  }

  void _calculateTotals() {
    double cal = 0; double pro = 0; double carb = 0; double fat = 0;
    for (var item in foodLog) {
      cal += (item['calories'] as num? ?? 0).toDouble();
      pro += (item['protein'] as num? ?? 0).toDouble();
      carb += (item['carbs'] as num? ?? 0).toDouble();
      fat += (item['fat'] as num? ?? 0).toDouble();
    }
    setState(() {
      totalCalories = cal; totalProtein = pro; totalCarbs = carb; totalFat = fat;
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> listToSave = foodLog.map((item) => jsonEncode(item)).toList();
    await prefs.setStringList('food_log_${AppState.dateKey}', listToSave);
  }

  Future<void> _deleteItem(int index) async {
    setState(() {
      foodLog.removeAt(index);
      _calculateTotals();
    });
    await _saveData();
  }

  // --- NUTRITION PROCESSING ---
  Future<void> _processNutrition(Function modalSetState) async {
    modalSetState(() {
      dropdownError = selectedCategory == 'Select Meal Type';
      qtyError = AppState.qtyController.text.isEmpty;
      nameError = AppState.nameController.text.isEmpty;
    });

    if (dropdownError || qtyError || nameError) return;

    Map<String, dynamic>? newEntry;
    double userWeightGrams = double.tryParse(AppState.qtyController.text) ?? 0.0;

    if (isManualMode) {
      newEntry = {
        'name': AppState.nameController.text,
        'category': selectedCategory,
        'qty': "${userWeightGrams.toInt()}g",
        'calories': double.tryParse(AppState.calGoalController.text) ?? 0.0,
        'protein': double.tryParse(AppState.proGoalController.text) ?? 0.0,
        'carbs': double.tryParse(AppState.carbGoalController.text) ?? 0.0,
        'fat': double.tryParse(AppState.fatGoalController.text) ?? 0.0,
      };
      Navigator.pop(context);
    } else {
      setState(() => _isLoading = true);
      Navigator.pop(context);

      try {
        final item = await NutritionServiceApi.fetchNutrition(AppState.nameController.text);
        if (item != null) {
          double apiServingWeight = (item['serving_size_g'] as num).toDouble();
          double multiplier = userWeightGrams / apiServingWeight;

          newEntry = {
            'name': item['name'],
            'category': selectedCategory,
            'qty': "${userWeightGrams.toInt()}g",
            'calories': (item['calories'] as num).toDouble() * multiplier,
            'protein': (item['protein_g'] as num).toDouble() * multiplier,
            'carbs': (item['carbohydrates_total_g'] as num).toDouble() * multiplier,
            'fat': (item['fat_total_g'] as num).toDouble() * multiplier
          };
        } else {
          _showError("Food not found. Try Manual Mode!");
        }
      } catch (e) {
        _showError("Connection Error");
      }
    }

    if (newEntry != null) {
      setState(() {
        if (editingIndex != null) {
          foodLog[editingIndex!] = newEntry!;
        } else {
          foodLog.insert(0, newEntry!);
        }
        _calculateTotals();
      });
      await _saveData();
      AppState.clearFoodInputs();
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.orange));
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

  // --- ADD FOOD PANEL ---
  void _showAddFoodPanel({bool isEditing = false}) {
    if (!isEditing) {
      setState(() {
        selectedCategory = 'Select Meal Type';
        isManualMode = false;
        editingIndex = null;
        dropdownError = false;
        qtyError = false;
        nameError = false;
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
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(isEditing ? "Edit Meal" : "Add New Meal", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                
                // MANUAL TOGGLE
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Text("Manual Entry Mode", style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(width: 8),
                    Switch(
                      value: isManualMode,
                      activeThumbColor: Colors.green,
                      activeTrackColor: Colors.green.withValues(alpha: 0.5),
                      onChanged: (val) {
                        setModalState(() {
                          isManualMode = val;
                          if (val) AppState.clearFoodInputs();
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // DROPDOWN
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: dropdownError ? Colors.red : Colors.teal.shade100, width: dropdownError ? 2 : 1),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedCategory,
                      isExpanded: true,
                      items: ["Select Meal Type", "Breakfast", "Lunch", "Dinner"].map((v) => DropdownMenuItem(value: v, child: Text(v, style: TextStyle(color: v == "Select Meal Type" ? Colors.grey : Colors.black)))).toList(),
                      onChanged: (val) => setModalState(() { selectedCategory = val!; dropdownError = false; }),
                    ),
                  ),
                ),
                const SizedBox(height: 15),

                // WEIGHT
                TextField(
                  controller: AppState.qtyController,
                  keyboardType: TextInputType.number,
                  onChanged: (val) => setModalState(() => qtyError = val.isEmpty),
                  decoration: InputDecoration(labelText: 'Weight (grams)', suffixText: 'g', errorText: qtyError ? "Required" : null, border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 15),

                // NAME + SEARCH + AI
                LayoutBuilder(
                  builder: (context, constraints) => Autocomplete<String>(
                    optionsBuilder: (TextEditingValue textEditingValue) async {
                      if (isManualMode) return const Iterable<String>.empty();
                      String input = textEditingValue.text.trim();
                      if (input.length < 3) return const Iterable<String>.empty();
                      try {
                        final item = await NutritionServiceApi.fetchNutrition(input);
                        return item != null ? [item['name'].toString().toUpperCase()] : [];
                      } catch (e) { return []; }
                    },
                    onSelected: (selection) {
                      AppState.nameController.text = selection;
                      setModalState(() => nameError = false);
                    },
                    fieldViewBuilder: (context, fieldController, focusNode, onFieldSubmitted) {
                      if (AppState.nameController.text.isNotEmpty && fieldController.text.isEmpty) {
                        fieldController.text = AppState.nameController.text;
                      }
                      return TextField(
                        controller: fieldController,
                        focusNode: focusNode,
                        onChanged: (val) { AppState.nameController.text = val; setModalState(() => nameError = val.isEmpty); },
                        decoration: InputDecoration(
                          labelText: isManualMode ? 'Describe meal (AI Search)' : 'Search Food Name',
                          errorText: nameError ? "Required" : null,
                          border: const OutlineInputBorder(),
                          suffixIcon: isManualMode 
                            ? (_isAiLoading 
                                ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                                : IconButton(icon: const Icon(Icons.auto_awesome, color: Colors.amber), onPressed: () => _analyzeWithGemini(fieldController.text, setModalState)))
                            : null,
                        ),
                      );
                    },
                  ),
                ),

                // MANUAL FIELDS
                if (isManualMode) ...[
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: AppState.calGoalController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'kcal', border: OutlineInputBorder()))),
                      const SizedBox(width: 10),
                      Expanded(child: TextField(controller: AppState.proGoalController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Protein (g)', border: OutlineInputBorder()))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: AppState.carbGoalController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Carbs (g)', border: OutlineInputBorder()))),
                      const SizedBox(width: 10),
                      Expanded(child: TextField(controller: AppState.fatGoalController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Fats (g)', border: OutlineInputBorder()))),
                    ],
                  ),
                ],

                const SizedBox(height: 25),

                // SUBMIT
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: selectedCategory == 'Select Meal Type' ? Colors.grey.shade400 : Colors.teal,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _processNutrition(setModalState),
                    child: Text(isEditing ? "UPDATE MEAL" : "TRACK IT", style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    int remaining = calorieGoal - totalCalories.toInt();
    double progress = calorieGoal > 0 ? (totalCalories / calorieGoal).clamp(0.0, 1.0) : 0;

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
          IconButton(icon: const Icon(Icons.chevron_right, color: Colors.teal), onPressed: AppState.selectedDate.isAfter(DateTime.now().subtract(const Duration(days: 1))) ? null : () { setState(() => AppState.selectedDate = AppState.selectedDate.add(const Duration(days: 1))); _loadData(); }),
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
            if (mounted) Navigator.pop(context);
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
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4))]),
        child: items.isEmpty
            ? const Padding(padding: EdgeInsets.all(20), child: Text("Empty", style: TextStyle(color: Colors.grey, fontSize: 12)))
            : Column(children: items.asMap().entries.map((entry) {
                int originalIndex = foodLog.indexOf(entry.value);
                var food = entry.value;
                return Column(children: [
                  Padding(padding: const EdgeInsets.all(12), child: Row(children: [
                    Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.teal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.restaurant, color: Colors.teal, size: 20)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text("${food['name'].toString().toUpperCase()} (${food['qty']})", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 4),
                      Text("${food['calories'].toInt()} kcal | P: ${food['protein'].toInt()}g | C: ${food['carbs'].toInt()}g | F: ${food['fat'].toInt()}g", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    ])),
                    IconButton(icon: const Icon(Icons.edit_outlined, color: Colors.blueAccent, size: 20), onPressed: () => _editItem(originalIndex)),
                    IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20), onPressed: () => _deleteItem(originalIndex)),
                  ])),
                  if (entry.key < items.length - 1) Divider(height: 1, thickness: 1, color: Colors.grey.shade100, indent: 20, endIndent: 20),
                ]);
              }).toList()),
      ),
      const SizedBox(height: 10),
    ]);
  }

  Widget _buildMacroRow(String label, double current, int goal, Color color) {
    double progress = goal > 0 ? (current / goal).clamp(0.0, 1.0) : 0.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(fontWeight: FontWeight.bold)), Text("${current.toInt()}g / ${goal}g")]),
      LinearProgressIndicator(value: progress, color: color, backgroundColor: color.withValues(alpha: 0.1),),
    ]);
  }
}