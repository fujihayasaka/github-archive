# typed: strict
# frozen_string_literal: true

class Business::LicenseConsumptionExport < ApplicationRecord::Domain::Users
  extend T::Sig

  include Instrumentation::Model
  include GitHub::Validations
  include GitHub::Memoizer
  include ActionView::Helpers::DateHelper
  include UrlHelpers

  LICENSE_CONSUMPTION_REPORT_EXPIRY_TIME = T.let(3.days.freeze, Integer) # Time to allow user to download report from object storage
  LICENSE_CONSUMPTION_REPORT_EMAIL_USER_COUNT = 1000 # email will be send with for business with this number of users or more

  belongs_to :actor, class_name: "User"
  belongs_to :business

  validates :business_id,  presence: true
  validates :actor_id,     presence: true
  validates :token,        presence: true
  enum :format,            { json: "json", csv: "csv" }

  before_validation :set_default_format, on: :create
  before_validation :generate_token, on: :create
  after_commit :increment_create_count
  after_commit :enqueue_process_export_results, on: :create
  before_destroy :delete_remote_file

  sig { returns(String) }
  def human_filename
    "consumed_licenses-#{business&.slug}-#{created_at.to_i}.#{format}"
  end

  sig { returns(String) }
  def filename
    "#{GitHub.filename_prefix_for_env}/#{token}.#{format}"
  end

  # Public: The content type for storing and downloading the license consumption export.
  #
  sig { returns(T.nilable(String)) }
  def content_type
    case format
    when "json"
      "application/json"
    when "csv"
      "text/csv"
    end
  end

  sig { returns(T.nilable(T::Boolean)) }
  def process
    GitHub.dogstats.distribution_time("business_license_consumption_export_process") do
      contents = Business::LicenseCsvGenerator.new(business).generate
      uploaded = store_results(contents)

      if uploaded
        instrument :business_license_consumption_export, total_entries: CSV.parse(contents).count

        ActiveRecord::Base.connected_to(role: :writing) do
          if notify_when_complete?
            BusinessMailer.enterprise_cloud_licensing_report(actor, business, download_url, expiry_in_words).deliver_later
            notify!
          end
          complete!
        end

        GlobalInstrumenter.instrument("enterprise_account.report_export", {
          enterprise: business,
          enterprise_size: business&.members.count,
          actor: actor,
          report_name: self.class.name.to_s.underscore,
          notification_sent: is_notified?,
        })
      else
        false
      end
    end
  end

  sig { returns(Aws::S3::Object) }
  memoize def remote_object
    Aws::S3::Object.new(
      bucket_name: GitHub.s3_license_consumption_bucket, key: filename, client: GitHub.s3_license_consumption_client,
    )
  end

  sig { returns(T::Boolean) }
  def remote_object?
    remote_object.exists?
  end

  # Public: The event prefix for the license consumption export event. It is dependent on
  # the business the export is performed against.
  #
  sig { returns(T.nilable(Symbol)) }
  def event_prefix
    business&.event_prefix
  end

  # Public: The event context to be logged for the license consumption export. Since
  # exports are temporary they don't include any lookup reference.
  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def event_context
    {}
  end

  sig { returns(String) }
  def to_param
    token
  end

  # Public: Check if the export is complete.
  sig { returns(T::Boolean) }
  def is_complete?
    completed_at.present?
  end

  # Public: Check if the export has been notified.
  sig { returns(T::Boolean) }
  def is_notified?
    notified_at.present?
  end

  # Public: Check if the export should be notified.
  sig { returns(T::Boolean) }
  def notify_when_complete?
    !is_notified? && business&.user_accounts&.count.to_i >= LICENSE_CONSUMPTION_REPORT_EMAIL_USER_COUNT
  end

  private

  # Private: Store the export results remotely.
  #
  # contents - The body of license consumption export to store.
  sig { params(contents: String).returns(T::Boolean) }
  def store_results(contents)
    result = GitHub.s3_license_consumption_client.put_object(
      acl: "private",
      content_type: content_type,
      body: contents,
      bucket: GitHub.s3_license_consumption_bucket,
      key: filename,
    )
    result.successful?
  rescue Aws::S3::Errors::ServiceError
    false
  end

  # Private: Process the export request in the background and report back to the
  # user when their export is ready for downloading.
  sig { void }
  def enqueue_process_export_results
    JobStatus.create(id: token)

    Licensing::ProcessBusinessLicenseConsumptionExportJob.perform_later(id)
  end

  # Private: The unique token for the license consumption used to download the export.
  sig { void }
  def generate_token
    self.token = SecureRandom.uuid
  end

  # Private: The default format for the export.
  # JSON export hasn't been implemented yet as we have an API for that.
  sig { void }
  def set_default_format
    self.format = "csv" if format.blank?
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def event_payload
    payload = {
      actor: actor,
    }

    business = self.business
    if business && business.respond_to?(:event_prefix)
      payload[business.event_prefix] = business
    else
      raise ArgumentError, "#{business} does not respond to #event_prefix"
    end

    payload
  end

  sig { void }
  def increment_create_count
    GitHub.dogstats.increment("license_consumption_export", tags: ["action:create", "format:#{format}"])
  end

  # Private: Ensures the remote file is deleted when the record is deleted. There
  # is a change it has already been deleted due to the bucket lifecycle having
  # deleted the file already.
  sig { void }
  def delete_remote_file
    # Do not attempt to delete the file on proxima, because s3 is not available there, so there will be nothing to
    # delete. This is temporary, we will want to delete these from azure once they are moved for proxima.
    remote_object.delete unless GitHub.multi_tenant_enterprise?
  rescue Aws::S3::Errors::NoSuchKey
    # File doesn't exist on S3.
  end

  # Private: The URL to download the license consumption export.
  sig { returns(String) }
  def download_url
    if triggered_via_stafftools
      export_stafftools_enterprise_licensing_url(token: token, format: format, slug: business&.slug, host: GitHub.url)
    else
      export_enterprise_licensing_url(token: token, format: format, slug: business&.slug, host: GitHub.url)
    end
  end

  # Private: The URL to download the license consumption export.
  sig { returns(T.nilable(Time)) }
  def expires_at
    (completed_at || Time.now) + LICENSE_CONSUMPTION_REPORT_EXPIRY_TIME
  end

  # Private: The expiry time in words for the license consumption export.
  sig { returns(String) }
  def expiry_in_words
    distance_of_time_in_words_to_now(expires_at)
  end

  # Private: Mark the export as complete.
  sig { void }
  def complete!
    update(completed_at: Time.now) unless is_complete?
  end

  # Private: Mark the export as notified.
  sig { void }
  def notify!
    update(notified_at: Time.now) unless is_notified?
  end
end
