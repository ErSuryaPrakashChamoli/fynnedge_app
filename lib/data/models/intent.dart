import 'package:flutter/material.dart';

import 'json.dart';
import 'loan.dart';

/// Screen 6 — what brought the customer to FynnEdge.
enum IntentOption {
  needLoan(
    'need_loan',
    'I need a loan',
    'Explore options matched to your profile',
    Icons.account_balance_rounded,
  ),
  reduceEmi(
    'reduce_emi',
    'I want to reduce my EMI',
    'Refinance, balance transfer or restructure',
    Icons.trending_down_rounded,
  ),
  compareOffers(
    'compare_offers',
    'I want to compare loan offers',
    'See the real cost side by side',
    Icons.compare_arrows_rounded,
  ),
  checkHealth(
    'check_health',
    'I want to check my financial health',
    'Get your FynnScore and where you stand',
    Icons.favorite_rounded,
  ),
  planGoal(
    'plan_goal',
    'I want to plan for a future goal',
    'Build towards something specific',
    Icons.flag_rounded,
  ),
  exploring(
    'exploring',
    "I'm just exploring",
    'Take a look around, no pressure',
    Icons.explore_rounded,
  );

  const IntentOption(this.id, this.label, this.description, this.icon);

  final String id;
  final String label;
  final String description;
  final IconData icon;

  static IntentOption? fromId(String? id) {
    if (id == null) return null;
    for (final o in IntentOption.values) {
      if (o.id == id) return o;
    }
    return null;
  }
}

/// Screen 7 — what the customer is planning for.
enum GoalCategory {
  business('business', 'Business', Icons.storefront_rounded),
  home('home', 'Home', Icons.home_rounded),
  car('car', 'Car', Icons.directions_car_rounded),
  education('education', 'Education', Icons.school_rounded),
  medical('medical', 'Medical / Emergency', Icons.local_hospital_rounded),
  debt('debt', 'Debt Management', Icons.account_balance_wallet_rounded),
  personal('personal', 'Personal Need', Icons.person_rounded),
  other('other', 'Other', Icons.more_horiz_rounded);

  const GoalCategory(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;

  static GoalCategory fromId(String? id) =>
      J.enumById(GoalCategory.values, id, (g) => g.id, GoalCategory.other);

  /// Which product category to open FynnMatch on for a goal of this kind.
  ///
  /// A starting point for the search, nothing more. The customer sees it on
  /// Loan Discovery and can change it, and FynnMatch alone decides what
  /// actually fits — a goal the catalogue cannot serve reaches the existing
  /// "nothing fits, and here is why" state rather than a fabricated match.
  ///
  /// The catalogue has four categories, so several goals share one. That is
  /// the catalogue's shape, not a judgement about the goal.
  LoanCategory get exploreCategory => switch (this) {
    GoalCategory.business => LoanCategory.business,
    GoalCategory.home => LoanCategory.home,
    GoalCategory.car ||
    GoalCategory.education ||
    GoalCategory.medical ||
    GoalCategory.debt ||
    GoalCategory.personal ||
    GoalCategory.other => LoanCategory.personal,
  };
}
