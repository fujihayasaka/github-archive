# typed: true
# frozen_string_literal: true

class Billing::MeteredReportExportJob < ApplicationJob
  DATE_FORMAT = "%Y-%m-%d"

  discard_on GitHub::Restraint::UnableToLock

  queue_as :billing

  def perform(requester, billable_owner, days, start_date: nil, end_date: nil)
    lock(billable_owner, days) do
      begin
        filepath = filepath_for(billable_owner: billable_owner, days: days)

        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        csv = Billing::MeteredUsageReportGenerator.csv_for(owner: billable_owner, days: days, requester: requester, start_date: start_date, end_date: end_date)
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        report_generation_time = end_time - start_time

        upload_to_s3(csv, filepath)

        report = with_write do
          Billing::MeteredUsageExport.create!(
            requester: requester,
            billable_owner: billable_owner,
            starts_on: start_date || GitHub::Billing.today - days.days,
            ends_on: end_date || GitHub::Billing.today,
            filename: filepath,
          )
        end
        GitHub.logger.info("Metered usage report generated and uploaded successfully.", {
          "code.namespace" => "Billing::MeteredReportExportJob",
          "code.function" => "perform",
          "gh.metered.billing.report.time" => report_generation_time,
          "gh.owner.id" => billable_owner.id,
          "gh.owner.type" => billable_owner_type(billable_owner),
          "gh.owner.name" => billable_owner&.name || billable_owner&.display_login,
        })
      rescue StandardError => e # rubocop:todo Lint/RescueException
        Billing::ReportMailer.metered_export_error(billable_owner, requester).deliver_later
        GitHub.dogstats.increment(
          "billing.metered_report_export_job.error",
          tags: [
            "billable_owner_id:#{billable_owner.id}",
            "billable_owner_type:#{billable_owner_type(billable_owner)}",
            "days:#{days}",
            "staff:#{requester.site_admin?}"
          ]
        )

        raise e
      end

      GitHub.dogstats.increment(
        "billing.metered_report_export_job.success",
        tags: [
          "days:#{days}",
          "staff:#{requester.site_admin?}"
        ]
      )

      Billing::ReportMailer.metered_export_complete_primer_layout(report, billable_owner: billable_owner).deliver_later
    end
  end

  private

  def filepath_for(billable_owner:, days:)
    [
      billable_owner.class,
      billable_owner.name.underscore,
      "#{SecureRandom.hex(4)}_#{Date.current.strftime(DATE_FORMAT)}_#{days}.csv",
    ].join("/")
  end

  def upload_to_s3(csv, filename)
    GitHub.logger.info("Skipping S3 upload for metered report; S3 exports deprecated", {
      "code.namespace" => "Billing::MeteredReportExportJob",
      "code.function" => "upload_to_s3",
      :filename => filename,
    })
  end

  # Internal: Use a GitHub::Restraint to prevent simultaneous updates
  def lock(billable_owner, days, &block)
    lock_key = "metered-export-#{billable_owner.class.to_s.downcase}-#{billable_owner.id}-#{days}"

    restraint.lock!(lock_key, _max_concurrency = 1, _ttl = 5.minutes, &block)
  end

  # Internal: The restraint for locking and preventing simultaneous updates
  #
  # Returns GitHub::Restraint
  def restraint
    @restraint ||= GitHub::Restraint.new
  end

  def billable_owner_type(billable_owner)
    if billable_owner.is_a?(Business)
      "business"
    elsif billable_owner.organization?
      "organization"
    else
      "user"
    end
  end
end
