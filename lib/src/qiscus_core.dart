library qiscus_chat_sdk;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:meta/meta.dart';

import 'core/core.dart';
import 'core/injector.dart';
import 'features/channel/channel.dart';
import 'features/core/core.dart';
import 'features/custom_event/usecase/realtime.dart';
import 'features/message/message.dart';
import 'features/realtime/realtime.dart';
import 'features/room/room.dart';
import 'features/user/user.dart';

typedef Subscription = void Function();
typedef UserPresenceHandler = void Function(String, bool, DateTime);
typedef UserTypingHandler = void Function(String, int, bool);

class QiscusSDK {
  static final instance = QiscusSDK();

  factory QiscusSDK() => QiscusSDK._internal();

  static Future<QiscusSDK> withAppId$(String appId) async {
    var qiscus = QiscusSDK();
    await qiscus.setup$(appId);
    return qiscus;
  }

  static Future<QiscusSDK> withCustomServer$(
    String appId, {
    String baseUrl = Storage.defaultBaseUrl,
    String brokerUrl = Storage.defaultBrokerUrl,
    String brokerLbUrl = Storage.defaultBrokerLbUrl,
    int syncInterval = Storage.defaultSyncInterval,
    int syncIntervalWhenConnected = Storage.defaultSyncIntervalWhenConnected,
  }) async {
    var qiscus = QiscusSDK();
    await qiscus.setupWithCustomServer$(
      appId,
      baseUrl: baseUrl,
      brokerUrl: brokerUrl,
      brokerLbUrl: brokerLbUrl,
      syncInterval: syncInterval,
      syncIntervalWhenConnected: syncIntervalWhenConnected,
    );
    return qiscus;
  }

  factory QiscusSDK.withAppId(
    String appId, {
    @required void Function(Exception) callback,
  }) {
    return QiscusSDK()..setup(appId, callback: callback);
  }

  factory QiscusSDK.withCustomServer(
    String appId, {
    String baseUrl = Storage.defaultBaseUrl,
    String brokerUrl = Storage.defaultBrokerUrl,
    String brokerLbUrl = Storage.defaultBrokerLbUrl,
    int syncInterval = Storage.defaultSyncInterval,
    int syncIntervalWhenConnected = Storage.defaultSyncIntervalWhenConnected,
    @required Function1<Exception, void> callback,
  }) {
    return QiscusSDK()
      ..setupWithCustomServer(
        appId,
        baseUrl: baseUrl,
        brokerUrl: brokerUrl,
        brokerLbUrl: brokerLbUrl,
        syncInterval: syncInterval,
        syncIntervalWhenConnected: syncIntervalWhenConnected,
        callback: callback,
      );
  }

  QiscusSDK._internal() {
    Injector.setup();
  }

  String get appId => _get<Storage>()?.appId;

  QAccount get currentUser => _get<Storage>()?.currentUser?.toModel();

  bool get isLogin => _get<Storage>()?.currentUser != null;

  String get token => _get<Storage>()?.token;

  Task<Either<Exception, void>> get _authenticated {
    final _isLogin = Stream<void>.periodic(const Duration(milliseconds: 300))
        .map((_) => isLogin)
        .distinct((p, n) => p == n)
        .firstWhere((it) => it == true);
    return Task(() => _isLogin).attempt().leftMapToException('Not logged in');
  }

  void addHttpInterceptors(RequestOptions Function(RequestOptions) onRequest) {
    _get<Dio>().interceptors.add(InterceptorsWrapper(
          onRequest: onRequest,
        ));
  }

  void addParticipants({
    @required int roomId,
    @required List<String> userIds,
    @required void Function(List<QParticipant>, Exception) callback,
  }) {
    final addParticipant = _get<AddParticipantUseCase>();
    _authenticated
        .andThen(addParticipant(ParticipantParams(roomId, userIds)))
        .rightMap((r) => r.map((m) => m.toModel()).toList())
        .toCallback(callback)
        .run();
  }

