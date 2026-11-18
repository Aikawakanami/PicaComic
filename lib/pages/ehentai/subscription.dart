import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:flutter/material.dart';
import 'package:pica_comic/tools/translations.dart';
import '../../network/eh_network/eh_gallery_page_loader.dart';
import '../../network/eh_network/eh_main_network.dart';
import '../../network/eh_network/eh_models.dart';
import '../../network/res.dart';

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: Appbar(title: Text("EH订阅".tl), actions: [
        Tooltip(
          message: "更多".tl,
          child: IconButton(
            icon: const Icon(Icons.more_horiz),
            onPressed: (){
              Future.microtask(() => showDialog(context: App.globalContext!, builder: (context){
                return AlertDialog(
                  title: Text("订阅".tl),
                  content: Text("请在网页端管理订阅".tl),
                  actions: [
                    TextButton(onPressed: ()=>App.globalBack(), child: Text("返回".tl)),
                  ],
                );
              }));
            },
          ),
        )
      ],),
      body: EhSubscriptionComics(),
    );
  }
}


class EhSubscriptionComics extends ComicsPage<EhGalleryBrief>{
  EhSubscriptionComics({super.key});

  final _loader = EhGalleryPageLoader(
    firstPageLoader: () =>
        EhNetwork().getGalleries("${EhNetwork().ehBaseUrl}/watched"),
    nextPageLoader: (url) => EhNetwork().getGalleries(url),
  );

  @override
  Future<Res<List<EhGalleryBrief>>> getComics(int i) => _loader(i);

  @override
  String? get tag => "EhSubscriptionPage";

  @override
  String? get title => null;

  @override
  String get sourceKey => 'ehentai';
}
