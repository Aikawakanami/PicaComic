part of 'components.dart';

class ComicsPageLogic<T> extends StateController {
  bool loading = true;

  final selection = ComicSelectionController();
  int _generation = 0;
  bool? _paged;
  int _sourcePagesPerPage = 1;
  int? _maxSourcePage;
  final _sourcePages = <int, List<T>>{};
  final _completedGroups = <int>{};
  final _groupErrors = <int, String>{};

  bool get groupsSourcePages => _sourcePagesPerPage > 1;

  void updateMode(bool paged, {int sourcePagesPerPage = 1}) {
    if (_paged != null && _paged != paged) selection.exit(notify: false);
    final count = paged ? sourcePagesPerPage : 1;
    if (_sourcePagesPerPage != count) {
      _sourcePagesPerPage = count;
      _resetPages();
    }
    _paged = paged;
  }

  ///用于正常模式下的漫画数据储存
  List<T>? comics;

  ///用于分页模式下的漫画数据储存
  Map<int, List<T>>? dividedComics;

  ///错误信息, null表示没有错误
  String? message;

  /// 最大页数, 为null表示不知道或者无穷
  int? maxPage;

  ///当前的页面序号
  int current = 1;

  ///是否正在获取数据， 用于在顺序浏览模式下， 避免同时进行多个网络请求
  bool loadingData = false;

  bool showFloatingButton = true;

  void get(Future<Res<List<T>>> Function(int) getComics) async {
    if (loadingData) return;
    if (groupsSourcePages) {
      await _loadGroup(getComics);
      return;
    }
    loadingData = true;
    final generation = _generation;
    Future.microtask(() => update());
    if (comics == null) {
      var res = await getComics(1);
      if (generation != _generation) return;
      if (res.error) {
        message = res.errorMessage;
      } else {
        comics = List<T>.of(res.data);
        dividedComics = {};
        dividedComics![1] = res.data;
        if (res.subData is int) {
          maxPage = res.subData;
        }
        if (res.data.isEmpty) {
          maxPage = 1;
        }
      }
      loading = false;
      loadingData = false;
      update();
    } else {
      final requestedPage = current;
      var res = await getComics(requestedPage);
      if (generation != _generation) return;
      if (res.error) {
        if (current == requestedPage) message = res.errorMessage;
      } else {
        dividedComics![requestedPage] = res.data;
        if (res.subData is int) maxPage = res.subData;
      }
      if (current == requestedPage) loading = false;
      loadingData = false;
      update();
    }
  }

  Future<void> _loadGroup(Future<Res<List<T>>> Function(int) getComics) async {
    loadingData = true;
    final generation = _generation;
    final requestedPage = current;
    final count = _sourcePagesPerPage;
    final first = (requestedPage - 1) * count + 1;
    final items = <T>[];
    String? error;
    await Future<void>.value();
    if (generation != _generation) return;

    for (var sourcePage = first; sourcePage < first + count; sourcePage++) {
      if (_maxSourcePage != null && sourcePage > _maxSourcePage!) break;
      var sourceItems = _sourcePages[sourcePage];
      if (sourceItems == null) {
        try {
          final response = await getComics(sourcePage);
          if (generation != _generation) return;
          if (response.error) {
            error = response.errorMessageWithoutNull;
            break;
          }
          final total = response.subData;
          if (total is int && total >= 0) {
            _maxSourcePage = total;
            maxPage = math.max(1, (total + count - 1) ~/ count);
            if (sourcePage > total) break;
          }
          sourceItems = response.data;
          _sourcePages[sourcePage] = sourceItems;
        } catch (exception) {
          if (generation != _generation) return;
          error = exception.toString();
          break;
        }
      }
      items.addAll(sourceItems);
      final previousLength = dividedComics?[requestedPage]?.length ?? 0;
      if (items.length > previousLength && current == requestedPage) {
        (dividedComics ??= {})[requestedPage] = List<T>.of(items);
        update();
      }
    }

    (dividedComics ??= {})[requestedPage] = items;
    if (error == null) {
      _completedGroups.add(requestedPage);
    } else {
      _groupErrors[requestedPage] = error;
    }
    loadingData = false;
    if (maxPage != null && current > maxPage!) current = maxPage!;
    _readGroupState();
    update();
  }

  void _readGroupState() {
    message = _groupErrors[current];
    loading = message == null && !_completedGroups.contains(current);
  }