  void blockUser({
    @required String userId,
    @required void Function(QUser, Exception) callback,
  }) {
    final blocUser = _get<BlockUserUseCase>();
    _authenticated
        .andThen(blocUser(BlockUserParams(userId)))
        .rightMap((it) => it.toModel())
        .toCallback(callback)
        .run();
  }

  Future<QChatRoom> chatUser$({
    @required String userId,
    Map<String, dynamic> extras,
  }) async {
    return _authenticated
        .andThen(_get<GetRoomByUserIdUseCase>()(UserIdParams(userId)))
        .rightMap((u) => u.toModel())
        .run()
        .then((either) => either.fold(
              (err) => Future<QChatRoom>.error(err),
              (room) => Future.value(room),
            ));
  }

  void chatUser({
    @required String userId,
    Map<String, dynamic> extras,
    @required Function2<QChatRoom, Exception, void> callback,
  }) {}

  Future<void> clearMessagesByChatRoomId$({
    @required List<String> roomUniqueIds,
  }) async {
    final clearRoom = _get<ClearRoomMessagesUseCase>();
    return _authenticated
        .andThen(clearRoom(ClearRoomMessagesParams(roomUniqueIds)))
        .run()
        .then((_) => null);
  }

  void clearMessagesByChatRoomId({
    @required List<String> roomUniqueIds,
    @required void Function(Exception) callback,
  }) =>
      clearMessagesByChatRoomId$(roomUniqueIds: roomUniqueIds)
          .toCallback1(callback);

  Future<void> clearUser$() async {
    return _authenticated.andThen(Task.delay(() {
      _get<Storage>().clear();
      _get<RealtimeService>('mqtt-service').end();
      _get<RealtimeService>('mqtt-service').end();
    })).run();
  }

  void clearUser({
    @required void Function(Exception) callback,
  }) {
    clearUser$().toCallback1(callback);
  }

  Future<QChatRoom> createChannel$({
    @required String uniqueId,
    String name,
    String avatarUrl,
    Map<String, dynamic> extras,
  }) async {
    final useCase = _get<GetOrCreateChannelUseCase>();
    return _authenticated
        .andThen(useCase(GetOrCreateChannelParams(
          uniqueId,
          name: name,
          avatarUrl: avatarUrl,
          options: extras,
        )))
        .rightMap((room) => room.toModel())
        .run()
        .then((either) => either.fold(
              (err) => Future.error(err),
              (room) => Future.value(room),
            ));
  }

  void createChannel({
    @required String uniqueId,
    String name,
    String avatarUrl,
    Map<String, dynamic> extras,
    @required void Function(QChatRoom, Exception) callback,
  }) =>
      createChannel$(
              uniqueId: uniqueId,
              name: name,
              avatarUrl: avatarUrl,
              extras: extras)
          .toCallback2(callback);

  void createGroupChat({
    @required String name,
    @required List<String> userIds,
    String avatarUrl,
    Map<String, dynamic> extras,
    @required void Function(QChatRoom, Exception) callback,
  }) {
    final useCase = _get<CreateGroupChatUseCase>();
    _authenticated
        .andThen(useCase(CreateGroupChatParams(
          name: name,
          userIds: userIds,
          avatarUrl: avatarUrl,
          extras: extras,
        )))
        .rightMap((r) => r.toModel())
        .toCallback(callback)
        .run();
  }

  void deleteMessages({
    @required List<String> messageUniqueIds,
    @required void Function(List<QMessage>, Exception) callback,
  }) {
    final useCase = _get<DeleteMessageUseCase>();
    _authenticated
        .andThen(useCase(DeleteMessageParams(messageUniqueIds)))
        .rightMap((it) => it.map((i) => i.toModel()).toList())
        .toCallback(callback)
        .run();
  }

  void enableDebugMode({
    @required bool enable,
    QLogLevel level = QLogLevel.verbose,
  }) {
    _get<Storage>()
      ..debugEnabled = enable
      ..logLevel = level;
  }

