import 'package:flutter/material.dart';
import 'package:pica_comic/foundation/favorite_query.dart';
import 'package:pica_comic/tools/translations.dart';

String favoriteSortLabel(FavoriteSort sort) => switch (sort) {
      FavoriteSort.manual => '排序'.tl,
      FavoriteSort.lastRead => '最后阅读时间'.tl,
      FavoriteSort.readCount => '阅读次数'.tl,
      FavoriteSort.readTime => '阅读时长'.tl,
      FavoriteSort.imageCount => '图片数量'.tl,
    };

/// Wrap controls on narrow screens instead of shrinking touch targets.
class FavoriteViewControls extends StatelessWidget {
  const FavoriteViewControls(
      {super.key,
      required this.options,
      required this.onChanged,
      required this.onRefresh});
  final FavoriteViewOptions options;
  final ValueChanged<FavoriteViewOptions> onChanged;
  final VoidCallback onRefresh;
  @override
  Widget build(BuildContext context) => Material(
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            PopupMenuButton<FavoriteSort>(
              tooltip: '排序'.tl,
              initialValue:
                  options.sort == FavoriteSort.manual ? null : options.sort,
              onSelected: (value) => onChanged(options.copyWith(
                  sort: value == options.sort ? FavoriteSort.manual : value,
                  descending: value != options.sort)),
              itemBuilder: (_) => [
                for (final value in FavoriteSort.values
                    .where((sort) => sort != FavoriteSort.manual))
                  CheckedPopupMenuItem(
                      value: value,
                      checked: value == options.sort,
                      child: Text(favoriteSortLabel(value)))
              ],
              child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.sort),
                    const SizedBox(width: 8),
                    Text(favoriteSortLabel(options.sort))
                  ])),
            ),
            if (options.sort != FavoriteSort.manual)
              IconButton(
                  tooltip: options.descending ? '降序'.tl : '升序'.tl,
                  icon: Icon(options.descending
                      ? Icons.arrow_downward
                      : Icons.arrow_upward),
                  onPressed: () => onChanged(
                      options.copyWith(descending: !options.descending))),
            IconButton(
                tooltip: options.paged ? '切换连续模式'.tl : '切换分页模式'.tl,
                icon: Icon(options.paged
                    ? Icons.view_carousel_outlined
                    : Icons.view_stream_outlined),
                onPressed: () =>
                    onChanged(options.copyWith(paged: !options.paged))),
            if (options.paged)
              PopupMenuButton<int>(
                  tooltip: '每页数量'.tl,
                  initialValue: options.pageSize,
                  onSelected: (size) =>
                      onChanged(options.copyWith(pageSize: size)),
                  itemBuilder: (_) => [
                        for (final size in favoritePageSizes)
                          CheckedPopupMenuItem(
                              value: size,
                              checked: size == options.pageSize,
                              child: Text('$size'))
                      ],
                  child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text('${options.pageSize} / ${"页".tl}'))),
            IconButton(
                tooltip: '刷新并重新排序'.tl,
                icon: const Icon(Icons.refresh),
                onPressed: onRefresh),
          ])));
}

class FavoritePager extends StatelessWidget {
  const FavoritePager(
      {super.key,
      required this.page,
      required this.pages,
      required this.total,
      required this.onChanged});
  final int page, pages, total;
  final ValueChanged<int> onChanged;
  Future<void> _jump(BuildContext context) async {
    final text = TextEditingController(text: '$page');
    final result = await showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text('跳转页码'.tl),
                content: TextField(
                    controller: text,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    onSubmitted: (value) {
                      final p = int.tryParse(value);
                      if (p != null && p >= 1 && p <= pages) {
                        Navigator.pop(context, p);
                      }
                    },
                    decoration: InputDecoration(helperText: '1 – $pages')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('取消'.tl)),
                  TextButton(
                      onPressed: () {
                        final p = int.tryParse(text.text);
                        if (p != null && p >= 1 && p <= pages) {
                          Navigator.pop(context, p);
                        }
                      },
                      child: Text('确认'.tl))
                ]));
    // The dialog's exit animation may still reference its controller.
    Future.delayed(const Duration(seconds: 1), text.dispose);
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) => Material(
      child: SafeArea(
          top: false,
          bottom: false,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
                tooltip: '上一页'.tl,
                onPressed: page > 1 ? () => onChanged(page - 1) : null,
                icon: const Icon(Icons.chevron_left)),
            TextButton(
                onPressed: () => _jump(context),
                child: Text('$page / $pages · $total')),
            IconButton(
                tooltip: '下一页'.tl,
                onPressed: page < pages ? () => onChanged(page + 1) : null,
                icon: const Icon(Icons.chevron_right)),
          ])));
}
