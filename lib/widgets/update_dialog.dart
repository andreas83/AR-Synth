import 'package:flutter/material.dart';

import '../services/update_service.dart';
import '../theme.dart';

/// Prompts the user to install an available update, showing download progress
/// and handing off to the system installer.
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({
    super.key,
    required this.update,
    required this.service,
  });

  final UpdateInfo update;
  final UpdateService service;

  /// Shows the dialog. Returns true if the installer was launched.
  static Future<bool?> show(
    BuildContext context, {
    required UpdateInfo update,
    required UpdateService service,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(update: update, service: service),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _downloading = false;
  double _progress = 0;
  String? _error;

  Future<void> _install() async {
    setState(() {
      _downloading = true;
      _error = null;
      _progress = 0;
    });

    final String? error = await widget.service.downloadAndInstall(
      widget.update,
      onProgress: (double p) {
        if (mounted) setState(() => _progress = p);
      },
    );

    if (!mounted) return;
    if (error != null) {
      setState(() {
        _downloading = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final UpdateInfo u = widget.update;
    return AlertDialog(
      title: const Row(
        children: <Widget>[
          Icon(Icons.system_update, size: 22, color: AppTheme.primary),
          SizedBox(width: 10),
          Text('Update available'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Version ${u.version}'
            '${u.sizeLabel.isNotEmpty ? ' · ${u.sizeLabel}' : ''}\n'
            'You have ${u.currentVersion}.',
            style: const TextStyle(fontSize: 14),
          ),
          if (u.notes.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(
                child: Text(
                  u.notes,
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ),
            ),
          ],
          if (_downloading) ...<Widget>[
            const SizedBox(height: 18),
            LinearProgressIndicator(value: _progress > 0 ? _progress : null),
            const SizedBox(height: 6),
            Text(
              _progress > 0
                  ? 'Downloading… ${(_progress * 100).round()}%'
                  : 'Downloading…',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: 14),
            Text(
              _error!,
              style: const TextStyle(fontSize: 12, color: Colors.orangeAccent),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed:
              _downloading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: _downloading ? null : _install,
          child: Text(_error != null ? 'Retry' : 'Install'),
        ),
      ],
    );
  }
}
