# typed: true
# frozen_string_literal: true

class AuditLogGitEventExport < ApplicationRecord::Collab

  VALID_SUBJECT_TYPES = %w(User Organization Business)
  AUDIT_LOG_GIT_EVENT_EXPORT_EXPIRATION = 1.hour
  AUDIT_LOG_GIT_EVENT_EXPORT_MAX_CONCURRENT_EXPORTS = 3

  include Instrumentation::Model

  belongs_to :actor, class_name: "User"
  belongs_to :subject, polymorphic: true

  validates :subject_type, inclusion: { in: VALID_SUBJECT_TYPES }
  validates :subject_id,   presence: true
  validates :actor_id,     presence: true
  validates :token,        presence: true
  validates :start,        presence: true
  validates :end,          presence: true
  validates :total_chunks, presence: true
  validate  :end_after_start
  validate  :has_in_progress_exports

  after_initialize :default_values

  before_validation :generate_token, on: :create

  after_create :increment_create_count
  after_commit :process, on: :create

  self.ignored_columns += [:truncated]

  class ExportError < StandardError
  end

  # Public: this is called from the asynchronous job to
  #         kick off a export job in Driftwood and wait
  #         for it to be done.
  #
  # Parameters:
  #
  #   lock_key - mutex group key to unlock once the process
  #              is done
  def process
    remote_object.start

    instrument :audit_log_git_event_export
  end

  def to_param
    token
  end

  def increment_create_count
    GitHub.dogstats.increment("audit_log_git_event_export_count", tags: ["action:create"])
  end

  def event_payload
    payload = {
      actor: actor,
      start: start,
      end: self[:end]
    }

    if subject.respond_to?(:event_prefix)
      payload[subject.event_prefix] = subject
    else
      raise ArgumentError, "#{subject} does not respond to #event_prefix"
    end

    payload
  end

  def content_type
    "application/gzip"
  end

  # Public: fetch and catch the results of a previously started export job
  #
  # Returns: a RemoteObject instance that contains the results
  def remote_object
    if @remote.nil?
      @remote = GitExport.new(self)
    end
    @remote
  end

  # Public: verify if the results of a previously started export job are available
  #
  # Returns: bool
  def remote_object?
    remote_object.successful?
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

  # Public: The event prefix for the audit log export event. It is dependent on
  # the subject the export is performed against.
  #
  # Returns Symbol
  def event_prefix
    subject.event_prefix
  end

  # Public: Check whether the results are truncated
  #
  # Returns bool
  def results_truncated?
    remote_object.truncated?
  end

  # Public: Return state of remote object and synchronize it with internal state
  #
  # Returns STATUS_TYPE_*
  def get_and_sync_status
    if T.must(created_at) < AUDIT_LOG_GIT_EVENT_EXPORT_EXPIRATION.ago
      unless completed
        ActiveRecord::Base.connected_to(role: :writing) do
          self.update_attribute(:completed, true)
        end
      end
      return :STATUS_TYPE_FAILED
    end

    status = remote_object.status
    unless status == :STATUS_TYPE_STARTED
      ActiveRecord::Base.connected_to(role: :writing) do
        self.update_attribute(:completed, true)
      end
    end
    status
  end

  def export_status
    remote_object.public_fetch_meta
  end

  private

  # Private: Check wether there are in progress exports for the same subject
  #
  # Returns nil.
  def has_in_progress_exports
    latest_exports = subject
      .audit_log_git_event_exports
      .where(actor_id: actor_id)
      .where("created_at > ?", AUDIT_LOG_GIT_EVENT_EXPORT_EXPIRATION.ago)
      .where(completed: false)

    if latest_exports.to_a.count { |e| e.get_and_sync_status == :STATUS_TYPE_STARTED } >= AUDIT_LOG_GIT_EVENT_EXPORT_MAX_CONCURRENT_EXPORTS
      errors.add(:subject, "can't create another export because the maximum limit of in-progress exports has been reached")
    end
  end

  # Private: The unique token for the audit log used to download the export.
  #
  # Returns String.
  def generate_token
    self.token = SecureRandom.uuid
  end

  # Private: Determine if the start date is before the end date
  #
  # Returns nothing.
  def end_after_start
    if self[:end] < start
      errors.add(:end, "must be after the start date")
    end
  end

  # Private: return export file extension based on API version
  def extension
    "json.gz"
  end

  # Private: initializes the time range with (-24h, current_time) to use sane
  #          defaults
  def default_values
    # For some reason, start is marked as a non-nilable ::ActiveSupport::TimeWithZone
    # but it should really be nilable as a new unsaved record can have nil values here.
    T.unsafe(self).start ||= Time.zone.now - 1.day
    T.unsafe(self).end ||= Time.zone.now
  end

  class GitExport
    def initialize(export)
      @export = export
    end

    def start
      options = {
        subject_id: @export.subject_id,
        subject_type: driftwood_subject_type,
        key_id: "plain",
        format_type:  Driftwood::V1::Client::FORMAT_JSON,
        export_id: @export.token,
        encrypted_phrase: "created:>#{@export.start.utc.iso8601} created:<#{@export[:end].utc.iso8601}",
        disclose_ip_address: false,
        feature_flags: [],
      }
      if @export.subject.is_a?(Business)
        if @export.subject.feature_flag_enabled?(:audit_sso_disclosure, default: false)
          options[:feature_flags] << "show_sso_information"
        end
      end

      if @export.subject.is_a?(Organization) || @export.subject.is_a?(Business)
        options[:feature_flags] << "show_actor_ip" if @export.subject.source_ip_disclosure_enabled?
      end

      Audit::Driftwood::GitExport.new.export_start_git(**options)
    end

    def completed?
      fetch_meta[:status] != :STATUS_TYPE_STARTED
    end

    def successful?
      fetch_meta[:status] == :STATUS_TYPE_SUCCESSFUL
    end

    def truncated?
      fetch_meta[:truncated]
    end

    def size
      fetch_meta[:size]
    end

    def status
      fetch_meta[:status]
    end

    def fetch(chunk_index)
      options = {
        subject_id: @export.subject_id,
        subject_type: driftwood_subject_type,
        format_type: Driftwood::V1::Client::FORMAT_JSON,
        export_id: @export.token,
        chunk_idx: chunk_index,
        feature_flags: [],
      }

      resp = Audit::Driftwood::GitExport.new.fetch_git_result(**options)
      raise ExportError, "results are empty" unless resp[:chunk_data].length > 0
      resp[:chunk_data]
    end

    def get
      raise ExportError, "results are not available" unless successful?
      @meta[:chunks].times do |index|
        yield fetch(index)
      end
    end

    def public_fetch_meta
      self.fetch_meta
    end

    private

    def fetch_meta
      if @meta.nil? || @meta[:status] == :STATUS_TYPE_STARTED
        options = {
          subject_id: @export.subject_id,
          subject_type: driftwood_subject_type,
          format_type:  Driftwood::V1::Client::FORMAT_JSON,
          export_id: @export.token,
          feature_flags: [],
        }

        @meta = Audit::Driftwood::GitExport.new.
          check_git_status(**options)
      end
      @meta
    end

    def driftwood_subject_type
      case @export.subject_type
      when "User"
        Driftwood::V1::Client::SUBJECT_ORG
      when "Business"
        if @export.subject.enterprise_managed_user_enabled?
          Driftwood::V1::Client::SUBJECT_EMU_BUSINESS
        else
          Driftwood::V1::Client::SUBJECT_BUSINESS
        end
      else
        raise ExportError, "subject type is unknown"
      end
    end
  end
end