  void getAllChatRooms({
    bool showParticipant,
    bool showRemoved,
    bool showEmpty,
    int limit,
    int page,
    @required void Function(List<QChatRoom>, Exception) callback,
  }) {
    final useCase = _get<GetAllRoomsUseCase>();
    _authenticated
        .andThen(useCase(GetAllRoomsParams(
          withParticipants: showParticipant,
          withRemovedRoom: showRemoved,
          withEmptyRoom: showEmpty,
          limit: limit,
          page: page,
        )))
        .rightMap((r) => r.map((c) => c.toModel()).toList())
        .toCallback(callback)
        .run();
  }

  final _get = Injector.get;

  void getBlockedUsers({
    int page,
    int limit,
    @required void Function(List<QUser>, Exception) callback,
  }) {
    _authenticated
        .andThen(_get<GetBlocedUserUseCase>().call(
          GetBlockedUserParams(
            page: page,
            limit: limit,
          ),
        ))
        .rightMap((it) => it.map((u) => u.toModel()).toList())
        .toCallback(callback)
        .run();
  }

  void getChannel({
    @required String uniqueId,
    @required void Function(QChatRoom, Exception) callback,
  }) {
    _authenticated
        .andThen(_get<GetOrCreateChannelUseCase>()(GetOrCreateChannelParams(
          uniqueId,
        )))
        .rightMap((room) => room.toModel())
        .toCallback(callback)
        .run();
  }

  void getChatRooms({
    List<int> roomIds,
    List<String> uniqueIds,
    int page,
    bool showRemoved,
    bool showParticipants,
    @required void Function(List<QChatRoom>, Exception) callback,
  }) {
    const errorMessage = 'Please specify either `roomIds` or `uniqueIds`';
    // Throw error if both roomIds and uniqueIds are null
    assert(roomIds == null && uniqueIds == null, errorMessage);
    assert(roomIds != null && uniqueIds != null, errorMessage);

    _authenticated
        .andThen(_get<GetRoomInfoUseCase>()(GetRoomInfoParams(
          roomIds: roomIds,
          uniqueIds: uniqueIds,
          withRemoved: showRemoved,
          withParticipants: showParticipants,
          page: page,
        )))
        .rightMap((r) => r.map((it) => it.toModel()).toList())
        .toCallback(callback)
        .run();
  }

  void getChatRoomWithMessages({
    @required int roomId,
    @required void Function(QChatRoom, List<QMessage>, Exception) callback,
  }) {
    _authenticated
        .andThen(_get<GetRoomWithMessagesUseCase>()(RoomIdParams(roomId)))
        .leftMap((err) => callback(null, null, err))
        .rightMap((it) => callback(
              it.value1.toModel(),
              it.value2.map((m) => m.toModel()).toList(),
              null,
            ))
        .run();
  }

  void getJWTNonce({
    void Function(String, Exception) callback,
  }) {
    _get<GetNonceUseCase>()(NoParams()).toCallback(callback).run();
  }

  void getNextMessagesById({
    @required int roomId,
    @required int messageId,
    int limit,
    @required void Function(List<QMessage>, Exception) callback,
  }) {
    _authenticated
        .andThen(_get<GetMessageListUseCase>()(
          GetMessageListParams(roomId, messageId, after: true, limit: limit),
        ))
        .rightMap((it) => it.map((it) => it.toModel()).toList())
        .toCallback(callback)
        .run();
  }

  void getParticipants({
    @required String roomUniqueId,
    int page,
    int limit,
    String sorting,
    @required void Function(List<QParticipant>, Exception) callback,
  }) {
    _authenticated
        .andThen(
            _get<GetParticipantsUseCase>()(RoomUniqueIdsParams(roomUniqueId)))
        .rightMap((r) => r.map((p) => p.toModel()).toList())
        .toCallback(callback)
        .run();
  }

  Future<List<QMessage>> getPreviousMessagesById$({
    @required int roomId,
    int limit,
    int messageId,
  }) async {
    return _authenticated
        .andThen(_get<GetMessageListUseCase>()(
          GetMessageListParams(roomId, messageId, after: false, limit: limit),
        ))
        .rightMap((it) => it.map((m) => m.toModel()).toList())
        .run()
        .then((either) => either.fold(
              (error) => Future<List<QMessage>>.error(error),
              (messages) => Future.value(messages),
            ));
  }

