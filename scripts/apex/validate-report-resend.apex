String monthKey = String.valueOf(Date.today().year()) + '-' + String.valueOf(Date.today().month()).leftPad(2, '0');
Id currentUserId = UserInfo.getUserId();
String currentUserIdText = String.valueOf(currentUserId);
String userToken = currentUserIdText.length() > 8 ? currentUserIdText.substring(currentUserIdText.length() - 8) : currentUserIdText;
String autoKey = monthKey + '-' + userToken;

delete [
    SELECT Id
    FROM KPHB_Monthly_Report_Log__c
    WHERE Report_Month__c = :monthKey
    AND Recipient_User_Id__c = :currentUserIdText
];

insert new KPHB_Monthly_Report_Log__c(
    Report_Key__c = autoKey,
    Report_Month__c = monthKey,
    Recipient_User_Id__c = currentUserIdText
);

String manualResult = KPHBRoomExpensesMonthlyReport.sendMonthlyReports(monthKey, false);
String autoResult = KPHBRoomExpensesMonthlyReport.sendMonthlyReports(monthKey, true);
System.debug('MANUAL_RESULT=' + manualResult);
System.debug('AUTO_RESULT=' + autoResult);
