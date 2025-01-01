# typed: true
# frozen_string_literal: true

# This class is used to track the completion status of a background job.
# That status can then be consumed via the JobsController#show action.
#
# This class typically transitions between states like so:
#
#              ┌─────────┐
#              │ PENDING │
#              └────┬────┘
#                   │
#                   ▼
#              ┌─────────┐
#              │ QUEUED  │
#              └────┬────┘
#                   │
#                   ▼
#              ┌─────────┐
#              │ STARTED │
#              └──┬───┬──┘
#                 │   │
#    ┌─────────┐  │   │  ┌───────┐
#    │ SUCCESS │◄─┘   └─►│ ERROR │
#    └─────────┘         └───────┘
#
# Job statuses are ephemeral. By default:
#   - Statuses expire three minutes after they transition to `success` or `error`. This can adjusted with the `ttl`
#     parameter on the `success!` and `error!` methods.
#   - Statuses expire after 7 days regardless of state. This can be adjusted via the `ttl` attribute passed to either
#     the `create` method or the initializer.
#
# You can store your own information in the job status class by extending it with the `JobStatus::Context` mixin:
#
#   class CustomJobStatus < JobStatus
#     include JobStatus::Context
#   end
#
# USAGE:
#
#   status = JobStatus.create # status = pending
#   status.started!
#   status.success!
#
#   retrieved_status = JobStatus.find(status.id)
#   retrieved_status.success? # => true
#
class JobStatus

  class NotFound < RuntimeError; end

  CACHE_KEY_PREFIX = "jobs:status:"
  MAX_ID_LENGTH = 255

  def self.max_custom_id_length
    MAX_ID_LENGTH - CACHE_KEY_PREFIX.length
  end

  def self.throttle(&block)
    ApplicationRecord::Domain::KeyValues.throttle(&block)
  end

  DEFAULT_OVERALL_TTL = 7.days
  DEFAULT_COMPLETED_JOB_TTL = 3.minutes

  def self.kv_store
    GitHub.kv # rubocop:todo GitHub/RequireDedicatedKV
  end

  def self.find(id, meta: {})
    json = kv_store.get(cache_key(id)).value!
    return nil unless json
    self.new(JSON.parse(json, { symbolize_names: true }))
  end

  def self.find_many(ids)
    return [] if ids.empty?

    json_array = kv_store.mget(ids.map { |id| cache_key(id) }).value!
    json_array.map do |json|
      next nil unless json
      self.new(JSON.parse(json, { symbolize_names: true }))
    end
  end

  def self.find_prefix(prefix)
    json_hash = kv_store.mget_prefix(cache_key(prefix)).value!
    json_hash.map do |_key, json|
      next nil unless json
      self.new(JSON.parse(json, { symbolize_names: true }))
    end
  end

  def self.find!(id)
    found = find(id)
    if !found
      raise JobStatus::NotFound, "job status id not found in memcache: #{id}"
    end
    found
  end

  def self.create(attributes = {})
    status = new(attributes)
    status.save
    status
  end

  STATES = %w[pending queued started success error].freeze

  attr_reader :id, :state, :error_message, :store

  def initialize(attributes = {})
    attributes = attributes.with_indifferent_access
    @id = attributes[:id] || SecureRandom.uuid
    @state = attributes[:state] || "pending"
    raise "bad state" if !STATES.include?(@state)

    self.ttl = attributes[:ttl] if attributes.key?(:ttl)
    @error_message = attributes[:error_message]
    @store = self.class.kv_store
  end

  def is_subscription?
    false
  end

  def ttl=(value)
    # String#to_i has a habit of returning 0 for non-integers. We don't want to make any mistakes
    # so let's use the Integer method instead.
    @ttl = Integer(value)
  end

  def ttl
    @ttl || DEFAULT_OVERALL_TTL
  end

  def save
    expires_at = Time.now + ttl
    with_write { store.set(cache_key, to_json, expires: expires_at) }
  end

  def destroy
    with_write { store.del(cache_key) }
  end

  sig { params(ttl: ActiveSupport::Duration).void }
  private def expire(ttl:)
    with_write { store.set(cache_key, to_json, expires: ttl.from_now) }
  end

  def pending?
    state == "pending"
  end

  def queued?
    state == "queued"
  end

  def started?
    state == "started"
  end

  def success?
    state == "success"
  end

  def error?
    state == "error"
  end

  def finished?
    %w[success error].include?(@state)
  end

  def queued!
    @state = "queued"
    save
  end

  def started!
    @state = "started"
    save
  end

  # Mark the job as successful.
  #
  # This also updates the expiration time of this object such that it expires after the given delay.
  #
  # @params ttl The delay after which this job status will expire.
  sig { params(ttl: ActiveSupport::Duration).void }
  def success!(ttl: DEFAULT_COMPLETED_JOB_TTL)
    @state = "success"
    expire(ttl:)
  end

  # Mark the job as failed.
  #
  # This also updates the expiration time of this object such that it expires after the given delay.
  #
  # @params message Optional error message to set on the job status.
  # @params ttl The delay after which this job status will expire.
  sig { params(message: T.nilable(String), ttl: ActiveSupport::Duration).void }
  def error!(message = nil, ttl: DEFAULT_COMPLETED_JOB_TTL)
    @state = "error"
    @error_message = message
    expire(ttl:)
  end

  def to_json
    as_json.to_json
  end

  def as_json
    {
      id: id,
      state: state,
      ttl: ttl,
      error_message: error_message,
    }
  end

  # Track the progress of the block. Ensures that the job status is updated
  # regardless of how the block finishes.
  #
  # Yields to the given block to complete that job.
  #
  # Returns nothing.
  def track
    started!
    yield
    success!
  rescue => boom # rubocop:todo Lint/GenericRescue
    error!(boom.message)
    raise boom
  end

  def readable_by?(actor)
    false
  end

  private

  def cache_key
    self.class.send(:cache_key, id)
  end

  def with_write(&block)
    ActiveRecord::Base.connected_to(role: :writing, &block)
  end

  def self.cache_key(id)
    "#{CACHE_KEY_PREFIX}#{id}"
  end
  private_class_method :cache_key
end
