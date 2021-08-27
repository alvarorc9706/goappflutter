import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart' as location;
import 'package:progress_dialog/progress_dialog.dart';
import 'package:goappflutter/src/api/environment.dart';
import 'package:goappflutter/src/models/travel_history.dart';
import 'package:goappflutter/src/models/client.dart';
import 'package:goappflutter/src/models/travel_info.dart';
import 'package:goappflutter/src/providers/auth_provider.dart';
import 'package:goappflutter/src/providers/client_provider.dart';
import 'package:goappflutter/src/providers/geofire_provider.dart';
import 'package:goappflutter/src/providers/driver_provider.dart';
import 'package:goappflutter/src/providers/push_notifications_provider.dart';
import 'package:goappflutter/src/providers/travel_history_provider.dart';
import 'package:goappflutter/src/providers/travel_info_provider.dart';
import 'package:goappflutter/src/providers/prices_provider.dart';
import 'package:goappflutter/src/utils/my_progress_dialog.dart';
import 'package:goappflutter/src/utils/snackbar.dart' as utils;
import 'package:goappflutter/src/models/driver.dart';
import 'package:goappflutter/src/models/prices.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:goappflutter/src/widgets/bottom_sheet_driver_info.dart';


class DriverTravelMapController {

  BuildContext context;
  Function refresh;
  GlobalKey<ScaffoldState> key = new GlobalKey<ScaffoldState>();
  Completer<GoogleMapController> _mapController = Completer();

  CameraPosition initialPosition = CameraPosition(
      target: LatLng(1.2342774, -77.2645446),
      zoom: 14.0
  );

  Map<MarkerId, Marker> markers = <MarkerId, Marker>{};

  Position _position;
  StreamSubscription<Position> _positionStream;

  BitmapDescriptor markerDriver;
  BitmapDescriptor fromMarker;
  BitmapDescriptor toMarker;

  GeofireProvider _geofireProvider;
  AuthProvider _authProvider;
  DriverProvider _driverProvider;
  PushNotificationsProvider _pushNotificationsProvider;
  TravelInfoProvider _travelInfoProvider;
  PricesProvider _pricesProvider;
  ClientProvider _clientProvider;
  TravelHistoryProvider _travelHistoryProvider;

  bool isConnect = false;
  ProgressDialog _progressDialog;

  StreamSubscription<DocumentSnapshot> _statusSuscription;
  StreamSubscription<DocumentSnapshot> _driverInfoSuscription;

  Set<Polyline> polylines = {};
  List<LatLng> points = new List();

  Driver driver;
  Client _client;

  String _idTravel;
  TravelInfo travelInfo;

  String currentStatus = 'INICIAR VIAJE';
  Color colorStatus = Colors.indigo;

  double _distanceBetween;

  Timer _timer;
  int seconds = 0;
  double mt = 0;
  double km = 0;

  Future init(BuildContext context, Function refresh) async {
    this.context = context;
    this.refresh = refresh;

    _idTravel = ModalRoute.of(context).settings.arguments as String;

    _geofireProvider = new GeofireProvider();
    _authProvider = new AuthProvider();
    _driverProvider = new DriverProvider();
    _travelInfoProvider = new TravelInfoProvider();
    _pushNotificationsProvider = new PushNotificationsProvider();
    _pricesProvider = new PricesProvider();
    _clientProvider = new ClientProvider();
    _travelHistoryProvider = new TravelHistoryProvider();
    _progressDialog = MyProgressDialog.createProgressDialog(context, 'Conectandose...');

    markerDriver = await createMarkerImageFromAsset('assets/img/taxi_icon.png');
    fromMarker = await createMarkerImageFromAsset('assets/img/map_pin_red.png');
    toMarker = await createMarkerImageFromAsset('assets/img/map_pin_blue.png');

    checkGPS();
    getDriverInfo();
  }

  void getClientInfo() async {
    _client = await _clientProvider.getById(_idTravel);
  }

  Future<double> calculatePrice() async {
    Prices prices = await _pricesProvider.getAll();

    if (seconds < 60) seconds = 60;
    if (km == 0) km = 0.1;

    int min = seconds ~/ 60;

    print('=========== MIN TOTALES ==============');
    print(min.toString());

    print('=========== KM TOTALES ==============');
    print(km.toString());

    double priceMin = min * prices.min;
    double priceKm = km * prices.km;

    double total = priceMin + priceKm;

    if (total < prices.minValue) {
      total = prices.minValue;
    }

    print('=========== TOTAL ==============');
    print(total.toString());

    return total;
  }

