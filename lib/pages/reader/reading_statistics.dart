part of pica_reader;

class ReadingStatisticsBoundary extends StatefulWidget {
  const ReadingStatisticsBoundary(
      {super.key, required this.logic, required this.child, this.session});
  final ComicReadingPageLogic logic;
  final Widget child;
  final ReadingSessionTracker? session;
  @override
  State<ReadingStatisticsBoundary> createState() =>
      _ReadingStatisticsBoundaryState();
}

class _ReadingStatisticsBoundaryState extends State<ReadingStatisticsBoundary>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    widget.logic.statisticsSession = widget.session ??
        ReadingSessionTracker(
          store: ReadingStatistics.instance,
          identity: widget.logic.data.statisticsIdentity,
          onError: (error, stack) => LogManager.addLog(
              LogLevel.error, 'Reading statistics', '$error\n$stack'),
        );
    _timer = Timer.periodic(const Duration(seconds: 10),
        (_) => widget.logic.statisticsSession?.checkpoint());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visibility();
  }

  void _visibility() => widget.logic.setReadingVisibility(_foreground &&
      TickerMode.valuesOf(context).enabled &&
      (ModalRoute.of(context)?.isCurrent ?? true));
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _visibility();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.logic.finishReadingSession();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
