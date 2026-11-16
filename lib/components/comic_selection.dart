part of 'components.dart';

/// Selection belongs to a list, and uses the same identity as the favorites DB.
class ComicSelectionController extends ChangeNotifier {
  final _selected = <(int, String), FavoriteItem>{};
  bool active = false;
  bool busy = false;

  List<FavoriteItem> get selected => _selected.values.toList(growable: false);

  bool isSelected(FavoriteItem comic) =>
      _selected.containsKey((comic.type.key, comic.target));

  int countIn(Iterable<FavoriteItem> comics) => comics
      .map((comic) => (comic.type.key, comic.target))
      .toSet()
      .where(_selected.containsKey)
      .length;

  void _add(FavoriteItem comic) {
    _selected.putIfAbsent((comic.type.key, comic.target),
        () => FavoriteItem.fromJson(comic.toJson()));
  }

  void begin(FavoriteItem comic) {
    if (busy) return;
    active = true;
    _add(comic);
    notifyListeners();
  }

  void toggle(FavoriteItem comic) {
    if (busy) return;
    final key = (comic.type.key, comic.target);
    if (_selected.containsKey(key)) {
      _selected.remove(key);
    } else {
      _add(comic);
    }
    notifyListeners();
  }

  void selectAll(Iterable<FavoriteItem> comics) {
    if (busy) return;
    for (final comic in comics) {
      _add(comic);
    }
    notifyListeners();
  }

  void clear() {
    if (busy) return;
    _selected.clear();
    notifyListeners();
  }

  void exit({bool notify = true}) {
    if (busy) return;
    active = false;
    _selected.clear();
    if (notify) notifyListeners();
  }

