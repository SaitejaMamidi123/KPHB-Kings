String monthKey = '2026-11';
Set<String> autoKeys = new Set<String>();
autoKeys.add('2026-11-hQtGDAA0');
autoKeys.add('2026-11-hR5SfAAK');
autoKeys.add('2026-11-hR6dFAAS');
List<KPHB_Monthly_Report_Log__c> items = [
    SELECT Id, Report_Key__c, Recipient_User_Id__c
    FROM KPHB_Monthly_Report_Log__c
    WHERE Report_Month__c = :monthKey
    AND Report_Key__c IN :autoKeys
];
System.debug('MATCH_COUNT=' + items.size());
for (KPHB_Monthly_Report_Log__c item : items) {
    System.debug(item.Report_Key__c + ' -> ' + item.Recipient_User_Id__c);
}