  void getPreviousMessagesById({
    @required int roomId,
    int limit,
    int messageId,
    @required Function2<List<QMessage>, Exception, void> callback,
  }) {
    getPreviousMessagesById$(roomId: roomId, limit: limit, messageId: messageId)
        .toCallback2(callback);
  }

  String getThumbnailURL(String url) => '';

  void getTotalUnreadCount({
    @required void Function(int, Exception) callback,
  }) {
    _authenticated
        .andThen(_get<GetTotalUnreadCountUseCase>()(noParams))
        .toCallback(callback)
        .run();
  }

  void getUserData({
    void Function(QAccount, Exception) callback,
  }) {
    _authenticated
        .andThen(_get<GetUserDataUseCase>().call(NoParams()))
        .rightMap((user) => user.toModel())
        .toCallback(callback)
        .run();
  }

  void getUsers({
    @deprecated String searchUsername,
    int page,
    int limit,
    @required void Function(List<QUser>, Exception) callback,
  }) {
    _authenticated
        .andThen(_get<GetUsersUseCase>().call(GetUserParams(
          query: searchUsername,
          page: page,
          limit: limit,
        )))
        .rightMap((it) => it.map((u) => u.toModel()).toList())
        .toCallback(callback)
        .run();
  }

  void hasSetupUser({
    @required void Function(bool) callback,
  }) {
    callback(currentUser != null);
  }

  void intercept({
    @required String interceptor,
    @required Future<QMessage> Function(QMessage) callback,
  }) {}

  void markAsDelivered({
    @required int roomId,
    @required int messageId,
    @required void Function(Exception) callback,
  }) {
    _authenticated
        .andThen(_get<UpdateMessageStatusUseCase>()(UpdateStatusParams(
          roomId,
          messageId,
          QMessageStatus.delivered,
        )))
        .toCallback((_, e) => callback(e))
        .run();
  }

  void markAsRead({
    @required int roomId,
    @required int messageId,
    @required void Function(Exception) callback,
  }) {
    _authenticated
        .andThen(_get<UpdateMessageStatusUseCase>()(UpdateStatusParams(
          roomId,
          messageId,
          QMessageStatus.read,
        )))
        .toCallback((_, e) => callback(e))
        .run();
  }

  Subscription onChatRoomCleared(void Function(int) handler) {
    var ret = _authenticated
        .andThen(_get<OnRoomMessagesCleared>().subscribe(noParams))
        .bind((s) => Task.delay(() => s.listen((it) => handler(it))))
        .run();
    return () => ret.then<void>((s) => s.cancel());
  }

  Subscription onConnected(void Function() handler) {
    var ret = _authenticated
        .andThen(_get<OnConnected>().subscribe(NoParams()))
        .bind((stream) => Task.delay(() => stream.listen((_) => handler())))
        .run();
    return () => ret.then<void>((s) => s.cancel());
  }

  Subscription onDisconnected(void Function() handler) {
    var ret = _authenticated
        .andThen(_get<OnDisconnected>().subscribe(noParams))
        .bind((s) => Task.delay(() => s.listen((_) => handler())))
        .run();
    return () => ret.then<void>((s) => s.cancel());
  }

  Subscription onMessageDeleted(Function1<QMessage, void> callback) {
    var subs = _authenticated
        .andThen(_get<OnMessageDeleted>().listen((m) => callback(m.toModel())))
        .run();
    return () => subs.then<void>((s) => s.cancel());
  }

  Subscription onMessageDelivered(void Function(QMessage) callback) {
    final subs = _authenticated
        .andThen(
            _get<OnMessageDelivered>().listen((m) => callback(m.toModel())))
        .run();
    return () => subs.then<void>((s) => s.cancel());
  }

  Subscription onMessageRead(void Function(QMessage) callback) {
    final subs = _authenticated
        .andThen(_get<OnMessageRead>().listen((m) => callback(m.toModel())))
        .run();
    return () => subs.then<void>((s) => s.cancel());
  }

