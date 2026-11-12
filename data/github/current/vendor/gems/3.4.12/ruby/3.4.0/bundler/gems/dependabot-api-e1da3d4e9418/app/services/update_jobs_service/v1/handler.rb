# frozen_string_literal: true

module UpdateJobsService
  module V1
    class Handler
      def list_jobs(req, _env)
        repo = Repo.find_by(github_id: req.repository_github_id)
        return Twirp::Error.not_found("Repository ID not found.") unless repo

        update_config = repo.update_configs.find_by(id: req.update_config_id)
        return Twirp::Error.not_found("UpdateConfig ID not found.") unless update_config

        forteen_days_ago = Time.current - 14.days
        jobs = UpdateJob.where(
          update_config_id: update_config.id,
          created_at: forteen_days_ago...,
        ).limit(100).order(created_at: :desc)

        jobs = jobs.reject(&:graph?)

        {
          update_config: serialize_config(update_config),
          update_jobs: safe_serialize(jobs),
        }
      end

      def get_job_status(req, _env)
        repo = Repo.find_by(github_id: req.repository_github_id)

        return Twirp::Error.not_found("Repository ID not found.") unless repo

        update_job = repo.update_jobs.find_by(id: req.update_job_id)
        return Twirp::Error.not_found("Job ID not found.") unless update_job

        # TODO: If completed, return the Pull Request GitHub ID
        {
          update_job: serialize_job_status(update_job),
        }
      end

      def get_job_status_by_github_request_id(req, _env)
        repo = find_repo(req.repository_github_id)

        return Twirp::Error.not_found("Repository ID not found.") unless repo

        update_job = repo.update_jobs.
                     find_by(github_request_id: req.github_request_id)

        return Twirp::Error.not_found("Job not found.") unless update_job

        {
          update_job: serialize_job_status(update_job),
        }
      end

      def get_job_logs(req, _env)
        repo = find_repo(req.repository_github_id)

        return Twirp::Error.not_found("Repository ID not found.") unless repo

        update_job = find_update_job(repo, req.update_job_id)

        return Twirp::Error.not_found("Job ID not found.") unless update_job

        {
          update_job: serialize_job_status(update_job),
          update_job_logs: serialize_logs(update_job),
        }
      end

      def get_job_logs_by_github_request_id(req, _env)
        repo = find_repo(req.repository_github_id)

        return Twirp::Error.not_found("Repository ID not found.") unless repo

        update_job = repo.update_jobs.
                     find_by(github_request_id: req.github_request_id)

        return Twirp::Error.not_found("Job not found.") unless update_job

        {
          update_job: serialize_job_status(update_job),
          update_job_logs: serialize_logs(update_job),
        }
      end

      def get_job_errors(req, _env)
        return Twirp::Error.invalid_argument("update_job_ids cannot be empty") if req.update_job_ids.empty?

        repo = find_repo(req.repository_github_id)

        return Twirp::Error.not_found("Repository ID not found.") unless repo

        update_jobs = repo.update_jobs.includes(:update_job_errors).where(id: req.update_job_ids.to_a)
        update_jobs_with_errors = update_jobs.map do |job|
          next unless job.update_job_errors.any?

          serialize_job_status(job)
        end.compact

        {
          update_jobs_with_errors: update_jobs_with_errors,
        }
      end

      private

      def find_repo(github_id)
        Repo.find_by(github_id: github_id)
      end

      def find_update_job(repo, update_job_id)
        repo.update_jobs.find_by(id: update_job_id)
      end

      def serialize_job(update_job)
        UpdateConfigsService::V1::UpdateJobSerializer.new(update_job).to_h
      end

      def serialize_config(update_config)
        UpdateConfigsService::V1::UpdateConfigSerializer.new(update_config).to_h
      end

      def serialize_job_status(update_job)
        UpdateConfigsService::V1::UpdateJobStatusSerializer.new(update_job).to_h
      end

      def serialize_logs(update_job)
        UpdateJobLogs.new(update_job).user_readable
      end

      def safe_serialize(jobs)
        jobs.map do |job|
          serialize_job(job)
        rescue StandardError => e
          Dependabot::Logger.info(
            msg: "Failed to serialize UpdateJob",
            "code.namespace": "UpdateJobService::V1::Handler",
            "exception.type": e.class.to_s,
            "exception.message": e.message,
            **job.telemetry_attributes,
          )
          nil
        end.compact
      end
    end
  end
end
