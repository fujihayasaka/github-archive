# this script is used to backfill vulnerabilities (our existing backfill doesn't actually trigger URVA jobs) on the gh/gh side
#
# this is a script that was executed via a gh/gh console w/ a gh-screen command on an ops shell, a la `gh-screen -S dg-api-vuln-backfill`
# to run this, you can just require_relative from a console to wherever you copied this script.
# make sure to reach out to dependabot-experiences to confirm when you intend to run this and for how many repos!

File.write("#{ENV['HOME']}/currentpid.txt", Process.pid)
# get this from a datadog or azure data exporer query
# this is expected to be in the same format as the backfill repos CSV -- one id per line
csv = CSV.read("#{ENV['HOME']}/repos.csv")
# checkpoint is just the last ID you saw output while this script is running. You can change this value if you need to pause for some reason.
checkpoint = 0

# this period is intentional. The dependabot experience team indicate they can handle around ~1000 jobs per second, so this scripts naively
# batches 166 every 10 seconds
periodSeconds = 10
numberOfJobsPerPeriod = 166
numberOfQueuesSoFar = 0

def enqueueUrva(repoBatch)
  repoBatch.each do |rid|
    repoId = rid[0].to_i
    UpdateRepositoryVulnerabilityAlertsJob.perform_later(repoId, { guid: UpdateRepositoryVulnerabilityAlertsJob.guid(repoId), reason: :on_push })
  end
end

while true
  start_time = Time.now
  batchOfRepoIds = csv.shift(numberOfJobsPerPeriod)
  if batchOfRepoIds.count == 0
    break
  end

  lastBatchedRepo = batchOfRepoIds.last[0].to_i
  if lastBatchedRepo <= checkpoint
    next
  end

  enqueueUrva(batchOfRepoIds)

  numberOfQueuesSoFar += batchOfRepoIds.count
  puts "Processed batch up to #{lastBatchedRepo} , a total of #{numberOfQueuesSoFar} have been queued."

  File.write("#{ENV['HOME']}/currentcheck.txt", lastBatchedRepo)

  duration = Time.now - start_time

  puts "Sleeping for #{periodSeconds - duration} seconds"

  sleep (periodSeconds - duration) if duration < periodSeconds

  puts "I'm awake!"
end

puts "All done! We processed #{numberOfQueuesSoFar} items. The last checkpoint was #{checkpoint}"
