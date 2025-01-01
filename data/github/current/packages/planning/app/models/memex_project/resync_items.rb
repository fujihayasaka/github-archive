# typed: strict
# frozen_string_literal: true

class MemexProject
  class ResyncItems

    class JobStatusError < StandardError; end

    sig do
      params(
        project_ids: T::Array[Integer],
        indices: T::Array[Elastomer::Indexes::MemexProjectItems],
        enable_beta_flag: T.nilable(T::Boolean),
        read_only: T.nilable(T::Boolean),
      )
      .returns(T::Array[Integer])
    end
    def self.resync_later(project_ids, indices: Elastomer::Indexes::MemexProjectItems.writable_indices, enable_beta_flag: nil, read_only: nil)
      project_ids.each_with_object([]) do |project_id, failed_ids|
        begin
          new(project_id, indices:, enable_beta_flag:, read_only:).resync_later
        rescue => error # rubocop:todo Lint/GenericRescue
          failed_ids << project_id

          GitHub.logger.info("Could not enqueue resync job for project", {
            "code.namespace": name,
            "code.function": "resync_later",
            "gh.memex.project_id": project_id,
            "exception.message": error.message,
            "exception.stacktrace": error.backtrace,
            "exception.type": error.class.name
          }.compact)
        end
      end
    end

    sig { returns(Integer) }
    attr_reader :project_id

    sig { returns(T::Array[Elastomer::Indexes::MemexProjectItems]) }
    attr_reader :indices

    sig { returns(T.nilable(T::Boolean)) }
    attr_reader :enable_beta_flag

    sig { returns(T.nilable(T::Boolean)) }
    attr_reader :read_only

    sig do
      params(
        project_id: Integer,
        indices: T::Array[Elastomer::Indexes::MemexProjectItems],
        enable_beta_flag: T.nilable(T::Boolean),
        read_only: T.nilable(T::Boolean),
      ).void
    end
    def initialize(project_id, indices: Elastomer::Indexes::MemexProjectItems.writable_indices, enable_beta_flag: nil, read_only: nil)
      @project_id = project_id
      @indices = indices
      @enable_beta_flag = enable_beta_flag
      @read_only = read_only
    end

    # Queues jobs which will resync each Elasticsearch index for a single project's items.
    #
    # Returns the JobStatus of the resync for the primary Elasticsearch index so that the progress of the job
    # can be monitored.
    sig { returns(T.nilable(ResyncMemexProjectItemsIndexJobStatus)) }
    def resync_later
      primary_job_status = T.let(nil, T.nilable(ResyncMemexProjectItemsIndexJobStatus))

      indices.each do |index|
        job_status = ResyncMemexProjectItemsIndexJobStatus.create(project_id)
        raise JobStatusError.new("No job status reported.") if job_status.blank?
        raise JobStatusError.new(job_status.error_message) if job_status.error?

        ResyncMemexProjectItemsIndexJob.perform_later(
          project_id,
          job_status.id,
          index_name: index.name,
          enable_beta_flag:,
          read_only:,
        )

        primary_job_status = job_status if index.primary?
      end

      primary_job_status
    end
  end
end
