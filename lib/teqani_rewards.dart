library teqani_rewards;

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'dart:convert';

import 'src/models/achievement.dart';
import 'src/models/streak.dart';
import 'src/models/challenge.dart';
import 'src/theme/teqani_rewards_theme.dart';
import 'src/widgets/streak_widgets.dart';
import 'src/widgets/achievement_widgets.dart';
import 'src/widgets/challenge_widgets.dart' hide DotsPatternPainter;
import 'src/onboarding/onboarding_screen.dart';
import 'src/storage/storage_manager.dart';
import 'src/services/analytics_service.dart';

export 'src/teqani_rewards.dart';
export 'src/services/analytics_service.dart';
export 'src/theme/teqani_rewards_theme.dart';
export 'src/models/achievement.dart';
export 'src/models/streak.dart';
export 'src/models/challenge.dart';
export 'src/widgets/achievement_widgets.dart';
export 'src/widgets/streak_widgets.dart';
export 'src/widgets/challenge_widgets.dart' hide DotsPatternPainter;
export 'src/onboarding/onboarding_screen.dart';
export 'src/onboarding/gamified_onboarding.dart';
export 'src/onboarding/quest_onboarding.dart';
export 'src/onboarding/pulse_onboarding.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Main entry point for the Teqani Rewards package
class TeqaniRewards {
  static TeqaniRewardsTheme? _theme;
  static StorageManager? _storageManager;
  static bool _isInitialized = false;
  static FirebaseAnalytics? _analytics;

  static Future<void> init({
    TeqaniRewardsTheme? theme,
    StorageType storageType = StorageType.sharedPreferences,
    Map<String, dynamic>? storageOptions,
    bool enableAnalytics = true,
  }) async {
    if (_isInitialized) {
      return;
    }

    _theme = theme ?? TeqaniRewardsTheme.defaultTheme;
    _storageManager = StorageManager(
      storageType: storageType,
      options: storageOptions,
    );
    await _storageManager!.initialize();

    if (enableAnalytics) {
      try {
        _analytics = FirebaseAnalytics.instance;
        await _analytics!.setAnalyticsCollectionEnabled(true);
        // Log event removed
      } catch (e) {
        debugPrint('Failed to initialize Firebase Analytics: $e');
      }
    }

    _isInitialized = true;
  }

  static TeqaniRewardsTheme get theme =>
      _theme ?? TeqaniRewardsTheme.defaultTheme;

  static StorageManager get storageManager {
    if (_storageManager == null) {
      throw Exception('TeqaniRewards is not initialized. Call TeqaniRewards.init() first.');
    }
    return _storageManager!;
  }

  static FirebaseAnalytics? get analytics => _analytics;

  static TeqaniAnalyticsService? get analyticsService =>
      _analytics != null ? TeqaniAnalyticsService(analytics: _analytics) : null;

  static bool get isInitialized => _isInitialized;

  static final streaks = TeqaniStreakWidgets();
  static final achievements = TeqaniAchievementWidgets();
  static final challenges = TeqaniChallengeWidgets();
  static final onboarding = TeqaniOnboardingWidgets();

  FirebaseFirestore? _firestore;
  FirebaseAuth? _auth;
  SharedPreferences? _prefs;
  String? _userId;
  StorageType _storageType = StorageType.sharedPreferences;

  Future<void> initialize({
    FirebaseApp? app,
    String? userId,
    StorageType storageType = StorageType.sharedPreferences,
  }) async {
    _storageType = storageType;

    if (storageType == StorageType.firebase) {
      if (app == null) {
        throw Exception('FirebaseApp is required when using Firebase storage');
      }
      _firestore = FirebaseFirestore.instance;
      _auth = FirebaseAuth.instance;
      _userId = userId ?? _auth?.currentUser?.uid;
    } else {
      _prefs = await SharedPreferences.getInstance();
      _userId = userId ?? 'local_user';
    }
  }

  Future<List<Achievement>> getAchievements() async {
    if (_storageType == StorageType.firebase) {
      if (_userId == null) throw Exception('User not authenticated');

      final snapshot = await _firestore!
          .collection('users')
          .doc(_userId)
          .collection('achievements')
          .get();

      return snapshot.docs
          .map((doc) => Achievement.fromJson(doc.data()))
          .toList();
    } else {
      final achievementsJson = _prefs?.getString('achievements_$_userId');
      if (achievementsJson == null) return [];

      final List<dynamic> decoded = jsonDecode(achievementsJson);
      return decoded.map((json) => Achievement.fromJson(json)).toList();
    }
  }

