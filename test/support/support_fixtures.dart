import 'package:fynnedge/core/utils/clock.dart';
import 'package:fynnedge/data/models/support.dart';

/// Support fixtures, shared by the unit tests and the golden catalogue.
///
/// Every one of these is a case the API can genuinely produce: the same
/// categories, the same status labels and sentences, the same reference
/// shape. A fixture with invented copy would be a picture of a screen that
/// cannot happen, and would let the real copy overflow unnoticed.
const List<SupportCategoryOption> supportCategories = [
  SupportCategoryOption(
    id: 'submission_status',
    label: 'Application status',
    description: 'Where an application has got to, and what happens next.',
  ),
  SupportCategoryOption(
    id: 'application',
    label: 'Application help',
    description: 'Something about an application you started.',
  ),
  SupportCategoryOption(
    id: 'documents',
    label: 'Document help',
    description: 'A document that will not upload, or was not accepted.',
  ),
  SupportCategoryOption(
    id: 'financial_guidance',
    label: 'Financial guidance',
    description: 'Whether borrowing makes sense for you right now.',
  ),
  SupportCategoryOption(
    id: 'account',
    label: 'Account help',
    description: 'Signing in, your details, or closing your account.',
  ),
  SupportCategoryOption(
    id: 'technical',
    label: 'Technical issue',
    description: 'Something in the app is not working.',
  ),
  SupportCategoryOption(
    id: 'general',
    label: 'Something else',
    description: 'Anything that does not fit the rest.',
  ),
];

SupportCase supportCase({
  String id = '1',
  String reference = 'FE-SUP-2026-000001',
  String category = 'general',
  String categoryLabel = 'Something else',
  SupportCaseStatus status = SupportCaseStatus.open,
  String statusLabel = 'Open',
  String statusDescription =
      'Your request has been recorded. We will come back to you.',
  String subject = 'A question about my account',
  String? description,
  String priority = 'normal',
  SupportContext? context,
  List<SupportMessage> messages = const [],
  List<SupportEvent> timeline = const [],
  Duration age = const Duration(hours: 2),
}) => SupportCase(
  id: id,
  reference: reference,
  category: category,
  categoryLabel: categoryLabel,
  status: status,
  statusLabel: statusLabel,
  statusDescription: statusDescription,
  isOpen: status != SupportCaseStatus.closed,
  acceptsMessages: status != SupportCaseStatus.closed,
  priority: priority,
  subject: subject,
  description: description,
  context: context,
  messages: messages,
  timeline: timeline,
  createdAt: AppClock.now().subtract(age),
);
