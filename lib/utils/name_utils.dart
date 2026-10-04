part of '../main.dart';

String makeAddress(String name, String honorific) {
  if (honorific.isEmpty) {
    return name;
  }
  return honorific == '이름+님' ? '$name님' : honorific;
}

