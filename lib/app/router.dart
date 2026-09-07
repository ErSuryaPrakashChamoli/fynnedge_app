import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/ai/ai_screen.dart';
import '../features/applications/application_detail_screen.dart';
import '../features/applications/applications_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/otp_screen.dart';
import '../features/explore/explore_screen.dart';
import '../features/fynnlab/emi_calculator_screen.dart';
import '../features/fynnlab/fynnlab_screen.dart';
import '../features/fynnlab/other_calculators.dart';
import '../features/home/home_screen.dart';
import '../features/loans/compare_screen.dart';
import '../features/applications/application_review_screen.dart';
import '../features/loans/fynn_mirror_screen.dart';
import '../features/loans/fynn_trust_screen.dart';
import '../features/loans/loan_detail_screen.dart';
import '../features/loans/loan_discovery_screen.dart';
import '../features/loans/loan_options_screen.dart';
import '../features/onboarding/basic_profile_screen.dart';
import '../features/onboarding/goal_screen.dart';
import '../features/onboarding/intent_screen.dart';
import '../features/profile/financial_profile_screen.dart';
import '../features/profile/goals_screen.dart';
import '../features/profile/notifications_screen.dart';
import '../features/credit/credit_screen.dart';
import '../features/profile/privacy_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/profile/support_screen.dart';
import '../features/score/fynn_score_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/splash/splash_screen.dart';
import '../features/twin/twin_screen.dart';
import '../features/vault/fynn_scan_screen.dart';
import '../features/vault/kyc_screen.dart';
import '../features/vault/scan_screen.dart';
import '../features/vault/second_opinion_screen.dart';
import '../features/vault/vault_screen.dart';
import '../features/welcome/welcome_screen.dart';
import 'theme/app_colors.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _homeKey = GlobalKey<NavigatorState>(debugLabel: 'home');
final _exploreKey = GlobalKey<NavigatorState>(debugLabel: 'explore');
final _aiKey = GlobalKey<NavigatorState>(debugLabel: 'ai');
final _activityKey = GlobalKey<NavigatorState>(debugLabel: 'activity');
final _profileKey = GlobalKey<NavigatorState>(debugLabel: 'profile');

