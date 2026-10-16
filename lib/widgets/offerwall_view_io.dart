import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../config/app_config.dart';
import '../services/offerwall_controller.dart';
import '../theme/app_theme.dart';

/// Native (Android / iOS) offerwall backed by a real WebView.
///
/// Loads the configured provider URL, or the bundled placeholder asset when no
/// URL is set. Exposes a JavaScriptChannel named [OfferwallConfig.bridgeName]
/// (`AndroidOfferwall`) whose `postMessage` receives JSON messages from the page.
class OfferwallView extends StatefulWidget {
  const OfferwallView({
    super.key,
    required this.controller,
    this.onPageError,
    this.onExternalLink,
  });

  final OfferwallController controller;
  final ValueChanged<String>? onPageError;
  final ValueChanged<String>? onExternalLink;

  @override
  State<OfferwallView> createState() => _OfferwallViewState();
}

class _OfferwallViewState extends State<OfferwallView> {
  late final WebViewController _web;
  bool _loading = true;

  @override
  void initState() {
    super.initState();

    final Color bg = Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkSurface
        : AppColors.lightSurface;

    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(bg)
      ..addJavaScriptChannel(
        OfferwallConfig.bridgeName,
        onMessageReceived: (JavaScriptMessage message) {
          widget.controller.handleMessage(message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (WebResourceError error) {
            if (error.isForMainFrame ?? false) {
              if (mounted) setState(() => _loading = false);
              widget.onPageError?.call(
                'Page failed to load (${error.errorCode})',
              );
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            if (widget.controller.isInternalUrl(request.url)) {
              return NavigationDecision.navigate;
            }
            widget.onExternalLink?.call(request.url);
            return NavigationDecision.prevent;
          },
        ),
      );

    // Let the controller request a balance push into the page.
    widget.controller.onPushBalance = _pushBalance;

    _load();
  }

  @override
  void dispose() {
    if (widget.controller.onPushBalance == _pushBalance) {
      widget.controller.onPushBalance = null;
    }
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.controller.isPlaceholder) {
      await _web.loadFlutterAsset(
        'assets/offerwall/offerwall_placeholder.html',
      );
    } else {
      await _web.loadRequest(Uri.parse(widget.controller.resolvedUrl));
    }
  }

  Future<void> _pushBalance(int balance) {
    return _web.runJavaScript(
      "window.dispatchEvent(new CustomEvent('nativeBalance',{detail:$balance}));",
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        WebViewWidget(controller: _web),
        if (_loading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 3),
          ),
      ],
    );
  }
}