  void changePage(int page) {
    if (selection.busy || page < 1 || page == current ||
        (maxPage != null && page > maxPage!)) {
      return;
    }
    current = page;
    if (groupsSourcePages) {
      _readGroupState();
    } else {
      message = null;
      loading = dividedComics?[page] == null;
    }
    update();
  }

  /// Retry the current request without discarding cross-page selections/cache.
  void retry() {
    if (selection.busy || loadingData) return;
    _groupErrors.remove(current);
    message = null;
    loading = true;
    update();
  }

  int _emptyPageCount = 0;

  void loadNextPage(Future<Res<List<T>>> Function(int) getComics) async {
    if (maxPage != null && current >= maxPage!) return;
    if (loadingData) return;
    loadingData = true;
    final generation = _generation;
    Future.microtask(() => update());
    var res = await getComics(current + 1);
    if (generation != _generation) return;
    if (res.error) {
      showToast(message: res.errorMessage!);
    } else {
      if (res.subData is int) {
        maxPage = res.subData;
      }
      if (res.data.isEmpty) {
        _emptyPageCount++;
        if (_emptyPageCount > 3 && maxPage == null) {
          // 某些漫画源不会返回总页数, 而app的网络代码会根据用户设置进行屏蔽操作
          // 空页面既可能是因为没有更多页面, 也可能是因为被屏蔽了
          // 如果连续3次加载空页面, 则认为已经加载完毕
          maxPage = current;
        }
        // 等待一会儿再加载, 避免因为某些错误导致无限加载
        await Future.delayed(const Duration(seconds: 1));
      } else {
        _emptyPageCount = 0;
        comics!.addAll(res.data);
      }
    }
    if (generation != _generation) return;
    current++;
    loadingData = false;
    update();
  }

  @override
  void refresh() {
    if (selection.busy) return;
    selection.exit();
    _resetPages();
    update();
  }

  void _resetPages() {
    _generation++;
    loadingData = false;
    current = 1;
    maxPage = null;
    _emptyPageCount = 0;
    loading = true;
    comics = null;
    dividedComics = null;
    message = null;
    _maxSourcePage = null;
    _sourcePages.clear();
    _completedGroups.clear();
    _groupErrors.clear();
  }
}

/// 漫画列表页面
///
/// T为漫画信息模型
abstract class ComicsPage<T extends BaseComic> extends StatelessWidget {
  const ComicsPage({super.key});

  ///标题
  String? get title;

  /// 是否居中标题
  bool get centerTitle => true;

  /// 获取图片, 参数为页面序号, **从1开始**
  ///
  /// 返回值Res的subData为页面总数
  Future<Res<List<T>>> getComics(int i);

  /// 漫画源标识符
  String get sourceKey;

  /// 显示一个刷新按钮, 需要Scaffold启用
  bool get withRefreshFloatingButton => false;

  String? get tag;

  Widget? get tailing => null;

  Widget? get header => null;

  bool get showPageIndicator => true;

  /// Opt-in only for the approved built-in browsing entry points.
  bool get enableMultiSelect => false;

  bool get _multiSelectEnabled =>
      enableMultiSelect &&
      const {'picacg', 'ehentai', 'jm', 'htmanga', 'nhentai'}
          .contains(sourceKey);

  List<ComicTileMenuOption>? get addonMenuOptions => null;

  /// 刷新页面
  void refresh() {
    StateController.find<ComicsPageLogic<T>>(tag: tag).refresh();
  }

