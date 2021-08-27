import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:goappflutter/src/providers/client_provider.dart';
import 'package:goappflutter/src/providers/driver_provider.dart';
import 'package:http/http.dart' as http;
import 'package:goappflutter/src/utils/shared_pref.dart';

class PushNotificationsProvider {

  FirebaseMessaging _firebaseMessaging = new FirebaseMessaging();
  StreamController _streamController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get message => _streamController.stream;


  void initPushNotifications() async {
    _firebaseMessaging.configure(
      onMessage: (Map<String, dynamic> message) {
        print('Cuando estamos en primer plano');
        print('OnMessage: $message');
        _streamController.sink.add(message);
      },
      onLaunch: (Map<String, dynamic> message) {
        print('OnLaunch: $message');
        _streamController.sink.add(message);
        SharedPref sharedPref = new SharedPref();
        sharedPref.save('isNotification', 'true');
      },
      onResume: (Map<String, dynamic> message) {
        print('OnResume $message');
        _streamController.sink.add(message);
      }
    );

    _firebaseMessaging.requestNotificationPermissions(
      const IosNotificationSettings(
        sound: true,
        badge: true,
        alert: true,
        provisional: true
      )
    );

    _firebaseMessaging.onIosSettingsRegistered.listen((IosNotificationSettings settings) {
      print('Coonfiguraciones para Ios fueron regustradas $settings');
    });


  }

  void saveToken(String idUser, String typeUser) async {
    String token = await _firebaseMessaging.getToken();
    Map<String, dynamic> data = {
      'token': token
    };

    if (typeUser == 'client') {
      ClientProvider clientProvider = new ClientProvider();
      clientProvider.update(data, idUser);
    }
    else {
      DriverProvider driverProvider = new DriverProvider();
      driverProvider.update(data, idUser);
    }

  }

  Future<void> sendMessage(String to, Map<String, dynamic> data, String title, String body) async {
    await http.post(
      'https://fcm.googleapis.com/fcm/send',
      headers: <String, String> {
        'Content-Type': 'application/json',
        'Authorization': 'key=AAAAY-pBnHw:APA91bEq6Sqgu-VhFT9iWiocEWdQfCaWWw18YsG9bdATMazH5OCMTrNhnS5r_PxIVc866-gUiB5ICO3XGuilU51B86R66nh6o-L7yTisoMZONJwHuY4pYUgUHU9KSVsLpVTXZDBWGKM8'
      },
      body: jsonEncode(
        <String, dynamic> {
          'notification': <String, dynamic> {
            'body': body,
            'title': title,
          },
          'priority': 'high',
          'ttl': '4500s',
          'data': data,
          'to': to
        }
      )
    );
  }

  void dispose () {
    _streamController?.onCancel;
  }

}