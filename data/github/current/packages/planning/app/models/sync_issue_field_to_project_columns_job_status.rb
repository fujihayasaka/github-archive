# typed: strict
# frozen_string_literal: true

# This is a custom job status that we use to track the behaviour of `SyncIssueFieldToProjectColumnsJob`.
#
# Job statuses created via this class are given a special ID that allows us to subsequently retrieve job statuses
# that were created for a particular issue field.
#
# USAGE:
#
#   issue_field = IssueField.find(123)
#   status = SyncIssueFieldToProjectColumnsJobStatus.create(issue_field.id)
#   status.context = { deleted_columns: 1, skipped_columns: 8, updated_columns: 1, reconciled_columns: 2, total_columns: 10 }
#   status.success!
class SyncIssueFieldToProjectColumnsJobStatus < Memex::JobStatus
  JOB_STATUS_ID_PREFIX = T.let("sync-issue-field-to-project-columns", String)
  OVERALL_TTL = T.let(3.days, ActiveSupport::Duration)
  DEFAULT_COMPLETED_JOB_TTL = T.let(1.hour, ActiveSupport::Duration)

  # This is a static type that should be used to control the value assigned
  # to the `context` key provided by the `JobStatus::Context` module.
  class Context < T::Struct

    # ID of the issue field that this job status is associated with.
    prop :issue_field_id, Integer

    # The time at which the resync process started.
    prop :started_at, T.nilable(String)

    # The total number of memex project columns that were deleted because the issue field was destroyed
    prop :deleted_columns, Integer, default: 0

    # The number of memex project columns that were skipped because they were already consistent with the issue field
    prop :skipped_columns, Integer, default: 0

    # The total number of memex project columns that were updated to reflect changes in the issue field
    prop :updated_columns, Integer, default: 0

    # The number of memex project columns that were changed (updated or deleted) because that representation differed from the issue field
    prop :reconciled_columns, Integer, default: 0

    # The total number of columns that the job checked for consistency with the issue field.
    prop :total_columns, Integer, default: 0

    # The total number of errors returned during sync operations.
    prop :total_errors, Integer, default: 0

    # Serializes this object to a Hash.
    sig { returns(T::Hash[Symbol, Integer]) }
    def to_h
      { issue_field_id:, started_at:, deleted_columns:, skipped_columns:, updated_columns:, reconciled_columns:, total_columns:, total_errors: }
    end

    # Creates an instance of this object from a hash.
    sig { params(hash: T.nilable(T::Hash[T.untyped, T.untyped])).returns(T.nilable(Context)) }
    def self.from_h(hash)
      if hash.present?
        self.new(
          hash.with_indifferent_access.slice(
            :issue_field_id,
            :started_at,
            :deleted_columns,
            :skipped_columns,
            :updated_columns,
            :reconciled_columns,
            :total_columns,
            :total_errors
          )
        )
      end
    end
  end

  # Hide the initializer; callers should use `create` factory instead.
  private_class_method :new

  # Overrides the base `create` method to ensure that we use our custom ID format.
  sig do
    override
      .params(issue_field_id: Integer, attributes: T::Hash[Symbol, T.untyped])
      .returns(SyncIssueFieldToProjectColumnsJobStatus)
  end
  def self.create(issue_field_id, attributes = {})
    super(attributes.merge(default_attributes(issue_field_id)))
  end

  # Returns the ID prefix that is shared by all job statuses created for the given issue field.
  #
  # USAGE:
  #
  #   issue_field = IssueField.find(123)
  #   prefix = SyncIssueFieldToProjectColumnsJobStatus.single_issue_field_id_prefix(issue_field.id)
  #   job_statuses = SyncIssueFieldToProjectColumnsJobStatus.find_prefix(prefix)
  sig { params(issue_field_id: Integer).returns(String) }
  def self.single_issue_field_id_prefix(issue_field_id)
    [JOB_STATUS_ID_PREFIX, issue_field_id].join(":")
  end

  # Returns the ID prefix that is shared by all job statuses created across all issue fields.
  #
  # USAGE:
  #
  #   global_prefix = SyncIssueFieldToProjectColumnsJobStatus.global_issue_field_id_prefix
  #   job_statuses = SyncIssueFieldToProjectColumnsJobStatus.find_prefix(global_prefix)
  sig { returns(String) }
  def self.global_issue_field_id_prefix
    JOB_STATUS_ID_PREFIX
  end

  # Returns attributes that are used to initialize new instances of this class.
  sig { params(issue_field_id: Integer).returns(T::Hash[Symbol, T.untyped]) }
  private_class_method def self.default_attributes(issue_field_id)
    {
      id: id(issue_field_id),
      ttl: OVERALL_TTL,
    }
  end

  # Returns a custom ID for the job status.
  #
  # This custom format is designed to allow us to retrieve the latest job status
  # for a particular issue field, or to retrieve all available job statuses across
  # issue fields. Both of those use cases can be achieved with the `JobStatus.find_prefix`
  # method.
  sig { params(issue_field_id: Integer).returns(String) }
  private_class_method def self.id(issue_field_id)
    [single_issue_field_id_prefix(issue_field_id), SecureRandom.hex(8)].join(":")
  end

  # Overrides the Memex::JobStatus#handles_id? method so that
  # the listed jobs get their statuses looked up via this class
  # instead of the base `Memex::JobStatus` class.
  sig { params(id: String).returns(T::Boolean) }
  def self.handles_id?(id)
    id.start_with?(JOB_STATUS_ID_PREFIX)
  end
end
