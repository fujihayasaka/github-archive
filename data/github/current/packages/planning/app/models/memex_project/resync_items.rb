# typed: strict
# frozen_string_literal: true

class MemexProject
  class ResyncItems
    extend T::Sig

    class JobStatusError < StandardError; end

    sig do
      params(
        project_ids: T::Array[Integer],
        enable_beta_flag: T.nilable(T::Boolean),
        read_only: T.nilable(T::Boolean),
      )
      .returns(T::Array[Integer])
    end
    def self.resync_later(project_ids, enable_beta_flag: nil, read_only: nil)
      project_ids.each_with_object([]) do |project_id, failed_ids|
        begin
          new(project_id, enable_beta_flag:, read_only:).resync_later
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

    sig { returns(T.nilable(T::Boolean)) }
    attr_reader :enable_beta_flag

    sig { returns(T.nilable(T::Boolean)) }
    attr_reader :read_only

    sig do
      params(
        project_id: Integer,
        enable_beta_flag: T.nilable(T::Boolean),
        read_only: T.nilable(T::Boolean),
      ).void
    end
    def initialize(project_id, enable_beta_flag: nil, read_only: nil)
      @project_id = project_id
      @enable_beta_flag = enable_beta_flag
      @read_only = read_only
    end

    # Queues a job which will resync the Elasticsearch index for a single project's items.
    # Returns a JobStatus so that the progress of the job can be monitored.
    sig { returns(ResyncMemexProjectItemsIndexJobStatus) }
    def resync_later
      job_status = ResyncMemexProjectItemsIndexJobStatus.create(project_id)
      raise JobStatusError.new("No job status reported.") if job_status.blank?
      raise JobStatusError.new(job_status.error_message) if job_status.error?

      ResyncMemexProjectItemsIndexJob.perform_later(project_id, job_status.id, enable_beta_flag:, read_only:)
      job_status
    end
  end
end
