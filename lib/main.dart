import 'package:feedback_app/feedback_page.dart';
import 'package:feedback_app/firebase_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<String?> _loadSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_email');
  }

  Future<bool> _isEmployeeRegistered(String email) async {
    final emailLower = email.trim().toLowerCase();

    final byLower = await FirebaseFirestore.instance
        .collection('employees')
        .where('emailLower', isEqualTo: emailLower)
        .limit(1)
        .get();
    if (byLower.docs.isNotEmpty) return true;

    final byEmailExact = await FirebaseFirestore.instance
        .collection('employees')
        .where('email', isEqualTo: email.trim())
        .limit(1)
        .get();
    if (byEmailExact.docs.isNotEmpty) return true;

    final byEmailLowerExact = await FirebaseFirestore.instance
        .collection('employees')
        .where('email', isEqualTo: emailLower)
        .limit(1)
        .get();
    return byEmailLowerExact.docs.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Feedback App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: FutureBuilder<String?>(
        future: _loadSavedEmail(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          final savedEmail = snapshot.data;
          if (savedEmail == null || savedEmail.isEmpty) {
            return const HomeScreen();
          }

          return FutureBuilder<bool>(
            future: _isEmployeeRegistered(savedEmail),
            builder: (context, regSnap) {
              if (regSnap.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              final isRegistered = regSnap.data ?? false;
              if (!isRegistered) {
                // Clear cached email so user must enter a valid Pay1 email again.
                SharedPreferences.getInstance().then((p) => p.remove('user_email'));
                return const HomeScreen();
              }

              return FeedbackPage(email: savedEmail);
            },
          );
        },
      ),
    );
  }
}
