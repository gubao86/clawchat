import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';

class InlineButton {
  final String text;
  final String callbackData;
  final String style; // 'primary' | 'success' | 'danger' | 'default'

  const InlineButton({
    required this.text,
    required this.callbackData,
    this.style = 'default',
  });

  factory InlineButton.fromJson(Map<String, dynamic> j) => InlineButton(
    text:         j['text'] ?? '',
    callbackData: j['callback_data'] ?? j['callbackData'] ?? '',
    style:        j['style'] ?? 'default',
  );
}

class InlineButtonGrid extends StatefulWidget {
  final List<List<InlineButton>> buttons;
  final void Function(String callbackData) onPressed;
  /// Called externally to reset loading state (e.g. after stream_end)
  final VoidCallback? onResetLoading;

  const InlineButtonGrid({
    super.key,
    required this.buttons,
    required this.onPressed,
    this.onResetLoading,
  });

  @override
  State<InlineButtonGrid> createState() => _InlineButtonGridState();
}

class _InlineButtonGridState extends State<InlineButtonGrid> {
  String? _loadingCallback;

  void resetLoading() {
    if (mounted) setState(() => _loadingCallback = null);
  }

  Color _bgColor(String style) {
    switch (style) {
      case 'primary': return const Color(0xFF1E3A5F);
      case 'success': return const Color(0xFF1A3D2E);
      case 'danger':  return const Color(0xFF3D1A1A);
      default:        return const Color(0xFF2D3748);
    }
  }

  Color _borderColor(String style) {
    switch (style) {
      case 'primary': return const Color(0xFF3B82F6);
      case 'success': return const Color(0xFF10B981);
      case 'danger':  return const Color(0xFFEF4444);
      default:        return const Color(0xFF4A5568);
    }
  }

  Color _textColor(String style) {
    switch (style) {
      case 'primary': return const Color(0xFF93C5FD);
      case 'success': return const Color(0xFF6EE7B7);
      case 'danger':  return const Color(0xFFFCA5A5);
      default:        return Colors.grey[300]!;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Auto-reset loading when streaming ends
    final isStreaming = context.watch<ChatProvider>().isStreaming;
    if (!isStreaming && _loadingCallback != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _loadingCallback = null);
      });
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: widget.buttons.map((row) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: row.map((btn) {
                final isLoading = _loadingCallback == btn.callbackData;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _loadingCallback != null ? null : () {
                          setState(() => _loadingCallback = btn.callbackData);
                          widget.onPressed(btn.callbackData);
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: _bgColor(btn.style),
                            border: Border.all(color: _borderColor(btn.style).withOpacity(0.5)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: isLoading
                              ? SizedBox(
                                  width: 14, height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: _textColor(btn.style),
                                  ),
                                )
                              : Text(
                                  btn.text,
                                  style: TextStyle(
                                    color: _textColor(btn.style),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }
}
