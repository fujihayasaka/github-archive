# typed: true
# frozen_string_literal: true

class AuditLogAsyncQuery < ApplicationRecord::Collab

  VALID_ACTOR_TYPES = %w(User)
  AUDIT_LOG_ASYNC_QUERY_EXPIRATION = 1.hour
  AUDIT_LOG_ASYNC_QUERY_MAX_CONCURRENT_QUERIES = 3

  include Instrumentation::Model

  belongs_to :actor, class_name: "User"

  validates :actor_id,         presence: true
  validates :actor_type,       inclusion: { in: VALID_ACTOR_TYPES }
  validates :query_id,         presence: true

  before_validation :generate_query_id, on: :create
  before_validation :start_async_query, on: :create, if: -> {
    T.bind(self, AuditLogAsyncQuery)
    VALID_ACTOR_TYPES.include?(actor_type) && !has_in_progress_queries_validator
  }
  after_create :increment_create_count

  attr_accessor :phrase, :per_page, :after, :before

  class AsyncQueryrror < StandardError
  end

  # Public: fetch results of stored query
  #
  # Returns: AsyncStafftoolsAuditEntriesResponse
  def results(per_page:, after:, before:)
    raise AsyncQueryrror, "results are not available" unless is_completed?
    return @results unless @results.nil?

    options = {
      query_id: query_id,
      per_page: per_page,
      after: after,
      before: before,
      feature_flags: [],
    }

    results = Audit::Driftwood::AsyncQuery.new.fetch_results(**options)

    if !results[:warnings].empty?
      raise AsyncQueryrror, "this attempt to get the async query status failed with warnings: #{results[:warnings].join(', ')}"
    end
    results
  end

  # Public: verify whether stored query is completed
  #
  # Returns: boolean
  def is_completed?
    if T.must(created_at) < AUDIT_LOG_ASYNC_QUERY_EXPIRATION.ago
      unless completed
        ActiveRecord::Base.connected_to(role: :writing) do
          self.update_attribute(:completed, true)
        end
      end
      return true
    end

    # If completed is true there is no need to update again
    return @completed if @completed

    resp = check_remote_state
    if resp[:completed]
      ActiveRecord::Base.connected_to(role: :writing) do
        self.update_attribute(:completed, true)
      end
      @completed = resp[:completed]
    end
    resp[:completed]
  end

  def event_payload
    payload = {
      actor: actor,
      query_id: query_id,
      operation_id: operation_id,
    }

    if actor.respond_to?(:event_prefix)
      payload[T.must(actor).event_prefix] = actor
    else
      raise ArgumentError, "#{actor} does not respond to #event_prefix"
    end

    payload
  end

  def event_prefix
    T.must(actor).event_prefix
  end

  def to_param
    query_id
  end

  # Public: kick off a stored query
  #
  # Returns nothing
  def start_async_query
    async_query = Audit::Driftwood::AsyncQuery.new
    options = {
      query_id: query_id,
      phrase: phrase,
      per_page: per_page,
      after: after,
      before: before,
      feature_flags: [],
    }

    operation_details = async_query.start(**options)

    if !operation_details[:warnings].empty?
      raise AsyncQueryrror, "this attempt to start the async query failed with warnings: #{operation_details[:warnings].join(', ')}"
    end

    self.operation_id = operation_details[:operation_id]

    instrument :audit_log_async_query
  end

  private

  # Private: Check whether ther are already too many in-progress stored-queries for this user
  #
  # Returns nothing
  def has_in_progress_queries_validator
    latest_async_queries = T.must(actor)
      .audit_log_async_queries
      .where("created_at > ?", AUDIT_LOG_ASYNC_QUERY_EXPIRATION.ago)
      .where(completed: false)

    if latest_async_queries.to_a.count { |e| !e.is_completed? } >= AUDIT_LOG_ASYNC_QUERY_MAX_CONCURRENT_QUERIES
      errors.add(:actor, "can't create another async query because the maximum limit of in-progress exports has been reached")
    end
  end

  # Private: The unique token for the audit log used to identify the stored-query.
  #
  # Returns String.
  def generate_query_id
    self.query_id = SecureRandom.uuid
  end

  # Private: Query Driftwood to fetch the state of the export job
  #
  # Returns Metadata of export job
  def check_remote_state
    options = {
      operation_id: operation_id,
      feature_flags: [],
    }

    operation_status = Audit::Driftwood::AsyncQuery.new.
      check_status(**options)

    if !operation_status[:warnings].empty?
      raise AsyncQueryrror, "this attempt to get the async query status failed with warnings: #{operation_status[:warnings].join(', ')}"
    end
    operation_status
  end

  # Private: increment counter for this action
  #
  # Returns nothing
  def increment_create_count
    GitHub.dogstats.increment("audit_log_web_async_query_count", tags: ["action:create"])
  end

end
