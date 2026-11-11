# typed: strict
# frozen_string_literal: true

# Tracks the progress and status of MemexBulkAddJob, allowing for resumable bulk add operations.
class MemexBatchedBulkAddJobStatus < Memex::JobStatus
  JOB_STATUS_ID_PREFIX = T.let("batched-memex-bulk-add", String)
  OVERALL_TTL = T.let(3.days, ActiveSupport::Duration)
  COMPLETED_JOB_TTL = T.let(1.hour, ActiveSupport::Duration)

  # Static type for the context hash
  class Context < T::Struct
    # The ID of the memex project this job is associated with
    prop :memex_project_id, Integer
    # The user ID performing the bulk add
    prop :user_id, Integer
    # The total number of items to add
    prop :total_items, Integer, default: 0
    # The number of items successfully added so far
    prop :added_items, Integer, default: 0
    # The number of items failed so far
    prop :failed_items, Integer, default: 0
    # Optional error message
    prop :error_message, T.nilable(String)
    # The time at which the bulk-add process started.
    prop :started_at, T.nilable(String)
    # Whether this is an initial import bulk add
    prop :initial_import, T.nilable(T::Boolean)
    # IDs of memex_project_items created during this import
    prop :created_item_ids, T::Array[Integer], default: []

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_h
      {
        memex_project_id: memex_project_id,
        user_id: user_id,
        total_items: total_items,
        added_items: added_items,
        failed_items: failed_items,
        error_message: error_message,
        initial_import: initial_import,
        created_item_ids: created_item_ids,
      }
    end

    sig { params(hash: T.nilable(T::Hash[T.untyped, T.untyped])).returns(T.nilable(Context)) }
    def self.from_h(hash)
      return unless hash.present?

      indifferent_hash = hash.with_indifferent_access
      required_keys = [:memex_project_id, :user_id]
      return if required_keys.any? { |key| indifferent_hash[key].nil? }

      self.new(
        indifferent_hash.slice(
          :memex_project_id,
          :user_id,
          :total_items,
          :added_items,
          :failed_items,
          :error_message,
          :initial_import,
          :created_item_ids,
        )
      )
    end
  end

  private_class_method :new

  sig do
    override
      .params(memex_project_id: Integer, user_id: Integer, attributes: T::Hash[Symbol, T.untyped])
      .returns(MemexBatchedBulkAddJobStatus)
  end
  def self.create(memex_project_id, user_id, attributes = {})
    super(attributes.merge(default_attributes(memex_project_id, user_id)))
  end

  sig { override.params(ttl: ActiveSupport::Duration).void }
  def success!(ttl: COMPLETED_JOB_TTL)
    super
  end

  sig { override.params(message: T.nilable(String), ttl: ActiveSupport::Duration).void }
  def error!(message = nil, ttl: COMPLETED_JOB_TTL)
    super
  end

  sig { params(memex_project_id: Integer, user_id: Integer).returns(T::Hash[Symbol, T.untyped]) }
  private_class_method def self.default_attributes(memex_project_id, user_id)
    {
      id: id(memex_project_id, user_id),
      memex_project_id: memex_project_id,
      user_id: user_id,
      total_items: 0,
      ttl: OVERALL_TTL,
    }
  end

  sig { params(memex_project_id: Integer, user_id: Integer).returns(String) }
  private_class_method def self.id(memex_project_id, user_id)
    [JOB_STATUS_ID_PREFIX, memex_project_id, user_id, SecureRandom.hex(8)].join(":")
  end

  sig { params(memex_project_id: Integer, user_id: Integer).returns(String) }
  def self.single_project_user_id_prefix(memex_project_id, user_id)
    [JOB_STATUS_ID_PREFIX, memex_project_id, user_id].join(":")
  end

  sig { returns(String) }
  def self.global_project_id_prefix
    JOB_STATUS_ID_PREFIX
  end

  sig { void }
  def mark_as_initial_import!
    self.context ||= {}
    T.must(self.context)[:initial_import] = true
    save
  end
end
