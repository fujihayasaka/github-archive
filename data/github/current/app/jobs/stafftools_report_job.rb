# typed: true
# frozen_string_literal: true

class StafftoolsReportJob < ApplicationJob
  queue_as :staff_tools_report

  locked_by timeout: ActiveJob::LockingJob::DEFAULT_LOCK_TIMEOUT, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  def perform(report, skipmc = false)
    GitHub.cache.skip = true if skipmc

    GitHub::Reports.update(report)
  end
end
