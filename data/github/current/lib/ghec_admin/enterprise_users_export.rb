# typed: true
# frozen_string_literal: true

module GHECAdmin
  # This class interacts with BusinessReportExport, EnterpriseUsersExportController, and
  # ProcessEnterpriseUsersExportJob.
  #
  # The logic for generating the actual report lives in GitHub::Reports::EnterpriseUsers
  class EnterpriseUsersExport
    include ActionView::Helpers::DateHelper
    include UrlHelpers
    include Instrumentation::Model

    if Rails.env.development?
      ENTERPRISE_USERS_REPORT_MAX_RUN_TIME = 1.second.freeze
    else
      ENTERPRISE_USERS_REPORT_MAX_RUN_TIME = 1.hour.freeze # Time to wait before considering export a failure.
    end
    ENTERPRISE_USERS_REPORT_EXPIRY_TIME = 3.days.freeze # Time to allow user to download report from S3
    EMAIL_BUSINESS_USER_COUNT = 1000 # number of users that will trigger email to be sent

    attr_reader :actor, :business, :business_report_export, :created_at, :completed_at, :triggered_via_stafftools

    def self.in_progress_for_business?(business:)
      business
        .business_report_exports
        .where(report_type: self.to_s)
        # Only show reports inside our expiry time window.
        .where("created_at > ?", ENTERPRISE_USERS_REPORT_MAX_RUN_TIME.ago)
        .where(completed_at: nil)
        .exists?
    end

    def self.latest_for_business(business:)
      exports = business
        .business_report_exports
        .where(report_type: self.to_s)
        # Only show reports inside our expiry time window.
        # The S3 bucket has 1 additional day buffer to prevent overlap issues
        .where(
          "created_at > :expiry_time OR completed_at > :expiry_time",
          expiry_time: ENTERPRISE_USERS_REPORT_EXPIRY_TIME.ago
        )
        # Take 4 reports so we can show the currently in-progress one (if there is one) plus the last 3 done
        .limit(4)
        .order(created_at: :desc)

      exports.map(&:report)
    end

    def initialize(business_report_export:)
      owner = if business_report_export.owner_type == "Business"
        # Ensure that reports for soft-deleted enterprises can be cleaned up.
        Business.including_deleted.find_by(id: business_report_export.owner_id)
      else
        business_report_export.owner
      end
      raise ArgumentError, "owner must be an enterprise account" unless owner.is_a?(Business)

      @business_report_export = business_report_export
      @business = owner
      @actor = business_report_export.actor
      @created_at = business_report_export.created_at
      @completed_at = business_report_export.completed_at
      @triggered_via_stafftools = business_report_export.triggered_via_stafftools
    end

    # Called from the BusinessReportExport#after_create callback
    def enqueue
      ProcessEnterpriseUsersExportJob.create_status(business_report_export.token)
      ProcessEnterpriseUsersExportJob.perform_later(business_report_export.id)
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

    # Called from ProcessEnterpriseUsersExportJob#perform
    def process
      GitHub.dogstats.time("enterprise_users_export_report", tags: ["action:process"]) do
        # Start the export process
        contents = Time.use_zone(actor.time_zone) do
          run
        end

        # The export is complete, store the results in S3
        uploaded = store_results(contents)

        if uploaded
          instrument :enterprise_users_export, total_entries: CSV.parse(contents).count
        end

        ActiveRecord::Base.connected_to(role: :writing) do
          if uploaded && notify_when_complete?
            BusinessMailer.enterprise_users_report(actor, business, download_url, expiry_in_words).deliver_later
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
    end

    def human_filename
      "export-#{business.slug}-#{created_at.to_i}.csv"
    end

    # filename used by remote storage
    def filename
      "#{GitHub.filename_prefix_for_env}/#{business_report_export.token}.csv"
    end

    def expires_at
      (completed_at || Time.now) + ENTERPRISE_USERS_REPORT_EXPIRY_TIME
    end

    def expiry_in_words
      distance_of_time_in_words_to_now(expires_at)
    end

    # Public: The content type for storing and downloading this report.
    #
    # Returns String.
    def content_type
      "text/csv"
    end

    def download_url
      if triggered_via_stafftools
        enterprise_users_export_stafftools_enterprise_url(
          host: GitHub.stafftools_url,
          slug: business.slug,
          token: business_report_export.token
        )
      else
        enterprise_users_export_enterprise_url(
          host: GitHub.url,
          slug: business.slug,
          token: business_report_export.token
        )
      end
    end

    def exists?
      storage.exists?
    end

    def in_progress?
      business_report_export.in_progress?
    end

    def notify_when_complete?
      !business_report_export.is_notified? &&
      business.user_accounts.count > EMAIL_BUSINESS_USER_COUNT
    end

    # Public: The event prefix for the enterprise users export event. It is dependent on
    # the business the export is performed against.
    #
    # Returns Symbol
    def event_prefix
      business.event_prefix
    end

    # Public: The event context to be logged for the enterprise users export. Since
    # exports are temporary they don't include any lookup reference.
    def event_context
      {}
    end

    def to_param
      business_report_export.token
    end

    def storage
      GHECAdmin::Storage.make(filename, :users)
    end

    private

    # Run the report to create CSV file
    def run
      args = { business_id: business.id }

      if business_report_export.settings&.any?
        settings = business_report_export.settings.transform_keys(&:to_sym)
        license_attributer_options = settings.slice(:include_nonlicensed_roles, :include_users_removed_this_cycle).compact
        args[:license_attributer_options] = license_attributer_options if license_attributer_options.any?
      end

      GitHub::Reports::EnterpriseUsers.new.data(**args)
    end

    def event_payload
      payload = {
        actor: actor,
        actor_id: actor.id,
        business: business,
        business_id: business.id,
      }

      if business.respond_to?(:event_prefix)
        payload[business.event_prefix] = business
      else
        raise ArgumentError, "#{business} does not respond to #event_prefix"
      end

      payload
    end

    # Private: Store the export results remotely.
    #
    # contents - The String body of report export to store.
    #
    # Returns true if stored, false if not.
    def store_results(contents)
      storage.store(contents, content_type)
    end
  end
end
