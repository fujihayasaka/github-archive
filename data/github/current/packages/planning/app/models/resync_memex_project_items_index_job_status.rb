# typed: strict
# frozen_string_literal: true

# This is a custom job status that we use to track the behaviour of `ResyncMemexProjectItemsIndexJob`.
#
# Job statuses created via this class are given a special ID that allows us to subsequently retrieve job statuses
# that were created for a particular project. Additionally, this class stores the raw data that we use in
# `ReportMemexProjectItemsIndexConsistencyMetricJob` to compute a data consistency score for the Elasticsearch
# index that stores project items.
#
# USAGE:
#
#   project = MemexProject.find(123)
#   status = ResyncMemexProjectItemsIndexJobStatus.create(project.id)
#   status.context = { reconciled_items: 2, total_items: 10 }
#   status.success!
class ResyncMemexProjectItemsIndexJobStatus < JobStatus
  extend T::Sig
  include JobStatus::Context

  JOB_STATUS_ID_PREFIX = T.let("resync-memex-project-items-index", String)
  OVERALL_TTL = T.let(3.days, ActiveSupport::Duration)
  COMPLETED_JOB_TTL = T.let(1.hour, ActiveSupport::Duration)

  # This is a static type that should be used to control the value assigned
  # to the `context` key provided by the `JobStatus::Context` module.
  class Context < T::Struct
    extend T::Sig

    # ID of the project that this job status is associated with.
    prop :memex_project_id, Integer

    # The time at which the resync process started.
    prop :started_at, T.nilable(String)

    # The number of items that were updated in Elasticsearch because that representation differed from the
    # canonical representation of that item (e.g. the data for that item stored in MySQL).
    prop :reconciled_items, Integer, default: 0

    # The total number of items that the job checked for consistency.
    prop :total_items, Integer, default: 0

    # Serializes this object to a Hash.
    sig { returns(T::Hash[Symbol, Integer]) }
    def to_h
      { memex_project_id:, started_at:, reconciled_items: , total_items: }
    end

    # Creates an instance of this object from a hash.
    sig { params(hash: T.nilable(T::Hash[T.untyped, T.untyped])).returns(T.nilable(Context)) }
    def self.from_h(hash)
      if hash.present?
        self.new(hash.with_indifferent_access.slice(:memex_project_id, :started_at, :reconciled_items, :total_items))
      end
    end
  end

  # Hide the initializer; callers should use `create` factory instead.
  private_class_method :new

  # Overrides the base `create` method to ensure that we use our custom ID format.
  sig do
    override
      .params(memex_project_id: Integer, attributes: T::Hash[Symbol, T.untyped])
      .returns(ResyncMemexProjectItemsIndexJobStatus)
  end
  def self.create(memex_project_id, attributes = {})
    super(attributes.merge(default_attributes(memex_project_id)))
  end

  sig { override.params(ttl: ActiveSupport::Duration).void }
  def success!(ttl: COMPLETED_JOB_TTL)
    super
  end

  sig { override.params(message: T.nilable(String), ttl: ActiveSupport::Duration).void }
  def error!(message = nil, ttl: COMPLETED_JOB_TTL)
    super
  end

  # Returns the ID prefix that is shared by all job statuses created for the given project.
  #
  # USAGE:
  #
  #   memex_project = MemexProject.find(123)
  #   prefix = ResyncMemexProjectItemsIndexJobStatus.single_project_id_prefix(project.id)
  #   job_statuses = ResyncMemexProjectItemsIndexJobStatus.find_prefix(prefix)
  sig { params(memex_project_id: Integer).returns(String) }
  def self.single_project_id_prefix(memex_project_id)
    [JOB_STATUS_ID_PREFIX, memex_project_id].join(":")
  end

  # Returns the ID prefix that is shared by all job statuses created across all projects.
  #
  # USAGE:
  #
  #   global_prefix = ResyncMemexProjectItemsIndexJobStatus.global_project_id_prefix
  #   job_statuses = ResyncMemexProjectItemsIndexJobStatus.find_prefix(global_prefix)
  sig { returns(String) }
  def self.global_project_id_prefix
    JOB_STATUS_ID_PREFIX
  end

  # Returns attributes that are used to initialize new instances of this class.
  sig { params(memex_project_id: Integer).returns(T::Hash[Symbol, T.untyped]) }
  private_class_method def self.default_attributes(memex_project_id)
    {
      id: id(memex_project_id),
      ttl: OVERALL_TTL,
    }
  end

  # Returns a custom ID for the job status.
  #
  # This custom format is designed to allow us to retrieve the latest job status
  # for a particular project, or to retrieve all available job statuses across
  # projects. Both of those use cases can be achieved with the `JobStatus.find_prefix`
  # method.
  sig { params(memex_project_id: Integer).returns(String) }
  private_class_method def self.id(memex_project_id)
    [single_project_id_prefix(memex_project_id), SecureRandom.hex(8)].join(":")
  end
end