/// Every route in FynnEdge. Screens 1–7 sit outside the shell; the five
/// persistent destinations live inside it; everything else pushes on top.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/',
    routes: [
      // ---------------------------------------------------------- onboarding
      GoRoute(path: '/', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: '/otp',
        builder: (context, state) => OtpScreen(devHint: state.extra as String?),
      ),
      GoRoute(
        path: '/onboarding/profile',
        builder: (_, _) => const BasicProfileScreen(),
      ),
      GoRoute(
        path: '/onboarding/intent',
        builder: (_, _) => const IntentScreen(),
      ),
      GoRoute(path: '/onboarding/goal', builder: (_, _) => const GoalScreen()),

      // --------------------------------------------------------- main shell
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            navigatorKey: _homeKey,
            routes: [
              GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _exploreKey,
            routes: [
              GoRoute(
                path: '/explore',
                builder: (_, _) => const ExploreScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _aiKey,
            routes: [GoRoute(path: '/ai', builder: (_, _) => const AiScreen())],
          ),
          StatefulShellBranch(
            navigatorKey: _activityKey,
            routes: [
              GoRoute(
                path: '/applications',
                builder: (_, _) => const ApplicationsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _profileKey,
            routes: [
              GoRoute(
                path: '/profile',
                builder: (_, _) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),

      // ------------------------------------------------------------- loans
      GoRoute(
        path: '/loan-discovery',
        parentNavigatorKey: _rootKey,
        pageBuilder: (context, state) =>
            fadeThrough(child: const LoanDiscoveryScreen(), state: state),
      ),
      GoRoute(
        path: '/loan-options',
        parentNavigatorKey: _rootKey,
        pageBuilder: (context, state) =>
            fadeThrough(child: const LoanOptionsScreen(), state: state),
      ),
      GoRoute(
        path: '/loan/:id',
        parentNavigatorKey: _rootKey,
        pageBuilder: (context, state) => fadeThrough(
          child: LoanDetailScreen(productId: state.pathParameters['id']!),
          state: state,
        ),
      ),
      GoRoute(
        path: '/apply/:id',
        parentNavigatorKey: _rootKey,
        pageBuilder: (context, state) => fadeThrough(
          child: ApplicationReviewScreen(
            productId: state.pathParameters['id']!,
          ),
          state: state,
        ),
      ),
      GoRoute(
        path: '/fynn-twin',
        parentNavigatorKey: _rootKey,
        pageBuilder: (context, state) {
          // Optional: arriving from a loan the customer is already looking
          // at, so FynnTwin opens on that loan rather than on defaults.
          final q = state.uri.queryParameters;
          return fadeThrough(
            child: TwinScreen(
              productId: q['product'],
              amount: double.tryParse(q['amount'] ?? ''),
              tenureMonths: int.tryParse(q['tenure'] ?? ''),
            ),
            state: state,
          );
        },
      ),
      GoRoute(
        path: '/compare',
        parentNavigatorKey: _rootKey,
        pageBuilder: (context, state) =>
            fadeThrough(child: const CompareScreen(), state: state),
      ),
      GoRoute(
        path: '/fynn-trust/:id',
        parentNavigatorKey: _rootKey,
        pageBuilder: (context, state) => fadeThrough(
          child: FynnTrustScreen(productId: state.pathParameters['id']!),
          state: state,
        ),
      ),
      GoRoute(
        path: '/fynn-mirror/:id',
        parentNavigatorKey: _rootKey,
        pageBuilder: (context, state) => fadeThrough(
          child: FynnMirrorScreen(productId: state.pathParameters['id']!),
          state: state,
        ),
      ),
      // ----------------------------------------------------------- fynnlab
      GoRoute(
        path: '/fynnlab',
        parentNavigatorKey: _rootKey,
        pageBuilder: (context, state) =>
            fadeThrough(child: const FynnLabScreen(), state: state),
        routes: [
          GoRoute(
            path: 'emi',
            parentNavigatorKey: _rootKey,
            pageBuilder: (context, state) =>
                fadeThrough(child: const EmiCalculatorScreen(), state: state),
          ),
          GoRoute(
            path: 'affordability',
            parentNavigatorKey: _rootKey,
            pageBuilder: (context, state) =>
                fadeThrough(child: const AffordabilityScreen(), state: state),
          ),
          GoRoute(
            path: 'prepayment',
            parentNavigatorKey: _rootKey,
            pageBuilder: (context, state) =>
                fadeThrough(child: const PrepaymentScreen(), state: state),
          ),
          GoRoute(
            path: 'balance-transfer',
            parentNavigatorKey: _rootKey,
            pageBuilder: (context, state) =>
                fadeThrough(child: const BalanceTransferScreen(), state: state),
          ),
          GoRoute(
            path: 'emergency-fund',
            parentNavigatorKey: _rootKey,
            pageBuilder: (context, state) =>
                fadeThrough(child: const EmergencyFundScreen(), state: state),
          ),
        ],
      ),

      // ------------------------------------------------------------- score
      GoRoute(
        path: '/fynn-score',
        parentNavigatorKey: _rootKey,
        pageBuilder: (context, state) =>
            fadeThrough(child: const FynnScoreScreen(), state: state),
      ),

      // ------------------------------------------------------ applications
      GoRoute(
        path: '/applications/:id',
        parentNavigatorKey: _rootKey,
        pageBuilder: (context, state) => fadeThrough(
          child: ApplicationDetailScreen(id: state.pathParameters['id']!),
          state: state,
        ),
      ),

      // ------------------------------------------------------------- vault
      GoRoute(
        path: '/vault',
        parentNavigatorKey: _rootKey,
        pageBuilder: (context, state) =>
            fadeThrough(child: const VaultScreen(), state: state),
      ),
      GoRoute(
        path: '/scan',
        parentNavigatorKey: _rootKey,
        pageBuilder: (context, state) =>
            fadeThrough(child: const ScanScreen(), state: state),
      ),
      GoRoute(
        path: '/scan/:id',
        parentNavigatorKey: _rootKey,
        pageBuilder: (context, state) => fadeThrough(
          child: FynnScanScreen(documentId: state.pathParameters['id']!),
          state: state,
        ),
      ),
      GoRoute(
        path: '/kyc/:id',
        parentNavigatorKey: _rootKey,
        pageBuilder: (context, state) => fadeThrough(
          child: KycScreen(documentId: state.pathParameters['id']!),
          state: state,
        ),
      ),
      GoRoute(
        path: '/second-opinion',
        parentNavigatorKey: _rootKey,
        pageBuilder: (context, state) =>
            fadeThrough(child: const SecondOpinionScreen(), state: state),
      ),

      // ----------------------------------------------------------- account
      GoRoute(
        path: '/financial-profile',
        parentNavigatorKey: _rootKey,
        pageBuilder: (context, state) =>
            fadeThrough(child: const FinancialProfileScreen(), state: state),
      ),
      GoRoute(
        path: '/goals',
        parentNavigatorKey: _rootKey,
        pageBuilder: (context, state) =>
            fadeThrough(child: const GoalsScreen(), state: state),
      ),
      GoRoute(
        path: '/notifications',
        parentNavigatorKey: _rootKey,
        pageBuilder: (context, state) =>
            fadeThrough(child: const NotificationsScreen(), state: state),
      ),
      GoRoute(
        path: '/credit',
        parentNavigatorKey: _rootKey,
        pageBuilder: (context, state) =>
            fadeThrough(child: const CreditScreen(), state: state),
      ),
      GoRoute(
        path: '/privacy',
        parentNavigatorKey: _rootKey,
        pageBuilder: (context, state) => fadeThrough(
          // ?section=ai lands the customer on AI Memory rather than the top.
          child: PrivacyScreen(section: state.uri.queryParameters['section']),
          state: state,
        ),
      ),
      GoRoute(
        path: '/support',
        parentNavigatorKey: _rootKey,
        pageBuilder: (context, state) =>
            fadeThrough(child: const SupportScreen(), state: state),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.explore_off_rounded,
                size: 40,
                color: AppColors.textTertiary,
              ),
              const SizedBox(height: 16),
              Text(
                'No screen at ${state.uri}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => context.go('/home'),
                child: const Text('Back to Home'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
});

/// Fade+rise transition used for pushed detail screens.
CustomTransitionPage<T> fadeThrough<T>({
  required Widget child,
  required GoRouterState state,
}) => CustomTransitionPage<T>(
  key: state.pageKey,
  transitionDuration: const Duration(milliseconds: 320),
  reverseTransitionDuration: const Duration(milliseconds: 220),
  child: child,
  transitionsBuilder: (context, animation, secondary, child) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.02),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  },
);
