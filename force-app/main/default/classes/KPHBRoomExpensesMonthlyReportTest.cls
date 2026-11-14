@IsTest
private class KPHBRoomExpensesMonthlyReportTest {
    private static String monthKeyForCurrentMonth() {
        Date currentMonth = Date.today().toStartOfMonth();
        String monthPart = String.valueOf(currentMonth.month()).leftPad(2, '0');
        return String.valueOf(currentMonth.year()) + '-' + monthPart;
    }

    private static String automaticReportKey(String monthKey, Id userId) {
        String userIdText = String.valueOf(userId);
        return monthKey + '-' + userIdText.substring(userIdText.length() - 8);
    }

    @TestSetup
    static void setupData() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User reportUser = new User(
            Alias = 'rpt1',
            Email = 'report.user1@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'ReportUser',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'report.user1.' + System.currentTimeMillis() + '@example.com',
            ProfileId = standardProfile.Id
        );
        insert reportUser;

        insert new Member__c(
            Name = 'Report User',
            User_Id__c = reportUser.Id,
            In_Split__c = true,
            Include_Rent__c = true,
            Include_Expenses__c = true,
            Split_Settings_Initialized__c = true
        );

        insert new Expense__c(
            Name = 'Test Expense',
            Label__c = 'Veg',
            Amount__c = 500,
            Spender_Id__c = reportUser.Id,
            Spender_Name__c = reportUser.Name
        );
    }

    @IsTest
    static void manualSendCanResendSameMonth() {
        User reportUser = [SELECT Id, Name, Email FROM User WHERE Email = 'report.user1@example.com' LIMIT 1];
        String monthKey = monthKeyForCurrentMonth();

        insert new KPHB_Monthly_Report_Log__c(
            Report_Key__c = automaticReportKey(monthKey, reportUser.Id),
            Report_Month__c = monthKey,
            Recipient_User_Id__c = String.valueOf(reportUser.Id)
        );

        Test.startTest();
        String result = KPHBRoomExpensesMonthlyReport.sendMonthlyReports(monthKey, false);
        Test.stopTest();

        System.assert(result.contains('accepted 1 personalized report email'));
        System.assert(result.contains('Acceptance is not a delivery confirmation'));
    }

    @IsTest
    static void automaticSendIsSkippedAfterFirstDelivery() {
        User reportUser = [SELECT Id, Name, Email FROM User WHERE Email = 'report.user1@example.com' LIMIT 1];
        String monthKey = monthKeyForCurrentMonth();

        insert new KPHB_Monthly_Report_Log__c(
            Report_Key__c = automaticReportKey(monthKey, reportUser.Id),
            Report_Month__c = monthKey,
            Recipient_User_Id__c = String.valueOf(reportUser.Id)
        );

        Test.startTest();
        String result = KPHBRoomExpensesMonthlyReport.sendMonthlyReports(monthKey, true);
        Test.stopTest();

        System.assert(result.contains('already sent automatically'));
    }

    @IsTest
    static void excludedExpenseMemberSpendingCreditsRentButIsNotShared() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User rentOnlyUser = new User(
            Alias = 'rentonly',
            Email = 'rent.only@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'RentOnly',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'rent.only.' + System.currentTimeMillis() + '@example.com',
            ProfileId = standardProfile.Id
        );
        insert rentOnlyUser;

        insert new Member__c(
            Name = 'Rent Only',
            User_Id__c = rentOnlyUser.Id,
            In_Split__c = true,
            Include_Rent__c = true,
            Include_Expenses__c = false,
            Split_Settings_Initialized__c = true
        );
        insert new Expense__c(
            Name = 'Excluded Expense',
            Label__c = 'Veg',
            Amount__c = 900,
            Spender_Id__c = rentOnlyUser.Id,
            Spender_Name__c = rentOnlyUser.Name
        );

        User noSpendUser = new User(
            Alias = 'nospend',
            Email = 'no.spend@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'NoSpend',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'no.spend.' + System.currentTimeMillis() + '@example.com',
            ProfileId = standardProfile.Id
        );
        insert noSpendUser;
        insert new Member__c(
            Name = 'No Spend',
            User_Id__c = noSpendUser.Id,
            In_Split__c = false,
            Include_Rent__c = false,
            Include_Expenses__c = false,
            Split_Settings_Initialized__c = true
        );

        Test.startTest();
        KPHBRoomExpensesController.DashboardData dashboard =
            KPHBRoomExpensesController.getDashboard(monthKeyForCurrentMonth());
        Test.stopTest();

        KPHBRoomExpensesController.PersonTotal rentOnlyTotal;
        for (KPHBRoomExpensesController.PersonTotal total : dashboard.personTotals) {
            if (total.userId == String.valueOf(rentOnlyUser.Id)) rentOnlyTotal = total;
        }
        System.assertNotEquals(null, rentOnlyTotal, 'Rent-only members should remain in the rent settlement.');
        System.assertEquals(900, rentOnlyTotal.spent, 'Recorded spending must be credited to the member.');
        System.assertEquals(rentOnlyTotal.rentShare - 900, rentOnlyTotal.finalToPay,
            'Recorded spending must reduce a rent-only member’s amount due.');
        System.assertEquals(1400, dashboard.totalExpense,
            'Every member’s spending counts toward the expense total, whether or not they share it.');
        System.assertEquals(1400, dashboard.fairShare * dashboard.memberCount,
            'The total is divided only among the members included in the expense split.');
        KPHBRoomExpensesController.PersonTotal noSpendTotal;
        for (KPHBRoomExpensesController.PersonTotal total : dashboard.personTotals) {
            if (total.userId == String.valueOf(noSpendUser.Id)) noSpendTotal = total;
        }
        System.assertNotEquals(null, noSpendTotal,
            'Members excluded from rent and expenses must still appear in the settlement.');
        System.assertEquals(0, noSpendTotal.rentShare, 'Excluded members have no rent share.');
        System.assertEquals(0, noSpendTotal.fairShare, 'Excluded members have no expense share.');
        System.assertEquals(0, noSpendTotal.finalToPay, 'Excluded members with no spending owe nothing.');
        Boolean noSpendMemberHasSheetColumn = false;
        for (KPHBRoomExpensesController.MemberRow member : dashboard.members) {
            if (member.userId == String.valueOf(noSpendUser.Id)) noSpendMemberHasSheetColumn = true;
        }
        System.assert(noSpendMemberHasSheetColumn,
            'Members with no expenses must still be present for a Sheet column.');
        Boolean excludedExpenseAppearsInSheet = false;
        for (KPHBRoomExpensesController.ExpenseRow expense : dashboard.selectedExpenses) {
            if (expense.spenderId == String.valueOf(rentOnlyUser.Id)) excludedExpenseAppearsInSheet = true;
        }
        System.assert(excludedExpenseAppearsInSheet,
            'The sheet must show recorded spending for members excluded from the expense split.');
    }
}