  Subscription onMessageReceived(void Function(QMessage) callback) {
    var listenable =
        _get<OnMessageReceived>().listen((m) => callback(m.toModel()));

    var subs = _authenticated.andThen(listenable).run();
    return () => subs.then<void>((s) => s.cancel());
  }

  Subscription onReconnecting(void Function() handler) {
    var ret = _authenticated
        .andThen(_get<OnReconnecting>().subscribe(noParams))
        .bind((s) => Task.delay(() => s.listen((_) => handler())))
        .run();
    return () => ret.then<void>((s) => s.cancel());
  }

  Subscription onUserOnlinePresence(
    void Function(String, bool, DateTime) handler,
  ) {
    final subs = _authenticated //
        .andThen(_get<PresenceUseCase>().listen((data) {
          handler(data.userId, data.isOnline, data.lastSeen);
        }))
        .run();
    return () => subs.then<void>((s) => s.cancel());
  }

  Subscription onUserTyping(void Function(String, int, bool) handler) {
    var subs = _authenticated
        .andThen(_get<TypingUseCase>().listen((data) {
          handler(data.userId, data.roomId, data.isTyping);
        }))
        .run();
    return () => subs.then<void>((s) => s.cancel());
  }

  void publishCustomEvent({
    @required int roomId,
    @required Map<String, dynamic> payload,
    @required void Function(Exception) callback,
  }) {
    _authenticated
        .andThen(
          _get<CustomEventUseCase>()(CustomEvent(roomId, payload)),
        )
        .map((either) => either.fold((e) => callback(e), (_) {}))
        .run();
  }

  void publishOnlinePresence({
    @required bool isOnline,
    @required void Function(Exception) callback,
  }) {
    _authenticated
        .andThen(_get<PresenceUseCase>()(Presence(
          userId: _get<Storage>().userId,
          isOnline: isOnline,
          lastSeen: DateTime.now(),
        )))
        .leftMap((error) => callback(error))
        .run();
  }

  void publishTyping({
    @required int roomId,
    bool isTyping,
  }) {
    _authenticated
        .andThen(_get<TypingUseCase>()(Typing(
          userId: _get<Storage>().userId,
          roomId: roomId,
          isTyping: isTyping,
        )))
        .run();
  }

  void registerDeviceToken({
    @required String token,
    bool isDevelopment,
    void Function(bool, Exception) callback,
  }) {
    _authenticated
        .andThen(_get<RegisterDeviceTokenUseCase>()(DeviceTokenParams(
          token,
          isDevelopment,
        )))
        .toCallback(callback)
        .run();
  }

  void removeDeviceToken({
    @required String token,
    bool isDevelopment,
    void Function(bool, Exception) callback,
  }) {
    _authenticated
        .andThen(_get<UnregisterDeviceTokenUseCase>()(DeviceTokenParams(
          token,
          isDevelopment,
        )))
        .toCallback(callback)
        .run();
  }

  void removeParticipants({
    @required int roomId,
    @required List<String> userIds,
    @required void Function(List<String>, Exception) callback,
  }) {
    _authenticated
        .andThen(_get<RemoveParticipantUseCase>()(
            ParticipantParams(roomId, userIds)))
        .toCallback(callback)
        .run();
  }

  void sendFileMessage({
    @required QMessage message,
    @required File file,
    @required void Function(Exception, double, QMessage) callback,
  }) {
    upload(
      file: file,
      callback: (error, progress, url) async {
        if (error != null) return callback(error, null, null);
        if (error == null && progress != null) {
          return callback(null, progress, null);
        }
        message.payload ??= <String, dynamic>{};
        message.payload['url'] = url;
        message.payload['size'] = await message.payload['size'];
        message.text = '[file] $url [/file]';
        sendMessage(
            message: message,
            callback: (message, error) {
              callback(error, null, message);
            });
      },
    );
  }

  Future<QMessage> sendMessage$({@required QMessage message}) async {
    return _authenticated
        .andThen(Task.delay(() {
          message.sender = _get<Storage>().currentUser?.toModel()?.asUser();
          return message;
        }))
        .bind((message) => _get<SendMessageUseCase>()(MessageParams(message)))
        .rightMap((it) => it.toModel())
        .run()
        .then((either) => either.fold(
              (err) => Future<QMessage>.error(err),
              (message) => Future.value(message),
            ));
  }

