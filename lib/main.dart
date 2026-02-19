import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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
  // Default Goals (will be overwritten by database)
  int calorieGoal = 2500;
  int proteinGoal = 150; 
  int carbsGoal = 300;   
  int fatGoal = 70;
  List<Map<String, dynamic>> foodLog = [];
  
  double totalCalories = 0;
  double totalProtein = 0;
  double totalCarbs = 0;
  double totalFat = 0;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _qtyController = TextEditingController();
  
  // Controllers for the Goals Menu
  final TextEditingController _calGoalController = TextEditingController();
  final TextEditingController _proGoalController = TextEditingController();
  final TextEditingController _carbGoalController = TextEditingController();
  final TextEditingController _fatGoalController = TextEditingController();

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData(); // <--- THIS IS CRITICAL. It loads the "Database" when the app starts.
  }

  // --- DATABASE: LOAD ---
  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Check if they have set goals before
    bool isFirstTime = prefs.getInt('calorie_goal') == null;

    setState(() {
      // Load Goals (or keep defaults if null)
      calorieGoal = prefs.getInt('calorie_goal') ?? 2500;
      proteinGoal = prefs.getInt('protein_goal') ?? 150;
      carbsGoal = prefs.getInt('carbs_goal') ?? 300;
      fatGoal = prefs.getInt('fat_goal') ?? 70;

      final List<String>? savedList = prefs.getStringList('my_food_log');
      
      if (savedList != null) {
        // Convert the saved Strings back into a List of Maps
        foodLog = savedList.map((item) => jsonDecode(item) as Map<String, dynamic>).toList();
        
        // Recalculate totals
        totalCalories = 0;
        totalProtein = 0;
        totalCarbs = 0;
        totalFat = 0;

        for (var item in foodLog) {
          totalCalories += item['calories'] ?? 0;
          totalProtein += item['protein'] ?? 0;
          totalCarbs += item['carbs'] ?? 0;
          totalFat += item['fat'] ?? 0;
        }
      }
    });

    // If it's their very first time, automatically show the Setup Menu!
    if (isFirstTime) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showGoalsMenu();
      });
    }
  }

  // --- DATABASE: SAVE ---
  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    // Convert the List of Maps into a List of Strings to save
    List<String> listToSave = foodLog.map((item) => jsonEncode(item)).toList();
    await prefs.setStringList('my_food_log', listToSave);
  }

  Future<void> _deleteItem(int index) async {
    setState(() {
      final item = foodLog[index];
      totalCalories -= item['calories'];
      totalProtein -= item['protein'];
      totalCarbs -= item['carbs'] ?? 0;
      totalFat -= item['fat'] ?? 0;
      foodLog.removeAt(index);
    });
    await _saveData(); // Save immediately after deleting
  }

  Future<void> _fetchNutrition() async {
    if (_nameController.text.isEmpty || _qtyController.text.isEmpty) return;
    
    Navigator.pop(context); 
    setState(() => _isLoading = true);

    // Smart Quantity Logic
    String rawQty = _qtyController.text.trim();
    String finalQty = rawQty;
    if (double.tryParse(rawQty) != null) {
      finalQty = "${rawQty}g";
    }

    String query = "$finalQty ${_nameController.text}";

    try {
      // !!! PASTE YOUR KEY HERE !!!
      const String apiKey = 'QvAFUhMlnE1V5/L0kLjFiQ==RjE8svTLjCtrwpCk'; 
      
      // Use Uri.https to handle spaces automatically
      final url = Uri.https('api.calorieninjas.com', '/v1/nutrition', {'query': query});
      final response = await http.get(url, headers: {'X-Api-Key': apiKey});

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['items'] as List;

        if (items.isNotEmpty) {
          final item = items[0]; 
          
          setState(() {
            double cals = (item['calories'] as num).toDouble();
            double prot = (item['protein_g'] as num).toDouble();
            double carb = (item['carbohydrates_total_g'] as num).toDouble();
            double fat = (item['fat_total_g'] as num).toDouble();

            totalCalories += cals;
            totalProtein += prot;
            totalCarbs += carb;
            totalFat += fat;
            
            // Use the API's name to auto-correct typos
            foodLog.insert(0, {
              'name': item['name'], 
              'qty': finalQty,
              'calories': cals,
              'protein': prot,
              'carbs': carb,
              'fat': fat
            });
          });
          
          await _saveData(); // Save immediately after adding
          
          _nameController.clear();
          _qtyController.clear();

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Added successfully!"), backgroundColor: Colors.green)
          );
        } else {
           _showError("Food not found: '${_nameController.text}'");
        }
      } else {
        _showError("API Error: ${response.statusCode}");
      }
    } catch (e) {
      _showError("Connection Error: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: const TextStyle(color: Colors.white)), backgroundColor: Colors.red),
    );
  }

  // --- THE SETTINGS MENU FOR GOALS ---
  void _showGoalsMenu() {
    // Fill the text boxes with current goals so they can edit them
    _calGoalController.text = calorieGoal.toString();
    _proGoalController.text = proteinGoal.toString();
    _carbGoalController.text = carbsGoal.toString();
    _fatGoalController.text = fatGoal.toString();

    showDialog(
      context: context,
      barrierDismissible: false, // Forces them to tap Save or Cancel
      builder: (context) {
        return AlertDialog(
          title: const Text("Set Your Goals", style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: _calGoalController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Daily Calories (kcal)')),
                const SizedBox(height: 10),
                TextField(controller: _proGoalController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Protein Goal (g)')),
                const SizedBox(height: 10),
                TextField(controller: _carbGoalController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Carbs Goal (g)')),
                const SizedBox(height: 10),
                TextField(controller: _fatGoalController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Fat Goal (g)')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                
                setState(() {
                  // Update UI with new numbers
                  calorieGoal = int.tryParse(_calGoalController.text) ?? 2500;
                  proteinGoal = int.tryParse(_proGoalController.text) ?? 150;
                  carbsGoal = int.tryParse(_carbGoalController.text) ?? 300;
                  fatGoal = int.tryParse(_fatGoalController.text) ?? 70;
                });

                // Save new numbers to Database
                await prefs.setInt('calorie_goal', calorieGoal);
                await prefs.setInt('protein_goal', proteinGoal);
                await prefs.setInt('carbs_goal', carbsGoal);
                await prefs.setInt('fat_goal', fatGoal);

                Navigator.pop(context);
              },
              child: const Text("Save Goals"),
            )
          ],
        );
      }
    );
  }

  void _showAddFoodPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Add Meal", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            Row(
              children: [
                SizedBox(
                  width: 80, 
                  child: TextField(
                    controller: _qtyController, 
                    autofocus: true,
                    keyboardType: TextInputType.number, 
                    decoration: const InputDecoration(labelText: 'Qty', border: OutlineInputBorder())
                  )
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Food Name (e.g. Chicken)', 
                      border: OutlineInputBorder()
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _fetchNutrition,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                child: const Text('TRACK IT', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    int remaining = calorieGoal - totalCalories.toInt();
    double progress = totalCalories / calorieGoal;
    if (progress > 1.0) progress = 1.0; 

    return Scaffold(
      appBar: AppBar(
        title: const Text("Daily Tracker", style: TextStyle(fontWeight: FontWeight.bold)), 
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.settings, color: Colors.teal),
          onPressed: _showGoalsMenu, // <-- The Settings Button
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.red),
            onPressed: () async {
              // Clear Database Button (Now only clears food, keeps goals)
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('my_food_log'); 
              setState(() {
                foodLog = [];
                totalCalories = 0;
                totalProtein = 0;
                totalCarbs = 0;
                totalFat = 0;
              });
            },
          )
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddFoodPanel,
        backgroundColor: Colors.teal,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("Add Food", style: TextStyle(color: Colors.white)),
      ),
      body: Column(
        children: [
          if (_isLoading) const LinearProgressIndicator(),
          Container(
            padding: const EdgeInsets.all(20),
            margin: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.grey.shade200, blurRadius: 10, offset: const Offset(0, 5))],
            ),
            child: Row(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 100, height: 100,
                      child: CircularProgressIndicator(
                        value: progress, 
                        strokeWidth: 10, 
                        backgroundColor: Colors.grey.shade200,
                        color: remaining < 0 ? Colors.red : Colors.teal,
                      ),
                    ),
                    Column(
                      children: [
                        Text("$remaining", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        const Text("kcal left", style: TextStyle(fontSize: 10, color: Colors.grey)),
                      ],
                    )
                  ],
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    children: [
                      _buildMacroRow("Protein", totalProtein, proteinGoal, Colors.blue),
                      const SizedBox(height: 12),
                      _buildMacroRow("Carbs", totalCarbs, carbsGoal, Colors.orange),
                      const SizedBox(height: 12),
                      _buildMacroRow("Fat", totalFat, fatGoal, Colors.red),
                    ],
                  ),
                )
              ],
            ),
          ), 
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text("Today's Meals", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
            ),
          ),
          
          Expanded(
            child: foodLog.isEmpty 
            ? Center(child: Text("Click '+ Add Food' to start", style: TextStyle(color: Colors.grey.shade400)))
            : ListView.builder(
              itemCount: foodLog.length,
              padding: const EdgeInsets.only(bottom: 80),
              itemBuilder: (context, index) {
                final food = foodLog[index];
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [BoxShadow(color: Colors.grey.shade100, blurRadius: 5)],
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.restaurant, color: Colors.teal),
                    ),
                    // 1. NAME + QUANTITY 
                    title: Text(
                      "${food['name'].toString().toUpperCase()} (${food['qty']})", 
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    // 2. COLORED MACROS using RichText
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(fontSize: 13), 
                          children: [
                            TextSpan(
                              text: "${food['calories']} kcal | ",
                              style: const TextStyle(color: Colors.grey),
                            ),
                            TextSpan(
                              text: "P: ${food['protein']}g |",
                              style: const TextStyle(color: Colors.grey),
                            ),
                            const TextSpan(text: " "), 
                            TextSpan(
                              text: "C: ${food['carbs'] ?? 0}g |",
                              style: const TextStyle(color: Colors.grey),
                            ),
                            const TextSpan(text: " "), 
                            TextSpan(
                              text: "F: ${food['fat'] ?? 0}g",
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _deleteItem(index),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- UPGRADED MACRO ROW WITH PROGRESS BAR ---
  Widget _buildMacroRow(String label, double current, int goal, Color color) {
    // Calculate progress (prevent it from breaking if it goes over 100%)
    double progress = goal > 0 ? current / goal : 0.0;
    if (progress > 1.0) progress = 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
            Text("${current.toInt()} / ${goal}g", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(5), // Rounded edges for the bar
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: color.withOpacity(0.2), // Light version of the color for the background
            color: color, // Solid color for the actual progress
            minHeight: 8, // Makes the bar a little thicker
          ),
        ),
      ],
    );
  }
}