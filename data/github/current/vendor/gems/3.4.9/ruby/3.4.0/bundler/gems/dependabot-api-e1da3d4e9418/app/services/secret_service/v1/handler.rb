# frozen_string_literal: true

module SecretService
  module V1
    class Handler
      IGNORED_STATES = %w(abandoned processed processed_with_errors timed_out).freeze

      def get_secret(req, _env)
        workflow_run_id = req.workflow_run_id
        return Twirp::Error.invalid_argument("workflow_run_id is not provided") if workflow_run_id.blank?

        update_job = UpdateJob.find_by!(actions_workflow_run_id: workflow_run_id)

        log_ignored_job_state(update_job, workflow_run_id) if ignore_job_state?(update_job)

        unless job_enqueued?(update_job)
          return Twirp::Error.failed_precondition(
            "Job is not in the enqueued state. " \
            "Current state: #{update_job.current_state}"
          )
        end

        update_job_tokens(update_job)
      rescue ActiveRecord::RecordNotFound
        log_job_not_found(workflow_run_id)
        invalid_tokens(req)
      end

      private

      def update_job_tokens(update_job)
        token_data = GenerateJobCredTokens.new.run
        external_job_token = token_data[:external_job_token][:job_token]
        hashed_job_token = token_data[:external_job_token][:hashed_token]

        external_cred_token = token_data[:external_cred_token][:cred_token]
        hashed_cred_token = token_data[:external_cred_token][:hashed_token]

        update_job.update!(
          hashed_token: hashed_job_token,
          hashed_credentials_token: hashed_cred_token,
        )

        log_updating_job_tokens(update_job, hashed_job_token, hashed_cred_token)

        {
          job_token: external_job_token,
          cred_token: external_cred_token,
        }
      end

      def job_enqueued?(update_job)
        is_enqueued = update_job.in_state?(:enqueued)
        unless is_enqueued
          # Log the current state if the job is not in the enqueued state
          Dependabot::Logger.info(
            msg: "Job is not in the enqueued state",
            "code.namespace": "SecretService::V1::Handler",
            "gh.actions.workflow_run.id": update_job.actions_workflow_run_id,
            "job.id": update_job.id,
            "job.state": update_job.current_state
          )
        end
        is_enqueued
      end

      def pull_request_hashed_token(workflow_run_id)
        pull_request_id = Dependabot.redis.get("pr-actions-workflow-run-id:#{workflow_run_id}")
        pull_request = PullRequest.find_by(id: pull_request_id)
        return "invalid" unless pull_request

        tokens = GenerateJobCredTokens.new.generate_autofix_token
        pull_request.hashed_token = tokens[:hashed_token]
        tokens[:pr_token]
      end

      def ignore_job_state?(update_job)
        IGNORED_STATES.include?(update_job.current_state)
      end

      def log_ignored_job_state(update_job, workflow_run_id)
        Dependabot::Logger.info(
          msg: "Ignoring job due to its state",
          "code.namespace": "SecretService::V1::Handler",
          "gh.actions.workflow_run.id": workflow_run_id,
          "job.id": update_job.id,
          "job.state": update_job.current_state,
          detail: "Job is not in the enqueued state to be processed."
        )
      end

      def log_updating_job_tokens(update_job, hashed_job_token, hashed_cred_token)
        Dependabot::Logger.info(
          msg: "Updating job tokens",
          "code.namespace": "SecretService::V1::Handler",
          "gh.actions.workflow_run.id": update_job.actions_workflow_run_id,
          "job.id": update_job.id,
          saved_job_token_hash: hashed_job_token&.then { |v| Digest::SHA256.hexdigest(v)[0, 12] },
          saved_cred_token_hash: hashed_cred_token&.then { |v| Digest::SHA256.hexdigest(v)[0, 12] }
        )
      end

      def invalid_tokens(req)
        {
          job_token: Prius.get(:dependabot_autofix_npm_token),
          cred_token: pull_request_hashed_token(req.workflow_run_id),
        }
      end

      def log_job_not_found(workflow_run_id)
        Dependabot::Logger.info(
          msg: "UpdateJob not found",
          "code.namespace": "SecretService::V1::Handler",
          "gh.actions.workflow_run.id": workflow_run_id
        )
      end
    end
  end
end
