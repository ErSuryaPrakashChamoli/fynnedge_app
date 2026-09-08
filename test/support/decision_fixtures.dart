import 'package:fynnedge/core/utils/clock.dart';
import 'package:fynnedge/data/models/decision.dart';

/// Decision fixtures, shared by the unit tests and the golden catalogue.
///
/// Every one is something the API can genuinely produce: the same types,
/// the same provenance labels, the same "not assessed" lines. A fixture
/// carrying a claim the backend refuses to make would be a picture of a
/// screen that cannot exist.
DecisionExplanation get emiExplanation => const DecisionExplanation(
  title: 'How the monthly payment was worked out',
  rule: 'A monthly payment comes from three things: how much is borrowed, '
      'the annual rate, and how many months it runs for.',
  factors: [
    ExplanationFactor(
      label: 'Amount',
      value: '₹10,00,000',
      source: 'customer_provided',
      sourceLabel: 'You told us',
    ),
    ExplanationFactor(
      label: 'Interest rate',
      value: '13.25% a year',
      source: 'catalogue_published',
      sourceLabel: 'Published by the lender',
      note: 'FynnEdge did not set it.',
    ),
    ExplanationFactor(
      label: 'Term',
      value: '60 months',
      source: 'customer_provided',
      sourceLabel: 'You told us',
    ),
  ],
  result: ExplanationFactor(
    label: 'Monthly payment',
    value: '₹22,881',
    source: 'simulated',
    sourceLabel: 'Simulated',
    note: 'A what-if. Nothing was applied for.',
  ),
);

DecisionExplanation get affordabilityExplanation => const DecisionExplanation(
  title: 'What that would do to your monthly commitments',
  rule: "FynnEdge measures repayments against 45% of monthly income. That is "
      "FynnEdge's own reference, not a lender's rule — no lender has told us "
      'what they would accept.',
  factors: [
    ExplanationFactor(
      label: 'Monthly income',
      value: '₹1,50,000',
      source: 'customer_provided',
      sourceLabel: 'You told us',
      note: 'As it was at the time.',
    ),
    ExplanationFactor(
      label: 'Repayments already committed',
      value: '₹10,000',
      source: 'customer_provided',
      sourceLabel: 'You told us',
      note: 'As it was at the time.',
    ),
  ],
  result: ExplanationFactor(
    label: 'Share of income with this added',
    value: '21.92%',
    source: 'calculated',
    sourceLabel: 'FynnEdge worked this out',
  ),
  notAssessed: [
    'Whether a lender would approve this. No lender has told FynnEdge what '
        'they accept, so nothing here is a view on that.',
  ],
);

Decision get simulationDecision => Decision(
  id: 'd3',
  type: 'simulation',
  title: 'You ran a simulation',
  description: 'A what-if, worked out from the figures you entered. Nothing '
      'was applied for.',
  occurredAt: AppClock.now().subtract(const Duration(hours: 3)),
  isSimulated: true,
  product: const DecisionProduct(
    code: 'prod_bl_b',
    name: 'SME Term Loan',
    version: 4,
  ),
  explanation: [emiExplanation, affordabilityExplanation],
);

Decision get comparisonDecision => Decision(
  id: 'd2',
  type: 'comparison',
  title: 'You compared options',
  description: 'You looked at these side by side. FynnEdge picked no winner.',
  occurredAt: AppClock.now().subtract(const Duration(days: 2)),
  isSimulated: false,
  explanation: const [
    DecisionExplanation(
      title: 'What you compared',
      rule: 'FynnEdge showed these together, on the same criteria. It picked '
          'no winner and recorded no preference.',
      factors: [
        ExplanationFactor(
          label: 'Option',
          value: 'prod_bl_a',
          source: 'catalogue_published',
          sourceLabel: 'Published by the lender',
        ),
        ExplanationFactor(
          label: 'Option',
          value: 'prod_bl_b',
          source: 'catalogue_published',
          sourceLabel: 'Published by the lender',
        ),
      ],
      notAssessed: [
        'Which of these suits you best. That depends on things FynnEdge has '
            'not been told, and it did not decide.',
      ],
    ),
  ],
);

Decision get applicationDecision => Decision(
  id: 'a1:started',
  type: 'application_started',
  title: 'You started an application',
  description: 'An application was created with the terms shown at the time.',
  occurredAt: AppClock.now().subtract(const Duration(days: 9)),
  isSimulated: false,
  reference: 'FE-2026-000042',
  product: const DecisionProduct(
    code: 'prod_bl_b',
    name: 'SME Term Loan',
    version: 4,
  ),
  explanation: [emiExplanation],
);

List<Decision> get decisionHistory => [
  simulationDecision,
  comparisonDecision,
  applicationDecision,
];
