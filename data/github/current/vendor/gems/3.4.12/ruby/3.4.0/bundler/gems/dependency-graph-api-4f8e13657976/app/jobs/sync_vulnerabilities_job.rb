# frozen_string_literal: true

class SyncVulnerabilitiesJob < RetryJob
  def perform
    VulnerableVersionRange.sync
    Instrument.increment("etl.vulnerability_sync.job.completed")
  end

  rescue_from(StandardError) do |exception|
    Instrument.increment("etl.vulnerability_sync.job.failed", { error_type: exception.class.to_s })
    Failbot.report(exception,
      "gh.aqueduct.queue.name" => queue_name,
      "gh.aqueduct.job.name" => "sync_vulnerabilities_job"
    )
  end
end
