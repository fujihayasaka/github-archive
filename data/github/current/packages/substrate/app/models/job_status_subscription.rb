# typed: true
# frozen_string_literal: true

class JobStatusSubscription < JobStatus
  ALLOWED_SUBCLASSES = {
    "" => "JobStatusSubscription",
    "i" => "Issues::JobStatusSubscription",
  }

  CACHE_KEY_PREFIX = "jobs:status:subcription:"

  MisformattedId = Class.new(ArgumentError)

  attr_reader :id, :state, :error_message, :percentage, :execution_errors, :user_id, :parent_global_relay_id, :job_id, :updated_at, :completed_item_ids

  def initialize(attributes = {})
    super(attributes)
    @percentage = attributes[:percentage] || 0
    @completed_item_ids = attributes[:completed_item_ids] || []
    @execution_errors = attributes[:execution_errors] || []
    @user_id = attributes[:user_id]
    @job_id = attributes[:job_id]
    @updated_at = attributes[:updated_at] || Time.now
    @parent_global_relay_id = attributes[:parent_global_relay_id]
    if @user_id.nil? || @parent_global_relay_id.nil?
      raise ArgumentError, "user_id and parent_global_relay_id are required"
    end
  end

  def is_subscription?
    true
  end

  def self.create(attributes = {})
    status = new(attributes)
    status.save
    status
  end

  def set_job_id(job_id)
    @job_id = job_id
    save
  end

  def set_percentage(percentage)
    @percentage = percentage
    save
  end

  def set_percentage_and_error(percentage, global_relay_id, error_msg)
    @percentage = percentage
    execution_errors << { node_id: global_relay_id, message: error_msg }
    save
  end

  def add_completed_item_id(db_id)
    completed_item_ids << db_id
    save(should_trigger_subscription: false)
  end

  def add_execution_error(global_relay_id, error_msg)
    execution_errors << { node_id: global_relay_id, message: error_msg }
    save(should_trigger_subscription: false)
  end

  def success!
    @state = "success"
    @percentage = 100
    expire(ttl: DEFAULT_COMPLETED_JOB_TTL)
  end

  def self.find(id)
    splitted_id = id.split(":")
    klass_name = ALLOWED_SUBCLASSES[splitted_id[0]]

    return klass_name.safe_constantize.find(id) if splitted_id.size != 1 && !klass_name.nil?

    json = self.kv_store.get(cache_key(id)).value!

    return nil unless json
    data = JSON.parse(json, { symbolize_names: true })
    self.new(data)
  end

  sig { override.params(ttl: ActiveSupport::Duration).void }
  private def expire(ttl:)
    super
    trigger_subscription
  end

  def save(should_trigger_subscription: true)
    @updated_at = Time.now
    write_to_cache
    if should_trigger_subscription
      trigger_subscription
    end
  end

  def as_json
    {
      id: id,
      state: state,
      percentage: percentage,
      completed_item_ids: completed_item_ids,
      ttl: ttl,
      error_message: error_message,
      execution_errors: execution_errors,
      user_id: user_id,
      parent_global_relay_id: parent_global_relay_id,
      job_id: job_id,
      updated_at: updated_at
    }
  end

  def write_to_cache
    expires_at = Time.now + ttl
    with_write { @store.set(cache_key, to_json, expires: expires_at) }
  end

  def trigger_subscription
    Platform::Schema.subscriptions.trigger(:job_status_updated, {
      id: id
    })
  end

  def self.kv_store
    JobStatus::KV.store
  end

  def cache_key
    self.class.send(:cache_key, id)
  end

  def self.cache_key(id)
    "#{CACHE_KEY_PREFIX}#{id}"
  end

  def self.handles_id?(id)
    id.start_with?(CACHE_KEY_PREFIX)
  end

  def readable_by?(actor)
    return false unless actor.instance_of?(User)
    @user_id == actor.id
  end

  def self.id_prefix
    ALLOWED_SUBCLASSES.find { |_prefix, klass_name| klass_name == self.name }.first
  end

  def self.validate_id(id)
    raise MisformattedId, "ID must start with '#{id_prefix}'" unless id.starts_with?(id_prefix)
  end

  def validate_id(id)
    self.class.validate_id(id)
  end
end
