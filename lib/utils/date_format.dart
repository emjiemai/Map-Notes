import 'package:intl/intl.dart';

/// Full, unambiguous timestamp — month, day, year, and time — used
/// wherever a rep's pin or comment timestamp is shown. Deliberately not a
/// relative "2h ago" style format: the whole point of showing this is so
/// it can be checked against exactly when a visit happened, not roughly.
String formatPinTimestamp(DateTime dateTime) {
  return DateFormat.yMMMd().add_jm().format(dateTime);
}
