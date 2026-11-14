String jobName = 'KPHB Monthly Report';
for (CronTrigger cronJob : [
    SELECT Id, CronJobDetail.Name
    FROM CronTrigger
    WHERE CronJobDetail.Name = :jobName
]) {
    System.abortJob(cronJob.Id);
}
System.schedule(jobName, '0 0 1 * * ?', new KPHBRoomExpensesReportScheduler());
