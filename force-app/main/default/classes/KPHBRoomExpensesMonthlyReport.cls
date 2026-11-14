public without sharing class KPHBRoomExpensesMonthlyReport {
    private static final List<String> LABELS = new List<String>{'Veg', 'Shop', 'Utilities', 'Meat', 'Others'};
    private static final List<String> COLORS = new List<String>{'#18a999', '#6d5ce8', '#f4a340', '#e66b76', '#3b82c4'};

    private class RecipientData {
        User recipient;
        Member__c member;
        Map<String, Decimal> personalTotals = new Map<String, Decimal>();
        Decimal spent = 0;

        RecipientData(User recipient, Member__c member) {
            this.recipient = recipient;
            this.member = member;
            for (String label : LABELS) personalTotals.put(label, 0);
        }
    }

    private class SettlementRow {
        String userId;
        String name;
        Decimal rentShare = 0;
        Decimal expenseShare = 0;
        Decimal spent = 0;
        Decimal finalAmount = 0;
    }

    public static String sendPreviousMonthReports() {
        Date previousMonth = Date.today().toStartOfMonth().addMonths(-1);
        return sendMonthlyReports(monthKeyForDate(previousMonth), true);
    }

    public static String sendMonthlyReports(String monthKey) {
        return sendMonthlyReports(monthKey, false);
    }

    public static String sendMonthlyReports(String monthKey, Boolean isAutomatic) {
        if (String.isBlank(monthKey) || !Pattern.matches('^[0-9]{4}-[0-9]{2}$', monthKey)) {
            throw new AuraHandledException('Choose a valid report month.');
        }
        Date reportMonth;
        try {
            reportMonth = Date.valueOf(monthKey + '-01');
        } catch (Exception ex) {
            throw new AuraHandledException('Choose a valid report month.');
        }
        Date currentMonth = Date.today().toStartOfMonth();
        if (reportMonth > currentMonth) {
            throw new AuraHandledException('Reports can only be sent for the current or a completed month.');
        }
        Date nextMonth = reportMonth.addMonths(1);
        Datetime startDate = Datetime.newInstance(reportMonth, Time.newInstance(0, 0, 0, 0));
        Datetime endDate = Datetime.newInstance(nextMonth, Time.newInstance(0, 0, 0, 0));

        KPHB_Config__c config = KPHB_Config__c.getOrgDefaults();
        Set<Id> alreadySent = new Set<Id>();

        List<Member__c> members = [
            SELECT Name, User_Id__c, Include_Rent__c, Include_Expenses__c
            FROM Member__c
            ORDER BY Name
        ];
        Set<Id> memberUserIds = new Set<Id>();
        Map<Id, Member__c> memberByUserId = new Map<Id, Member__c>();
        for (Member__c member : members) {
            if (String.isBlank(member.User_Id__c)) continue;
            try {
                Id userId = (Id)member.User_Id__c;
                memberUserIds.add(userId);
                memberByUserId.put(userId, member);
            } catch (Exception ignored) {
                // User_Id__c is historical text data; only valid Salesforce User IDs can receive reports.
            }
        }
        if (memberUserIds.isEmpty()) return 'No linked roommate users were found for ' + monthLabel(reportMonth) + '.';

        Set<String> memberUserIdStrings = new Set<String>();
        for (Id userId : memberUserIds) memberUserIdStrings.add(String.valueOf(userId));
        if (isAutomatic) {
            Set<String> autoReportKeys = new Set<String>();
            for (Id userId : memberUserIds) autoReportKeys.add(buildReportKey(monthKey, userId, true));
            for (KPHB_Monthly_Report_Log__c reportLog : [
                SELECT Report_Key__c, Recipient_User_Id__c
                FROM KPHB_Monthly_Report_Log__c
                WHERE Report_Month__c = :monthKey
                AND Report_Key__c IN :autoReportKeys
            ]) {
                try {
                    alreadySent.add((Id)reportLog.Recipient_User_Id__c);
                } catch (Exception ignored) {
                    // Ignore invalid historical user IDs in report log rows.
                }
            }
        }

        Map<Id, RecipientData> recipients = new Map<Id, RecipientData>();
        for (User userRecord : [SELECT Id, Name, Email FROM User WHERE Id IN :memberUserIds]) {
            if (String.isBlank(userRecord.Email) || (isAutomatic && alreadySent.contains(userRecord.Id))) continue;
            recipients.put(userRecord.Id, new RecipientData(userRecord, memberByUserId.get(userRecord.Id)));
        }
        if (recipients.isEmpty()) {
            return isAutomatic && alreadySent.size() > 0
                ? 'Reports for ' + monthLabel(reportMonth) + ' were already sent automatically to all linked members.'
                : 'No linked member has an email address. Add email addresses to their Salesforce User records first.';
        }
        Map<String, Integer> emailAddressCounts = new Map<String, Integer>();
        for (User userRecord : [SELECT Id, Email FROM User WHERE Id IN :recipients.keySet()]) {
            String normalizedEmail = userRecord.Email == null ? '' : userRecord.Email.trim().toLowerCase();
            if (String.isBlank(normalizedEmail)) continue;
            emailAddressCounts.put(normalizedEmail, emailAddressCounts.containsKey(normalizedEmail)
                ? emailAddressCounts.get(normalizedEmail) + 1
                : 1);
        }
        Integer duplicateEmailAddressCount = 0;
        for (Integer addressCount : emailAddressCounts.values()) {
            if (addressCount > 1) duplicateEmailAddressCount++;
        }

        List<Member__c> expenseMembers = new List<Member__c>();
        Set<String> expenseUserIds = new Set<String>();
        Set<String> allMemberUserIds = new Set<String>();
        for (Member__c member : members) {
            if (!String.isBlank(member.User_Id__c)) allMemberUserIds.add(member.User_Id__c);
            if (member.Include_Expenses__c && !String.isBlank(member.User_Id__c)) {
                expenseMembers.add(member);
                expenseUserIds.add(member.User_Id__c);
            }
        }

        Map<String, Decimal> groupLabelTotals = new Map<String, Decimal>();
        Map<String, Decimal> spentByMember = new Map<String, Decimal>();
        for (String label : LABELS) groupLabelTotals.put(label, 0);
        for (String userId : allMemberUserIds) spentByMember.put(userId, 0);
        List<Expense__c> monthExpenses = new List<Expense__c>();
        if (!allMemberUserIds.isEmpty()) {
            monthExpenses = [
                SELECT Name, Label__c, Amount__c, Spender_Id__c, Spender_Name__c, CreatedDate
                FROM Expense__c
                WHERE Spender_Id__c IN :allMemberUserIds AND CreatedDate >= :startDate AND CreatedDate < :endDate
                ORDER BY CreatedDate ASC
            ];
        }
        for (Expense__c expense : monthExpenses) {
            Decimal amount = expense.Amount__c == null ? 0 : expense.Amount__c;
            if (spentByMember.containsKey(expense.Spender_Id__c)) {
                spentByMember.put(expense.Spender_Id__c, spentByMember.get(expense.Spender_Id__c) + amount);
            }
            try {
                Id spenderId = (Id)expense.Spender_Id__c;
                if (recipients.containsKey(spenderId) && recipients.get(spenderId).personalTotals.containsKey(expense.Label__c)) {
                    RecipientData recipient = recipients.get(spenderId);
                    recipient.personalTotals.put(expense.Label__c, recipient.personalTotals.get(expense.Label__c) + amount);
                    recipient.spent += amount;
                }
            } catch (Exception ignored) {
                // Expenses with no valid User ID are excluded from personalized summaries.
            }
            if (groupLabelTotals.containsKey(expense.Label__c)) {
                groupLabelTotals.put(expense.Label__c, groupLabelTotals.get(expense.Label__c) + amount);
            }
        }

        Decimal groupExpenseTotal = 0;
        for (Decimal amount : groupLabelTotals.values()) groupExpenseTotal += amount;
        Decimal expenseShare = expenseMembers.isEmpty() ? 0 : (groupExpenseTotal / expenseMembers.size()).setScale(2);
        Decimal rentAmount = config == null || config.Rent_Amount__c == null ? 23200 : config.Rent_Amount__c;
        Integer rentMemberCount = 0;
        for (Member__c member : members) if (member.Include_Rent__c) rentMemberCount++;
        Decimal rentShare = rentMemberCount == 0 ? 0 : (rentAmount / rentMemberCount).setScale(2);

        List<SettlementRow> settlements = new List<SettlementRow>();
        for (Member__c member : members) {
            SettlementRow row = new SettlementRow();
            row.userId = member.User_Id__c;
            row.name = member.Name;
            row.rentShare = member.Include_Rent__c ? rentShare : 0;
            row.expenseShare = member.Include_Expenses__c ? expenseShare : 0;
            row.spent = spentByMember.containsKey(member.User_Id__c)
                ? spentByMember.get(member.User_Id__c)
                : 0;
            row.finalAmount = row.rentShare + row.expenseShare - row.spent;
            settlements.add(row);
        }

        List<Messaging.SingleEmailMessage> pendingEmails = new List<Messaging.SingleEmailMessage>();
        List<Id> pendingRecipientIds = new List<Id>();
        for (Id userId : recipients.keySet()) {
            RecipientData recipient = recipients.get(userId);
            Member__c recipientMember = memberByUserId.get(userId);
            Decimal personalSpent = spentByMember.containsKey(String.valueOf(userId))
                ? spentByMember.get(String.valueOf(userId))
                : 0;
            Decimal personalRentShare = recipientMember != null && recipientMember.Include_Rent__c ? rentShare : 0;
            Decimal personalExpenseShare = recipientMember != null && recipientMember.Include_Expenses__c ? expenseShare : 0;
            Decimal personalFinalAmount = personalRentShare + personalExpenseShare - personalSpent;
            Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
            attachment.setFileName('KPHB-Kings-' + monthKey + '-Monthly-Report.xls');
            attachment.setContentType('application/vnd.ms-excel;charset=UTF-8');
            attachment.setBody(Blob.valueOf(buildWorkbookHtml(
                recipient, monthLabel(reportMonth), monthKey, groupLabelTotals,
                groupExpenseTotal, expenseShare, rentAmount, rentShare, rentMemberCount,
                expenseMembers, members, monthExpenses, spentByMember, settlements,
                personalSpent, personalFinalAmount
            )));

            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setTargetObjectId(userId);
            email.setSaveAsActivity(false);
            email.setSubject('KPHB Kings | ' + monthLabel(reportMonth) + ' Monthly Expense & Rent Report for ' + recipient.recipient.Name);
            String finalLabel = personalFinalAmount < 0 ? 'Amount to receive' : 'Amount to pay';
            Decimal finalAbsoluteAmount = personalFinalAmount < 0 ? personalFinalAmount * -1 : personalFinalAmount;
            email.setPlainTextBody(
                'Hello ' + recipient.recipient.Name + ',\n\n' +
                'Your KPHB Kings monthly report for ' + monthLabel(reportMonth) + ' is attached.\n\n' +
                'YOUR SETTLEMENT\nTotal you spent: ' + money(personalSpent) + '\n' +
                finalLabel + ': ' + money(finalAbsoluteAmount) + '\n\n' +
                'The attachment includes your spending chart, the full group settlement, and the expense sheet.\n\n' +
                'Thank you,\nKPHB Kings'
            );
            String finalColor = personalFinalAmount < 0 ? '#12836c' : '#c0392b';
            email.setHtmlBody(
                '<p>Hello ' + escape(recipient.recipient.Name) + ',</p>' +
                '<p>Your KPHB Kings monthly report for <strong>' + escape(monthLabel(reportMonth)) + '</strong> is attached.</p>' +
                '<table style="border-collapse:collapse;width:100%;max-width:560px;margin:16px 0;background:#f3f8f6">' +
                '<tr><th colspan="2" style="padding:12px;text-align:left;background:#145e55;color:#fff">Your settlement</th></tr>' +
                '<tr><td style="padding:12px;border:1px solid #dce5e2">Total you spent</td>' +
                '<td style="padding:12px;border:1px solid #dce5e2;text-align:right;font-size:18px;font-weight:bold">' + money(personalSpent) + '</td></tr>' +
                '<tr><td style="padding:12px;border:1px solid #dce5e2;font-weight:bold">' + finalLabel + '</td>' +
                '<td style="padding:12px;border:1px solid #dce5e2;text-align:right;font-size:22px;font-weight:bold;color:' + finalColor + '">' + money(finalAbsoluteAmount) + '</td></tr></table>' +
                '<p>The attachment includes your spending chart, the full group settlement, and the expense sheet.</p>' +
                '<p>Thank you,<br/>KPHB Kings</p>'
            );
            email.setFileAttachments(new List<Messaging.EmailFileAttachment>{attachment});
            pendingEmails.add(email);
            pendingRecipientIds.add(userId);
        }

        Integer sentCount = 0;
        Integer failedCount = 0;
        Integer logFailureCount = 0;
        String firstFailureMessage;
        List<KPHB_Monthly_Report_Log__c> successfulLogs = new List<KPHB_Monthly_Report_Log__c>();
        for (Integer startIndex = 0; startIndex < pendingEmails.size(); startIndex += 10) {
            Integer endIndex = Math.min(startIndex + 10, pendingEmails.size());
            List<Messaging.SingleEmailMessage> batch = new List<Messaging.SingleEmailMessage>();
            for (Integer index = startIndex; index < endIndex; index++) batch.add(pendingEmails[index]);
            Messaging.SendEmailResult[] results = Messaging.sendEmail(batch, false);
            for (Integer offset = 0; offset < results.size(); offset++) {
                if (results[offset].isSuccess()) {
                    Id sentUserId = pendingRecipientIds[startIndex + offset];
                    String reportKey = buildReportKey(monthKey, sentUserId, isAutomatic);
                    successfulLogs.add(new KPHB_Monthly_Report_Log__c(
                        Report_Key__c = reportKey,
                        Report_Month__c = monthKey,
                        Recipient_User_Id__c = String.valueOf(sentUserId)
                    ));
                    sentCount++;
                } else {
                    failedCount++;
                    for (Messaging.SendEmailError error : results[offset].getErrors()) {
                        System.debug(LoggingLevel.ERROR, 'Monthly report email failed: ' + error.getMessage());
                        if (String.isBlank(firstFailureMessage)) firstFailureMessage = error.getMessage();
                    }
                }
            }
        }

        if (!successfulLogs.isEmpty()) {
            Database.SaveResult[] logResults = Database.insert(successfulLogs, false);
            for (Database.SaveResult logResult : logResults) {
                if (!logResult.isSuccess()) {
                    logFailureCount++;
                    for (Database.Error error : logResult.getErrors()) {
                        System.debug(LoggingLevel.ERROR, 'Monthly report delivery log failed: ' + error.getMessage());
                    }
                }
            }
        }
        String resultMessage = sentCount == 0
            ? 'Salesforce did not accept any report emails for ' + monthLabel(reportMonth) + '.'
            : 'Salesforce accepted ' + sentCount + ' personalized report email' + (sentCount == 1 ? '' : 's') + ' for delivery for ' + monthLabel(reportMonth) + '.';
        if (failedCount > 0) {
            resultMessage += ' ' + failedCount + ' email' + (failedCount == 1 ? '' : 's') + ' could not be queued.';
            if (!String.isBlank(firstFailureMessage)) resultMessage += ' First error: ' + firstFailureMessage;
        }
        if (logFailureCount > 0) resultMessage += ' Warning: ' + logFailureCount + ' accepted email(s) could not be recorded in the report log.';
        if (duplicateEmailAddressCount > 0) {
            resultMessage += ' Warning: multiple linked member records share an email address; their separate personalized reports go to the same mailbox. Update their Salesforce User email addresses if each member should receive their own copy.';
        }
        resultMessage += ' Acceptance is not a delivery confirmation; check the recipient mailbox spam folder and Salesforce Email Log Files if it does not arrive.';
        return resultMessage;
    }

    private static String buildWorkbookHtml(
        RecipientData recipient, String reportMonth, String monthKey,
        Map<String, Decimal> groupLabelTotals, Decimal groupExpenseTotal,
        Decimal expenseShare, Decimal rentAmount, Decimal rentShare, Integer rentMemberCount,
        List<Member__c> expenseMembers, List<Member__c> sheetMembers, List<Expense__c> monthExpenses,
        Map<String, Decimal> spentByMember, List<SettlementRow> settlements,
        Decimal personalSpent, Decimal personalFinalAmount
    ) {
        String html = '<html><head><meta charset="UTF-8"/><style>body{font-family:Arial,sans-serif;color:#243247}h1{color:#145e55}h2{color:#176f65;margin-top:24px}table{border-collapse:collapse;width:100%;margin-bottom:18px}th{background:#e8f4f1;color:#20364a;text-align:left}th,td{border:1px solid #dce5e2;padding:7px}.num{text-align:right}.muted{color:#687587}.total{background:#e8f4f1;font-weight:bold}.bar{height:16px}</style></head><body>';
        html += '<h1>KPHB Kings — ' + escape(reportMonth) + ' Monthly Report</h1>';
        html += '<p>Hello ' + escape(recipient.recipient.Name) + ', here is your personal spending overview and the full group report.</p>';
        String personalFinalLabel = personalFinalAmount < 0 ? 'Amount to receive' : 'Amount to pay';
        String personalFinalColor = personalFinalAmount < 0 ? '#12836c' : '#c0392b';
        Decimal personalFinalAbsolute = personalFinalAmount < 0 ? personalFinalAmount * -1 : personalFinalAmount;
        html += '<h2>Your settlement</h2><table style="max-width:620px;background:#f3f8f6"><tr><th>Total you spent</th><th>' + personalFinalLabel + '</th></tr>' +
            '<tr><td style="font-size:22px;font-weight:bold">' + money(personalSpent) + '</td>' +
            '<td style="font-size:26px;font-weight:bold;color:' + personalFinalColor + '">' + money(personalFinalAbsolute) + '</td></tr></table>';
        html += '<h2>My spending chart</h2><table><tr><th>Label</th><th class="num">Spent</th><th>Chart</th></tr>';
        for (Integer index = 0; index < LABELS.size(); index++) {
            String label = LABELS[index];
            Decimal amount = recipient.personalTotals.get(label);
            Decimal percent = recipient.spent == 0 ? 0 : (amount * 100 / recipient.spent).setScale(0);
            Integer barWidth = Integer.valueOf(String.valueOf(percent));
            html += '<tr><td>' + escape(label) + '</td><td class="num">' + money(amount) + '</td><td><table style="width:100%;margin:0"><tr><td class="bar" bgcolor="' + COLORS[index] + '" width="' + barWidth + '%"></td><td style="border:0"></td></tr></table></td></tr>';
        }
        html += '<tr class="total"><td>Total spent</td><td class="num">' + money(recipient.spent) + '</td><td></td></tr></table>';
        html += '<h2>Everyone — group spending chart</h2><table><tr><th>Label</th><th class="num">Group spent</th><th>Chart</th></tr>';
        for (Integer index = 0; index < LABELS.size(); index++) {
            String label = LABELS[index];
            Decimal amount = groupLabelTotals.get(label);
            Decimal percent = groupExpenseTotal == 0 ? 0 : (amount * 100 / groupExpenseTotal).setScale(0);
            Integer barWidth = Integer.valueOf(String.valueOf(percent));
            html += '<tr><td>' + escape(label) + '</td><td class="num">' + money(amount) + '</td><td><table style="width:100%;margin:0"><tr><td class="bar" bgcolor="' + COLORS[index] + '" width="' + barWidth + '%"></td><td style="border:0"></td></tr></table></td></tr>';
        }
        html += '<tr class="total"><td>Total expenses shared</td><td class="num">' + money(groupExpenseTotal) + '</td><td></td></tr></table>';
        html += '<h2>Everyone — monthly summary</h2><p class="muted">Expense split: ' + expenseMembers.size() + ' roommates · Expense share each: ' + money(expenseShare) + '<br/>Monthly rent: ' + money(rentAmount) + ' · Rent split: ' + rentMemberCount + ' roommates · Rent share each: ' + money(rentShare) + '</p>';
        html += '<table><tr><th>Roommate</th><th class="num">Rent share</th><th class="num">Expense share</th><th class="num">You spent</th><th class="num">Final amount</th></tr>';
        for (SettlementRow row : settlements) {
            String ownRowStyle = row.userId == String.valueOf(recipient.recipient.Id) ? ' style="background:#fff7d6;font-weight:bold"' : '';
            String rowColor = row.finalAmount < 0 ? '#12836c' : '#c0392b';
            html += '<tr' + ownRowStyle + '><td>' + escape(row.name) + '</td><td class="num">' + money(row.rentShare) + '</td><td class="num">' + money(row.expenseShare) + '</td><td class="num">' + money(row.spent) + '</td><td class="num total" style="color:' + rowColor + '">' + money(row.finalAmount) + '</td></tr>';
        }
        html += '</table><h2>Everyone — expense sheet</h2><table><tr>';
        for (Member__c member : sheetMembers) html += '<th>' + escape(member.Name) + '</th>';
        html += '</tr>';
        Map<String, List<Expense__c>> expensesByMember = new Map<String, List<Expense__c>>();
        Integer maxRows = 0;
        for (Member__c member : sheetMembers) expensesByMember.put(member.User_Id__c, new List<Expense__c>());
        for (Expense__c expense : monthExpenses) {
            if (!expensesByMember.containsKey(expense.Spender_Id__c)) continue;
            expensesByMember.get(expense.Spender_Id__c).add(expense);
            maxRows = Math.max(maxRows, expensesByMember.get(expense.Spender_Id__c).size());
        }
        for (Integer rowIndex = 0; rowIndex < maxRows; rowIndex++) {
            html += '<tr>';
            for (Member__c member : sheetMembers) {
                List<Expense__c> memberExpenses = expensesByMember.get(member.User_Id__c);
                if (rowIndex < memberExpenses.size()) {
                    Expense__c expense = memberExpenses[rowIndex];
                    html += '<td>' + escape(expense.Name) + ' (' + escape(expense.Label__c) + ') — ' + money(expense.Amount__c) + '</td>';
                } else {
                    html += '<td></td>';
                }
            }
            html += '</tr>';
        }
        html += '<tr class="total">';
        for (Member__c member : sheetMembers) html += '<td>Total: ' + money(spentByMember.get(member.User_Id__c)) + '</td>';
        html += '</tr></table><p class="muted">This sheet shows recorded spending for every roommate; expense participation only affects the shared split. Generated by KPHB Kings for ' + escape(monthKey) + '.</p></body></html>';
        return html;
    }

    private static String buildReportKey(String monthKey, Id userId, Boolean isAutomatic) {
        String userIdText = String.valueOf(userId);
        String userToken = userIdText.length() > 8 ? userIdText.substring(userIdText.length() - 8) : userIdText;
        if (isAutomatic) {
            return monthKey + '-' + userToken;
        }
        String timestampToken = String.valueOf(System.now().getTime());
        return monthKey + '-' + userToken + '-' + timestampToken.substring(Math.max(0, timestampToken.length() - 8));
    }

    private static String monthKeyForDate(Date value) {
        String monthPart = value.month() < 10 ? '0' + String.valueOf(value.month()) : String.valueOf(value.month());
        return String.valueOf(value.year()) + '-' + monthPart;
    }

    private static String monthLabel(Date value) {
        return Datetime.newInstance(value, Time.newInstance(0, 0, 0, 0)).format('MMMM yyyy');
    }

    private static String money(Decimal amount) {
        return '₹' + String.valueOf((amount == null ? 0 : amount).setScale(2));
    }

    private static String escape(String value) {
        return String.isBlank(value) ? '' : value.escapeHtml4();
    }

}