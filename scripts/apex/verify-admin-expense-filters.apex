String monthKey = String.valueOf(Date.today().year()) + '-' + String.valueOf(Date.today().month()).leftPad(2, '0');
List<KPHBRoomExpensesController.ExpenseRow> rows = KPHBRoomExpensesController.getAdminExpenses(monthKey);
System.debug('FILTER_MONTH=' + monthKey + ', FILTERABLE_EXPENSE_COUNT=' + rows.size());
for (KPHBRoomExpensesController.ExpenseRow row : rows) {
    System.debug('EXPENSE=' + row.name + ', ROOMMATE=' + row.spenderName + ', LABEL=' + row.label + ', AMOUNT=' + row.amount);
}