  void sendMessage({
    @required QMessage message,
    @required void Function(QMessage, Exception) callback,
  }) =>
      sendMessage$(message: message).toCallback2(callback);

  void setCustomHeader(Map<String, String> headers) {
    _get<Storage>().customHeaders = headers;
  }

  void setSyncInterval(double interval) {
    _get<Storage>().syncInterval = interval.ceil();
  }

  Future<void> setup$(String appId) async {
    return setupWithCustomServer$(appId);
  }

  void setup(String appId, {@required Function1<Exception, void> callback}) {
    setup$(appId).toCallback1(callback);
  }

  Future<void> setupWithCustomServer$(
    String appId, {
    String baseUrl = Storage.defaultBaseUrl,
    String brokerUrl = Storage.defaultBrokerUrl,
    String brokerLbUrl = Storage.defaultBrokerLbUrl,
    int syncInterval = Storage.defaultSyncInterval,
    int syncIntervalWhenConnected = Storage.defaultSyncIntervalWhenConnected,
  }) async {
    final storage = _get<Storage>();
    storage
      ..appId = appId
      ..baseUrl = baseUrl
      ..brokerUrl = brokerUrl
      ..brokerLbUrl = brokerLbUrl
      ..syncInterval = syncInterval
      ..syncIntervalWhenConnected = syncIntervalWhenConnected;

    return _get<AppConfigUseCase>()(noParams)
        .tap((_) {
          // override server value with user provided value
          storage
            ..appId = appId
            ..baseUrl = baseUrl
            ..brokerUrl = brokerUrl
            ..brokerLbUrl = brokerLbUrl
            ..syncInterval = syncInterval
            ..syncIntervalWhenConnected = syncIntervalWhenConnected;
        })
        .map((either) => either.fold(
              (err) => Future<void>.error(err),
              (_) => Future.value(null),
            ))
        .run();
  }

  void setupWithCustomServer(
    String appId, {
    String baseUrl = Storage.defaultBaseUrl,
    String brokerUrl = Storage.defaultBrokerUrl,
    String brokerLbUrl = Storage.defaultBrokerLbUrl,
    int syncInterval = Storage.defaultSyncInterval,
    int syncIntervalWhenConnected = Storage.defaultSyncIntervalWhenConnected,
    @required Function1<Exception, void> callback,
  }) {
    setupWithCustomServer$(appId,
            baseUrl: baseUrl,
            brokerUrl: brokerUrl,
            brokerLbUrl: brokerLbUrl,
            syncInterval: syncInterval,
            syncIntervalWhenConnected: syncIntervalWhenConnected)
        .toCallback1(callback);
  }

  void _markDelivered(int roomId, int messageId) {
    markAsDelivered(roomId: roomId, messageId: messageId, callback: (_) {});
  }

  void _receiveMessage(Stream<Message> stream) {
    stream.tap((message) {
      message.chatRoomId.fold(() {}, (roomId) {
        _markDelivered(roomId, message.id);
      });
    });
  }

  Task<Either<Exception, void>> _subscribes(String token) {
    return _get<OnMessageReceived>()
        .subscribe(TokenParams(token))
        .bind((stream) => Task.delay(() => _receiveMessage(stream)))
        .andThen(_get<RealtimeService>()
            .subscribe(TopicBuilder.notification(token)));
  }

  Future<QAccount> setUser$({
    @required String userId,
    @required String userKey,
    String username,
    String avatarUrl,
    Map<String, dynamic> extras,
  }) {
    final authenticate = _get<AuthenticateUserUseCase>();
    final params = AuthenticateParams(
      userId: userId,
      userKey: userKey,
      name: username,
      avatarUrl: avatarUrl,
      extras: extras,
    );
    return authenticate(params)
        .tap((data) => _subscribes(data.value1))
        .run()
        .then((either) => either.fold(
              (error) => Future.error(error),
              (data) => Future.value(data.value2.toModel()),
            ));
  }

