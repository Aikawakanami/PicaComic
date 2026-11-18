import '../res.dart';
import 'eh_models.dart';

/// Resolves page numbers by following the links returned by EH.
class EhGalleryPageLoader {
  EhGalleryPageLoader({
    required this.firstPageLoader,
    required this.nextPageLoader,
  });

  final Future<Res<Galleries>> Function() firstPageLoader;
  final Future<Res<Galleries>> Function(String) nextPageLoader;
  final _pages = <List<EhGalleryBrief>>[];
  String? _nextPage;
  int _generation = 0;

  Future<Res<List<EhGalleryBrief>>> call(int page) async {
    final reset = page == 1 || _pages.isEmpty;
    if (reset) {
      _generation++;
      _pages.clear();
      _nextPage = null;
    }
    final generation = _generation;
    if (reset) {
      final response = await firstPageLoader();
      if (generation != _generation) {
        return const Res.error('Page request superseded');
      }
      if (response.error) return Res.fromErrorRes(response);
      _append(response.data);
    }
    while (page > _pages.length) {
      final url = _nextPage;
      if (url == null) break;
      final loaded = _pages.length;
      final response = await nextPageLoader(url);
      if (generation != _generation) {
        return const Res.error('Page request superseded');
      }
      if (_pages.length != loaded) continue;
      if (response.error) return Res.fromErrorRes(response);
      _append(response.data);
    }
    return Res(
      page <= _pages.length ? _pages[page - 1] : const <EhGalleryBrief>[],
      subData: _nextPage == null ? _pages.length : null,
    );
  }

  void _append(Galleries page) {
    _pages.add(page.galleries);
    _nextPage = page.next;
  }
}
