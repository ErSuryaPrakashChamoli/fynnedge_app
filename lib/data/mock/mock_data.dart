// ---------------------------------------------------------------------------
// MOCK DATA — DEVELOPMENT ONLY
//
// Every fake value in FynnEdge lives in this file. Nothing here is a real
// lender, rate or offer; lender names are fictional on purpose so screenshots
// can never be mistaken for live market pricing.
//
// When the real backend lands, delete nothing — just flip ApiConfig.useMock to
// false. Mock services are the only consumers of this file.
// ---------------------------------------------------------------------------

import '../../core/utils/clock.dart';
import '../models/goal.dart';
import '../models/notification.dart';
import '../models/intent.dart';
import '../models/loan.dart';
import '../models/score.dart';
import '../models/user.dart';

class MockData {
  const MockData._();

  // A getter, not a cached field: tests freeze the clock and expect every
  // derived date to follow it.
  static DateTime get _now => AppClock.now();

  // -------------------------------------------------------------- customer
  static const UserProfile customer = UserProfile(
    id: 'usr_mock_001',
    mobile: '9876543210',
    fullName: 'Rahul Sharma',
    age: 34,
    city: 'Pune',
    email: 'rahul.sharma@example.com',
    intent: 'need_loan',
    primaryGoal: 'business',
  );

  static const FinancialProfile financials = FinancialProfile(
    monthlyIncome: 100000,
    monthlyExpenses: 40000,
    existingEmi: 20000,
    savings: 180000,
    employment: EmploymentType.business,
  );

  // ------------------------------------------------------------------ goals
  static List<Goal> get goals => [
    Goal(
      id: 'goal_1',
      title: 'Business Expansion',
      category: GoalCategory.business,
      targetAmount: 1500000,
      targetDate: _now.add(const Duration(days: 540)),
      savedAmount: 320000,
      note: 'Second outlet + inventory',
    ),
    Goal(
      id: 'goal_2',
      title: 'Emergency Fund',
      category: GoalCategory.medical,
      targetAmount: 360000,
      targetDate: _now.add(const Duration(days: 365)),
      savedAmount: 180000,
    ),
    Goal(
      id: 'goal_3',
      title: 'Buy a Home',
      category: GoalCategory.home,
      targetAmount: 8000000,
      targetDate: _now.add(const Duration(days: 1460)),
      savedAmount: 450000,
    ),
  ];

  // --------------------------------------------------------------- products
  static ScoreFactor _f(String label, int v, String why) =>
      ScoreFactor(label: label, value: v, explanation: why);

