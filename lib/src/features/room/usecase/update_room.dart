import 'package:dartz/dartz.dart';
import 'package:meta/meta.dart';
import 'package:qiscus_chat_sdk/src/core/core.dart';
import 'package:qiscus_chat_sdk/src/features/room/repository.dart';
import 'package:qiscus_chat_sdk/src/features/room/room.dart';

class UpdateRoomUseCase
    extends UseCase<RoomRepository, ChatRoom, UpdateRoomParams> {
  UpdateRoomUseCase(RoomRepository repository) : super(repository);

  @override
  Task<Either<Exception, ChatRoom>> call(p) {
    return repository.updateRoom(
      roomId: p.roomId,
      name: p.name,
      avatarUrl: p.avatarUrl,
      extras: p.extras,
    );
  }
}

@sealed
@immutable
class UpdateRoomParams {
  const UpdateRoomParams({
    @required this.roomId,
    this.name,
    this.avatarUrl,
    this.extras,
  });

  final int roomId;
  final String name;
  final String avatarUrl;
  final Map<String, dynamic> extras;
}
