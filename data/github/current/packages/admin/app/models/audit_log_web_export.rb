# typed: true
# frozen_string_literal: true

class AuditLogWebExport < ApplicationRecord::Collab

  VALID_SUBJECT_TYPES = %w(User Business)
  VALID_FORMAT_TYPES = %w(json csv)
  AUDIT_LOG_WEB_EXPORT_EXPIRATION = 1.hour
  AUDIT_LOG_WEB_EXPORT_MAX_CONCURRENT_EXPORTS = 3

  include Instrumentation::Model

  belongs_to :actor, class_name: "User"
  belongs_to :subject, polymorphic: true

  validates :actor_id,      presence: true
  validates :subject_id,    presence: true
  validates :subject_type,  inclusion: { in: VALID_SUBJECT_TYPES }
  validates :format_type,   inclusion: { in: VALID_FORMAT_TYPES }
  validates :export_id,     presence: true
  validates :total_chunks,  presence: true
  validates :phrase,        length: { maximum: 1024 }, allow_blank: true
  validate  :has_in_progress_exports_validator, if: -> {
    T.bind(self, AuditLogWebExport)
    VALID_SUBJECT_TYPES.include?(subject_type)
  }

  before_validation :default_values, on: :create
  before_validation :generate_export_id, on: :create

  after_create :increment_create_count

  attr_accessor :non_sso_org_ids

  self.ignored_columns += [:truncated]

  class WebExportError < StandardError
  end

  def has_in_progress_exports_validator
    latest_exports = subject
      .audit_log_web_exports
      .where(actor_id: actor_id)
      .where("created_at > ?", AUDIT_LOG_WEB_EXPORT_EXPIRATION.ago)
      .where(completed: false)

    if latest_exports.to_a.count { |e| e.get_and_sync_status == :STATUS_TYPE_STARTED } >= AUDIT_LOG_WEB_EXPORT_MAX_CONCURRENT_EXPORTS
      errors.add(:subject, "can't create another export because the maximum limit of in-progress exports has been reached")
    end
  end

  # Class that implements a remote object
  # that can be used by the existing audit_log_helpers.rb
  # to render the results back to the user.
  class RemoteObject
    def initialize(subject_id:, subject_type:, format_type:, export_id:, meta:, feature_flags: [])
      raise WebExportError, "results are not available" unless meta[:status] == :STATUS_TYPE_SUCCESSFUL
      @subject_id = subject_id
      @subject_type = subject_type
      @format_type = format_type
      @export_id = export_id
      @meta = meta
      @feature_flags = feature_flags
    end

    def size
      @meta[:size]
    end

    def fetch(chunk_index)
      options = {
        subject_id: @subject_id,
        subject_type: @subject_type,
        format_type: @format_type,
        export_id: @export_id,
        chunk_idx: chunk_index,
        feature_flags: @feature_flags,
      }

      resp = Audit::Driftwood::WebExport.new.fetch_web_result(**options)
      raise WebExportError, "results are empty" unless resp[:chunk_data].length > 0
      resp[:chunk_data]
    end

    def get
      @meta[:chunks].times do |index|
        yield fetch(index)
      end
    end
  end

  # Public: fetch and catch the results of a previously started export job
  #
  # Returns: a RemoteObject instance that contains the results
  def remote_object
    if @remote.nil?

      options = {
        subject_id: subject_id,
        subject_type: driftwood_subject_type,
        format_type: driftwood_format_type,
        export_id: export_id,
        meta: check_remote_state,
        feature_flags: []
      }

      @remote = RemoteObject.new(**options)
    end
    @remote
  end

  # Public: verify if the results of a previously started export job are available
  #
  # Returns: Boolean
  def remote_object?
    check_remote_state[:status] == :STATUS_TYPE_SUCCESSFUL
  end

  # Public: verify if the results of a previously started export job are started, successful or have failed
  #
  # Returns: STATUS_TYPE
  def get_and_sync_status
    if T.must(created_at) < AUDIT_LOG_WEB_EXPORT_EXPIRATION.ago
      unless completed
        ActiveRecord::Base.connected_to(role: :writing) do
          self.update_attribute(:completed, true)
        end
      end
      return :STATUS_TYPE_FAILED
    end

    resp = check_remote_state
    unless resp[:status] == :STATUS_TYPE_STARTED
      ActiveRecord::Base.connected_to(role: :writing) do
        self.update_attribute(:completed, true)
      end
    end
    resp[:status]
  end

  # Public: Check whether the results are truncated
  #
  # Returns bool
  def results_truncated?
    resp = check_remote_state
    resp[:truncated]
  end

  def content_type
    "application/gzip"
  end

  def human_filename(chunk_index = -1)
    if chunk_index > -1
      "export-#{subject_label}-#{created_at.to_i}-#{chunk_index + 1}.#{extension}"
    else
      "export-#{subject_label}-#{created_at.to_i}.#{extension}"
    end
  end

  # Public: The human readable name for the subject.
  #
  # Returns String.
  def subject_label
    case subject
    when User, Organization
      subject.login
    when Business
      subject.slug
    end
  end

  def event_payload
    payload = {
      actor: actor,
      format_type: format_type,
      export_id: export_id,
    }

    if subject.respond_to?(:event_prefix)
      payload[subject.event_prefix] = subject
    else
      raise ArgumentError, "#{subject} does not respond to #event_prefix"
    end

    payload
  end

  # Public: The event prefix for the audit log export event. It is dependent on
  # the subject the export is performed against.
  #
  # Returns Symbol
  def event_prefix
    subject.event_prefix
  end

  # Public: Return the representation of the subject type as Driftwood::Exports::V1::SubjectType
  #
  # Returns Driftwood::Exports::V1::SubjectType
  def driftwood_subject_type
    case subject_type
    when "User"
      if subject.organization?
        Driftwood::V1::Client::SUBJECT_ORG
      else
        Driftwood::V1::Client::SUBJECT_USER
      end
    when "Business"
      if subject.enterprise_managed_user_enabled?
        Driftwood::V1::Client::SUBJECT_EMU_BUSINESS
      else
        Driftwood::V1::Client::SUBJECT_BUSINESS
      end
    else
      raise WebExportError, "subject type is unknown"
    end
  end

  # Public: Return the representation of the format type as Driftwood::Exports::V1::FormatType
  #
  # Returns Driftwood::Exports::V1::FormatType
  def driftwood_format_type
    case format_type
    when "json"
      Driftwood::V1::Client::FORMAT_JSON
    when "csv"
      Driftwood::V1::Client::FORMAT_CSV
    else
      raise WebExportError, "format type is unknown"
    end
  end

  def to_param
    export_id
  end

  def has_in_progress_exports_for_subject?
    subject
      .audit_log_web_exports
      .where("created_at > ?", AUDIT_LOG_WEB_EXPORT_EXPIRATION.ago)
      .where(completed: false)
      .exists?
  end

  # Public: kick off export
  #
  # Returns: boolean
  def start_export
    export = Audit::Driftwood::WebExport.new
    options = {
      subject_id: subject_id,
      subject_type: driftwood_subject_type,
      key_id: "plain",
      format_type: driftwood_format_type,
      export_id: export_id,
      encrypted_phrase: phrase,
      disclose_ip_address: T.let(false, T::Boolean),
      feature_flags: [],
      non_sso_org_ids: non_sso_org_ids,
    }

    is_biz_or_org = subject.is_a?(Business) || subject.is_a?(Organization)
    if is_biz_or_org && subject.source_ip_disclosure_enabled?
      options[:disclose_ip_address] = true
      options[:feature_flags] << "show_actor_ip"
    end

    if is_biz_or_org && subject.feature_enabled?(:audit_sso_disclosure)
      options[:feature_flags] << "show_sso_information"
    end

    export.export_start_web(**options)

    instrument :audit_log_export, query_phrase: phrase
  end

  def export_status
    self.check_remote_state
  end

  private

  # Private: The unique token for the audit log used to download the export.
  #
  # Returns String.
  def generate_export_id
    self.export_id = SecureRandom.uuid
  end

  # Private: Query Driftwood to fetch the state of the export job
  #
  # Returns Metadata of export job
  def check_remote_state
    options = {
      subject_id: subject_id,
      subject_type: driftwood_subject_type,
      format_type: driftwood_format_type,
      export_id: export_id,
      feature_flags: [],
    }

    Audit::Driftwood::WebExport.new.
      check_web_status(**options)
  end

  # Private: initializes the format type to .json to be sane
  #          defaults
  def default_values
    # For some reason, start is marked as a non-nilable ::ActiveSupport::TimeWithZone
    # but it should really be nilable as a new unsaved record can have nil values here.
    T.unsafe(self).format_type ||= "json"
  end

  # Private: return export file extension based on API version
  def extension
    case format_type
    when "json"
      "json.gz"
    when "csv"
      "csv.gz"
    else
      raise WebExportError, "format type is unknown"
    end
  end

  # Private: increment counter for this action
  #
  # Returns nothing
  def increment_create_count
    GitHub.dogstats.increment("audit_log_web_export_count", tags: ["action:create"])
  end

end