  @override
  Widget build(context) {
    Widget? removeSliver(Widget? widget) {
      if (widget == null) return null;

      if (widget is SliverToBoxAdapter) {
        return widget.child;
      }

      if (widget is SliverPersistentHeader) {
        return SizedBox(
          height: widget.delegate.minExtent,
          child: widget.delegate.build(
            context,
            widget.delegate.minExtent,
            false,
          ),
        );
      }

      return widget;
    }

    Widget body = StateBuilder<ComicsPageLogic<T>>(
        init: ComicsPageLogic<T>(),
        tag: tag,
        builder: (logic) {
          final paged = appdata.settings[25] != '0';
          logic.updateMode(paged,
              sourcePagesPerPage: appdata.appSettings.browseSourcePagesPerPage);
          Widget buildList() {
            if (!logic.groupsSourcePages &&
                logic.dividedComics?[logic.current] == null &&
                logic.message == null &&
                paged) {
              logic.loading = true;
            }
            final hasPartialGroup = logic.groupsSourcePages &&
                (logic.dividedComics?[logic.current]?.isNotEmpty ?? false);
            if (logic.loading) logic.get(getComics);
            if (logic.loading && !hasPartialGroup) {
              return Column(
                children: [
                  if (title != null) const Appbar(title: Text("")),
                  removeSliver(header) ?? const SizedBox(),
                  const Expanded(
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  )
                ],
              );
            } else if (logic.message != null && !hasPartialGroup) {
              return Column(
                children: [
                  removeSliver(header) ?? const SizedBox(),
                  if (paged &&
                      (logic.comics != null ||
                          (logic.groupsSourcePages && logic.current > 1)) &&
                      showPageIndicator)
                    SizedBox(
                      width: double.infinity,
                      child: removeSliver(buildPageSelector(context, logic))!,
                    ),
                  Expanded(
                      child: NetworkError(
                    message: logic.message ?? "Network Error",
                    retry: logic.retry,
                    withAppbar: title != null,
                  ))
                ],
              );
            } else {
              if (!paged) {
                List<T> comics = [];
                if (appdata.appSettings.fullyHideBlockedWorks) {
                  for (var comic in logic.comics!) {
                    if (isBlocked(comic) == null) {
                      comics.add(comic);
                    }
                  }
                } else {
                  comics = logic.comics!;
                }
                if (comics.isEmpty) {
                  return SmoothCustomScrollView(
                    slivers: [
                      if (title != null)
                        SliverAppbar(
                          title: Text(title!),
                          actions: tailing != null ? [tailing!] : null,
                        ),
                      if (header != null) header!,
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: buildEmptyView(context),
                      ),
                    ],
                  );
                }
                return SmoothCustomScrollView(
                  slivers: [
                    if (title != null)
                      SliverAppbar(
                        title: Text(title!),
                        actions: tailing != null ? [tailing!] : null,
                      ),
                    if (header != null) header!,
                    SliverGrid(
                      delegate: SliverChildBuilderDelegate(
                          childCount: comics.length, (context, i) {
                        if (i == comics.length - 1) {
                          logic.loadNextPage(getComics);
                        }
                        return buildItem(context, comics[i]);
                      }),
                      gridDelegate: SliverGridDelegateWithComics(),
                    ),
                    if (logic.current < (logic.maxPage ?? 114514) &&
                        logic.loadingData)
                      const SliverToBoxAdapter(
                        child: ListLoadingIndicator(),
                      )
                    else
                      const SliverToBoxAdapter(
                        child: SizedBox(
                          height: 80,
                        ),
                      )
                  ],
                );
              } else {
                final groupStatus =
                    hasPartialGroup ? _buildGroupStatus(logic) : null;
                List<T> comics = [];
                if (appdata.appSettings.fullyHideBlockedWorks) {
                  for (var comic in logic.dividedComics![logic.current]!) {
                    if (isBlocked(comic) == null) {
                      comics.add(comic);
                    }
                  }
                } else {
                  comics = logic.dividedComics![logic.current]!;
                }
                if (comics.isEmpty) {
                  return SmoothCustomScrollView(
                    slivers: [
                      if (title != null)
                        SliverAppbar(
                          title: Text(title!),
                          actions: tailing != null ? [tailing!] : null,
                        ),
                      if (header != null) header!,
                      if (showPageIndicator &&
                          (logic.maxPage != 1 || logic.current > 1))
                        buildPageSelector(context, logic),
                      if (groupStatus != null) groupStatus,
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: buildEmptyView(context),
                      ),
                    ],
                  );
                }
                Widget body = SmoothCustomScrollView(
                  slivers: [
                    if (title != null)
                      SliverAppbar(
                        title: Text(title!),
                        actions: tailing != null ? [tailing!] : null,
                      ),
                    if (header != null) header!,
                    if (showPageIndicator &&
                        appdata.settings[64] == "0" &&
                        (logic.maxPage != 1 || logic.current > 1))
                      buildPageSelector(context, logic),
                    if (groupStatus != null) groupStatus,
                    SliverGrid(
                      delegate: SliverChildBuilderDelegate(
                          childCount: comics.length, (context, i) {
                        return buildItem(context, comics[i]);
                      }),
                      gridDelegate: SliverGridDelegateWithComics(),
                    ),
                    if (showPageIndicator &&
                        appdata.settings[64] == "0" &&
                        (logic.maxPage != 1 || logic.current > 1))
                      buildPageSelector(context, logic),
                    SliverPadding(
                        padding: EdgeInsets.only(
                            bottom: MediaQuery.of(context).padding.bottom))
                  ],
                );

                body = NotificationListener<ScrollUpdateNotification>(
                  onNotification: (notifications) {
                    if (notifications.scrollDelta != null) {
                      if (notifications.scrollDelta! > 0 &&
                          logic.showFloatingButton) {
                        logic.showFloatingButton = false;
                        logic.update();
                      } else if ((notifications.scrollDelta! < 0 ||
                              notifications.metrics.pixels ==
                                  notifications.metrics.minScrollExtent ||
                              notifications.metrics.pixels ==
                                  notifications.metrics.maxScrollExtent) &&
                          !logic.showFloatingButton) {
                        logic.showFloatingButton = true;
                        logic.update();
                      }
                    }
                    return false;
                  },
                  child: body,
                );

                if (showPageIndicator && appdata.settings[64] == "1") {
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: body,
                      ),
                      Positioned(
                        left: 0,
                        right: 12,
                        top: 0,
                        bottom: 0,
                        child: buildPageSelectorRight(context, logic),
                      )
                    ],
                  );
                } else {
                  return body;
                }
              }
            }
          }

          final list = buildList();
          if (!_multiSelectEnabled) return list;
          final items =
              paged ? (logic.dividedComics?[logic.current]) : logic.comics;
          final available = <FavoriteItem>[];
          for (final item in items ?? <T>[]) {
            if (isBlocked(item) != null) continue;
            final tile = buildComicTile(context, item, sourceKey);
            if (tile is ComicTile && tile.favoriteItem != null) {
              available.add(tile.favoriteItem!);
            }
          }
          return ComicSelectionRegion(
            controller: logic.selection,
            available: available,
            paged: paged,
            child: list,
          );
        });

    if (header != null && UiMode.m1(context)) {
      body = SafeArea(
        bottom: false,
        child: body,
      );
    }

    if (withRefreshFloatingButton) {
      return Scaffold(
        floatingActionButton: FloatingActionButton(
          child: const Icon(Icons.refresh),
          onPressed: () {
            refresh();
          },
        ),
        body: body,
      );
    } else {
      return Material(
        child: body,
      );
    }
  }

  Widget? _buildGroupStatus(ComicsPageLogic<T> logic) {
    if (logic.loading) {
      return const SliverToBoxAdapter(child: LinearProgressIndicator());
    }
    final message = logic.message;
    if (message == null) return null;
    return SliverToBoxAdapter(
      child: ListTile(
        title: Text("源页加载失败".tl),
        subtitle: Text(message),
        trailing: TextButton(
          onPressed: logic.retry,
          child: Text("重试".tl),
        ),
      ),
    );
  }

  Widget buildPageSelector(BuildContext context, ComicsPageLogic logic) {
    return SliverToBoxAdapter(
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 8),
          child: SizedBox(
            width: 300,
            height: 42,
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                ),
                FilledButton.tonal(
                    onPressed: () => prevPage(logic), child: Text("上一页".tl)),
                const Spacer(),
                ActionChip(
                  label: Text(
                      "${"页面".tl}: ${logic.current}/${logic.maxPage?.toString() ?? "?"}"),
                  onPressed: () async {
                    selectPage(logic);
                  },
                  elevation: 1,
                  side: BorderSide.none,
                ),
                const Spacer(),
                FilledButton.tonal(
                    onPressed: () => nextPage(logic), child: Text("下一页".tl)),
                const SizedBox(
                  width: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildPageSelectorRight(BuildContext context, ComicsPageLogic logic) {
    return Align(
        alignment: Alignment.centerRight,
        child: AnimatedSlide(
          offset: logic.showFloatingButton
              ? const Offset(0, 0)
              : const Offset(1.5, 0),
          duration: const Duration(milliseconds: 200),
          child: Material(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(16),
            elevation: 3,
            child: SizedBox(
              height: 156,
              width: 58,
              child: Column(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16)),
                      onTap: () {
                        prevPage(logic);
                      },
                      child: const SizedBox.expand(
                        child: Center(
                          child: Icon(Icons.keyboard_arrow_left),
                        ),
                      ),
                    ),
                  ),
                  const Divider(
                    height: 1,
                  ),
                  Expanded(
                      child: InkWell(
                    onTap: () {
                      selectPage(logic);
                    },
                    child: SizedBox.expand(
                      child: Center(
                        child: Text(
                            "${logic.current}/${logic.maxPage?.toString() ?? "?"}"),
                      ),
                    ),
                  )),
                  const Divider(
                    height: 1,
                  ),
                  Expanded(
                    child: InkWell(
                      borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(16),
                          bottomRight: Radius.circular(16)),
                      onTap: () {
                        nextPage(logic);
                      },
                      child: const SizedBox.expand(
                        child: Center(
                          child: Icon(Icons.keyboard_arrow_right),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ));
  }

  void nextPage(ComicsPageLogic logic) {
    if (logic.selection.busy) return;
    if ((logic.maxPage != null && logic.current >= logic.maxPage!) ||
        logic.current == 0) {
      showToast(message: "已经是最后一页了".tl);
    } else {
      logic.changePage(logic.current + 1);
    }
  }

  void prevPage(ComicsPageLogic logic) {
    if (logic.selection.busy) return;
    if (logic.current == 1 || logic.current == 0) {
      showToast(message: "已经是第一页了".tl);
    } else {
      logic.changePage(logic.current - 1);
    }
  }

  void selectPage(ComicsPageLogic logic) async {
    if (logic.selection.busy) return;
    String res = "";
    await showDialog(
        context: App.globalContext!,
        builder: (dialogContext) {
          var controller = TextEditingController();
          return SimpleDialog(
            title: const Text("切换页面"),
            children: [
              const SizedBox(
                width: 300,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                child: TextField(
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: "页码".tl,
                    suffixText:
                        "${"输入范围: ".tl}1-${logic.maxPage?.toString() ?? "?"}",
                  ),
                  controller: controller,
                  onSubmitted: (s) {
                    res = s;
                    App.globalBack();
                  },
                ),
              ),
              Center(
                child: FilledButton(
                  child: Text("提交".tl),
                  onPressed: () {
                    res = controller.text;
                    App.globalBack();
                  },
                ),
              )
            ],
          );
        });
    if (res.isNum) {
      int i = int.parse(res);
      if (logic.maxPage == null || (i > 0 && i <= logic.maxPage!)) {
        logic.changePage(i);
        return;
      }
    }
    if (res != "") {
      showToast(message: "输入的数字不正确".tl);
    }
  }

  Widget buildEmptyView(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off, size: 56),
          const SizedBox(height: 12),
          Text("无匹配结果".tl,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget buildItem(BuildContext context, T item) {
    return buildComicTile(context, item, sourceKey, addonMenuOptions: addonMenuOptions);
  }
}

class SliverGridComicsController extends StateController {}

class SliverGridComics extends StatelessWidget {
  const SliverGridComics({
    super.key,
    required this.comics,
    required this.sourceKey,
    this.onLastItemBuild,
  });

  final List<BaseComic> comics;

  final String sourceKey;

  final void Function()? onLastItemBuild;

  @override
  Widget build(BuildContext context) {
    return StateBuilder<SliverGridComicsController>(
      init: SliverGridComicsController(),
      builder: (controller) {
        List<BaseComic> comics = [];
        if (appdata.appSettings.fullyHideBlockedWorks) {
          for (var comic in this.comics) {
            if (isBlocked(comic) == null) {
              comics.add(comic);
            }
          }
        } else {
          comics = this.comics;
        }
        return _SliverGridComics(
          comics: comics,
          sourceKey: sourceKey,
          onLastItemBuild: onLastItemBuild,
        );
      },
    );
  }
}

class _SliverGridComics extends StatelessWidget {
  const _SliverGridComics({
    required this.comics,
    required this.sourceKey,
    this.onLastItemBuild,
  });

  final List<BaseComic> comics;

  final String sourceKey;

  final void Function()? onLastItemBuild;

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      delegate: SliverChildBuilderDelegate(
            (context, index) {
          if (index == comics.length - 1) {
            onLastItemBuild?.call();
          }
          return buildComicTile(context, comics[index], sourceKey);
        },
        childCount: comics.length,
      ),
      gridDelegate: SliverGridDelegateWithComics(),
    );
  }
}