  Future<void> unlockAchievement(String achievementId) async {
    if (_storageType == StorageType.firebase) {
      if (_userId == null) throw Exception('User not authenticated');

      final achievement = await _firestore!
          .collection('users')
          .doc(_userId)
          .collection('achievements')
          .doc(achievementId)
          .get();

      if (!achievement.exists) {
        throw Exception('Achievement not found');
      }

      await _firestore!
          .collection('users')
          .doc(_userId)
          .collection('achievements')
          .doc(achievementId)
          .update({
        'isUnlocked': true,
        'unlockedAt': DateTime.now().toIso8601String(),
      });
    } else {
      final achievements = await getAchievements();
      final achievementIndex =
      achievements.indexWhere((a) => a.id == achievementId);

      if (achievementIndex == -1) {
        throw Exception('Achievement not found');
      }

      achievements[achievementIndex] = achievements[achievementIndex].copyWith(
        isUnlocked: true,
        unlockedAt: DateTime.now(),
      );

      await _prefs?.setString(
        'achievements_$_userId',
        jsonEncode(achievements.map((a) => a.toJson()).toList()),
      );
    }
  }

  Future<Streak> getStreak(String streakType) async {
    if (_storageType == StorageType.firebase) {
      if (_userId == null) throw Exception('User not authenticated');

      final snapshot = await _firestore!
          .collection('users')
          .doc(_userId)
          .collection('streaks')
          .doc(streakType)
          .get();

      if (!snapshot.exists) {
        return Streak(
          id: streakType,
          currentStreak: 0,
          longestStreak: 0,
          lastActivityDate: DateTime.now(),
          streakType: streakType,
        );
      }

      return Streak.fromJson(snapshot.data()!);
    } else {
      final streakJson = _prefs?.getString('streak_${_userId}_$streakType');
      if (streakJson == null) {
        return Streak(
          id: streakType,
          currentStreak: 0,
          longestStreak: 0,
          lastActivityDate: DateTime.now(),
          streakType: streakType,
        );
      }

      return Streak.fromJson(jsonDecode(streakJson));
    }
  }

  Future<void> updateStreak(String streakType) async {
    if (_userId == null) throw Exception('User not authenticated');

    final streak = await getStreak(streakType);
    final now = DateTime.now();
    final daysSinceLastActivity = streak.getDaysSinceLastActivity();

    int newCurrentStreak = streak.currentStreak;
    if (daysSinceLastActivity == 0) {
      return;
    } else if (daysSinceLastActivity == 1) {
      newCurrentStreak++;
    } else {
      newCurrentStreak = 1;
    }

    final newStreak = Streak(
      id: streakType,
      currentStreak: newCurrentStreak,
      longestStreak: newCurrentStreak > streak.longestStreak
          ? newCurrentStreak
          : streak.longestStreak,
      lastActivityDate: now,
      streakType: streakType,
    );

    if (_storageType == StorageType.firebase) {
      await _firestore!
          .collection('users')
          .doc(_userId)
          .collection('streaks')
          .doc(streakType)
          .set(newStreak.toJson());
    } else {
      await _prefs?.setString(
        'streak_${_userId}_$streakType',
        jsonEncode(newStreak.toJson()),
      );
    }
  }

  Future<List<Challenge>> getChallenges() async {
    if (_storageType == StorageType.firebase) {
      if (_userId == null) throw Exception('User not authenticated');

      final snapshot = await _firestore!
          .collection('users')
          .doc(_userId)
          .collection('challenges')
          .get();

      return snapshot.docs
          .map((doc) => Challenge.fromJson(doc.data()))
          .toList();
    } else {
      final challengesJson = _prefs?.getString('challenges_$_userId');
      if (challengesJson == null) return [];

      final List<dynamic> decoded = jsonDecode(challengesJson);
      return decoded.map((json) => Challenge.fromJson(json)).toList();
    }
  }

  Future<void> updateChallengeProgress(
      String challengeId, double progress) async {
    if (_storageType == StorageType.firebase) {
      if (_userId == null) throw Exception('User not authenticated');

      final challenge = await _firestore!
          .collection('users')
          .doc(_userId)
          .collection('challenges')
          .doc(challengeId)
          .get();

      if (!challenge.exists) {
        throw Exception('Challenge not found');
      }

      await _firestore!
          .collection('users')
          .doc(_userId)
          .collection('challenges')
          .doc(challengeId)
          .update({
        'progress': progress,
        'lastUpdated': DateTime.now().toIso8601String(),
      });
    } else {
      final challenges = await getChallenges();
      final challengeIndex = challenges.indexWhere((c) => c.id == challengeId);

      if (challengeIndex == -1) {
        throw Exception('Challenge not found');
      }

      challenges[challengeIndex] = challenges[challengeIndex].copyWith(
        progress: progress,
        lastUpdated: DateTime.now(),
      );

      await _prefs?.setString(
        'challenges_$_userId',
        jsonEncode(challenges.map((c) => c.toJson()).toList()),
      );
    }
  }
}

/// Available storage types for persisting data
enum StorageType {
  /// Uses SharedPreferences for local storage
  sharedPreferences,

  /// Uses SQLite database for local storage
  sqlite,

  /// Uses Hive for local storage
  hive,

  /// Uses Firebase for cloud storage
  firebase,

  /// Uses custom storage implementation
  custom,
}
