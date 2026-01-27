import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _saveEmailAndContinue() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    final email = _emailController.text.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_email', email);

    if (!mounted) return;
    setState(() {
      _isSaving = false;
    });

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => FeedbackPage(email: email),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enter Email'),
        centerTitle: true,
      ),
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
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) {
                        return 'Email is required';
                      }
                      final emailRegex =
                          RegExp(r'^[^@]+@[^@]+\.[^@]+', caseSensitive: false);
                      if (!emailRegex.hasMatch(text)) {
                        return 'Enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveEmailAndContinue,
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Continue'),
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

/// Third page: show feedback form with 1–5 star rating and store locally.
class FeedbackPage extends StatefulWidget {
  const FeedbackPage({
    super.key,
    required this.email,
  });

  final String email;

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final TextEditingController _shopController = TextEditingController();
  int _priceRating = 0;
  int _presentationRating = 0;
  int _staffBehaviorRating = 0;
  int _foodQualityRating = 0;
  int _overallRating = 0;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _shopController.dispose();
    super.dispose();
  }

  Future<void> _storeFeedbackLocally() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('feedback_submissions');
    final List<dynamic> list =
        raw == null || raw.isEmpty ? <dynamic>[] : (jsonDecode(raw) as List);

    list.add({
      'email': widget.email,
      'shopName': _shopController.text.trim(),
      'priceRating': _priceRating,
      'presentationAndHygieneRating': _presentationRating,
      'staffBehaviorRating': _staffBehaviorRating,
      'foodQualityRating': _foodQualityRating,
      'overallRating': _overallRating,
      'createdAt': DateTime.now().toIso8601String(),
    });

    await prefs.setString('feedback_submissions', jsonEncode(list));
  }

  Future<void> _storeFeedbackInFirestore() async {
    final shopName = _shopController.text.trim();
    if (shopName.isEmpty) return;

    final data = {
      'email': widget.email,
      'shopName': shopName,
      'priceRating': _priceRating,
      'presentationAndHygieneRating': _presentationRating,
      'staffBehaviorRating': _staffBehaviorRating,
      'foodQualityRating': _foodQualityRating,
      'overallRating': _overallRating,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Structure: feedbackByUser/{email}/shops/{shopName}
    await FirebaseFirestore.instance
        .collection('feedbackByUser')
        .doc(widget.email)
        .collection('shops')
        .doc(shopName)
        .set(data, SetOptions(merge: true));
  }

  Future<void> _submitFeedback() async {
    final shopName = _shopController.text.trim();
    if (shopName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter shop name')),
      );
      return;
    }

    if (_priceRating == 0 ||
        _presentationRating == 0 ||
        _staffBehaviorRating == 0 ||
        _foodQualityRating == 0 ||
        _overallRating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please rate all questions, including overall rating'),
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      await _storeFeedbackLocally();
      await _storeFeedbackInFirestore();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Feedback submitted successfully')),
      );

      // After submitting, allow submitting another feedback.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => FeedbackPage(email: widget.email),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving feedback: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Give Feedback'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Scrollbar(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Email: ${widget.email}',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _shopController,
                  decoration: const InputDecoration(
                    labelText: 'Shop name',
                    hintText: 'Enter shop / branch name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Please rate the following:',
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                _buildQuestionWithStars(
                  context,
                  questionText:
                      'Is the price appropriate for the quantity you receive?',
                  currentValue: _priceRating,
                  onChanged: (value) {
                    setState(() {
                      _priceRating = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                _buildQuestionWithStars(
                  context,
                  questionText:
                      'How would you rate the presentation and hygiene at the shop?',
                  currentValue: _presentationRating,
                  onChanged: (value) {
                    setState(() {
                      _presentationRating = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                _buildQuestionWithStars(
                  context,
                  questionText:
                      'How would you rate the behaviour of the staff?',
                  currentValue: _staffBehaviorRating,
                  onChanged: (value) {
                    setState(() {
                      _staffBehaviorRating = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                _buildQuestionWithStars(
                  context,
                  questionText: 'How would you rate the food quality?',
                  currentValue: _foodQualityRating,
                  onChanged: (value) {
                    setState(() {
                      _foodQualityRating = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                _buildQuestionWithStars(
                  context,
                  questionText: 'Overall, how would you rate your experience?',
                  currentValue: _overallRating,
                  onChanged: (value) {
                    setState(() {
                      _overallRating = value;
                    });
                  },
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _submitFeedback,
                    icon: _isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
                    label: Text(
                        _isSubmitting ? 'Submitting...' : 'Submit Feedback'),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'After submitting you can give another rating.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuestionWithStars(
    BuildContext context, {
    required String questionText,
    required int currentValue,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          questionText,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: List.generate(5, (index) {
            final starIndex = index + 1;
            return IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              iconSize: 32,
              icon: Icon(
                starIndex <= currentValue
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
                color: Colors.amber,
              ),
              onPressed: () => onChanged(starIndex),
            );
          }),
        ),
      ],
    );
  }
}
