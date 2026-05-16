import 'package:flutter/material.dart';

import '../services/app_strings.dart';
import '../services/report_api.dart';
import '../theme/whatsapp_call_theme.dart';

/// Modal that asks the user to pick a moderation reason + optional
/// details, then submits via [ReportApi].
///
/// Returns `true` if the report was successfully submitted, `false` if
/// the user cancelled, and surfaces failures via a snackbar on the
/// supplied [context]. Either way the underlying dialog is closed
/// before this returns.
///
/// Designed to be called from anywhere a peer is reachable (profile
/// screen, chat list, in-thread menu, etc.).
Future<bool> showReportDialog(
  BuildContext context, {
  required String reporterId,
  required String reportedId,
  required String peerName,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => _ReportDialog(
      reporterId: reporterId,
      reportedId: reportedId,
      peerName: peerName,
    ),
  );
  return result == true;
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({
    required this.reporterId,
    required this.reportedId,
    required this.peerName,
  });

  final String reporterId;
  final String reportedId;
  final String peerName;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  ReportReason _reason = ReportReason.harassment;
  final _detailsCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _detailsCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final ok = await ReportApi.submit(
      reporterId: widget.reporterId,
      reportedId: widget.reportedId,
      reason: _reason,
      details: _detailsCtrl.text,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.t('report_thanks'))),
      );
    } else {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.t('report_failed'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: WhatsAppCallTheme.bar,
      title: Text(
        AppStrings.t('report_q', args: {'name': widget.peerName}),
        style: const TextStyle(color: WhatsAppCallTheme.strongText),
      ),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppStrings.t('report_body'),
              style: const TextStyle(
                color: WhatsAppCallTheme.subtleText,
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            for (final r in ReportReason.values)
              RadioListTile<ReportReason>(
                value: r,
                groupValue: _reason,
                onChanged: _submitting
                    ? null
                    : (v) => setState(() => _reason = v ?? _reason),
                dense: true,
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                activeColor: WhatsAppCallTheme.accent,
                title: Text(
                  AppStrings.t(r.i18nKey),
                  style: const TextStyle(
                    color: WhatsAppCallTheme.strongText,
                    fontSize: 14,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _detailsCtrl,
              enabled: !_submitting,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              cursorColor: WhatsAppCallTheme.accent,
              style: const TextStyle(color: WhatsAppCallTheme.strongText),
              decoration: InputDecoration(
                hintText: AppStrings.t('report_details_hint'),
                hintStyle:
                    const TextStyle(color: WhatsAppCallTheme.subtleText),
                filled: true,
                fillColor: WhatsAppCallTheme.scaffold,
                border: const OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: Text(AppStrings.t('cancel')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFE53935),
          ),
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(AppStrings.t('report_submit')),
        ),
      ],
    );
  }
}