  void setUser({
    @required String userId,
    @required String userKey,
    String username,
    String avatarUrl,
    Map<String, dynamic> extras,
    @required void Function(QAccount, Exception) callback,
  }) {
    setUser$(
            userId: userId,
            userKey: userKey,
            username: username,
            avatarUrl: avatarUrl,
            extras: extras)
        .toCallback2(callback);
  }

  Future<QAccount> setUserWithIdentityToken$({String token}) {
    var completer = Completer<QAccount>();
    _get<AuthenticateUserWithTokenUseCase>()
        .call(AuthenticateWithTokenParams(token))
        .rightMap((user) => user.toModel())
        .run()
        .then((either) => either.fold(
              (err) => completer.completeError(err),
              (account) => completer.complete(account),
            ));
    return completer.future;
  }

  void setUserWithIdentityToken({
    String token,
    @required void Function(QAccount, Exception) callback,
  }) {
    setUserWithIdentityToken$(token: token).toCallback2(callback);
  }

  void unsubscribeChatRoom(QChatRoom room) {
    final params = RoomIdParams(room.id);

    final read = _get<OnMessageRead>().unsubscribe(params);
    final delivered = _get<OnMessageDelivered>().unsubscribe(params);
    final typing = _get<TypingUseCase>().unsubscribe(Typing(
      roomId: room.id,
      userId: '+',
    ));

    _authenticated.andThen(read).andThen(delivered).andThen(typing).run();
  }

  void subscribeChatRoom(QChatRoom room) {
    final params = RoomIdParams(room.id);

    final read = _get<OnMessageRead>().subscribe(params);
    final delivered = _get<OnMessageDelivered>().subscribe(params);
    final typing = _get<TypingUseCase>().subscribe(Typing(
      roomId: room.id,
      userId: '+',
    ));
    _authenticated.andThen(read).andThen(delivered).andThen(typing).run();
  }

  void subscribeCustomEvent({
    @required int roomId,
    @required void Function(Map<String, dynamic>) callback,
  }) {
    _authenticated
        .andThen(_get<CustomEventUseCase>().subscribe(RoomIdParams(roomId)))
        .bind((stream) =>
            Task.delay(() => stream.listen((data) => callback(data.payload))))
        .run();
  }

  void subscribeUserOnlinePresence(String userId) {
    _authenticated
        .andThen(_get<PresenceUseCase>().subscribe(Presence(userId: userId)))
        .run();
  }

  void synchronize({String lastMessageId}) {
    _authenticated
        .andThen(_get<RealtimeService>().synchronize(int.parse(lastMessageId)))
        .run()
        .catchError((dynamic _) {});
  }

  void synchronizeEvent({String lastEventId}) {
    _authenticated
        .andThen(_get<RealtimeService>().synchronizeEvent(lastEventId))
        .run()
        .catchError((dynamic _) {});
  }

  void unblockUser({
    @required String userId,
    @required void Function(QUser, Exception) callback,
  }) {
    _authenticated
        .andThen(_get<UnblockUserUseCase>().call(UnblockUserParams(userId)))
        .rightMap((u) => u.toModel())
        .toCallback(callback)
        .run();
  }

  void unsubscribeCustomEvent({@required int roomId}) {
    _authenticated
        .andThen(_get<CustomEventUseCase>().unsubscribe(RoomIdParams(roomId)))
        .run();
  }

  void unsubscribeUserOnlinePresence(String userId) {
    _authenticated
        .andThen(_get<PresenceUseCase>().unsubscribe(Presence(userId: userId)))
        .run();
  }

  void updateChatRoom({
    int roomId,
    String name,
    String avatarUrl,
    Map<String, dynamic> extras,
    @required void Function(QChatRoom, Exception) callback,
  }) {
    _authenticated
        .andThen(_get<UpdateRoomUseCase>()(UpdateRoomParams(
          roomId: roomId,
          name: name,
          avatarUrl: avatarUrl,
          extras: extras,
        )))
        .rightMap((r) => r.toModel())
        .toCallback(callback)
        .run();
  }

