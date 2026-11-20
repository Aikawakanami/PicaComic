import 'package:flutter/material.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/pair.dart';
import 'package:pica_comic/foundation/ui_mode.dart';
import 'package:pica_comic/pages/comic_page.dart';
import 'package:pica_comic/pages/search_result_page.dart';
import 'package:pica_comic/tools/app_links.dart';
import 'package:pica_comic/tools/extensions.dart';
import 'package:pica_comic/tools/tags_translation.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:sliver_tools/sliver_tools.dart';

typedef FilterChip = FilterChipFixedWidth;

class _FloatingSearchBar extends StatefulWidget {
  const _FloatingSearchBar(
      {Key? key,
      required this.supportingText,
      required this.onFinish,
      required this.controller,
      this.onChanged,
      this.focusNode})
      : super(key: key);

  final void Function(String) onFinish;
  final String supportingText;
  final TextEditingController controller;
  final void Function(String)? onChanged;
  final FocusNode? focusNode;

  @override
  State<_FloatingSearchBar> createState() => _FloatingSearchBarState();
}

class _FloatingSearchBarState extends State<_FloatingSearchBar> {
  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    var padding = 12.0;
    return Container(
      padding: EdgeInsets.fromLTRB(padding, 0, padding, 0),
      margin: const EdgeInsets.symmetric(horizontal: 12) +
          const EdgeInsets.only(top: 8),
      width: double.infinity,
      height: 48,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(32),
      ),
      child: Row(children: [
        Tooltip(
          message: "返回".tl,
          child: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        Expanded(
          child: Center(
            child: TextField(
              controller: widget.controller,
              onChanged: (s) {
                if (s.length <= 1) {
                  setState(() {});
                }
                widget.onChanged?.call(s);
              },
              focusNode: widget.focusNode,
              onTapOutside: (_) => widget.focusNode?.unfocus(),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: widget.supportingText,
                hintStyle: textTheme.bodyLarge?.apply(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: widget.onFinish,
            ),
          ),
        ),
        if (widget.controller.text.isNotEmpty)
          Tooltip(
            message: "clear",
            child: IconButton(
              icon: const Icon(Icons.clear_rounded),
              iconSize: 18,
              onPressed: () {
                setState(() {
                  widget.controller.clear();
                });
                widget.onChanged?.call("");
              },
            ),
          ),
        Tooltip(
          message: "search",
          child: IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              widget.onFinish(widget.controller.text);
            },
          ),
        ),
      ]),
    );
  }
}

class PreSearchController extends StateController {
  String target = '';

  SearchPageData get searchPageData =>
      ComicSource.find(target)!.searchPageData!;

  var options = <String>[];

  var suggestions = <Pair<String, TranslationType>>[];

  String? language;

  bool limitHistory = true;

  void updateOptions() {
    for (var source in ComicSource.sources) {
      if (source.key == target &&
          source.searchPageData?.searchOptions != null) {
        options = List.generate(
          source.searchPageData!.searchOptions!.length,
          (index) => source.searchPageData!.searchOptions![index].defaultValue,
        );
      }
    }
  }

  void updateTarget(String i) {
    target = i;
    updateOptions();
    update();
  }

  PreSearchController() {
    var searchSource = <String>[];
    for (var source in ComicSource.sources) {
      searchSource.add(source.key);
    }
    if (!searchSource.contains(appdata.appSettings.initialSearchTarget)) {
      appdata.appSettings.initialSearchTarget = searchSource.first;
      appdata.updateSettings();
    }
    target = appdata.appSettings.initialSearchTarget;
    updateOptions();
  }
}

class PreSearchPage extends StatelessWidget {
  PreSearchPage({String initialValue = "", super.key})
      : controller = TextEditingController(text: initialValue);

  final TextEditingController controller;

  final searchController = StateController.put(PreSearchController());

  final comicSources =
      ComicSource.sources.where((element) => element.searchPageData != null);

  final FocusNode _focusNode = FocusNode();

  void search([String? s, String? type]) {
    var keyword = (s ?? controller.text).trim();
    final target = type ?? searchController.target;
    final isCurrentSource = target == searchController.target;
    if (ComicSource.find(target)?.searchPageData == null) return;
    _focusNode.unfocus();

    if (isCurrentSource &&
        searchController.language != null &&
        searchController.searchPageData.enableLanguageFilter) {
      // 在添加语言筛选前，先移除掉可能存在的 language: 部分
      // 主要是为了解决强迫症
      final languagePattern = RegExp(r'\s*language:\w+');
      keyword = keyword.replaceAll(languagePattern, '').trim();
      keyword += " language:${searchController.language}";
    }

    var context = App.mainNavigatorKey!.currentContext!;
    context.to<void>(
      () => SearchResultPage(
        keyword: keyword,
        sourceKey: target,
        options: isCurrentSource ? searchController.options : const [],
      ),
    ).then((_) => searchController.update(["history"]));
  }

