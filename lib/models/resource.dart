enum ResourceType { seat, room }

class Resource {
  const Resource(
      {required this.id,
      required this.name,
      required this.type,
      required this.takenSlotsToday});

  final String id;
  final String name;
  final ResourceType type;
  final List<String> takenSlotsToday;
}
