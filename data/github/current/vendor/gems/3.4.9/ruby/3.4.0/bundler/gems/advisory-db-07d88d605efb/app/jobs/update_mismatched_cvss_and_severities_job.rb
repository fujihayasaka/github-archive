# frozen_string_literal: true

class UpdateMismatchedCVSSAndSeveritiesJob < ApplicationJob
  queue_as :low

  # There are currently just over 4,000 of these
  DEFAULT_LIMIT = 5000

  def perform(limit: DEFAULT_LIMIT, dry_run: true, log: false)
    query = Advisory.where.not(cvss_v3: [nil, ""])
      .and(Advisory.where.not(cvss_v4: [nil, ""]))
      .and(Advisory.where(withdrawn_at: nil))

    if dry_run
      File.open("log/dry_run_update_mismatched_cvss_and_severities_job.log", "a") do |file|
        file.write("Running in dry run mode.\n")
        file.write("#{query.count} Advisories to update.\n")
      end
    end

    if query.count == 0
      GitHub::Telemetry::Logs.logger.info("No Advisories to update.") if log
    else
      GitHub::Telemetry::Logs.logger.info("#{query.count} Advisories to update.") if log

      if limit.present?
        query = query.limit(limit)
      end

      begin
        query.find_each do |advisory|
          advisory_review = advisory.advisory_review
          advisory_payload = advisory_review.advisory_payload
          updated_severity = SeverityCalculator.from_cvss_v4(advisory_payload["cvss_v4"])

          if advisory.severity != updated_severity
            if dry_run
              File.write(
                "log/dry_run_update_mismatched_cvss_and_severities_job.log",
                "Would update severity for Advisory #{advisory.ghsa_id} from #{advisory.severity} to #{updated_severity}.\n",
                mode: "a",
              )
            else
              GitHub::Telemetry::Logs.logger.info("Attempting to update severity for Advisory #{advisory.ghsa_id} from #{advisory.severity} to #{updated_severity}. . .") if log

              advisory.update!(severity: updated_severity)

              PublishAdvisoryToHydroJob.perform_later(advisory)
            end
          end

          if advisory_review.severity != updated_severity
            if dry_run
              File.write(
                "log/dry_run_update_mismatched_cvss_and_severities_job.log",
                "Would update severity for Advisory Review #{advisory_review.ghsa_id} from #{advisory_review.severity} to #{updated_severity}. . .\n",
                mode: "a",
              )
            else
              GitHub::Telemetry::Logs.logger.info("Attempting to update severity for Advisory Review #{advisory_review.ghsa_id} from #{advisory_review.severity} to #{updated_severity}.") if log

              advisory_payload["severity"] = updated_severity

              advisory_review.update!(advisory_payload: advisory_payload)
            end
          end
        end
      rescue StandardError => error
        GitHub::Telemetry::Logs.logger.error(
          "Exception raised while updating mismatched CVSS and severities.",
          { exception: error, "gh.ghsa_id": advisory.ghsa_id },
        )
      end
    end
  end
end
