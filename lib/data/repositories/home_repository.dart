import '../models/home_snapshot.dart';
import '../services/home_service.dart';

class HomeRepository {
  HomeRepository(this._service);
  final HomeService _service;

  Future<HomeSnapshot> load() => _service.getSnapshot();
}