  void findSuggestions() {
    var text = controller.text.split(" ").last;
    var suggestions = searchController.suggestions;

    suggestions.clear();

    if (canHandle(controller.text)) {
      suggestions.add(Pair("**URL**", TranslationType.other));
    } else {
      var text = controller.text;

      for (var comicSource in ComicSource.sources) {
        if (comicSource.idMatcher?.hasMatch(text) ?? false) {
          suggestions
              .add(Pair("**${comicSource.key}**", TranslationType.other));
        }
      }
    }

    if (!searchController.searchPageData.enableTagsSuggestions) return;

    bool check(String text, String key, String value) {
      if (text.removeAllBlank == "") {
        return false;
      }
      if (key.length >= text.length && key.substring(0, text.length) == text ||
          (key.contains(" ") &&
              key.split(" ").last.length >= text.length &&
              key.split(" ").last.substring(0, text.length) == text)) {
        return true;
      } else if (value.length >= text.length && value.contains(text)) {
        return true;
      }
      return false;
    }

    void find(Map<String, String> map, TranslationType type) {
      for (var element in map.entries) {
        if (suggestions.length > 200) {
          break;
        }
        if (check(text, element.key, element.value)) {
          suggestions.add(Pair(element.key, type));
        }
      }
    }

    find(TagsTranslation.femaleTags, TranslationType.female);
    find(TagsTranslation.maleTags, TranslationType.male);
    find(TagsTranslation.parodyTags, TranslationType.parody);
    find(TagsTranslation.characterTranslations, TranslationType.character);
    find(TagsTranslation.otherTags, TranslationType.other);
    find(TagsTranslation.mixedTags, TranslationType.mixed);
    find(TagsTranslation.languageTranslations, TranslationType.language);
    find(TagsTranslation.artistTags, TranslationType.artist);
    find(TagsTranslation.groupTags, TranslationType.group);
    find(TagsTranslation.cosplayerTags, TranslationType.cosplayer);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: search,
        child: const Icon(Icons.search),
      ),
      body: Column(
        children: [
          if (UiMode.m1(context))
            SizedBox(
              height: MediaQuery.of(context).padding.top,
            ),
          Builder(
            builder: (context) => _FloatingSearchBar(
              supportingText: '${'搜索'.tl} / ${'链接'.tl} / ID',
              onFinish: (s) {
                // if (s == "") return;
                search();
              },
              controller: controller,
              onChanged: (s) {
                findSuggestions();
                searchController.update([1, 100]);
              },
              focusNode: _focusNode,
            ),
          ),
          const SizedBox(
            height: 8,
          ),
          buildBody(context)
        ],
      ),
    );
  }

  Widget buildBody(BuildContext context) {
    var widget = StateBuilder<PreSearchController>(
      id: 100,
      builder: (logic) {
        if (controller.text.removeAllBlank.isEmpty ||
            controller.text.endsWith(" ") ||
            searchController.suggestions.isEmpty) {
          return buildMainView(context);
        } else {
          return buildSuggestions(context);
        }
      },
    );
    return Expanded(
      child: widget,
    );
  }

  Widget buildMainView(BuildContext context) {
    final showSideBar = MediaQuery.of(context).size.width > 950;
    var addWidth = (MediaQuery.of(context).size.width - 950) * 0.25;
    addWidth = addWidth.clamp(0, 50);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showSideBar)
          SizedBox(
            width: 250 + addWidth,
            height: double.infinity,
            child: CustomScrollView(
              slivers: [buildSearchSection(context, history: true)],
            ),
          ),
        if (showSideBar)
          const VerticalDivider(
            width: 1,
          ),
        Expanded(
            child: CustomScrollView(
          slivers: [
            if (showSideBar)
              ListTile(
                leading: const Icon(Icons.select_all),
                title: Text("搜索选项".tl),
              ).toSliver(),
            buildTargetSelector(context).toSliver(),
            SliverAnimatedPaintExtent(
              duration: const Duration(milliseconds: 180),
              child: buildSearchOptions(context).toSliver(),
            ),
            if (!showSideBar) ...[
              buildSearchSection(context,
                  history: true, limitHistoryOnOpen: true),
              buildSearchSection(context, history: false),
            ],
            SliverPadding(
              padding: EdgeInsets.only(bottom: context.padding.bottom),
            )
          ],
        )),
        if (showSideBar)
          const VerticalDivider(
            width: 1,
          ),
        if (showSideBar)
          SizedBox(
            width: 250 + addWidth,
            height: double.infinity,
            child: CustomScrollView(
              slivers: [buildSearchSection(context, history: false)],
            ),
          ),
      ],
    );
  }

  Widget buildSuggestions(BuildContext context) {
    bool check(String text, String key, String value) {
      if (text.removeAllBlank == "") {
        return false;
      }
      if (key.length >= text.length && key.substring(0, text.length) == text ||
          (key.contains(" ") &&
              key.split(" ").last.length >= text.length &&
              key.split(" ").last.substring(0, text.length) == text)) {
        return true;
      } else if (value.length >= text.length && value.contains(text)) {
        return true;
      }
      return false;
    }

    return StateBuilder<PreSearchController>(
      builder: (logic) {
        void onSelected(String text, TranslationType? type) {
          var words = controller.text.split(" ");
          if (words.length >= 2 &&
              check("${words[words.length - 2]} ${words[words.length - 1]}",
                  text, text.translateTagsToCN)) {
            controller.text = controller.text.replaceLast(
                "${words[words.length - 2]} ${words[words.length - 1]}", "");
          } else {
            controller.text =
                controller.text.replaceLast(words[words.length - 1], "");
          }
          if (text.contains(" ")) {
            if (logic.target == '3' &&
                ["male", "female", "language"].contains(type?.name)) {
              text = text.replaceAll(" ", '_');
              text = "${type?.name}:$text";
            } else {
              text = "\"$text\"";
            }
          }
          if (logic.target == '1') {
            if (type != null) {
              controller.text += "${type.name}:$text ";
            } else {
              controller.text += "$text ";
            }
          } else {
            controller.text += "$text ";
          }
          logic.update([1, 100]);
        }

        Widget widget;

        if (controller.text.removeAllBlank.isEmpty) {
          widget = buildMainView(context);
        } else {
          bool showMethod = MediaQuery.of(context).size.width < 600;
          bool showTranslation = App.locale.languageCode == "zh";
          Widget buildItem(Pair<String, TranslationType> value) {
            if (value.left == "**URL**") {
              return ListTile(
                leading: const Icon(Icons.link),
                title: Text("打开链接".tl),
                subtitle: Text(
                  controller.text,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                ),
                trailing: const Icon(Icons.arrow_right),
                onTap: () {
                  _focusNode.unfocus();
                  handleAppLinks(Uri.parse(controller.text));
                },
              );
            }

            if (RegExp(r"^\*\*.*\*\*$").hasMatch(value.left)) {
              var key = value.left.substring(2, value.left.length - 2);
              var comicSource = ComicSource.find(key);
              if (comicSource == null) {
                return const SizedBox();
              }
              return ListTile(
                leading: const Icon(Icons.link),
                title: Text("${"打开漫画".tl}: ${comicSource.name}"),
                subtitle: Text(
                  controller.text,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                ),
                trailing: const Icon(Icons.arrow_right),
                onTap: () {
                  _focusNode.unfocus();
                  context.to(
                    () => ComicPage(
                      sourceKey: key,
                      id: controller.text,
                    ),
                  );
                },
              );
            }

            var subTitle = TagsTranslation.translationTagWithNamespace(
                value.left, value.right.name);
            return TextFieldTapRegion(
              child: ListTile(
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(value.left),
                    if (!showMethod)
                      const SizedBox(
                        width: 12,
                      ),
                    if (!showMethod && showTranslation)
                      Text(
                        subTitle,
                        style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.outline),
                      )
                  ],
                ),
                subtitle:
                    (showMethod && showTranslation) ? Text(subTitle) : null,
                trailing: Text(
                  value.right.name,
                  style: const TextStyle(fontSize: 13),
                ),
                onTap: () => onSelected(value.left, value.right),
              ),
            );
          }

          widget = Column(
            children: [
              SizedBox(
                height: 32,
                child: Row(
                  children: [
                    const SizedBox(
                      width: 32,
                    ),
                    Text("建议".tl),
                    const Spacer(),
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        searchController.suggestions.clear();
                        logic.update([100]);
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.close,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(
                      width: 36,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: searchController.suggestions.length,
                  itemBuilder: (context, index) =>
                      buildItem(searchController.suggestions[index]),
                ),
              )
            ],
          );
        }
        return widget;
      },
      id: 1,
    );
  }

  Widget buildTargetSelector(BuildContext context) {
    buildItem(PreSearchController logic, String id, String text) => Padding(
          padding: const EdgeInsets.all(4),
          child: FilterChip(
            label: Text(text),
            selected: logic.target == id,
            onSelected: (b) {
              _focusNode.unfocus();
              logic.updateTarget(id);
            },
          ),
        );

    return StateBuilder<PreSearchController>(
      builder: (logic) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text("目标".tl)),
            Wrap(
              children: [
                for (var source in comicSources)
                  buildItem(logic, source.key, source.name.tl)
              ],
            ).paddingHorizontal(12),
            const SizedBox(height: 8)
          ],
        );
      },
    );
  }

  Widget buildSearchOptions(BuildContext context) {
    Widget buildLangSelector() {
      const languages = ["chinese", "japanese", "english"];
      return Padding(
        padding: const EdgeInsets.only(top: 8, left: 12, right: 12),
        child: Row(
          children: [
            const SizedBox(
              width: 8,
            ),
            Text("语言".tl),
            const SizedBox(
              width: 16,
            ),
            Select(
              initialValue: languages.indexOf(searchController.language ?? ""),
              onChange: (i) => searchController.language = languages[i],
              values: languages,
              outline: true,
            ),
          ],
        ),
      );
    }

    return StateBuilder<PreSearchController>(
      id: "mode",
      builder: (logic) {
        var children = <Widget>[];
        if (logic.searchPageData.customOptionsBuilder != null) {
          children.add(
            logic.searchPageData.customOptionsBuilder!(context, [], (options) {
              logic.options = options;
            }),
          );
        } else {
          final searchOptions =
              logic.searchPageData.searchOptions ?? <SearchOptions>[];
          for (int i = 0; i < searchOptions.length; i++) {
            final option = searchOptions[i];
            children.add(ListTile(
              title: Text(option.label.tl),
            ));
            children.add(Wrap(
              runSpacing: 8,
              spacing: 8,
              children: option.options.entries.map((e) {
                return OptionChip(
                  text: e.value.tl,
                  isSelected: logic.options[i] == e.key,
                  onTap: () {
                    logic.options[i] = e.key;
                    logic.update();
                  },
                );
              }).toList(),
            ).paddingHorizontal(16));
          }
        }
        if (logic.searchPageData.enableLanguageFilter) {
          children.add(buildLangSelector());
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ).paddingBottom(12);
      },
    );
  }

  Widget buildSourceIcon(String sourceKey) {
    final name = ComicSource.find(sourceKey)?.name.tl ?? sourceKey;
    const icons = {"picacg", "ehentai", "jm", "hitomi", "nhentai"};
    return Tooltip(
      message: name,
      triggerMode: TooltipTriggerMode.manual,
      child: icons.contains(sourceKey)
          ? Image.asset(
              "assets/search_sources/$sourceKey.png",
              width: 18,
              height: 18,
              fit: BoxFit.contain,
              semanticLabel: name,
            )
          : Icon(Icons.language, size: 18, semanticLabel: name),
    );
  }

  String favoriteSourceKey(String tag) {
    final prefix = tag.split(':').first;
    return switch (prefix.toLowerCase()) {
      "picacg" => "picacg",
      "ehentai" => "ehentai",
      "jmcomic" => "jm",
      "hitomi" => "hitomi",
      "htcomic" => "htmanga",
      "nhentai" => "nhentai",
      _ => prefix,
    };
  }

  String favoriteKeyword(String tag) => tag.substring(tag.indexOf(':') + 1);

  Future<void> editSearchFavorite(BuildContext context, {String? history}) async {
    _focusNode.unfocus();
    final available = {for (final source in comicSources) source.key: source};
    final selected = <String>{
      if (history != null)
        ...appdata.searchSourcesFor(history).where(available.containsKey),
    };
    final sources = {...selected, ...available.keys};
    var keyword = history ?? "";
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text("添加搜索收藏".tl),
          scrollable: true,
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (history == null)
                  TextFormField(
                    decoration: InputDecoration(labelText: "搜索词".tl),
                    onChanged: (text) => setState(() => keyword = text),
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                  )
                else
                  Text(history, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Text("漫画源".tl),
                for (final key in sources)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Row(
                      children: [
                        buildSourceIcon(key),
                        const SizedBox(width: 8),
                        Expanded(child: Text(available[key]!.name.tl)),
                      ],
                    ),
                    value: selected.contains(key),
                    onChanged: (checked) => setState(() {
                      if (checked == true) {
                        selected.add(key);
                      } else {
                        selected.remove(key);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text("取消".tl),
            ),
            FilledButton(
              onPressed: keyword.trim().isEmpty || selected.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(true),
              child: Text("收藏".tl),
            ),
          ],
        ),
      ),
    );
    if (save != true || !context.mounted) return;

    final term = keyword.trim();
    final existing = appdata.favoriteTags
        .where((tag) => favoriteKeyword(tag) == term)
        .map(favoriteSourceKey)
        .toSet();
    final added = selected.difference(existing);
    appdata.favoriteTags = {
      for (final source in added) "$source:$term",
      ...appdata.favoriteTags,
    };
    searchController.update(["favorites"]);
    await appdata.writeHistory();
    if (context.mounted) {
      showToast(message: "已收藏".tl);
    }
  }

  Future<void> pickSearchFavorite(BuildContext context) async {
    _focusNode.unfocus();
    final choice = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        constraints: const BoxConstraints(minWidth: 280, maxWidth: 400),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          primary: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text("添加搜索收藏".tl,
                    style: const TextStyle(fontSize: 22)),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text("手动输入".tl),
                onTap: () => Navigator.of(context).pop(false),
              ),
              if (appdata.searchHistory.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.history),
                  title: Text("从历史选择".tl),
                  onTap: () => Navigator.of(context).pop(true),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    if (!choice) {
      await editSearchFavorite(context);
      return;
    }

    final history = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text("从历史选择".tl),
        children: [
          for (final keyword in appdata.searchHistory.reversed)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(keyword),
              child: buildHistoryRow(keyword),
            ),
        ],
      ),
    );
    if (history != null && context.mounted) {
      await editSearchFavorite(context, history: history);
    }
  }

  Widget buildHistoryRow(String keyword) {
    final sources = appdata.searchSourcesFor(keyword);
    const visibleSourceCount = 3;
    final extraSources = sources.length - visibleSourceCount;
    return Row(
      children: [
        Expanded(child: Text(keyword, style: const TextStyle(fontSize: 16))),
        for (final source in sources.take(visibleSourceCount)) ...[
          const SizedBox(width: 5),
          buildSourceIcon(source),
        ],
        if (extraSources > 0) ...[
          const SizedBox(width: 5),
          Text("+$extraSources"),
        ],
      ],
    );
  }

  Widget buildHistoryItem(
    BuildContext pageContext,
    String history,
    PreSearchController logic,
  ) {
    return Flyout(
      enableLongPress: true,
      enableSecondaryTap: true,
      onShow: _focusNode.unfocus,
      navigator: App.navigatorKey.currentState,
      flyoutBuilder: (context) {
        return FlyoutContent(
          title: "历史搜索".tl,
          actions: [
            FilledButton.tonal(
              onPressed: () {
                Navigator.of(context).pop();
                if (pageContext.mounted) {
                  editSearchFavorite(pageContext, history: history);
                }
              },
              child: Text("收藏".tl),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.all(
                  Theme.of(context).colorScheme.error,
                ),
              ),
              onPressed: () {
                appdata.removeSearch(history);
                logic.update(["history"]);
                Navigator.of(context).pop();
              },
              child: Text("删除".tl),
            )
          ],
        );
      },
      child: InkWell(
        onTap: () => search(history),
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: buildHistoryRow(history),
          ),
        ),
      ),
    );
  }

  Widget buildFavoriteItem(String tag, PreSearchController logic) {
    return Flyout(
      enableLongPress: true,
      enableSecondaryTap: true,
      onShow: _focusNode.unfocus,
      navigator: App.navigatorKey.currentState,
      flyoutBuilder: (context) {
        return FlyoutContent(
          title: "要删除此项目吗?".tl,
          actions: [
            FilledButton(
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.all(
                  Theme.of(context).colorScheme.error,
                ),
              ),
              onPressed: () {
                appdata.favoriteTags.remove(tag);
                searchController.update();
                appdata.writeHistory();
                App.globalBack();
              },
              child: Text("确认".tl),
            )
          ],
        );
      },
      child: ListTile(
        title: Text(favoriteKeyword(tag)),
        subtitle: Text(
          ComicSource.find(favoriteSourceKey(tag))?.name.tl ??
              tag.split(':').first,
        ),
        onTap: () => search(favoriteKeyword(tag), favoriteSourceKey(tag)),
      ),
    );
  }

  Widget buildClearHistoryButton(PreSearchController logic) {
    return FlyoutIconButton(
      navigator: App.navigatorKey.currentState,
      flyoutBuilder: (context) {
        return FlyoutContent(
          title: "要清空历史记录吗?".tl,
          actions: [
            FilledButton(
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.all(
                  Theme.of(context).colorScheme.error,
                ),
              ),
              onPressed: () {
                appdata.clearSearchHistory();
                logic.update(["history"]);
                App.globalBack();
              },
              child: Text("确认".tl),
            )
          ],
        );
      },
      icon: const Icon(Icons.delete_forever),
    );
  }

  Widget buildClearFavoriteButton(PreSearchController logic) {
    return FlyoutIconButton(
      navigator: App.navigatorKey.currentState,
      flyoutBuilder: (context) {
        return FlyoutContent(
          title: "要清空所有漫画源的收藏吗?".tl,
          actions: [
            FilledButton(
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.all(
                  Theme.of(context).colorScheme.error,
                ),
              ),
              onPressed: () {
                appdata.favoriteTags.clear();
                appdata.writeHistory();
                logic.update();
                App.globalBack();
              },
              child: Text("确认".tl),
            )
          ],
        );
      },
      icon: const Icon(Icons.delete_forever),
    );
  }

  Widget buildSearchSection(
    BuildContext context, {
    required bool history,
    bool limitHistoryOnOpen = false,
  }) {
    final sectionId = history ? "history" : "favorites";
    final theme = Theme.of(context);
    return StateBuilder<PreSearchController>(
      id: sectionId,
      builder: (logic) {
        final expanded = history
            ? appdata.searchHistoryExpanded
            : appdata.searchFavoritesExpanded;
        return SliverMainAxisGroup(
          slivers: [
            Theme(
              data: theme.copyWith(
                splashFactory: NoSplash.splashFactory,
                highlightColor: Colors.transparent,
              ),
              child: ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                leading: Icon(history ? Icons.history : Icons.favorite_border),
                initiallyExpanded: expanded,
                title: Row(
                  children: [
                    Expanded(child: Text(history ? "历史搜索".tl : "收藏".tl)),
                    if (!history)
                      IconButton(
                        tooltip: "添加搜索收藏".tl,
                        icon: const Icon(Icons.add),
                        onPressed: () => pickSearchFavorite(context),
                      ),
                    Theme(
                      data: theme,
                      child: history
                          ? buildClearHistoryButton(logic)
                          : buildClearFavoriteButton(logic),
                    ),
                  ],
                ),
                onExpansionChanged: (expanded) {
                  if (history) {
                    appdata.searchHistoryExpanded = expanded;
                  } else {
                    appdata.searchFavoritesExpanded = expanded;
                  }
                  appdata.writeImplicitData();
                  logic.update([sectionId]);
                },
              ),
            ).toSliver(),
            // Keep the entries in the outer scroll view so they build lazily.
            if (expanded)
              history
                  ? buildHistoryList(logic, limitHistoryOnOpen)
                  : buildFavoriteList(logic),
          ],
        );
      },
    );
  }

  Widget buildFavoriteList(PreSearchController logic) {
    final favorites = appdata.favoriteTags
        .where((tag) => favoriteSourceKey(tag) == logic.target)
        .toList();
    return SliverList.builder(
      itemCount: favorites.length,
      itemBuilder: (context, index) => buildFavoriteItem(favorites[index], logic),
    );
  }

  Widget buildHistoryList(PreSearchController logic, bool limitHistoryOnOpen) {
    final history = appdata.searchHistory;
    if (limitHistoryOnOpen && history.length < 10) {
      logic.limitHistory = false;
    }
    final limited = limitHistoryOnOpen && logic.limitHistory;
    return SliverList.builder(
      itemCount: limited ? 10 : history.length,
      itemBuilder: (context, index) {
        if (limited && index == 9) {
          return TextButton(
            child: Text("查看更多".tl),
            onPressed: () {
              logic.limitHistory = false;
              logic.update(["history"]);
            },
          ).toAlign(Alignment.center);
        }
        return buildHistoryItem(
          context,
          history[history.length - index - 1],
          logic,
        );
      },
    );
  }
}
