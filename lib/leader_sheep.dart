import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class LeaderboardPage extends StatelessWidget {
  const LeaderboardPage({super.key, this.currentEmail});

  final String? currentEmail;

  Stream<List<_ShopLeaderboardEntry>> _leaderboardStreamAll() {
    // Note: we also have a root-level `shops` collection for shop master data.
    // Filter by overallRating so only feedback docs are included in leaderboard.
    return FirebaseFirestore.instance
        .collectionGroup('shops')
        .where('overallRating', isGreaterThan: 0)
        .snapshots()
        .map((snapshot) {
          log("Getting All Shops Data List : ${snapshot.docs.length}");
          return _mapSnapshotToEntries(snapshot);
        });
  }

  Stream<List<_ShopLeaderboardEntry>> _leaderboardStreamForEmail(String email) {
    return FirebaseFirestore.instance
        .collection('feedbackByUser')
        .doc(email)
        .collection('shops')
        .snapshots()
        .map((snapshot) {
          log(
            "Getting My Shops Data List for $email : ${snapshot.docs.length}",
          );
          return _mapSnapshotToEntries(snapshot);
        });
  }

  List<_ShopLeaderboardEntry> _mapSnapshotToEntries(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final Map<String, _MutableShopAggregate> aggregates = {};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final rawShopName = (data['shopName'] ?? '').toString().trim();
      if (rawShopName.isEmpty) continue;

      // Normalize shop name for grouping so "XYZ" and "xyz" are treated the same.
      final normalizedShopName = rawShopName.toLowerCase();

      // Prefer explicit overall rating, but fall back to averaging other fields
      // so older feedback without overallRating is still counted.
      final overall = data['overallRating'];
      double? overallForDoc;
      if (overall is num) {
        overallForDoc = overall.toDouble();
      } else if (overall != null) {
        overallForDoc = double.tryParse('$overall');
      }

      if (overallForDoc == null) {
        // Fallback: compute average from individual category ratings if available.
        final candidates = <num?>[
          data['priceRating'],
          data['presentationAndHygieneRating'],
          data['staffBehaviorRating'],
          data['foodQualityRating'],
        ].whereType<num>().toList();

        if (candidates.isNotEmpty) {
          overallForDoc =
              candidates.fold<double>(0.0, (sum, v) => sum + v.toDouble()) /
              candidates.length;
        }
      }

      if (overallForDoc == null) continue;

      var ratingValue = overallForDoc.round();
      if (ratingValue < 1 || ratingValue > 5) continue;

      final agg = aggregates.putIfAbsent(
        normalizedShopName,
        () => _MutableShopAggregate(rawShopName),
      );
      agg.addRating(ratingValue);
    }

    final list = aggregates.values.map((e) => e.toEntry()).toList();
    list.sort((a, b) {
      // Sort by average rating desc, then by total count desc, then by name.
      final avgCompare = b.averageRating.compareTo(a.averageRating);
      if (avgCompare != 0) return avgCompare;
      final countCompare = b.totalCount.compareTo(a.totalCount);
      if (countCompare != 0) return countCompare;
      return a.shopName.toLowerCase().compareTo(b.shopName.toLowerCase());
    });
    return list;
  }

  Widget _buildLeaderboardList(
    BuildContext context,
    Stream<List<_ShopLeaderboardEntry>> stream,
  ) {
    return StreamBuilder<List<_ShopLeaderboardEntry>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: SelectableText(
                'Error loading leaderboard: ${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final shops = snapshot.data ?? [];
        if (shops.isEmpty) {
          return const Center(child: Text('No feedback available yet.'));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16.0),
          itemCount: shops.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final entry = shops[index];
            return Card(
              elevation: 2,
              child: ListTile(
                leading: CircleAvatar(child: Text('${index + 1}')),
                title: Text(entry.shopName),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      'Average rating: ${entry.averageRating.toStringAsFixed(1)} ★ '
                      '(${entry.totalCount} rating${entry.totalCount == 1 ? '' : 's'})',
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '5★: ${entry.ratingCounts[5] ?? 0}   '
                      '4★: ${entry.ratingCounts[4] ?? 0}   '
                      '3★: ${entry.ratingCounts[3] ?? 0}   '
                      '2★: ${entry.ratingCounts[2] ?? 0}   '
                      '1★: ${entry.ratingCounts[1] ?? 0}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                trailing: Chip(
                  label: Text(
                    '${entry.averageRating.toStringAsFixed(1)} ★',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  backgroundColor: Colors.amber.shade100,
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Shop Leaderboard'),
          centerTitle: true,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'My shops'),
              Tab(text: 'All shops'),
            ],
          ),
        ),
        body: Stack(
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

            TabBarView(
              children: [
                if (currentEmail == null || currentEmail!.isEmpty)
                  const Center(
                    child: Text('No email available to filter by user.'),
                  )
                else
                  _buildLeaderboardList(
                    context,
                    _leaderboardStreamForEmail(currentEmail!),
                  ),
                _buildLeaderboardList(context, _leaderboardStreamAll()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MutableShopAggregate {
  _MutableShopAggregate(this.shopName);

  /// Display name for the shop (first seen casing).
  final String shopName;
  int totalCount = 0;
  double totalRating = 0;
  final Map<int, int> ratingCounts = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};

  void addRating(int rating) {
    totalCount++;
    totalRating += rating;
    ratingCounts[rating] = (ratingCounts[rating] ?? 0) + 1;
  }

  _ShopLeaderboardEntry toEntry() {
    final avg = totalCount == 0 ? 0.0 : totalRating / totalCount;
    return _ShopLeaderboardEntry(
      shopName: shopName,
      averageRating: avg,
      totalCount: totalCount,
      ratingCounts: Map<int, int>.from(ratingCounts),
    );
  }
}

class _ShopLeaderboardEntry {
  const _ShopLeaderboardEntry({
    required this.shopName,
    required this.averageRating,
    required this.totalCount,
    required this.ratingCounts,
  });

  final String shopName;
  final double averageRating;
  final int totalCount;
  final Map<int, int> ratingCounts;
}
