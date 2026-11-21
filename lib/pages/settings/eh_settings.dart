part of pica_settings;

class EhSettings extends StatefulWidget {
  const EhSettings(this.popUp, {Key? key}) : super(key: key);
  final bool popUp;

  @override
  State<EhSettings> createState() => _EhSettingsState();
}

class _EhSettingsState extends State<EhSettings> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const ListTile(
          title: Text("E-Hentai"),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.card_giftcard_outlined),
          title: Text('自动领取每日奖励'.tl),
          value: appdata.appSettings.ehDawnOnOpen,
          onChanged: (enabled) {
            setState(() => appdata.appSettings.ehDawnOnOpen = enabled);
            appdata.updateSettings(false);
          },
        ),
        ValueListenableBuilder<int>(
          valueListenable: EhDawn.instance.changes,
          builder: (context, _, __) => FutureBuilder<EhDawnResult?>(
            future: EhDawn.instance.latest(),
            builder: (context, snapshot) {
              final result = snapshot.data;
              return ListTile(
                leading: const Icon(Icons.refresh),
                title: Text('检查每日奖励'.tl),
                subtitle: Text(result?.status == EhDawnStatus.claimed
                    ? '${result!.at.toLocal().toString().substring(0, 16)} ${'已领取'.tl}'
                    : '未领取'.tl),
                onTap: _showDawnDetails,
                trailing: EhDawn.instance.checking
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right),
              );
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.dns),
          title: Text("画廊站点".tl),
          trailing: Select(
            initialValue: int.parse(appdata.settings[20]),
            width: 150,
            values: const [
              "e-hentai.org",
              "exhentai.org",
            ],
            onChange: (i) {
              appdata.settings[20] = i.toString();
              appdata.updateSettings();
            },
          ),
          //onTap: () => setEhDomain(context),
        ),
        ListTile(
          leading: const Icon(Icons.image),
          title: Text("优先加载原图".tl),
          subtitle: Text("可能导致加载失败".tl),
          trailing: Switch(
            value: appdata.settings[29] == "1",
            onChanged: (b) {
              setState(() {
                appdata.settings[29] = b ? "1" : "0";
              });
              appdata.updateSettings();
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.notifications_off_outlined),
          title: Text("忽略警告".tl),
          trailing: Switch(
            value: appdata.settings[47] == "1",
            onChanged: (b) {
              setState(() {
                appdata.settings[47] = b ? "1" : "0";
              });
              appdata.updateSettings();
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.notes),
          title: Text("优先显示副标题".tl),
          subtitle: Text("适用于已下载的画廊".tl),
          trailing: Switch(
            value: appdata.settings[78] == "1",
            onChanged: (b) {
              setState(() {
                appdata.settings[78] = b ? "1" : "0";
              });
              appdata.updateSettings();
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.request_page_rounded),
          title: Text("配置文件".tl),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => App.to(context, () => const EhProfileSelectPage()),
        )
      ],
    );
  }

  void _showDawnDetails() {
    final details = EhDawn.instance.checkDetails();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('检查每日奖励'.tl),
        scrollable: true,
        content: FutureBuilder<EhDawnDetails>(
          future: details,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                heightFactor: 2,
                child: CircularProgressIndicator(),
              );
            }
            final data = snapshot.data;
            final result = data?.result;
            final heading = Theme.of(context).textTheme.titleSmall;
            String amount(Object? value) => value?.toString() ?? '未获取'.tl;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(result == null ? '每日奖励检查失败'.tl : _dawnMessage(result)),
                const SizedBox(height: 14),
                Text('本次奖励'.tl, style: heading),
                Text('EXP  ${amount(result?.exp)}'),
                Text('GP  ${amount(result?.gp)}'),
                Text('Credits  ${amount(result?.credits)}'),
                const SizedBox(height: 14),
                Text('当前可用余额'.tl, style: heading),
                Text('GP  ${amount(data?.gp)}'),
                Text('Credits  ${amount(data?.credits)}'),
                Text('Hath  ${amount(data?.hath)}'),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('关闭'.tl),
          ),
        ],
      ),
    );
  }

  String _dawnMessage(EhDawnResult result) => switch (result.status) {
        EhDawnStatus.claimed => '已领取'.tl,
        EhDawnStatus.unconfirmed => 'EH 未返回奖励提示，可能已通过其他方式领取'.tl,
        EhDawnStatus.noSession => '请先登录 E-Hentai'.tl,
        EhDawnStatus.expiredSession => 'E-Hentai 登录已过期，请重新登录'.tl,
        EhDawnStatus.challenge => 'E-Hentai 要求进行网页验证'.tl,
        EhDawnStatus.rateLimited => 'E-Hentai 暂时限制访问，请稍后重试'.tl,
        EhDawnStatus.networkError => '无法连接 E-Hentai，请检查网络和代理'.tl,
        EhDawnStatus.unexpectedResponse => 'E-Hentai 返回了无法识别的页面'.tl,
      };
}

class EhProfileSelectPage extends StatefulWidget {
  const EhProfileSelectPage({super.key});

  @override
  State<EhProfileSelectPage> createState() => _EhProfileSelectPageState();
}

class _EhProfileSelectPageState extends State<EhProfileSelectPage> {
  bool loading = true;

  Map<String, String>? profiles;

  String? error;

  void loadData() async {
    var res = await EhNetwork().getProfiles();
    loading = false;
    if (res.error) {
      setState(() {
        error = res.errorMessageWithoutNull;
      });
    } else {
      setState(() {
        profiles = res.data;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      loadData();
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text("Profile"),
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : error != null
              ? Center(child: Text(error!))
              : profiles == null
                  ? const Center(child: Text("Unknown Error"))
                  : buildBody(),
    );
  }

  Widget buildBody(){
    profiles?[""] = "Do not modify";
    var keys = profiles?.keys.toList();
    if(keys != null){
      keys.sort();
    }
    return ListView.builder(
      itemCount: profiles!.length,
      itemBuilder: (context, index) {
        var key = keys!.elementAt(index);
        var value = profiles![key]!;
        return RadioListTile<String>(
          title: Text(value),
          value: key,
          groupValue: appdata.settings[75],
          onChanged: (value) async {
            setState(() {
              appdata.settings[75] = key;
            });
            appdata.updateSettings();
          },
        );
      },
    );
  }
}
