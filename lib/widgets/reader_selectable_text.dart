import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef ReaderTextAction = void Function(String selectedText);

class ReaderSelectableText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final TextAlign? textAlign;
  final ReaderTextAction? onNote;
  final ReaderTextAction? onSpeak;
  final ReaderTextAction? onSearch;
  final ReaderTextAction? onSettings;
  final ReaderTextAction? onShare;

  const ReaderSelectableText(
    this.text, {
    super.key,
    required this.style,
    this.textAlign,
    this.onNote,
    this.onSpeak,
    this.onSearch,
    this.onSettings,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return SelectableText(
      text,
      style: style,
      textAlign: textAlign,
      contextMenuBuilder: (context, editableTextState) {
        final selectedText = _selectedText(editableTextState);
        if (selectedText.isEmpty) {
          return AdaptiveTextSelectionToolbar.editableText(
            editableTextState: editableTextState,
          );
        }

        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: editableTextState.contextMenuAnchors,
          buttonItems: [
            ContextMenuButtonItem(
              label: 'Sao chép',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: selectedText));
                editableTextState.hideToolbar();
                _showSnack(context, 'Đã sao chép đoạn chọn');
              },
            ),
            if (onNote != null)
              ContextMenuButtonItem(
                label: 'Ghi chú',
                onPressed: () {
                  editableTextState.hideToolbar(false);
                  onNote!(selectedText);
                },
              ),
            if (onSpeak != null)
              ContextMenuButtonItem(
                label: 'Đọc',
                onPressed: () {
                  editableTextState.hideToolbar(false);
                  onSpeak!(selectedText);
                },
              ),
            if (onSearch != null)
              ContextMenuButtonItem(
                label: 'Tìm kiếm',
                onPressed: () {
                  editableTextState.hideToolbar(false);
                  onSearch!(selectedText);
                },
              ),
            if (onSettings != null)
              ContextMenuButtonItem(
                label: 'Cài đặt',
                onPressed: () {
                  editableTextState.hideToolbar(false);
                  onSettings!(selectedText);
                },
              ),
            if (onShare != null)
              ContextMenuButtonItem(
                label: 'Chia sẻ',
                onPressed: () {
                  editableTextState.hideToolbar();
                  onShare!(selectedText);
                },
              ),
          ],
        );
      },
    );
  }

  static String _selectedText(EditableTextState state) {
    final value = state.textEditingValue;
    final selection = value.selection;
    if (!selection.isValid || selection.isCollapsed) return '';
    return selection.textInside(value.text).trim();
  }

  static void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1000),
      ),
    );
  }
}
