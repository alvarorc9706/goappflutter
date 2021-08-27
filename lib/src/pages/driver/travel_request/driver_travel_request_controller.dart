import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:goappflutter/src/models/client.dart';
import 'package:goappflutter/src/models/travel_info.dart';
import 'package:goappflutter/src/providers/client_provider.dart';
import 'package:goappflutter/src/providers/geofire_provider.dart';
import 'package:goappflutter/src/utils/shared_pref.dart';
import 'package:goappflutter/src/providers/travel_info_provider.dart';
import 'package:goappflutter/src/providers/auth_provider.dart';
import 'package:goappflutter/src/utils/snackbar.dart' as utils;

class DriverTravelRequestController {

  BuildContext context;
  GlobalKey<ScaffoldState> key = new GlobalKey();
  Function refresh;
  SharedPref _sharedPref;

  String from;
  String to;
  String idClient;
  Client client;

  ClientProvider _clientProvider;
  TravelInfoProvider _travelInfoProvider;
  AuthProvider _authProvider;
  GeofireProvider _geofireProvider;
  TravelInfo travelInfo;
  StreamSubscription<DocumentSnapshot> _streamTravelController;

  Timer _timer;
  int seconds = 30;

  Future init (BuildContext context, Function refresh) {
    this.context = context;
    this.refresh = refresh;
    _sharedPref = new SharedPref();
    _sharedPref.save('isNotification', 'false');

    _clientProvider = new ClientProvider();
    _travelInfoProvider = new TravelInfoProvider();
    _authProvider = new AuthProvider();
    _geofireProvider = new GeofireProvider();

    Map<String, dynamic> arguments = ModalRoute.of(context).settings.arguments as Map<String, dynamic>;

    print('Arguments: $arguments');

    from = arguments['data']['origin'];
    to = arguments['data']['destination'];
    idClient = arguments['data']['idClient'];

    getClientInfo();
    startTimer();
  }

  void dispose () {
    _timer?.cancel();
  }

  void startTimer() {
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      seconds = seconds - 1;
      refresh();
      if (seconds == 0) {
        cancelTravel();
      }
    });
  }

  void acceptTravel() async {
    Stream<DocumentSnapshot> stream = _travelInfoProvider.getByIdStream(_authProvider.getUser().uid);
    _streamTravelController = stream.listen((DocumentSnapshot document) {
      travelInfo = TravelInfo.fromJson(document.data());

      if (travelInfo.status == 'created') {
          Map<String, dynamic> data = {
            'idDriver': _authProvider.getUser().uid,
            'status': 'accepted'
          };

          _timer?.cancel();

          _travelInfoProvider.update(data, idClient);
          _geofireProvider.delete(_authProvider.getUser().uid);
          Navigator.pushNamedAndRemoveUntil(context, 'driver/travel/map', (route) => false, arguments: idClient);
          // Navigator.pushReplacementNamed(context, 'driver/travel/map', arguments: idClient);

      }
      else{
        utils.Snackbar.showSnackbar(context, key, 'otro conductor ya acepto el viaje');
        print('El usuario se registro correctamente');
        _timer?.cancel();
        Navigator.pushNamedAndRemoveUntil(context, 'driver/map', (route) => false);
      }
        refresh();

    });
  }






  void cancelTravel() {
    Map<String, dynamic> data = {
      'status': 'no_accepted'
    };
    _timer?.cancel();
    _travelInfoProvider.update(data, idClient);
    Navigator.pushNamedAndRemoveUntil(context, 'driver/map', (route) => false);
  }



  void getClientInfo() async {
    client = await _clientProvider.getById(idClient);
    print('Client: ${client.toJson()}');
    refresh();
  }

}