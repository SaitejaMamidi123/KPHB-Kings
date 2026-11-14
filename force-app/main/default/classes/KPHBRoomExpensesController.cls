public without sharing class KPHBRoomExpensesController {
    private static final Decimal DEFAULT_RENT = 23200;
    private static final List<String> LABELS = new List<String>{'Veg', 'Shop', 'Utilities', 'Meat', 'Others'};

    public class DashboardData {
        @AuraEnabled public Boolean isAdmin { get; set; }
        @AuraEnabled public Boolean currentMemberInSplit { get; set; }
        @AuraEnabled public Decimal rentAmount { get; set; }
        @AuraEnabled public String payeeUpiId { get; set; }
        @AuraEnabled public Decimal totalExpense { get; set; }
        @AuraEnabled public Decimal fairShare { get; set; }
        @AuraEnabled public Decimal rentShare { get; set; }
        @AuraEnabled public Integer memberCount { get; set; }
        @AuraEnabled public Integer rentMemberCount { get; set; }
        @AuraEnabled public String selectedMonthKey { get; set; }
        @AuraEnabled public List<MonthOption> monthOptions { get; set; }
        @AuraEnabled public List<ExpenseRow> myExpenses { get; set; }
        @AuraEnabled public List<ExpenseRow> adminExpenses { get; set; }
        @AuraEnabled public List<ExpenseRow> selectedExpenses { get; set; }
        @AuraEnabled public List<LabelTotal> myLabelTotals { get; set; }
        @AuraEnabled public List<LabelTotal> labelTotals { get; set; }
        @AuraEnabled public List<PersonTotal> personTotals { get; set; }
        @AuraEnabled public List<MemberRow> members { get; set; }
    }

    public class ExpenseRow {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public Decimal amount { get; set; }
        @AuraEnabled public String spenderId { get; set; }
        @AuraEnabled public String spenderName { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
        @AuraEnabled public Boolean canEdit { get; set; }
    }

    public class LabelTotal {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public Decimal amount { get; set; }
    }

    public class PersonTotal {
        @AuraEnabled public String userId { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public Decimal spent { get; set; }
        @AuraEnabled public Decimal fairShare { get; set; }
        @AuraEnabled public Decimal expenseBalance { get; set; }
        @AuraEnabled public Decimal getsBack { get; set; }
        @AuraEnabled public Decimal paysExpenses { get; set; }
        @AuraEnabled public Decimal rentShare { get; set; }
        @AuraEnabled public Decimal finalToPay { get; set; }
    }

    public class MemberRow {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String userId { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public Boolean inSplit { get; set; }
        @AuraEnabled public Boolean includeRent { get; set; }
        @AuraEnabled public Boolean includeExpenses { get; set; }
    }

    public class MemberUpdate {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public Boolean inSplit { get; set; }
        @AuraEnabled public Boolean includeRent { get; set; }
        @AuraEnabled public Boolean includeExpenses { get; set; }
    }

    public class MonthOption {
        @AuraEnabled public String value { get; set; }
        @AuraEnabled public String label { get; set; }
    }

    @AuraEnabled
    public static DashboardData getDashboard(String monthKey) {
        String currentUserId = UserInfo.getUserId();
        ensureCurrentMember();
        migrateSplitSettings();
        Date currentMonth = Date.newInstance(Date.today().year(), Date.today().month(), 1);
        Date selectedMonth = String.isBlank(monthKey) ? currentMonth : parseMonthKey(monthKey);
        Date nextMonth = selectedMonth.addMonths(1);
        Datetime monthStart = Datetime.newInstance(selectedMonth, Time.newInstance(0, 0, 0, 0));
        Datetime monthEnd = Datetime.newInstance(nextMonth, Time.newInstance(0, 0, 0, 0));

        DashboardData result = new DashboardData();
        result.isAdmin = FeatureManagement.checkPermission('KPHB_Admin');
        result.myExpenses = new List<ExpenseRow>();
        result.adminExpenses = new List<ExpenseRow>();
        result.selectedExpenses = new List<ExpenseRow>();
        result.myLabelTotals = new List<LabelTotal>();
        result.labelTotals = new List<LabelTotal>();
        result.personTotals = new List<PersonTotal>();
        result.members = new List<MemberRow>();
        result.selectedMonthKey = monthKeyForDate(selectedMonth);
        result.monthOptions = buildMonthOptions(currentMonth);

        Map<String, Decimal> myByLabel = new Map<String, Decimal>();
        Map<String, Decimal> allByLabel = new Map<String, Decimal>();
        Map<String, Decimal> spentByMember = new Map<String, Decimal>();
        Map<String, Member__c> expenseSplitById = new Map<String, Member__c>();
        Map<String, Member__c> rentSplitById = new Map<String, Member__c>();
        Set<String> allMemberIds = new Set<String>();
        List<Member__c> allMembers = [
            SELECT Id, Name, User_Id__c, In_Split__c, Include_Rent__c, Include_Expenses__c
            FROM Member__c
            ORDER BY Name
        ];
        for (Member__c member : allMembers) {
            if (!String.isBlank(member.User_Id__c)) {
                allMemberIds.add(member.User_Id__c);
                spentByMember.put(member.User_Id__c, 0);
            }
            if (member.Include_Expenses__c) expenseSplitById.put(member.User_Id__c, member);
            if (member.Include_Rent__c) rentSplitById.put(member.User_Id__c, member);
            MemberRow memberRow = new MemberRow();
            memberRow.id = member.Id;
            memberRow.userId = member.User_Id__c;
            memberRow.name = member.Name;
            memberRow.inSplit = member.In_Split__c;
            memberRow.includeRent = member.Include_Rent__c;
            memberRow.includeExpenses = member.Include_Expenses__c;
            result.members.add(memberRow);
        }
        result.currentMemberInSplit = expenseSplitById.containsKey(currentUserId);
        result.memberCount = expenseSplitById.size();
        result.rentMemberCount = rentSplitById.size();
        result.rentAmount = getRentAmount();
        result.payeeUpiId = getPayeeUpiId();
        result.fairShare = 0;
        result.rentShare = 0;
        for (String label : LABELS) {
            myByLabel.put(label, 0);
            allByLabel.put(label, 0);
        }
        List<Expense__c> currentExpenses = [
            SELECT Id, Name, Label__c, Amount__c, Spender_Id__c, Spender_Name__c, CreatedDate
            FROM Expense__c
            WHERE Spender_Id__c = :currentUserId AND CreatedDate >= :monthStart AND CreatedDate < :monthEnd
            ORDER BY CreatedDate DESC
        ];
        for (Expense__c expense : currentExpenses) {
            ExpenseRow row = toExpenseRow(expense);
            result.myExpenses.add(row);
            if (myByLabel.containsKey(expense.Label__c)) {
                myByLabel.put(expense.Label__c, myByLabel.get(expense.Label__c) + expense.Amount__c);
            }
        }

        if (result.isAdmin) {
            for (Expense__c expense : [
                SELECT Id, Name, Label__c, Amount__c, Spender_Id__c, Spender_Name__c, CreatedDate
                FROM Expense__c
                WHERE CreatedDate >= :monthStart AND CreatedDate < :monthEnd
                ORDER BY CreatedDate DESC
            ]) {
                result.adminExpenses.add(toExpenseRow(expense));
            }
        }

        Decimal total = 0;
        Decimal settlementExpenseTotal = 0;
        if (!allMemberIds.isEmpty()) {
            for (Expense__c expense : [
                SELECT Id, Name, Label__c, Amount__c, Spender_Id__c, Spender_Name__c, CreatedDate
                FROM Expense__c
                WHERE Spender_Id__c IN :allMemberIds AND CreatedDate >= :monthStart AND CreatedDate < :monthEnd
                ORDER BY CreatedDate ASC
            ]) {
                Decimal amount = expense.Amount__c == null ? 0 : expense.Amount__c;
                if (spentByMember.containsKey(expense.Spender_Id__c)) {
                    spentByMember.put(expense.Spender_Id__c, spentByMember.get(expense.Spender_Id__c) + amount);
                }
                result.selectedExpenses.add(toExpenseRow(expense));
                total += amount;
                settlementExpenseTotal += amount;
                if (allByLabel.containsKey(expense.Label__c)) {
                    allByLabel.put(expense.Label__c, allByLabel.get(expense.Label__c) + amount);
                }
            }
        }

        result.totalExpense = total;
        if (result.memberCount > 0) {
            result.fairShare = (total / result.memberCount).setScale(2);
        }
        Decimal settlementExpenseShare = result.memberCount > 0
            ? (settlementExpenseTotal / result.memberCount).setScale(2)
            : 0;
        if (!rentSplitById.isEmpty()) {
            result.rentShare = (result.rentAmount / rentSplitById.size()).setScale(2);
        }
        for (String label : LABELS) {
            LabelTotal mine = new LabelTotal();
            mine.label = label;
            mine.amount = myByLabel.get(label);
            result.myLabelTotals.add(mine);

            LabelTotal everyone = new LabelTotal();
            everyone.label = label;
            everyone.amount = allByLabel.get(label);
            result.labelTotals.add(everyone);
        }
        for (Member__c member : allMembers) {
            String memberId = member.User_Id__c;
            Decimal spent = spentByMember.containsKey(memberId)
                ? spentByMember.get(memberId)
                : 0;
            Decimal fairShare = member.Include_Expenses__c ? settlementExpenseShare : 0;
            Decimal rentShare = member.Include_Rent__c && !rentSplitById.isEmpty()
                ? result.rentShare
                : 0;
            Decimal net = member.Include_Expenses__c ? spent - fairShare : 0;
            PersonTotal person = new PersonTotal();
            person.userId = memberId;
            person.name = member.Name;
            person.spent = spent;
            person.fairShare = fairShare;
            person.expenseBalance = member.Include_Expenses__c ? -net : 0;
            person.getsBack = net > 0 ? net : 0;
            person.paysExpenses = net < 0 ? -net : 0;
            person.rentShare = rentShare;
            // Settlement uses actual included expenses and credits all recorded member spending.
            person.finalToPay = rentShare + fairShare - spent;
            result.personTotals.add(person);
        }
        return result;
    }

    @AuraEnabled
    public static void addExpense(String label, String expenseName, Decimal amount) {
        validateExpenseValues(label, expenseName, amount);
        ensureCurrentMember();
        Expense__c expense = new Expense__c(
            Name = expenseName.trim(),
            Label__c = label,
            Amount__c = amount,
            Spender_Id__c = UserInfo.getUserId(),
            Spender_Name__c = UserInfo.getName()
        );
        insert expense;
    }

    @AuraEnabled
    public static void updateExpense(Id expenseId, String label, String expenseName, Decimal amount) {
        validateExpenseValues(label, expenseName, amount);
        Expense__c expense = getExpenseForManagement(expenseId);
        expense.Name = expenseName.trim();
        expense.Label__c = label;
        expense.Amount__c = amount;
        update expense;
    }

    @AuraEnabled
    public static void deleteExpense(Id expenseId) {
        Expense__c expense = getExpenseForManagement(expenseId);
        delete expense;
    }

    @AuraEnabled
    public static String sendMonthlyReport(String monthKey) {
        requireAdmin();
        return KPHBRoomExpensesMonthlyReport.sendMonthlyReports(monthKey, false);
    }

    @AuraEnabled(cacheable=true)
    public static List<ExpenseRow> getAdminExpenses(String monthKey) {
        requireAdmin();
        Date selectedMonth = String.isBlank(monthKey)
            ? Date.newInstance(Date.today().year(), Date.today().month(), 1)
            : parseMonthKey(monthKey);
        Date nextMonth = selectedMonth.addMonths(1);
        Datetime monthStart = Datetime.newInstance(selectedMonth, Time.newInstance(0, 0, 0, 0));
        Datetime monthEnd = Datetime.newInstance(nextMonth, Time.newInstance(0, 0, 0, 0));
        List<ExpenseRow> rows = new List<ExpenseRow>();
        for (Expense__c expense : [
            SELECT Id, Name, Label__c, Amount__c, Spender_Id__c, Spender_Name__c, CreatedDate
            FROM Expense__c
            WHERE CreatedDate >= :monthStart AND CreatedDate < :monthEnd
            ORDER BY CreatedDate DESC
        ]) {
            rows.add(toExpenseRow(expense));
        }
        return rows;
    }

    private static void validateExpenseValues(String label, String expenseName, Decimal amount) {
        if (String.isBlank(expenseName) || amount == null || amount <= 0) {
            throw new AuraHandledException('Enter an expense name and an amount greater than zero.');
        }
        if (expenseName.trim().length() > 80) {
            throw new AuraHandledException('Expense names must be 80 characters or fewer.');
        }
        if (!LABELS.contains(label)) {
            throw new AuraHandledException('Choose a valid expense label.');
        }
    }

    private static Expense__c getExpenseForManagement(Id expenseId) {
        if (expenseId == null) {
            throw new AuraHandledException('The expense could not be found. Refresh and try again.');
        }
        List<Expense__c> expenses = [
            SELECT Id, Name, Label__c, Amount__c, Spender_Id__c, CreatedDate
            FROM Expense__c
            WHERE Id = :expenseId
            LIMIT 1
        ];
        if (expenses.isEmpty()) {
            throw new AuraHandledException('The expense no longer exists. Refresh and try again.');
        }
        Expense__c expense = expenses[0];
        if (expense.CreatedDate < currentMonthStart()) {
            throw new AuraHandledException('This month is closed. Completed-month expenses are locked.');
        }
        if (FeatureManagement.checkPermission('KPHB_Admin')) return expense;
        if (expense.Spender_Id__c != UserInfo.getUserId()) {
            throw new AuraHandledException('You can only edit or delete your own expenses.');
        }
        if (System.now() > expense.CreatedDate.addMinutes(5)) {
            throw new AuraHandledException('This expense is locked. Roommates can edit or delete it only within 5 minutes of creation.');
        }
        return expense;
    }

    @AuraEnabled
    public static void saveAdminSettings(List<MemberUpdate> updates, Decimal rentAmount, String payeeUpiId) {
        requireAdmin();
        if (rentAmount == null || rentAmount < 0) {
            throw new AuraHandledException('Rent must be zero or greater.');
        }
        String cleanUpiId = String.isBlank(payeeUpiId) ? null : payeeUpiId.trim();
        if (cleanUpiId != null && !Pattern.matches('[A-Za-z0-9._-]{2,100}@[A-Za-z][A-Za-z0-9]{1,63}', cleanUpiId)) {
            throw new AuraHandledException('Enter a valid UPI ID, for example name@bank.');
        }
        Set<Id> memberIds = new Set<Id>();
        if (updates != null) {
            for (MemberUpdate updateRow : updates) if (updateRow.id != null) memberIds.add(updateRow.id);
        }
        Map<Id, Member__c> existing = new Map<Id, Member__c>([
            SELECT Id, In_Split__c, Include_Rent__c, Include_Expenses__c, Split_Settings_Initialized__c
            FROM Member__c WHERE Id IN :memberIds
        ]);
        List<Member__c> changes = new List<Member__c>();
        if (updates != null) {
            for (MemberUpdate updateRow : updates) {
                if (existing.containsKey(updateRow.id)) {
                    Member__c member = existing.get(updateRow.id);
                    if (updateRow.includeRent != null) member.Include_Rent__c = updateRow.includeRent;
                    if (updateRow.includeExpenses != null) member.Include_Expenses__c = updateRow.includeExpenses;
                    member.In_Split__c = member.Include_Rent__c || member.Include_Expenses__c;
                    member.Split_Settings_Initialized__c = true;
                    changes.add(member);
                }
            }
        }
        if (!changes.isEmpty()) update changes;

        KPHB_Config__c config = KPHB_Config__c.getOrgDefaults();
        if (config == null) config = new KPHB_Config__c(SetupOwnerId = UserInfo.getOrganizationId());
        config.Rent_Amount__c = rentAmount;
        config.Payee_UPI_Id__c = cleanUpiId;
        upsert config;
    }

    private static Member__c ensureCurrentMember() {
        String userId = UserInfo.getUserId();
        List<Member__c> found = [
            SELECT Id, Name, User_Id__c, In_Split__c
            FROM Member__c WHERE User_Id__c = :userId LIMIT 1
        ];
        if (!found.isEmpty()) {
            Member__c member = found[0];
            if (member.Name != UserInfo.getName()) {
                member.Name = UserInfo.getName();
                update member;
            }
            return member;
        }
        Member__c member = new Member__c(
            Name = UserInfo.getName(),
            User_Id__c = userId,
            In_Split__c = true
        );
        insert member;
        return member;
    }

    private static void migrateSplitSettings() {
        List<Member__c> membersToInitialize = new List<Member__c>();
        for (Member__c member : [
            SELECT Id, In_Split__c, Include_Rent__c, Include_Expenses__c, Split_Settings_Initialized__c
            FROM Member__c
            WHERE Split_Settings_Initialized__c = false
        ]) {
            member.Include_Rent__c = member.In_Split__c;
            member.Include_Expenses__c = member.In_Split__c;
            member.Split_Settings_Initialized__c = true;
            membersToInitialize.add(member);
        }
        if (!membersToInitialize.isEmpty()) update membersToInitialize;
    }

    private static String getPayeeUpiId() {
        KPHB_Config__c config = KPHB_Config__c.getOrgDefaults();
        return config != null && !String.isBlank(config.Payee_UPI_Id__c) ? config.Payee_UPI_Id__c : null;
    }

    private static Decimal getRentAmount() {
        KPHB_Config__c config = KPHB_Config__c.getOrgDefaults();
        return config != null && config.Rent_Amount__c != null ? config.Rent_Amount__c : DEFAULT_RENT;
    }

    private static Date parseMonthKey(String monthKey) {
        if (!Pattern.matches('^[0-9]{4}-[0-9]{2}$', monthKey)) {
            throw new AuraHandledException('Choose a valid expense month.');
        }
        try {
            return Date.valueOf(monthKey + '-01');
        } catch (Exception ex) {
            throw new AuraHandledException('Choose a valid expense month.');
        }
    }

    private static String monthKeyForDate(Date value) {
        String monthPart = value.month() < 10 ? '0' + String.valueOf(value.month()) : String.valueOf(value.month());
        return String.valueOf(value.year()) + '-' + monthPart;
    }

    private static List<MonthOption> buildMonthOptions(Date currentMonth) {
        Set<String> keys = new Set<String>{ monthKeyForDate(currentMonth) };
        Set<String> memberIds = new Set<String>();
        for (Member__c member : [SELECT User_Id__c FROM Member__c]) memberIds.add(member.User_Id__c);
        if (!memberIds.isEmpty()) {
            for (AggregateResult groupedMonth : [
                SELECT CALENDAR_YEAR(CreatedDate) calendarYear, CALENDAR_MONTH(CreatedDate) calendarMonth
                FROM Expense__c
                WHERE Spender_Id__c IN :memberIds
                GROUP BY CALENDAR_YEAR(CreatedDate), CALENDAR_MONTH(CreatedDate)
            ]) {
                Integer yearValue = Integer.valueOf(String.valueOf(groupedMonth.get('calendarYear')));
                Integer monthValue = Integer.valueOf(String.valueOf(groupedMonth.get('calendarMonth')));
                Date firstDay = Date.newInstance(yearValue, monthValue, 1);
                keys.add(monthKeyForDate(firstDay));
            }
        }
        List<String> sortedKeys = new List<String>(keys);
        sortedKeys.sort();
        List<MonthOption> options = new List<MonthOption>();
        for (Integer index = sortedKeys.size() - 1; index >= 0; index--) {
            String key = sortedKeys[index];
            Date monthDate = Date.valueOf(key + '-01');
            Datetime monthDateTime = Datetime.newInstance(monthDate, Time.newInstance(0, 0, 0, 0));
            MonthOption option = new MonthOption();
            option.value = key;
            option.label = monthDateTime.format('MMMM yyyy');
            options.add(option);
        }
        return options;
    }

    private static void requireAdmin() {
        if (!FeatureManagement.checkPermission('KPHB_Admin')) {
            throw new AuraHandledException('You do not have permission to change the group settings.');
        }
    }

    private static Datetime currentMonthStart() {
        Date today = Date.today();
        Date monthStart = Date.newInstance(today.year(), today.month(), 1);
        return Datetime.newInstance(monthStart, Time.newInstance(0, 0, 0, 0));
    }

    private static ExpenseRow toExpenseRow(Expense__c expense) {
        ExpenseRow row = new ExpenseRow();
        row.id = expense.Id;
        row.name = expense.Name;
        row.label = expense.Label__c;
        row.amount = expense.Amount__c;
        row.spenderId = expense.Spender_Id__c;
        row.spenderName = expense.Spender_Name__c;
        row.createdDate = expense.CreatedDate;
        row.canEdit = expense.CreatedDate >= currentMonthStart()
            && (FeatureManagement.checkPermission('KPHB_Admin')
            || (expense.Spender_Id__c == UserInfo.getUserId()
                && System.now() <= expense.CreatedDate.addMinutes(5)));
        return row;
    }
}