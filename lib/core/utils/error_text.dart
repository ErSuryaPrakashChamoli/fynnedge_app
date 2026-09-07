import '../../data/services/api_client.dart';

/// Turns a thrown failure into one sentence a customer can act on.
///
/// Field-level validation wins over the generic summary, because "Enter a
/// valid 10-digit mobile number" is useful and "The given data was invalid"
/// is not. Server faults are deliberately generic — internal detail must
/// never reach the screen.
String messageFor(Object error, {String? field}) {
  if (error is ValidationException) {
    if (field != null) {
      final fieldMessage = error.forField(field);
      if (fieldMessage != null) return fieldMessage;
    }
    if (error.hasFieldErrors) return error.errors.values.first.first;
    return error.message;
  }

  if (error is ApiException) return error.message;

  return 'Something went wrong. Please try again.';
}

/// True when retrying immediately is pointless — the customer must wait.
bool shouldWaitBeforeRetry(Object error) => error is RateLimitedException;

/// Message for a failed *load*, where there is nothing on screen to preserve.
String messageForLoad(Object error) => messageFor(error);
