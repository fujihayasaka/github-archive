# typed: true
# frozen_string_literal: true

module GHECAdmin
  # This class interacts with BusinessReportExport, DormantUsersExportController, and
  # ProcessDormantUsersExportJob.
  #
  # The logic for generating the actual report lives in GitHub::Reports::DormantUsers
  class EnterpriseDormantUsersExport
    include ActionView::Helpers::DateHelper
    include UrlHelpers

    GHEC_DORMANCY_THRESHOLD = 30.days
    GHEC_DORMANCY_REPORT_EXPIRY_TIME = 72.hours

    attr_reader :actor, :business, :business_report_export, :triggered_via_stafftools, :created_at, :completed_at

    def self.in_progress_for_business?(business:)
      business
        .business_report_exports
        .where(report_type: self.to_s)
        # Only show reports inside our expiry time window.
        # The S3 bucket has 1 additional day buffer to prevent overlap issues
        .where("created_at > ?", GHEC_DORMANCY_REPORT_EXPIRY_TIME.ago)
        .where(triggered_via_stafftools: false)
        .where(completed_at: nil)
        .exists?

    end

    def self.latest_for_business(business:, include_stafftools_reports: false)
      exports = business
        .business_report_exports
        .where(report_type: self.to_s)
        # Only show reports inside our expiry time window.
        # The S3 bucket has 1 additional day buffer to prevent overlap issues
        .where(
          "created_at > :expiry_time OR completed_at > :expiry_time",
          expiry_time: GHEC_DORMANCY_REPORT_EXPIRY_TIME.ago
        )
        # Take 4 reports so we can show the currently in-progress one (if there is one) plus the last 3 done
        .limit(4)
        .order(created_at: :desc)

      exports = exports.where(triggered_via_stafftools: false) unless include_stafftools_reports

      exports.map(&:report)
    end

    def initialize(business_report_export:)
      owner = if business_report_export.owner_type == "Business"
        # Ensure that reports for soft-deleted enterprises can be cleaned up.
        Business.including_deleted.find_by(id: business_report_export.owner_id)
      else
        business_report_export.owner
      end
      raise ArgumentError, "owner must be a Business" unless owner.is_a?(Business)

      @business_report_export = business_report_export
      @business = owner
      @actor = business_report_export.actor
      @triggered_via_stafftools = business_report_export.triggered_via_stafftools
      @created_at = business_report_export.created_at
      @completed_at = business_report_export.completed_at
    end

    # Called from the BusinessReportExport#after_create callback
    def enqueue
      ProcessDormantUsersExportJob.create_status(business_report_export.token)
      ProcessDormantUsersExportJob.perform_later(business_report_export.id)
    end

    # Called from the BusinessReportExport#before_destroy callback.
    # Ensures the remote file is deleted when the record is deleted. There
    # is a chance it has already been deleted due to the bucket lifecycle having
    # deleted the file already.
    #
    # Returns nothing.
    def cleanup
      storage.cleanup
    end

    # Called from ProcessDormantUsersExportJob#perform
    def process
      begin
        GitHub.dogstats.time("dormant_users_export_report", tags: ["action:process"]) do
          # Start the export process
          contents = Time.use_zone(actor.time_zone) do
            run
          end

          # The export is complete, store the results in S3
          uploaded = store_results(contents)

          ActiveRecord::Base.connected_to(role: :writing) do
            if uploaded
              return if business_report_export.is_notified?

              BusinessMailer.dormant_users_report(actor, business, reports_url, expiry_in_words).deliver_later
              business_report_export.notify!
            end

            business_report_export.complete!
          end
          GlobalInstrumenter.instrument("enterprise_account.report_export", {
            enterprise: business,
            enterprise_size: business.members.count,
            actor: actor,
            report_name: T.must(self.class.name).underscore,
            notification_sent: business_report_export.is_notified?,
          })
        end
      rescue StandardError => e # rubocop:todo Lint/RescueException
        # Still report the error so we can track it down later
        Failbot.report(e)
        BusinessMailer.dormant_users_report_failed(actor, business, reports_url, expiry_in_words).deliver_later
        ActiveRecord::Base.connected_to(role: :writing) do
          business_report_export.error!
        end
      end
    end

    def human_filename
      "export-#{business.slug}-#{created_at.to_i}.csv"
    end

    # filename used by remote storage
    def filename
      "#{GitHub.filename_prefix_for_env}/#{business_report_export.token}.csv"
    end

    def reports_url
      if triggered_via_stafftools
        stafftools_enterprise_people_url(
          host: GitHub.stafftools_url,
          slug: business.slug,
          anchor: "reports"
        )
      else
        settings_compliance_enterprise_url(
          host: GitHub.url,
          slug: business.slug,
          anchor: "reports"
        )
      end
    end

    def expires_at
      (completed_at || Time.now) + GHECAdmin::EnterpriseDormantUsersExport::GHEC_DORMANCY_REPORT_EXPIRY_TIME
    end

    def expiry_in_words
      distance_of_time_in_words_to_now(expires_at)
    end

    # Public: The content type for storing and downloading the organization members export.
    #
    # Returns String.
    def content_type
      "text/csv"
    end

    def download_url
      if triggered_via_stafftools
        dormant_users_export_stafftools_enterprise_url(
          host: GitHub.stafftools_url,
          slug: business.slug,
          token: business_report_export.token
        )
      else
        dormant_users_export_enterprise_url(
          host: GitHub.url,
          slug: business.slug,
          token: business_report_export.token
        )
      end
    end

    def storage
      GHECAdmin::Storage.make(filename, :dormant_users)
    end

    def exists?
      storage.exists?
    end

    def in_progress?
      business_report_export.in_progress?
    end

    def has_errored?
      business_report_export.has_errored?
    end

    def notify_when_complete?
      !business_report_export.is_notified?
    end

    def status
      business_report_export.status
    end

    private

    # get all the dormant users under a particular business as a CSV
    def run
      GitHub::Reports::GHECDormantUsers.new.data(
        threshold: GHEC_DORMANCY_THRESHOLD,
        business_id: business.id,
        business_report_export: business_report_export
      )
    end

    # Private: Store the export results remotely.
    #
    # contents - The String body of dormant users export to store.
    #
    # Returns true if stored, false if not.
    def store_results(contents)
      storage.store(contents, content_type)
    end
  end
end