  void startTimer() {
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      seconds = timer.tick;
      refresh();
    });
  }

  void isCloseToPickupPosition(LatLng from, LatLng to) {
    _distanceBetween = Geolocator.distanceBetween(
        from.latitude,
        from.longitude,
        to.latitude,
        to.longitude
    );
    print('------ DISTANCE: $_distanceBetween--------');
  }

  void updateStatus () {
    if (travelInfo.status == 'accepted') {
      startTravel();
    }
    else if (travelInfo.status == 'started') {
      finishTravel();
    }
  }

  void startTravel() async {
    if (_distanceBetween <= 300) {
      Map<String, dynamic> data = {
        'status': 'started'
      };
      await _travelInfoProvider.update(data, _idTravel);
      travelInfo.status = 'started';
      currentStatus = 'FINALIZAR VIAJE';
      colorStatus = Colors.cyan;

      polylines = {};
      points = List();
      // markers.remove(markers['from']);
      markers.removeWhere((key, marker) => marker.markerId.value == 'from');
      addSimpleMarker(
          'to',
          travelInfo.toLat,
          travelInfo.toLng,
          'Destino',
          '',
          toMarker
      );

      LatLng from = new LatLng(_position.latitude, _position.longitude);
      LatLng to = new LatLng(travelInfo.toLat, travelInfo.toLng);

      setPolylines(from, to);
      startTimer();
      refresh();
    }
    else {
      utils.Snackbar.showSnackbar(context, key, 'Debes estar cerca a la posicion del cliente para iniciar el viaje');
    }

    refresh();
  }

  void finishTravel() async {
    _timer?.cancel();

    double total = await calculatePrice();

    saveTravelHistory(total);

  }

  void saveTravelHistory(double price) async {
    TravelHistory travelHistory = new TravelHistory(
      from: travelInfo.from,
      to: travelInfo.to,
      idDriver: _authProvider.getUser().uid,
      idClient: _idTravel,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      price: price
    );

    String id = await _travelHistoryProvider.create(travelHistory);

    Map<String, dynamic> data = {
      'status': 'finished',
      'idTravelHistory': id,
      'price': price,
    };
    await _travelInfoProvider.update(data, _idTravel);
    travelInfo.status = 'finished';

    Navigator.pushNamedAndRemoveUntil(context, 'driver/travel/calification', (route) => false, arguments: id);
  }

  void _getTravelInfo() async {
    travelInfo = await _travelInfoProvider.getById(_idTravel);
    LatLng from = new LatLng(_position.latitude, _position.longitude);
    LatLng to = new LatLng(travelInfo.fromLat, travelInfo.fromLng);
    addSimpleMarker('from', to.latitude, to.longitude, 'Recoger aqui', '', fromMarker);
    setPolylines(from, to);
    getClientInfo();
  }

  Future<void> setPolylines(LatLng from, LatLng to) async {
    PointLatLng pointFromLatLng = PointLatLng(from.latitude, from.longitude);
    PointLatLng pointToLatLng = PointLatLng(to.latitude, to.longitude);

    PolylineResult result = await PolylinePoints().getRouteBetweenCoordinates(
        Environment.API_KEY_MAPS,
        pointFromLatLng,
        pointToLatLng
    );

    for (PointLatLng point in result.points) {
      points.add(LatLng(point.latitude, point.longitude));
    }

    Polyline polyline = Polyline(
        polylineId: PolylineId('poly'),
        color: Colors.indigo,
        points: points,
        width: 6
    );

    polylines.add(polyline);

    // addMarker('to', toLatLng.latitude, toLatLng.longitude, 'Destino', '', toMarker);

    refresh();
  }

  void getDriverInfo() {
    Stream<DocumentSnapshot> driverStream = _driverProvider.getByIdStream(_authProvider.getUser().uid);
    _driverInfoSuscription = driverStream.listen((DocumentSnapshot document) {
      driver = Driver.fromJson(document.data());
      refresh();
    });
  }

  void dispose() {
    _timer?.cancel();
    _positionStream?.cancel();
    _statusSuscription?.cancel();
    _driverInfoSuscription?.cancel();
  }

  void onMapCreated(GoogleMapController controller) {
    controller.setMapStyle('[{"elementType":"geometry","stylers":[{"color":"#1d2c4d"}]},{"elementType":"labels.text.fill","stylers":[{"color":"#8ec3b9"}]},{"elementType":"labels.text.stroke","stylers":[{"color":"#1a3646"}]},{"featureType":"administrative.country","elementType":"geometry.stroke","stylers":[{"color":"#4b6878"}]},{"featureType":"administrative.land_parcel","elementType":"labels.text.fill","stylers":[{"color":"#64779e"}]},{"featureType":"administrative.province","elementType":"geometry.stroke","stylers":[{"color":"#4b6878"}]},{"featureType":"landscape.man_made","elementType":"geometry.stroke","stylers":[{"color":"#334e87"}]},{"featureType":"landscape.natural","elementType":"geometry","stylers":[{"color":"#023e58"}]},{"featureType":"poi","elementType":"geometry","stylers":[{"color":"#283d6a"}]},{"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#6f9ba5"}]},{"featureType":"poi","elementType":"labels.text.stroke","stylers":[{"color":"#1d2c4d"}]},{"featureType":"poi.park","elementType":"geometry.fill","stylers":[{"color":"#023e58"}]},{"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#3C7680"}]},{"featureType":"road","elementType":"geometry","stylers":[{"color":"#304a7d"}]},{"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#98a5be"}]},{"featureType":"road","elementType":"labels.text.stroke","stylers":[{"color":"#1d2c4d"}]},{"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#2c6675"}]},{"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#255763"}]},{"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#b0d5ce"}]},{"featureType":"road.highway","elementType":"labels.text.stroke","stylers":[{"color":"#023e58"}]},{"featureType":"transit","elementType":"labels.text.fill","stylers":[{"color":"#98a5be"}]},{"featureType":"transit","elementType":"labels.text.stroke","stylers":[{"color":"#1d2c4d"}]},{"featureType":"transit.line","elementType":"geometry.fill","stylers":[{"color":"#283d6a"}]},{"featureType":"transit.station","elementType":"geometry","stylers":[{"color":"#3a4762"}]},{"featureType":"water","elementType":"geometry","stylers":[{"color":"#0e1626"}]},{"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#4e6d70"}]}]');
    _mapController.complete(controller);
  }

  void saveLocation() async {
    await _geofireProvider.createWorking(
        _authProvider.getUser().uid,
        _position.latitude,
        _position.longitude
    );
    _progressDialog.hide();
  }




  void updateLocation() async  {
    try {
      await _determinePosition();
      _position = await Geolocator.getLastKnownPosition();
      centerPosition();
      saveLocation();

      addMarker(
          'driver',
          _position.latitude,
          _position.longitude,
          'Tu posicion',
          '',
          markerDriver
      );
      refresh();

      _positionStream = Geolocator.getPositionStream(
          desiredAccuracy: LocationAccuracy.best,
          distanceFilter: 1
      ).listen((Position position) {
        _position = position;
        addMarker(
            'driver',
            _position.latitude,
            _position.longitude,
            'Tu posicion',
            '',
            markerDriver
        );
        animateCameraToPosition(_position.latitude, _position.longitude);

        if (isConnect) {
          saveLocation();
        }

        refresh();
      });

    } catch(error) {
      print('Error en la localizacion: $error');
    }
  }
  void openBottomSheet() {
    if (_client == null) return;

    showMaterialModalBottomSheet(
        context: context,
        builder: (context) => BottomSheetDriverInfo(
          imageUrl: _client?.image,
          username: _client?.username,
          email: _client?.email,
        )
    );
  }

  void centerPosition() {
    if (_position != null) {
      animateCameraToPosition(_position.latitude, _position.longitude);
    }
    else {
      utils.Snackbar.showSnackbar(context, key, 'Activa el GPS para obtener la posicion');
    }
  }

  void checkGPS() async {
    bool isLocationEnabled = await Geolocator.isLocationServiceEnabled();
    if (isLocationEnabled) {
      print('GPS ACTIVADO');
      updateLocation();
    }
    else {
      print('GPS DESACTIVADO');
      bool locationGPS = await location.Location().requestService();
      if (locationGPS) {
        updateLocation();
        print('ACTIVO EL GPS');
      }
    }

  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.deniedForever) {
      return Future.error(
          'Location permissions are permantly denied, we cannot request permissions.');
    }

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        return Future.error(
            'Location permissions are denied (actual value: $permission).');
      }
    }

    return await Geolocator.getCurrentPosition();
  }

  Future animateCameraToPosition(double latitude, double longitude) async {
    GoogleMapController controller = await _mapController.future;
    if (controller != null) {
      controller.animateCamera(CameraUpdate.newCameraPosition(
          CameraPosition(
              bearing: 0,
              target: LatLng(latitude, longitude),
              zoom: 15
          )
      ));
    }
  }

  Future<BitmapDescriptor> createMarkerImageFromAsset(String path) async {
    ImageConfiguration configuration = ImageConfiguration();
    BitmapDescriptor bitmapDescriptor =
    await BitmapDescriptor.fromAssetImage(configuration, path);
    return bitmapDescriptor;
  }

  void addMarker(
      String markerId,
      double lat,
      double lng,
      String title,
      String content,
      BitmapDescriptor iconMarker
      ) {

    MarkerId id = MarkerId(markerId);
    Marker marker = Marker(
        markerId: id,
        icon: iconMarker,
        position: LatLng(lat, lng),
        infoWindow: InfoWindow(title: title, snippet: content),
        draggable: false,
        zIndex: 2,
        flat: true,
        anchor: Offset(0.5, 0.5),
        rotation: _position.heading
    );

    markers[id] = marker;

  }

  void addSimpleMarker(
      String markerId,
      double lat,
      double lng,
      String title,
      String content,
      BitmapDescriptor iconMarker
      ) {

    MarkerId id = MarkerId(markerId);
    Marker marker = Marker(
        markerId: id,
        icon: iconMarker,
        position: LatLng(lat, lng),
        infoWindow: InfoWindow(title: title, snippet: content),
    );

    markers[id] = marker;
  }


}