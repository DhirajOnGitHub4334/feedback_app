import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:feedback_app/leader_sheep.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key, required this.email});

  final String email;

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  String? _selectedShopId;
  String? _selectedShopName;
  String? _selectedEmployeeName;
  int _priceRating = 0;
  int _presentationRating = 0;
  int _staffBehaviorRating = 0;
  int _foodQualityRating = 0;
  int _overallRating = 0;
  bool _isSubmitting = false;

  Future<void> _storeFeedbackLocally() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('feedback_submissions');
    final List<dynamic> list = raw == null || raw.isEmpty
        ? <dynamic>[]
        : (jsonDecode(raw) as List);

    list.add({
      'email': widget.email,
      'shopName': _selectedShopName,
      'shopId': _selectedShopId,
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
    final shopName = _selectedShopName?.trim() ?? '';
    final shopId = _selectedShopId?.trim() ?? '';
    if (shopName.isEmpty || shopId.isEmpty) return;

    final data = {
      'email': widget.email,
      'shopName': shopName,
      'shopId': shopId,
      'priceRating': _priceRating,
      'presentationAndHygieneRating': _presentationRating,
      'staffBehaviorRating': _staffBehaviorRating,
      'foodQualityRating': _foodQualityRating,
      'overallRating': _overallRating,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final firestore = FirebaseFirestore.instance;

    // 1) Keep a unique list of shops (one doc per shop).
    // Structure: shops/{shopId}
    // await firestore.collection('shops').doc(shopId).set({
    //   'shopId': shopId,
    //   'shopName': shopName,
    //   'shopNameLower': shopName.toLowerCase(),
    //   'updatedAt': FieldValue.serverTimestamp(),
    // }, SetOptions(merge: true));

    // 2) Store user feedback (one doc per email per shop).
    // Structure: feedbackByUser/{email}/shops/{shopId}
    await firestore
        .collection('feedbackByUser')
        .doc(widget.email)
        .collection('shops')
        .doc(shopId)
        .set(data, SetOptions(merge: true));
  }

  Future<void> _submitFeedback() async {
    final selectedShopId = _selectedShopId;
    // final selectedShopName = _selectedShopName;

    if ((selectedShopId ?? '').isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a shop')));
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
        MaterialPageRoute(builder: (_) => FeedbackPage(email: widget.email)),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error saving feedback: $e')));
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
        actions: [
          IconButton(
            icon: const Icon(Icons.leaderboard),
            tooltip: 'View leaderboard',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LeaderboardPage(currentEmail: widget.email),
                ),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Stack(
          children: [
            Container(
              padding: EdgeInsets.all(20),
              height: MediaQuery.of(context).size.height,
              width: MediaQuery.of(context).size.width,
              child: Image.asset(
                "assets/images/one.png",
                opacity: AlwaysStoppedAnimation(0.1),
              ),
            ),
            Scrollbar(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Email: ${widget.email}',
                      style: Theme.of(context).textTheme.titleMedium!.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('shops')
                          .orderBy('shopNameLower')
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Text(
                            'Error loading shops: ${snapshot.error}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          );
                        }

                        final docs = snapshot.data?.docs ?? [];
                        final items = docs
                            .map((d) {
                              final data = d.data();
                              final shopId = (data['shopId'] ?? d.id)
                                  .toString();
                              final shopName = (data['shopName'] ?? '')
                                  .toString()
                                  .trim();
                              final employeeName = (data['employeeName'] ?? '')
                                  .toString()
                                  .trim();
                              if (shopName.isEmpty) return null;
                              return DropdownMenuItem<String>(
                                value: shopId,
                                child: Text(
                                  employeeName.isEmpty
                                      ? shopName
                                      : '$shopName  •  $employeeName',
                                ),
                              );
                            })
                            .whereType<DropdownMenuItem<String>>()
                            .toList();

                        return DropdownButtonFormField<String>(
                          key: ValueKey(_selectedShopId),
                          menuMaxHeight: 300,
                          isDense: true,

                          value: _selectedShopId,
                          items: items,
                          decoration: const InputDecoration(
                            labelText: 'Shop name',
                            border: OutlineInputBorder(),
                          ),
                          hint:
                              snapshot.connectionState ==
                                  ConnectionState.waiting
                              ? const Text('Loading shops...')
                              : const Text('Select shop'),
                          onChanged: (value) {
                            if (value == null) return;
                            final selectedDoc = docs.firstWhere(
                              (d) =>
                                  (d.data()['shopId'] ?? d.id).toString() ==
                                  value,
                              //orElse: () => docs.firstWhere((d) => d.id == value),
                            );
                            final data = selectedDoc.data();
                            setState(() {
                              _selectedShopId =
                                  (data['shopId'] ?? selectedDoc.id).toString();
                              _selectedShopName = (data['shopName'] ?? '')
                                  .toString()
                                  .trim();
                              _selectedEmployeeName =
                                  (data['employeeName'] ?? '')
                                      .toString()
                                      .trim();
                            });
                          },
                        );
                      },
                    ),
                    if ((_selectedEmployeeName ?? '').isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Employee: $_selectedEmployeeName',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
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
                      questionText:
                          'Overall, how would you rate your experience?',
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
                          _isSubmitting ? 'Submitting...' : 'Submit Feedback',
                        ),
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
          ],
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
          style: Theme.of(
            context,
          ).textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.bold),
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
                color: Colors.red,
              ),
              onPressed: () => onChanged(starIndex),
            );
          }),
        ),
      ],
    );
  }
}
