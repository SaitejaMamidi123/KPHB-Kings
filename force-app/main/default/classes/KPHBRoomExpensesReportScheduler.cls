global class KPHBRoomExpensesReportScheduler implements Schedulable {
    global void execute(SchedulableContext context) {
        try {
            KPHBRoomExpensesMonthlyReport.sendPreviousMonthReports();
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'KPHB monthly room expense report failed: ' + ex.getMessage());
        }
    }
}