  void updateUser({
    String name,
    String avatarUrl,
    Map<String, dynamic> extras,
    @required void Function(QAccount, Exception) callback,
  }) {
    _authenticated
        .andThen(_get<UpdateUserUseCase>()(UpdateUserParams(
          name: name,
          avatarUrl: avatarUrl,
          extras: extras,
        )))
        .rightMap((u) => u.toModel())
        .toCallback(callback)
        .run();
  }

  void upload({
    @required File file,
    @required void Function(Exception, double, String) callback,
  }) async {
    final uploadUrl = _get<Storage>().uploadUrl;
    final dio = _get<Dio>();
    var filename = file.path.split('/').last;
    var formData = FormData.fromMap(<String, dynamic>{
      'file': await MultipartFile.fromFile(file.path, filename: filename),
    });
    await dio.post<Map<String, dynamic>>(
      uploadUrl,
      data: formData,
      onSendProgress: (count, total) {
        var percentage = (count / total) * 100;
        callback(null, percentage, null);
      },
    ).then((resp) {
      var json = resp.data;
      var url = json['results']['file']['url'] as String;
      callback(null, null, url);
    }).catchError((dynamic error) {
      callback(Exception(error.toString()), null, null);
    });
  }

  String _generateUniqueId() =>
      'flutter-${DateTime.now().millisecondsSinceEpoch}';

  QMessage generateMessage({
    @required int chatRoomId,
    @required String text,
    Map<String, dynamic> extras,
  }) {
    var id = Random.secure().nextInt(10000);
    return QMessage(
      // Provided by user
      chatRoomId: chatRoomId,
      text: text,
      extras: extras,
      timestamp: DateTime.now(),
      uniqueId: _generateUniqueId(),
      //
      id: id,
      payload: null,
      previousMessageId: 0,
      sender: currentUser.asUser(),
      status: QMessageStatus.sending,
      type: QMessageType.text,
    );
  }

  QMessage generateCustomMessage({
    @required int chatRoomId,
    @required String text,
    @required String type,
    Map<String, dynamic> extras,
    @required Map<String, dynamic> payload,
  }) {
    var id = Random.secure().nextInt(10000);
    return QMessage(
      // Provided by user
      chatRoomId: chatRoomId,
      text: text,
      timestamp: DateTime.now(),
      uniqueId: _generateUniqueId(),
      extras: extras,
      payload: <String, dynamic>{
        'type': type,
        'payload': payload,
      },
      //
      id: id,
      previousMessageId: 0,
      sender: currentUser.asUser(),
      status: QMessageStatus.sending,
      type: QMessageType.custom,
    );
  }

  QMessage generateFileAttachmentMessage({
    @required int chatRoomId,
    @required String caption,
    @required String url,
    String filename,
    String text,
    int size,
    Map<String, dynamic> extras,
  }) {
    var id = Random.secure().nextInt(10000);
    return QMessage(
      // Provided by user
      chatRoomId: chatRoomId,
      text: text,
      timestamp: DateTime.now(),
      uniqueId: _generateUniqueId(),
      extras: extras,
      payload: <String, dynamic>{
        'url': '',
        'file_name': filename,
        'size': size,
        'caption': caption,
      },
      //
      id: id,
      previousMessageId: 0,
      sender: currentUser.asUser(),
      status: QMessageStatus.sending,
      type: QMessageType.custom,
    );
  }
}

extension _TaskX<L1, R1> on Task<Either<L1, R1>> {
  Task<Either<void, void>> toCallback(void Function(R1, L1) callback) {
    return leftMap((err) {
      callback(null, err);
    }).rightMap((val) {
      callback(val, null);
    });
  }
}

extension _FutureX<T> on Future<T> {
  void toCallback1(void Function(Exception) callback) {
    this.then(
      (_) => callback(null),
      onError: (Object error) => callback(error as Exception),
    );
  }

  void toCallback2(void Function(T, Exception) callback) {
    this.then(
      (value) => callback(value, null),
      onError: (Object error) => callback(null, error as Exception),
    );
  }
}
