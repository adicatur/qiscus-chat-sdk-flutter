import 'package:dartz/dartz.dart';
import 'package:meta/meta.dart';
import 'package:qiscus_chat_sdk/src/core/core.dart';
import 'package:qiscus_chat_sdk/src/features/room/room.dart';

class CreateGroupChatParams {
  const CreateGroupChatParams({
    @required this.name,
    @required this.userIds,
    this.avatarUrl,
    this.extras,
  });
  final String name;
  final List<String> userIds;
  final String avatarUrl;
  final Map<String, dynamic> extras;
}

class CreateGroupChatUseCase
    extends UseCase<RoomRepository, ChatRoom, CreateGroupChatParams> {
  CreateGroupChatUseCase(RoomRepository repository) : super(repository);

  @override
  Task<Either<Exception, ChatRoom>> call(p) {
    return repository.createGroup(
      name: p.name,
      userIds: p.userIds,
      avatarUrl: p.avatarUrl,
      extras: p.extras,
    );
  }
}