  static final List<LoanProduct> products = [
    LoanProduct(
      id: 'prod_pl_a',
      // Documented requirements FynnMatch can evaluate. Null on the products
      // that publish none — never a stand-in value.
      minMonthlyIncome: 40000,
      minAge: 23,
      maxAgeAtMaturity: 58,
      lender: 'Meridian Bank',
      name: 'Personal Loan A',
      lenderTag: 'Unsecured',
      category: LoanCategory.personal,
      minAmount: 500000,
      maxAmount: 1500000,
      interestRate: 11.5,
      minTenureMonths: 12,
      maxTenureMonths: 60,
      processingFeePercent: 1.0,
      processingFeeCap: 12000,
      fynnTrust: 86,
      prepaymentCharge: 'Nil after 6 EMIs',
      suitedReasons: [
        'The rate is among the lowest in your eligible set',
        'Prepayment is free after six EMIs, so you can close early',
        'Processing fee is capped at ₹12,000 regardless of loan size',
      ],
      considerations: [
        'Requires 2 years of income proof',
        'Rate quoted is the best-case rate for strong profiles',
      ],
      conditions: [
        'Minimum monthly income ₹40,000',
        'Age 23–58 at loan maturity',
        'Foreclosure permitted after 6 EMIs at nil charge',
      ],
      trustBreakdown: TrustBreakdown(
        cost: _f(
          'Cost',
          88,
          'At 11.5% this sits below the median rate for comparable personal loans in your band.',
        ),
        fees: _f(
          'Fees',
          84,
          'A 1% processing fee capped at ₹12,000 keeps the one-time cost predictable.',
        ),
        flexibility: _f(
          'Flexibility',
          90,
          'Free prepayment after six EMIs and tenure choices from 1 to 5 years.',
        ),
        suitability: _f(
          'Suitability',
          82,
          'The amount range and EMI fit your stated income and surplus.',
        ),
        transparency: _f(
          'Transparency',
          86,
          'All charges are published up front with no conditional add-ons.',
        ),
      ),
    ),
    LoanProduct(
      id: 'prod_pl_b',
      minMonthlyIncome: 30000,
      lender: 'Northline Finance',
      name: 'Personal Loan B',
      lenderTag: 'Flexible eligibility',
      category: LoanCategory.personal,
      minAmount: 300000,
      maxAmount: 1200000,
      interestRate: 12.5,
      minTenureMonths: 12,
      maxTenureMonths: 72,
      processingFeePercent: 1.5,
      fynnTrust: 78,
      prepaymentCharge: '2% of outstanding',
      suitedReasons: [
        'Accepts a wider range of income profiles',
        'Longer tenure available if you need a smaller EMI',
      ],
      considerations: [
        'Rate is 1 percentage point above the best option in your set',
        'Prepayment carries a 2% charge on the outstanding amount',
        'No cap on the processing fee',
      ],
      conditions: [
        'Minimum monthly income ₹30,000',
        'Prepayment allowed after 12 EMIs at 2%',
      ],
      trustBreakdown: TrustBreakdown(
        cost: _f(
          'Cost',
          72,
          'At 12.5% you pay noticeably more interest over the full tenure.',
        ),
        fees: _f(
          'Fees',
          68,
          'The 1.5% processing fee is uncapped, so it scales with the loan.',
        ),
        flexibility: _f(
          'Flexibility',
          74,
          'Tenure up to 72 months helps, but prepayment costs 2%.',
        ),
        suitability: _f(
          'Suitability',
          86,
          'The published eligibility rules are wider than most in this set.',
        ),
        transparency: _f(
          'Transparency',
          80,
          'Charges are disclosed, though the fee structure takes reading.',
        ),
      ),
    ),
    LoanProduct(
      id: 'prod_bl_a',
      lender: 'Arcus Capital',
      name: 'Business Growth Loan',
      lenderTag: 'For business owners',
      category: LoanCategory.business,
      minAmount: 500000,
      maxAmount: 5000000,
      interestRate: 13.25,
      minTenureMonths: 12,
      maxTenureMonths: 84,
      processingFeePercent: 1.75,
      fynnTrust: 81,
      prepaymentCharge: '3% before 24 EMIs, nil after',
      suitedReasons: [
        'Built for self-employed and business borrowers like you',
        'Amount range covers your ₹10L requirement comfortably',
        'Tenure up to 7 years keeps the EMI manageable',
      ],
      considerations: [
        'Business vintage of 3 years is required',
        'Early prepayment within 2 years carries a 3% charge',
      ],
      conditions: [
        'Business vintage minimum 3 years',
        'GST returns for the last 4 quarters',
        'Prepayment 3% before 24 EMIs',
      ],
      trustBreakdown: TrustBreakdown(
        cost: _f(
          'Cost',
          74,
          'Business loans price higher than personal loans; 13.25% is fair for this segment.',
        ),
        fees: _f(
          'Fees',
          70,
          'A 1.75% uncapped processing fee is on the higher side.',
        ),
        flexibility: _f(
          'Flexibility',
          78,
          'Long tenure options, but prepayment is penalised for two years.',
        ),
        suitability: _f(
          'Suitability',
          94,
          'Matches your business intent, amount and income profile closely.',
        ),
        transparency: _f(
          'Transparency',
          88,
          'Terms and charges are clearly stated with no hidden conditions.',
        ),
      ),
    ),
    LoanProduct(
      id: 'prod_bl_b',
      lender: 'United Credit Bank',
      name: 'SME Term Loan',
      lenderTag: 'Lowest rate in this set',
      category: LoanCategory.business,
      minAmount: 1000000,
      maxAmount: 7500000,
      interestRate: 12.4,
      minTenureMonths: 24,
      maxTenureMonths: 84,
      processingFeePercent: 1.0,
      processingFeeCap: 25000,
      fynnTrust: 89,
      prepaymentCharge: 'Nil after 12 EMIs',
      suitedReasons: [
        'The lowest published rate in this sample set for a business loan',
        'Processing fee is capped, saving you money at this loan size',
        'Free prepayment after the first year',
      ],
      considerations: [
        'Minimum loan amount is ₹10L, so this only works at your full ask',
        'The published minimum is high, so smaller amounts are not served',
      ],
      conditions: [
        'Audited financials for 2 years',
        'Minimum turnover ₹50L',
        'Collateral-free up to ₹25L',
      ],
      trustBreakdown: TrustBreakdown(
        cost: _f(
          'Cost',
          92,
          'At 12.4% this is the lowest published business rate in this sample set.',
        ),
        fees: _f(
          'Fees',
          90,
          'The ₹25,000 cap on a 1% fee is a meaningful saving at ₹10L+.',
        ),
        flexibility: _f(
          'Flexibility',
          86,
          'Prepay free after 12 EMIs, with tenure up to 84 months.',
        ),
        suitability: _f(
          'Suitability',
          84,
          'Well matched to your amount, though the process is slower.',
        ),
        transparency: _f(
          'Transparency',
          92,
          'Full schedule of charges published, including all edge cases.',
        ),
      ),
    ),
    LoanProduct(
      id: 'prod_hl_a',
      lender: 'Sentinel Housing Finance',
      name: 'Home Loan Prime',
      lenderTag: 'Long tenure',
      category: LoanCategory.home,
      minAmount: 2500000,
      maxAmount: 50000000,
      interestRate: 8.6,
      minTenureMonths: 60,
      maxTenureMonths: 360,
      processingFeePercent: 0.35,
      processingFeeCap: 15000,
      fynnTrust: 91,
      prepaymentCharge: 'Nil on floating rate',
      suitedReasons: [
        'Home loans carry the lowest interest of any borrowing you can do',
        'Floating-rate prepayment is free at any time',
      ],
      considerations: [
        'Requires property documents and legal verification',
        'Disbursal is linked to construction stage for under-construction property',
      ],
      conditions: [
        'Property must be approved by the lender panel',
        'Up to 80% of property value',
      ],
      trustBreakdown: TrustBreakdown(
        cost: _f(
          'Cost',
          96,
          'At 8.6% this is the lowest published rate in this sample set.',
        ),
        fees: _f(
          'Fees',
          92,
          'A 0.35% fee capped at ₹15,000 is very low relative to loan size.',
        ),
        flexibility: _f(
          'Flexibility',
          94,
          'Free prepayment on floating rate and tenure up to 30 years.',
        ),
        suitability: _f(
          'Suitability',
          70,
          'Only relevant if you are actually buying property.',
        ),
        transparency: _f(
          'Transparency',
          90,
          'Rate resets and charges are documented clearly.',
        ),
      ),
    ),
    LoanProduct(
      id: 'prod_lap_a',
      lender: 'Trilo Finserv',
      name: 'Loan Against Property',
      lenderTag: 'Secured',
      category: LoanCategory.lap,
      minAmount: 1000000,
      maxAmount: 20000000,
      interestRate: 10.25,
      minTenureMonths: 36,
      maxTenureMonths: 180,
      processingFeePercent: 1.0,
      fynnTrust: 83,
      prepaymentCharge: 'Nil for individual borrowers',
      suitedReasons: [
        'Cheaper than an unsecured business loan because it is secured',
        'Higher amounts available against your property value',
      ],
      considerations: [
        'Your property is at risk if repayments are missed',
        'Valuation and legal checks add 2 to 3 weeks',
      ],
      conditions: [
        'Property title must be clear and marketable',
        'Up to 60% of property value',
      ],
      trustBreakdown: TrustBreakdown(
        cost: _f(
          'Cost',
          86,
          'Secured lending at 10.25% undercuts unsecured business rates.',
        ),
        fees: _f('Fees', 76, 'A 1% uncapped fee is standard for this product.'),
        flexibility: _f(
          'Flexibility',
          88,
          'No prepayment charge for individual borrowers on floating rate.',
        ),
        suitability: _f(
          'Suitability',
          72,
          'Only suitable if you own property and accept the collateral risk.',
        ),
        transparency: _f(
          'Transparency',
          84,
          'Charges are clear, though valuation costs are billed separately.',
        ),
      ),
    ),
  ];

  // --------------------------------------------------------- notifications
  /// No notification has ever been sent.
  ///
  /// Nothing in FynnEdge writes one: no provider reports anything, no
  /// advisor replies, and no engine watches a figure over time. The four
  /// seeded items that used to live here are gone — one quoted an EMI ratio
  /// and a month-on-month change FynnEdge had never calculated, and one was
  /// a message from an advisor who does not exist. The API answers with an
  /// empty list, so mock mode does too, and what a customer sees is the
  /// screen's empty state.
  static const List<AppNotification> notifications = [];
}
