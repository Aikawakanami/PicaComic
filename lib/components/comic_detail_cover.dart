import 'package:flutter/material.dart';

/// Keeps a working entry cover and loads the detail cover only on failure.
class ComicDetailCover extends StatefulWidget {
  const ComicDetailCover({
    super.key,
    required this.entryUrl,
    required this.detailUrl,
    required this.imageFor,
    required this.onOpen,
    required this.onDetailCoverShown,
  });

  final String? entryUrl;
  final String? detailUrl;
  final ImageProvider Function(String url) imageFor;
  final void Function(String url, ImageProvider image) onOpen;
  final void Function(String url) onDetailCoverShown;

  @override
  State<ComicDetailCover> createState() => _ComicDetailCoverState();
}

class _ComicDetailCoverState extends State<ComicDetailCover> {
  String? _reportedDetailUrl;

  @override
  void didUpdateWidget(covariant ComicDetailCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.entryUrl != oldWidget.entryUrl ||
        widget.detailUrl != oldWidget.detailUrl) {
      _reportedDetailUrl = null;
    }
  }

  Widget _missingCover(BuildContext context) => ColoredBox(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: const Center(child: Icon(Icons.error)),
      );

  Widget _image(String url, {String? fallback}) {
    final provider = widget.imageFor(url);
    return Image(
      key: ValueKey(url),
      image: provider,
      fit: BoxFit.cover,
      frameBuilder: (context, child, frame, synchronouslyLoaded) {
        if (frame == null && !synchronouslyLoaded) return child;
        if (widget.detailUrl == url && _reportedDetailUrl != url) {
          _reportedDetailUrl = url;
          final entry = widget.entryUrl;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted &&
                widget.entryUrl == entry &&
                widget.detailUrl == url) {
              widget.onDetailCoverShown(url);
            }
          });
        }
        return GestureDetector(
          onTap: () => widget.onOpen(url, provider),
          child: child,
        );
      },
      errorBuilder: (context, error, stackTrace) =>
          fallback == null ? _missingCover(context) : _image(fallback),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entryUrl;
    final detail = widget.detailUrl;
    if (entry != null) {
      return _image(entry, fallback: detail == entry ? null : detail);
    }
    return detail == null ? _missingCover(context) : _image(detail);
  }
}
