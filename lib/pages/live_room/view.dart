import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:PiliPlus/http/live.dart';
import 'package:PiliPlus/pages/live_room/widgets/chat.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:floating/floating.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:PiliPlus/common/widgets/network_img_layer.dart';
import 'package:PiliPlus/plugin/pl_player/index.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../../utils/storage.dart';
import 'controller.dart';
import 'widgets/bottom_control.dart';

class LiveRoomPage extends StatefulWidget {
  const LiveRoomPage({super.key});

  @override
  State<LiveRoomPage> createState() => _LiveRoomPageState();
}

class _LiveRoomPageState extends State<LiveRoomPage>
    with WidgetsBindingObserver {
  late final int _roomId;
  late final LiveRoomController _liveRoomController;
  late final PlPlayerController plPlayerController;
  late Future? _futureBuilder;
  late Future? _futureBuilderFuture;

  bool isShowCover = true;
  bool isPlay = true;
  Floating? floating;

  late final _isLogin = GStorage.userInfo.get('userInfoCache') != null;
  late final _node = FocusNode();
  late final _ctr = TextEditingController();
  StreamSubscription? _listener;

  int latestAddedPosition = -1;
  bool? _isFullScreen;
  bool? _isPipMode;

  void playCallBack() {
    plPlayerController.play();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _roomId = int.parse(Get.parameters['roomid'] ?? '-1');
    _liveRoomController = Get.put(
      LiveRoomController(),
      tag: Utils.makeHeroTag(_roomId),
    );
    PlPlayerController.setPlayCallBack(playCallBack);
    if (Platform.isAndroid) {
      floating = Floating();
    }
    videoSourceInit();
    _futureBuilderFuture = _liveRoomController.queryLiveInfo();
    plPlayerController.autoEnterFullscreen();
    _liveRoomController.liveMsg();
    _listener = plPlayerController.isFullScreen.listen((isFullScreen) {
      if (isFullScreen != _isFullScreen) {
        _isFullScreen = isFullScreen;
        _updateFontSize();
      }
    });
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   if (context.orientation == Orientation.landscape) {
    //     plPlayerController.triggerFullScreen(status: true);
    //   }
    // });
  }

  void _updateFontSize() async {
    if (Platform.isAndroid) {
      _isPipMode =
          await const MethodChannel("floating").invokeMethod('inPipAlready');
    }
    if (_liveRoomController.controller != null) {
      _liveRoomController.controller!.updateOption(
        _liveRoomController.controller!.option.copyWith(
          fontSize: _getFontSize(plPlayerController.isFullScreen.value),
        ),
      );
    }
  }

  double _getFontSize(isFullScreen) {
    return isFullScreen == false || _isPipMode == true
        ? 15 * plPlayerController.fontSizeVal
        : 15 * plPlayerController.fontSizeFSVal;
  }

  Future<void> videoSourceInit() async {
    _futureBuilder = _liveRoomController.queryLiveInfoH5();
    plPlayerController = _liveRoomController.plPlayerController;
  }

  @override
  void dispose() {
    _listener?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    ScreenBrightness().resetApplicationScreenBrightness();
    PlPlayerController.setPlayCallBack(null);
    _liveRoomController.msgStream?.close();
    // floating?.dispose();
    _node.dispose();
    plPlayerController.dispose();
    _ctr.dispose();
    _liveRoomController.scrollController.removeListener(() {});
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _liveRoomController.showDanmaku = true;
    } else if (state == AppLifecycleState.paused) {
      _liveRoomController.showDanmaku = false;
      plPlayerController.danmakuController?.clear();
    }
  }

  final GlobalKey videoPlayerKey = GlobalKey();
  final GlobalKey playerKey = GlobalKey();

  Widget videoPlayerPanel([Color? fill]) {
    return FutureBuilder(
      key: videoPlayerKey,
      future: _futureBuilderFuture,
      builder: (BuildContext context, AsyncSnapshot snapshot) {
        if (snapshot.hasData && snapshot.data['status']) {
          return PLVideoPlayer(
            key: playerKey,
            fill: fill,
            plPlayerController: plPlayerController,
            bottomControl: BottomControl(
              plPlayerController: plPlayerController,
              liveRoomCtr: _liveRoomController,
              floating: floating,
              onRefresh: () {
                _futureBuilderFuture = _liveRoomController.queryLiveInfo();
              },
            ),
            danmuWidget: Obx(
              () => AnimatedOpacity(
                opacity: plPlayerController.isOpenDanmu.value ? 1 : 0,
                duration: const Duration(milliseconds: 100),
                child: DanmakuScreen(
                  createdController: (DanmakuController e) {
                    plPlayerController.danmakuController =
                        _liveRoomController.controller = e;
                  },
                  option: DanmakuOption(
                    fontSize:
                        _getFontSize(plPlayerController.isFullScreen.value),
                    fontWeight: plPlayerController.fontWeight,
                    area: plPlayerController.showArea,
                    opacity: plPlayerController.opacityVal,
                    hideTop: plPlayerController.blockTypes.contains(5),
                    hideScroll: plPlayerController.blockTypes.contains(2),
                    hideBottom: plPlayerController.blockTypes.contains(4),
                    duration: plPlayerController.danmakuDurationVal ~/
                        plPlayerController.playbackSpeed,
                    strokeWidth: plPlayerController.strokeWidth,
                    lineHeight: plPlayerController.danmakuLineHeight,
                  ),
                ),
              ),
            ),
          );
        } else {
          return const SizedBox();
        }
      },
    );
  }

  Widget childWhenDisabled(bool isPortrait) {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            bottom: 0,
            child: Opacity(
              opacity: 0.6,
              child: Image.asset(
                'assets/images/live/default_bg.webp',
                fit: BoxFit.cover,
              ),
            ),
          ),
          Obx(
            () => Positioned(
              left: 0,
              top: 0,
              right: 0,
              bottom: 0,
              child: _liveRoomController
                              .roomInfoH5.value.roomInfo?.appBackground !=
                          '' &&
                      _liveRoomController
                              .roomInfoH5.value.roomInfo?.appBackground !=
                          null
                  ? Opacity(
                      opacity: 0.6,
                      child: NetworkImgLayer(
                        width: Get.width,
                        height: Get.height,
                        type: 'bg',
                        src: _liveRoomController
                                .roomInfoH5.value.roomInfo?.appBackground ??
                            '',
                      ),
                    )
                  : const SizedBox(),
            ),
          ),
          isPortrait
              ? Scaffold(
                  backgroundColor: Colors.transparent,
                  body: Column(
                    children: [
                      _buildAppBar,
                      ..._buildBodyP,
                    ],
                  ),
                )
              : Column(
                  children: [
                    _buildAppBar,
                    _buildBodyH,
                  ],
                ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateFontSize();
    });
    return OrientationBuilder(
      builder: (BuildContext context, Orientation orientation) {
        if (Platform.isAndroid) {
          return PiPSwitcher(
            getChildWhenDisabled: () =>
                childWhenDisabled(orientation == Orientation.portrait),
            getChildWhenEnabled: () => videoPlayerPanel(),
            floating: floating,
          );
        } else {
          return childWhenDisabled(orientation == Orientation.portrait);
        }
      },
    );
  }

  Color get _color => Color(0xFFEEEEEE);

  Widget get _buildAppBar => Obx(
        () => AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          titleTextStyle: TextStyle(color: Colors.white),
          toolbarHeight: plPlayerController.isFullScreen.value ? 0 : null,
          title: FutureBuilder(
            future: _futureBuilder,
            builder: (context, snapshot) {
              if (snapshot.data == null) {
                return const SizedBox();
              }
              Map data = snapshot.data as Map;
              if (data['status']) {
                return Obx(
                  () => Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          _node.unfocus();
                          dynamic uid = _liveRoomController
                              .roomInfoH5.value.roomInfo?.uid;
                          Get.toNamed(
                            '/member?mid=$uid',
                            arguments: {
                              'heroTag': Utils.makeHeroTag(uid),
                            },
                          );
                        },
                        child: NetworkImgLayer(
                          width: 34,
                          height: 34,
                          type: 'avatar',
                          src: _liveRoomController
                              .roomInfoH5.value.anchorInfo!.baseInfo!.face,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _liveRoomController
                                .roomInfoH5.value.anchorInfo!.baseInfo!.uname!,
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(height: 1),
                          if (_liveRoomController
                                  .roomInfoH5.value.watchedShow !=
                              null)
                            Text(
                              _liveRoomController.roomInfoH5.value
                                      .watchedShow!['text_large'] ??
                                  '',
                              style: const TextStyle(fontSize: 12),
                            ),
                        ],
                      ),
                      const Spacer(),
                      //刷新
                      IconButton(
                        tooltip: '刷新',
                        onPressed: () {
                          _futureBuilderFuture =
                              _liveRoomController.queryLiveInfo();
                          // videoSourceInit();
                        },
                        icon: const Icon(Icons.refresh),
                      ),
                      //内置浏览器打开
                      IconButton(
                          tooltip: '浏览器打开',
                          onPressed: () {
                            Utils.inAppWebview(
                              'https://live.bilibili.com/h5/${_liveRoomController.roomId}',
                              off: true,
                            );
                          },
                          icon: const Icon(Icons.open_in_browser)),
                    ],
                  ),
                );
              } else {
                return const SizedBox();
              }
            },
          ),
        ),
      );

  Widget get _buildBodyH {
    double videoWidth =
        max(context.height / context.width * 1.04, 0.58) * context.width;
    return Expanded(
      child: Row(
        children: [
          Obx(
            () => PopScope(
              canPop: plPlayerController.isFullScreen.value != true,
              onPopInvokedWithResult: (bool didPop, Object? result) {
                if (plPlayerController.isFullScreen.value == true) {
                  plPlayerController.triggerFullScreen(status: false);
                }
              },
              child: Listener(
                onPointerDown: (_) {
                  _node.unfocus();
                },
                child: SizedBox(
                  width: plPlayerController.isFullScreen.value
                      ? Get.size.width
                      : videoWidth,
                  height: plPlayerController.isFullScreen.value
                      ? Get.size.height
                      : Get.size.width * 9 / 16,
                  child: MediaQuery.removePadding(
                    removeRight: true,
                    context: context,
                    child: videoPlayerPanel(Colors.transparent),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: SafeArea(
                left: false,
                top: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _buildBottomWidget,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> get _buildBodyP => [
        Obx(
          () => PopScope(
            canPop: plPlayerController.isFullScreen.value != true,
            onPopInvokedWithResult: (bool didPop, Object? result) {
              if (plPlayerController.isFullScreen.value == true) {
                plPlayerController.triggerFullScreen(status: false);
              }
            },
            child: Listener(
              onPointerDown: (_) {
                _node.unfocus();
              },
              child: SizedBox(
                width: Get.size.width,
                height: plPlayerController.isFullScreen.value
                    ? Get.size.height
                    : Get.size.width * 9 / 16,
                child: videoPlayerPanel(),
              ),
            ),
          ),
        ),
        ..._buildBottomWidget,
      ];

  final GlobalKey chatKey = GlobalKey();

  List<Widget> get _buildBottomWidget => [
        Expanded(
          child: Listener(
            onPointerDown: (_) {
              _node.unfocus();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: LiveRoomChat(
                key: chatKey,
                roomId: _roomId,
                liveRoomController: _liveRoomController,
              ),
            ),
          ),
        ),
        Container(
          padding: EdgeInsets.only(
            left: 10,
            top: 10,
            right: 10,
            bottom: 25 + MediaQuery.of(context).padding.bottom,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            border: Border(
              top: BorderSide(color: Color(0x1AFFFFFF)),
            ),
            color: Color(0x1AFFFFFF),
          ),
          child: Row(
            children: [
              Obx(
                () => IconButton(
                  onPressed: () {
                    plPlayerController.isOpenDanmu.value =
                        !plPlayerController.isOpenDanmu.value;
                    GStorage.setting.put(SettingBoxKey.enableShowDanmaku,
                        plPlayerController.isOpenDanmu.value);
                  },
                  icon: Icon(
                    plPlayerController.isOpenDanmu.value
                        ? Icons.subtitles_outlined
                        : Icons.subtitles_off_outlined,
                    color: _color,
                  ),
                ),
              ),
              Expanded(
                child: TextField(
                  focusNode: _node,
                  controller: _ctr,
                  textInputAction: TextInputAction.send,
                  cursorColor: _color,
                  style: TextStyle(color: _color),
                  onSubmitted: (value) {
                    if (value.isNotEmpty) {
                      _onSendMsg(value);
                    }
                  },
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: '发送弹幕',
                    hintStyle: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: () {
                  if (_ctr.text.isNotEmpty) {
                    _onSendMsg(_ctr.text);
                  }
                },
                icon: Icon(
                  Icons.send,
                  color: _color,
                ),
              ),
            ],
          ),
        )
      ];

  void _onSendMsg(msg) async {
    if (!_isLogin) {
      SmartDialog.showToast('未登录');
      return;
    }
    dynamic res = await LiveHttp.sendLiveMsg(
        roomId: _liveRoomController.roomId, msg: msg);
    if (res['status']) {
      _ctr.clear();
      if (mounted) {
        FocusScope.of(context).unfocus();
      }
      SmartDialog.showToast('发送成功');
    } else {
      SmartDialog.showToast(res['msg']);
    }
  }
}
