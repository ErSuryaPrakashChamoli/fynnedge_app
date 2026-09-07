import '../models/consent.dart';

/// The consent catalogue, mirroring App\Domain\Consent\ConsentType.
///
/// **The backend is authoritative.** This exists so mock mode offers exactly
/// what the API offers — including refusing the same things — and
/// test/consent_parity_test.dart asserts the two against a fixture the
/// Laravel side generated. If they diverge, that test fails.
///
/// NOTE FOR PRODUCT/LEGAL: these are v1 of FynnEdge's own plain-English
/// descriptions of what the software does. No privacy policy or terms
/// document exists in this project yet.
class MockConsents {
  const MockConsents._();

  static List<ConsentItem> catalogue() => const [
    ConsentItem(
      type: ConsentType.serviceTerms,
      label: 'Using FynnEdge',
      description:
          'FynnEdge uses the income, expenses, EMIs and savings you enter to '
          'work out your FynnScore, which products fit, and what a loan would '
          'cost you. Without this there is nothing for FynnEdge to calculate.',
      isRequired: true,
      isAvailable: true,
      isGranted: false,
      currentVersion: 'v1',
    ),
    ConsentItem(
      type: ConsentType.privacyNotice,
      label: 'How we use your information',
      description:
          'Your figures are stored against your account and used to produce '
          'the numbers you see in the app. They are not sold, and they are '
          'not shared with anyone outside FynnEdge.',
      isRequired: true,
      isAvailable: true,
      isGranted: false,
      currentVersion: 'v1',
    ),
    ConsentItem(
      type: ConsentType.aiMemory,
      label: 'FynnAI remembers your figures',
      description:
          'FynnAI reads your financial profile so its answers use your actual '
          'numbers instead of generic advice. Turn this off and it answers '
          'without them.',
      isRequired: false,
      isAvailable: true,
      isGranted: false,
      currentVersion: 'v1',
    ),

    // Not offered: the capability behind each of these does not exist, and
    // consent to something FynnEdge cannot do is not consent to anything.
    ConsentItem(
      type: ConsentType.creditBureauCheck,
      label: 'Credit information check',
      description:
          'Would let FynnEdge ask a credit bureau for your credit score. '
          'FynnEdge has no bureau connection, so there is nothing to permit '
          'yet.',
      isRequired: false,
      isAvailable: false,
      isGranted: false,
      unavailableReason:
          'Available when a credit bureau connection exists. FynnEdge will '
          'ask you then.',
    ),
    ConsentItem(
      type: ConsentType.documentProcessing,
      label: 'Reading your documents',
      description:
          'Would let FynnEdge send a document to a document-processing '
          'provider to read it. FynnEdge has no such connection, so there is '
          'nothing to permit yet.',
      isRequired: false,
      isAvailable: false,
      isGranted: false,
      unavailableReason:
          'Available when a document-reading service exists. FynnEdge will '
          'ask you then.',
    ),
    ConsentItem(
      type: ConsentType.identityVerification,
      label: 'Checking your identity document',
      description:
          'Would let FynnEdge have an identity document checked by a '
          'verification service. FynnEdge has no such connection, so there '
          'is nothing to permit yet.',
      isRequired: false,
      isAvailable: false,
      isGranted: false,
      unavailableReason:
          'Available when a verification service exists. FynnEdge will ask '
          'you then.',
    ),
    ConsentItem(
      type: ConsentType.lenderDataSharing,
      label: 'Sharing with a provider',
      description:
          'Would let FynnEdge send an application to a provider. FynnEdge '
          'has no submission connection, so applications are recorded by '
          'FynnEdge and sent to nobody.',
      isRequired: false,
      isAvailable: false,
      isGranted: false,
      unavailableReason:
          'Available when a submission provider exists. FynnEdge will ask '
          'you then.',
    ),
    ConsentItem(
      type: ConsentType.aiTraining,
      label: 'Improving FynnAI',
      description:
          'Would allow your conversations to be reviewed to improve FynnAI. '
          'Nothing reviews them today.',
      isRequired: false,
      isAvailable: false,
      isGranted: false,
      unavailableReason:
          'Available if FynnEdge ever reviews conversations. It does not '
          'today.',
    ),
    ConsentItem(
      type: ConsentType.marketingMessages,
      label: 'Offers and updates',
      description:
          'Would allow FynnEdge to send you offers and updates. FynnEdge '
          'sends none.',
      isRequired: false,
      isAvailable: false,
      isGranted: false,
      unavailableReason:
          'Available if FynnEdge starts sending messages. It does not today.',
    ),
  ];
}
