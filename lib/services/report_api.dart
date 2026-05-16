import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Reasons we surface in the report dialog. The string values match the
/// `reason` CHECK constraint in `0010_reports.sql` exactly — adding a
/// case here must be paired with a migration.
enum ReportReason {
  spam,
  harassment,
  fakeProfile,
  inappropriateContent,
  underage,
  scam,
  other,
}

extension ReportReasonDb on ReportReason {
  String get dbValue {
    switch (this) {
      case ReportReason.spam:
        return 'spam';
      case ReportReason.harassment:
        return 'harassment';
      case ReportReason.fakeProfile:
        return 'fake_profile';
      case ReportReason.inappropriateContent:
        return 'inappropriate_content';
      case ReportReason.underage:
        return 'underage';
      case ReportReason.scam:
        return 'scam';
      case ReportReason.other:
        return 'other';
    }
  }

  /// AppStrings key for the human-readable label.
  String get i18nKey {
    switch (this) {
      case ReportReason.spam:
        return 'report_reason_spam';
      case ReportReason.harassment:
        return 'report_reason_harassment';
      case ReportReason.fakeProfile:
        return 'report_reason_fake';
      case ReportReason.inappropriateContent:
        return 'report_reason_inappropriate';
      case ReportReason.underage:
        return 'report_reason_underage';
      case ReportReason.scam:
        return 'report_reason_scam';
      case ReportReason.other:
        return 'report_reason_other';
    }
  }
}

abstract final class ReportApi {
  static SupabaseClient get _c => Supabase.instance.client;

  /// Insert a moderation report. Returns true on success. Best-effort:
  /// network / RLS failures only surface in the debug log, the caller
  /// gets a bool to decide whether to show a "thanks" or "error" toast.
  static Future<bool> submit({
    required String reporterId,
    required String reportedId,
    required ReportReason reason,
    String? details,
  }) async {
    if (!isSupabaseReady) return false;
    if (reporterId.isEmpty || reportedId.isEmpty || reporterId == reportedId) {
      return false;
    }
    try {
      final body = <String, dynamic>{
        'reporter': reporterId,
        'reported': reportedId,
        'reason': reason.dbValue,
      };
      final trimmed = details?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        body['details'] = trimmed;
      }
      await _c.from('reports').insert(body);
      return true;
    } catch (e) {
      debugPrint('ReportApi.submit failed: $e');
      return false;
    }
  }
}
