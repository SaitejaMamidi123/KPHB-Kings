String monthKey = String.valueOf(Date.today().year()) + '-' + String.valueOf(Date.today().month()).leftPad(2, '0');
KPHBRoomExpensesController.DashboardData dashboard = KPHBRoomExpensesController.getDashboard(monthKey);
for (KPHBRoomExpensesController.MemberRow member : dashboard.members) {
    Boolean hasSheetSpend = false;
    Integer memberExpenseCount = 0;
    for (KPHBRoomExpensesController.ExpenseRow expense : dashboard.selectedExpenses) {
        if (expense.spenderId == member.userId) {
            hasSheetSpend = true;
            memberExpenseCount++;
        }
    }
    System.debug('SHEET_MEMBER_COLUMN=' + member.name + ', HAS_SPEND=' + hasSheetSpend + ', EXPENSE_COUNT=' + memberExpenseCount + ', INCLUDED_IN_SHARE=' + member.includeExpenses);
    if (!member.includeExpenses) {
        for (KPHBRoomExpensesController.PersonTotal total : dashboard.personTotals) {
            if (total.userId == member.userId) {
                System.debug('EXCLUDED_MEMBER=' + member.name + ', SPENT=' + total.spent + ', FINAL=' + total.finalToPay + ', RENT=' + total.rentShare);
            }
        }
    }
}
System.debug('SHEET_MEMBER_COLUMN_COUNT=' + dashboard.members.size());
System.debug('SHARED_EXPENSE_TOTAL=' + dashboard.totalExpense);
