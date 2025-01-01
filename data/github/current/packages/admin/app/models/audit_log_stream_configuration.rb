# typed: true
# frozen_string_literal: true

class AuditLogStreamConfiguration < ApplicationRecord::Collab
  include Instrumentation::Model

  MAX_AUDIT_LOG_STREAMS_ALLOWED = 2

  belongs_to :business
  validates_associated :business
  belongs_to :sink, polymorphic: true, dependent: :destroy, autosave: true

  scope :streams, -> { includes(:sink) }

  validates_presence_of :business_id
  validates_presence_of :sink
  validates_length_of   :status, maximum: 1024
  validate :has_too_many_streams, on: :create

  after_initialize :set_idx, unless: :persisted?
  after_commit :instrument_creation, on: :create
  after_commit :instrument_update, on: :update
  after_commit :instrument_destroy, on: :destroy

  SHOW_ACTOR_IP_FLAG = "show_actor_ip".freeze
  SHOW_SSO_INFORMATION_FLAG = "show_sso_information".freeze

  def has_too_many_streams
    streams_count = business&.audit_log_stream_configurations&.select(:id)&.where&.not("id" => nil)&.count

    if streams_count >= MAX_AUDIT_LOG_STREAMS_ALLOWED
      errors.add(:subject, "can't create another stream because the maximum limit of stream has been created")
    end
  end

  def set_idx
    first_idx_available = business&.audit_log_stream_configurations&.select(:id)&.where&.not("id" => nil)&.pluck(:idx)&.sort || []
    available_idxs = (0..MAX_AUDIT_LOG_STREAMS_ALLOWED).to_a - first_idx_available

    self.idx = available_idxs.first || MAX_AUDIT_LOG_STREAMS_ALLOWED
  end

  def as_json(*)
    {
      id: id,
      enabled: enabled,
      created_at: created_at,
      updated_at: updated_at,
      paused_at: paused_at,
      stream_type: sink.sink_type,
      stream_details: sink.sink_details
    }
  end

  # Use the configured public stream key to encrypt a token using RbNacl::Boxes::Sealed
  def self.public_encrypt_token(token)
    key = GitHub.driftwood_stream_key
    raise "driftwood stream key is not set" if key.nil?

    public_key = RbNaCl::PublicKey.new(Base64.strict_decode64(key))
    box = RbNaCl::Boxes::Sealed.from_public_key(public_key)
    encrypted_token = box.encrypt(token)
    Base64.strict_encode64(encrypted_token)
  end

  # Return a subset of streams in a format that can be directly used by the streaming Twirp API
  # in Api::Internal::Twirp::Auditlog::Streaming::V1::StreamingAPIHandler
  #
  # limit  - the number of streams to return
  # offset - the offset to start from
  #
  # The returned object will look like this:
  #
  # {
  #   "splunks": [{domain: X, port: Y, ...}, ...]
  #   "azure_hubs": [{name: X, encrypted_connstring: Y, ...}, ...],
  #   "s3_buckets": [{bucket: X, encrypted_access_key: Y, ...}, ...]
  #   "count": 100,
  #   "offset": 0
  # }
  def self.streaming_api_confs_with_offset(limit: 10, offset: 0)
    if GitHub.flipper[:audit_streaming_exclude_softdeleted].enabled?
      return self.streaming_api_confs_exclude_softdeleted(limit: limit, offset: offset)
    end

    streams
      .limit(limit)
      .offset(offset)
      .reject { |s| s.sink.nil? }
      .reject { |s| s.as_streaming_api_conf.empty? }
      .group_by { |s| s.sink.streaming_api_conf_key }
      .transform_values { |s| s.map(&:as_streaming_api_conf) }
  end

  # Return all streams in a format that can be directly used by the streaming Twirp API
  # in Api::Internal::Twirp::Auditlog::Streaming::V1::StreamingAPIHandler
  #
  # The returned object will look like this:
  #
  # {
  #   "splunks": [{domain: X, port: Y, ...}, ...]
  #   "azure_hubs": [{name: X, encrypted_connstring: Y, ...}, ...],
  #   "s3_buckets": [{bucket: X, encrypted_access_key: Y, ...}, ...]
  # }
  def self.streaming_api_confs
    if GitHub.flipper[:audit_streaming_exclude_softdeleted].enabled?
      return self.streaming_api_confs_exclude_softdeleted
    end

    streams
      .reject { |s| s.sink.nil? }
      .reject { |s| s.as_streaming_api_conf.empty? }
      .group_by { |s| s.sink.streaming_api_conf_key }
      .transform_values { |s| s.map(&:as_streaming_api_conf) }
  end

  def self.streaming_api_confs_exclude_softdeleted(limit: 0, offset: 0)
    # Fetch business ids that have a configured stream
    if limit > 0
      business_ids = self.select(:business_id).limit(limit).offset(offset).order(:business_id).map(&:business_id)
    else
      business_ids = self.select(:business_id).map(&:business_id)
    end

    # This uses default_scope in Business which excludes soft-deleted businesses.
    business_ids = Business.where(id: business_ids).select(:id).map(&:id)

    self
      .where(business_id: business_ids)
      .includes(:sink)
      .reject { |s| s.sink.nil? }
      .reject { |s| s.as_streaming_api_conf.empty? }
      .group_by { |s| s.sink.streaming_api_conf_key }
      .transform_values { |s| s.map(&:as_streaming_api_conf) }
  end

  def event_prefix
    :audit_log_streaming
  end

  def instrument_creation
    instrument :create, sink_payload
  end

  def instrument_update
    updated_attrs_audit = {}

    if saved_change_to_enabled? && !enabled && gh_staff_disabled
      updated_attrs_audit[:reason] = "Stream is paused after a failed periodical health check"
    elsif saved_change_to_enabled? && !enabled
      updated_attrs_audit[:reason] = "User initiated pause"
    elsif saved_change_to_enabled? && enabled
      updated_attrs_audit[:reason] = "User initiated resume"
    end

    instrument :update, { audit_log_stream_enabled: enabled }.merge(sink_payload).merge(updated_attrs_audit)
  end

  def instrument_destroy
    instrument :destroy, business_payload
  end

  def instrument_check(result, business)
    payload = business_payload[:business].nil? ? { business: business } : business_payload
    instrument :check, { audit_log_stream_result: result }.merge(payload)
  end

  def sink_payload
    p = business_payload
    p = p.merge(sink.event_payload) unless sink.nil?
    p
  end

  def business_payload
    {
      business: business
    }
  end

  def check_sink(business, new_sink = nil)
    sink_to_check = new_sink || sink

    if sink.input_contains_whitespaces?
      return "Zero-width spaces have been accidentally copied with your input"
    end
    msg = sink_to_check.check(business)
    instrument_check(msg, business)
    msg
  end

  def feature_flags
    flags = []
    flags << SHOW_ACTOR_IP_FLAG if business&.source_ip_disclosure_enabled?
    flags << SHOW_SSO_INFORMATION_FLAG if GitHub.flipper[:audit_sso_disclosure].enabled?(business)
    flags
  end

  def as_streaming_api_conf
    conf = {
      subject_id: business_id,
      is_disabled: !enabled?,
      feature_flags: feature_flags,
      paused_at: Google::Protobuf::Timestamp.new(seconds: paused_at.to_i),
      is_gh_staff_disabled: gh_staff_disabled,
      idx: idx,
    }

    if GitHub.flipper[:audit_log_streaming_add_api_events_status_in_conf].enabled?(business)
      conf[:are_api_events_enabled] = business&.api_request_events_enabled?
    else
      conf[:are_api_events_enabled] = true
    end
    if !business&.audit_log_multiple_streaming_endpoint_enabled? && conf[:idx] != 0
      return {}
    end

    sink.as_streaming_api_conf.merge(conf)
  end

  def is_gh_staff_disabled
    !enabled? && gh_staff_disabled
  end

  def is_stream_paused_for_more_than_1_week?
    paused_at&.before?(1.week.ago)
  end

  def is_stream_clear
    paused_at&.before?(3.weeks.ago)
  end
end
