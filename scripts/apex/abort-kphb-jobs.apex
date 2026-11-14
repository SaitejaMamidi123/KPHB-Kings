for (CronTrigger cronJob : [
    SELECT Id, CronJobDetail.Name
    FROM CronTrigger
    WHERE CronJobDetail.Name LIKE 'KPHB%'
]) {
    System.abortJob(cronJob.Id);
}
