String monthKey = String.valueOf(Date.today().year()) + '-' + String.valueOf(Date.today().month()).leftPad(2, '0');
String userIdText = String.valueOf(UserInfo.getUserId());
String userToken = userIdText.length() > 8 ? userIdText.substring(userIdText.length() - 8) : userIdText;
System.debug('USERID=' + userIdText);
System.debug('TOKEN=' + userToken);
System.debug('AUTOKEY=' + monthKey + '-' + userToken);
