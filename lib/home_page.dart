import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:feedback_app/feedback_page.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// First page: enter and remember email, then move to feedback page.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isSaving = false;
  bool _isCheckingEmployee = false;
  bool? _isEmployeeRegistered;
  Timer? _debounce;
  bool _isSeedingEmployees = false;
  bool _isSeedingShops = false;
  bool _isImportingEmployees = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _emailController.dispose();
    super.dispose();
  }

  bool _isValidEmailFormat(String email) {
    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+', caseSensitive: false);
    return emailRegex.hasMatch(email.trim());
  }

  bool _isPay1Email(String email) {
    return email.trim().toLowerCase().endsWith('@pay1.in');
  }

  Future<bool> _checkEmployeeExistsByEmail(String email) async {
    final emailLower = email.trim().toLowerCase();

    // Recommended schema:
    // employees/{employeeId} with fields: email, emailLower
    final byLower = await FirebaseFirestore.instance
        .collection('employees')
        .where('emailLower', isEqualTo: emailLower)
        .limit(1)
        .get();
    if (byLower.docs.isNotEmpty) return true;

    // Backward compatible fallback if you only stored `email` (case sensitive).
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

  void _onEmailChanged(String value) {
    final email = value.trim();

    // Don't check Firestore until format + domain are OK.
    if (!_isValidEmailFormat(email) || !_isPay1Email(email)) {
      setState(() {
        _isCheckingEmployee = false;
        _isEmployeeRegistered = null;
      });
      return;
    }

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      setState(() {
        _isCheckingEmployee = true;
      });

      final exists = await _checkEmployeeExistsByEmail(email);
      if (!mounted) return;

      setState(() {
        _isCheckingEmployee = false;
        _isEmployeeRegistered = exists;
      });

      // Re-run validator to show/hide error instantly.
      _formKey.currentState?.validate();
    });
  }

  Future<void> _verifyEmailAndContinue() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    final email = _emailController.text.trim();
    try {
      // Final gate at submit time (even if user didn’t wait for debounce).
      if (!_isValidEmailFormat(email) || !_isPay1Email(email)) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Enter a Pay1 email id.')));
        return;
      }

      final exists = await _checkEmployeeExistsByEmail(email);
      if (!exists) {
        if (!mounted) return;
        setState(() {
          _isEmployeeRegistered = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Enter a Pay1 email id.')));
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_email', email);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => FeedbackPage(email: email)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error checking employee: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _seedTestEmployees() async {
    if (_isSeedingEmployees) return;
    setState(() {
      _isSeedingEmployees = true;
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final batch = firestore.batch();

      final now = FieldValue.serverTimestamp();

      final testEmployees = <Map<String, String>>[
        {'employeeId': 'EMP001', 'email': 'dhiraj.wabale@pay1.in'},
        {'employeeId': 'EMP002', 'email': 'test.user1@pay1.in'},
        {'employeeId': 'EMP003', 'email': 'test.user2@pay1.in'},
      ];

      for (final emp in testEmployees) {
        final employeeId = emp['employeeId']!;
        final email = emp['email']!;
        final ref = firestore.collection('employees').doc(employeeId);
        batch.set(ref, {
          'employeeId': employeeId,
          'email': email,
          'emailLower': email.toLowerCase(),
          'active': true,
          'createdAt': now,
          'updatedAt': now,
        }, SetOptions(merge: true));
      }

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Test employees added to Firestore')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding test employees: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSeedingEmployees = false;
        });
      }
    }
  }

  Future<void> _seedDemoShop() async {
    if (_isSeedingShops) return;
    setState(() {
      _isSeedingShops = true;
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final shopName = 'spicy chana express';
      final shopId = shopName.trim().toLowerCase();
      final employeeName = 'Bhalwant';

      await firestore.collection('shops').doc(shopId).set({
        'shopId': shopId,
        'shopName': shopName,
        'shopNameLower': shopName.toLowerCase(),
        'employeeName': employeeName,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Demo shop added to Firestore')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error adding demo shop: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isSeedingShops = false;
        });
      }
    }
  }

  Future<void> _importEmployeesFromFile() async {
    if (_isImportingEmployees) return;
    setState(() {
      _isImportingEmployees = true;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv', 'xlsx'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final name = file.name.toLowerCase();
      final bytes = file.bytes;
      if (bytes == null) throw Exception('Could not read file bytes');

      final rows = <List<String>>[];

      if (name.endsWith('.csv')) {
        final csvText = utf8.decode(bytes);
        final csvRows = const CsvToListConverter(eol: '\n').convert(csvText);
        for (final r in csvRows) {
          rows.add(r.map((e) => e?.toString() ?? '').toList());
        }
      } else if (name.endsWith('.xlsx')) {
        final excel = Excel.decodeBytes(bytes);
        if (excel.tables.isEmpty) throw Exception('No sheets found in file');
        final sheet = excel.tables.values.first;
        if (sheet == null) throw Exception('Could not read first sheet');
        for (final r in sheet.rows) {
          rows.add(r.map((c) => (c?.value ?? '').toString()).toList());
        }
      } else {
        throw Exception('Unsupported file type. Use .csv or .xlsx');
      }

      if (rows.isEmpty) throw Exception('File has no rows');

      // Header support: employeeId,email
      var startIndex = 0;
      final header = rows.first.map((e) => e.trim().toLowerCase()).toList();
      final hasHeader = header.any((c) => c.contains('employee')) &&
          header.any((c) => c.contains('email'));
      if (hasHeader) startIndex = 1;

      final firestore = FirebaseFirestore.instance;
      int added = 0;
      int skipped = 0;
      int invalid = 0;

      WriteBatch batch = firestore.batch();
      var batchCount = 0;

      Future<void> commitIfNeeded({bool force = false}) async {
        if (batchCount == 0) return;
        if (!force && batchCount < 450) return;
        await batch.commit();
        batch = firestore.batch();
        batchCount = 0;
      }

      for (var i = startIndex; i < rows.length; i++) {
        final row = rows[i];
        final employeeId = (row.isNotEmpty ? row[0] : '').trim();
        final email = (row.length > 1 ? row[1] : '').trim();

        if (employeeId.isEmpty || email.isEmpty) {
          invalid++;
          continue;
        }

        // Skip if already in table (by employeeId doc id).
        final ref = firestore.collection('employees').doc(employeeId);
        final existing = await ref.get();
        if (existing.exists) {
          skipped++;
          continue;
        }

        batch.set(ref, {
          'employeeId': employeeId,
          'email': email,
          'emailLower': email.toLowerCase(),
          'active': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        batchCount++;
        added++;

        await commitIfNeeded();
      }

      await commitIfNeeded(force: true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Import complete. Added: $added, Skipped(existing): $skipped, Invalid: $invalid',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error importing employees: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isImportingEmployees = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enter Email'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Welcome!',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Please enter your email address. '
                    'We will remember this for your feedback submissions.',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    onChanged: _onEmailChanged,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.email_outlined),
                      helperText: _isCheckingEmployee
                          ? 'Checking employee...'
                          : 'Only Pay1 registered emails can submit feedback.',
                      suffixIcon: _isCheckingEmployee
                          ? const Padding(
                              padding: EdgeInsets.all(12.0),
                              child: SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : (_isEmployeeRegistered == true
                                ? const Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                  )
                                : null),
                    ),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) {
                        return 'Email is required';
                      }
                      if (!_isValidEmailFormat(text)) {
                        return 'Enter a valid email';
                      }
                      if (!_isPay1Email(text)) {
                        return 'Enter a Pay1 email id.';
                      }
                      if (_isEmployeeRegistered == false) {
                        return 'Enter a Pay1 email id.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _verifyEmailAndContinue,
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Continue'),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // OutlinedButton.icon(
                  //   onPressed: _isSeedingEmployees ? null : _seedTestEmployees,
                  //   icon: _isSeedingEmployees
                  //       ? const SizedBox(
                  //           height: 18,
                  //           width: 18,
                  //           child: CircularProgressIndicator(strokeWidth: 2),
                  //         )
                  //       : const Icon(Icons.cloud_upload_outlined),
                  //   label: Text(
                  //     _isSeedingEmployees
                  //         ? 'Adding test employees...'
                  //         : 'Create test employees (Firestore)',
                  //   ),
                  // ),

                  // OutlinedButton.icon(
                  //   onPressed: _isSeedingShops ? null : _seedDemoShop,
                  //   icon: _isSeedingShops
                  //       ? const SizedBox(
                  //           height: 18,
                  //           width: 18,
                  //           child: CircularProgressIndicator(strokeWidth: 2),
                  //         )
                  //       : const Icon(Icons.storefront_outlined),
                  //   label: Text(
                  //     _isSeedingShops
                  //         ? 'Adding demo shop...'
                  //         : 'Create demo shop (Firestore)',
                  //   ),
                  // ),

                  OutlinedButton.icon(
                    onPressed:
                        _isImportingEmployees ? null : _importEmployeesFromFile,
                    icon: _isImportingEmployees
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file_outlined),
                    label: Text(
                      _isImportingEmployees
                          ? 'Importing employees...'
                          : 'Import employees (CSV/XLSX)',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