  Future<FavoriteBatchResult?> save(
      Future<FavoriteBatchResult> Function(List<FavoriteItem>) writer) async {
    if (busy || _selected.isEmpty) return null;
    final snapshot = selected;
    busy = true;
    notifyListeners();
    try {
      final result = await writer(snapshot);
      _selected.clear();
      for (final comic in result.failed) {
        _selected[(comic.type.key, comic.target)] = comic;
      }
      active = result.failed.isNotEmpty;
      return result;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}

class ComicSelectionScope extends InheritedNotifier<ComicSelectionController> {
  const ComicSelectionScope({
    super.key,
    required ComicSelectionController controller,
    required super.child,
  }) : super(notifier: controller);

  static ComicSelectionController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ComicSelectionScope>()
      ?.notifier;
}

class ComicSelectionRegion extends StatelessWidget {
  const ComicSelectionRegion({
    super.key,
    required this.controller,
    required this.available,
    required this.paged,
    required this.child,
  });

  final ComicSelectionController controller;
  final List<FavoriteItem> available;
  final bool paged;
  final Widget child;

  Future<void> _showSelected(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('查看已选'.tl),
        content: SizedBox(
          width: 420,
          height: math.min(480, MediaQuery.sizeOf(dialogContext).height * 0.6),
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final comics = controller.selected;
              if (comics.isEmpty) {
                return Center(child: Text('未选择任何项目'.tl));
              }
              return ListView.builder(
                itemCount: comics.length,
                itemBuilder: (context, index) {
                  final comic = comics[index];
                  return ListTile(
                    title: Text(comic.name,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(comic.author.isEmpty
                        ? comic.type.name
                        : '${comic.type.name} · ${comic.author}'),
                    trailing: IconButton(
                      tooltip: '取消选择'.tl,
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: controller.busy
                          ? null
                          : () => controller.toggle(comic),
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('关闭'.tl),
          )
        ],
      ),
    );
  }

  Future<void> _save(BuildContext context) async {
    if (controller.busy || controller.selected.isEmpty) return;
    final manager = LocalFavoritesManager();
    final folders = manager.folderNames;
    if (folders.isEmpty) {
      showToast(message: '请先在本地收藏中新建收藏夹'.tl);
      return;
    }
    var folder = folders.contains(appdata.settings[51])
        ? appdata.settings[51]
        : folders.first;
    final target = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('添加收藏'.tl),
        content: DropdownButtonFormField<String>(
          initialValue: folder,
          decoration: InputDecoration(labelText: '收藏夹'.tl),
          isExpanded: true,
          items: [
            for (final name in folders)
              DropdownMenuItem(value: name, child: Text(name)),
          ],
          onChanged: (value) {
            if (value != null) folder = value;
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('取消'.tl),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(folder),
            child: Text('确认'.tl),
          ),
        ],
      ),
    );
    if (target == null || !context.mounted) return;
    await _saveToFolder(context, target);
  }

  Future<void> _quickSave(BuildContext context) async {
    if (controller.busy || controller.selected.isEmpty) return;
    final target = appdata.settings[51];
    if (!LocalFavoritesManager().folderNames.contains(target)) {
      showToast(message: '请先在设置的本地收藏中配置快速收藏夹'.tl);
      return;
    }
    await _saveToFolder(context, target);
  }

  Future<void> _saveToFolder(BuildContext context, String target) async {
    try {
      final result = await controller.save((comics) =>
          LocalFavoritesManager().addComicsToFolder(target, comics));
      if (result == null || !context.mounted || appdata.settings[90] != '1') {
        return;
      }
      showToast(
        atTop: true,
        message: '新增 @added，已存在 @existing，失败 @failed'.tlParams({
          'added': '${result.added.length}',
          'existing': '${result.existing.length}',
          'failed': '${result.failed.length}',
        }),
      );
    } catch (_) {
      if (context.mounted) {
        showToast(message: '收藏失败，请重试'.tl, atTop: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ComicSelectionScope(
      controller: controller,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => PopScope(
          canPop: !controller.active,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) controller.exit();
          },
          child: Column(
            children: [
              // Keep the list in the same element slot to preserve scroll offset.
              if (controller.active)
                Material(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            IconButton(
                              tooltip: '退出多选'.tl,
                              onPressed:
                                  controller.busy ? null : controller.exit,
                              icon: const Icon(Icons.close),
                            ),
                            Expanded(
                              child: Semantics(
                                liveRegion: true,
                                child: Text(paged
                                    ? '共选 @total 项，本页 @page 项'.tlParams({
                                        'total':
                                            '${controller.selected.length}',
                                        'page':
                                            '${controller.countIn(available)}',
                                      })
                                    : '已选择 @num 个项目'.tlParams({
                                        'num': '${controller.selected.length}',
                                      })),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(
                          width: double.infinity,
                          child: Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              IconButton(
                                tooltip: paged ? '全选当前页'.tl : '全选已加载'.tl,
                                iconSize: 32,
                                constraints: const BoxConstraints(
                                    minWidth: 48, minHeight: 48),
                                onPressed: controller.busy || available.isEmpty
                                    ? null
                                    : () => controller.selectAll(available),
                                icon: const Icon(Icons.select_all),
                              ),
                              IconButton(
                                tooltip: '全不选'.tl,
                                iconSize: 32,
                                constraints: const BoxConstraints(
                                    minWidth: 48, minHeight: 48),
                                onPressed: controller.busy ||
                                        controller.selected.isEmpty
                                    ? null
                                    : controller.clear,
                                icon: const Icon(Icons.deselect),
                              ),
                              IconButton(
                                tooltip: '查看已选'.tl,
                                iconSize: 32,
                                constraints: const BoxConstraints(
                                    minWidth: 48, minHeight: 48),
                                onPressed: controller.busy ||
                                        controller.selected.isEmpty
                                    ? null
                                    : () => _showSelected(context),
                                icon: const Icon(Icons.checklist),
                              ),
                              Tooltip(
                                message: '长按收藏按钮执行快速收藏'.tl,
                                child: FilledButton.icon(
                                  onPressed: controller.busy ||
                                          controller.selected.isEmpty
                                      ? null
                                      : () => _save(context),
                                  onLongPress: controller.busy ||
                                          controller.selected.isEmpty
                                      ? null
                                      : () => _quickSave(context),
                                  icon: controller.busy
                                      ? const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : const Icon(Icons.bookmark_add_outlined),
                                  label: Text('本地收藏'.tl),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                )
              else
                const SizedBox.shrink(),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
