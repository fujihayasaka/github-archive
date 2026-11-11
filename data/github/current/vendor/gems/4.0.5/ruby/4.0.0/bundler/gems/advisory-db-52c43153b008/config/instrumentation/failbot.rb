# frozen_string_literal: true

# Failbot instrumentation, copied from: https://github.com/github/github/blob/f6b464c67ccaa983c8a08b5007c39cdc9589740e/config/instrumentation/failbot.rb#L16
# Record stats for reported exceptions.
#
# data                   - a Hash of reported exception data
# data["app"]            - the bucket that the exception was reported to (.e.g. "github",
#                         "github-user", etc)
# data["report_status"]  - whether or not the report succeeded (`success` or `error`)
# data["elapsed_ms"]     - Time to send report in milliseconds
# data["exception_type"] - If the status is `failure`, then the exception that was
#                          thrown when the report failed.
# data["action"]         - If the status is `failure`, then the step in the reporting
#                          process at which the report failed
ActiveSupport::Notifications.subscribe("report.failbot") do |_name, _start, _ending, _transaction_id, data|
  tags = [
    "application:#{data["app"]}",
    "status:#{data["report_status"]}",
  ]
  tags << "exception:#{data["exception_type"]}" if data.key?("exception_type")
  tags << "action:#{data["action"]}" if data.key?("action")

  # App name is automatically prepended, don't do it here.
  AdvisoryDB.stats.distribution("failbot.report", data.fetch("elapsed_ms", 0), tags: tags)
end
