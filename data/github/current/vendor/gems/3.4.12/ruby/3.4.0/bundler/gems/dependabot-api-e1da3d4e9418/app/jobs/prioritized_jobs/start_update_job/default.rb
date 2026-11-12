# frozen_string_literal: true

require "github_helpers"

module PrioritizedJobs
  module StartUpdateJob
    class Default < ApplicationJob
      queue_as do
        :actions_dynamic_workflow_p2
      end

      class RepoSyncInstallationError < StandardError; end

      # Retry over the next 2.5 hours, with exponential backoff
      T.unsafe(self).include ActiveJob::Retry.new(
        strategy: RateLimitBackoffStrategy.new(
          limit: 10,
          retryable_exceptions: [
            *GitHubHelpers::RETRYABLE_ERRORS,
            Excon::Error::Server,
            Excon::Error::Socket,
            Excon::Error::TooManyRequests,
            Octokit::Unauthorized,
            RepoSyncInstallationError,
          ],
        ),
        callback: proc do |exception, _|
          log_failure_to_start("UpdateJob raised retryable exception", exception)
          update_job.increment_metric("update_job.repo_sync_error.retry") if exception.is_a?(RepoSyncInstallationError)
        end,
      )

      # TODO: Cleanly transition AWS jobs to processed_with_errors as well when they fail out
      rescue_from(StandardError) { |error| handle_error(error) }

      rescue_from(RepoSyncInstallationError) do |_error|
        update_job.cancel!(reason: "repo_sync_installation_error")
      end

      default_retries_for_idempotent_jobs do |job_with_no_more_retries, error|
        job_with_no_more_retries.handle_error(error)
      end

      attr_reader :update_job, :repo_settings

      def perform(update_job)
        @update_job = update_job
        @repo_settings = nil

        return update_job.cancel!(reason: "disabled_ecosystem") if ecosystem_disabled?
        return update_job.cancel!(reason: "inactive_config") if inactive_config?

        # Update any details we're storing on our side from GitHub. Usefully,
        # making this request also gets an installation token from GitHub and
        # caches it, meaning the UpdateJobSerializerPrivate class can use that
        # cached value when it is requested by the updater.
        result = synchronize_repo_state
        if result.success?
          @repo_settings = result.repo_settings
          update_job.set_runner_type(repository_settings: result.repo_settings)
          update_job.save!
          start_update_job
        elsif result.intermittent_failure?
          raise RepoSyncInstallationError, result.reason
        else
          update_job.cancel!(reason: result.reason)
        end
      rescue Statesman::TransitionFailedError => e
        handle_transition_error(e)
      end

      def handle_error(error)
        raise unless update_job.actions?

        HandleActionsRunnerFailure.new(update_job: update_job, error: error).run
      end

      private

      def ecosystem_disabled?
        repo.feature_enabled?("disable_#{update_job.package_manager}_jobs")
      end

      def inactive_config?
        !repo.account.active? || (!update_job.update_config.active? && !update_job.pull_request_transition)
      end

      def synchronize_repo_state
        SynchronizeRepoState.new(
          repo: repo,
          event_source: "job.start_update",
        ).run
      rescue Octokit::TooManyRequests
        raise unless update_job.config_feature_enabled?("spammy")

        SynchronizeRepoState::SynchronizeRepoStateResult.error(reason: "spammy_rate_limited")
      end

      def start_update_job
        token_data = GenerateJobCredTokens.new.run
        hashed_job_token = token_data[:external_job_token][:hashed_token]
        hashed_cred_token = token_data[:external_cred_token][:hashed_token]

        update_job.transition_to!(
          :enqueued,
          hashed_token: hashed_job_token,
          hashed_credentials_token: hashed_cred_token,
        )

        dispatch_updater
      end

      def dispatch_updater
        runner_settings = extract_runner_settings_hash
        RunUpdater::Actions.new(update_job, runner_settings).run
      rescue StandardError => e
        # In the event RunUpdater raises an error, we must roll back to pending so
        # any retries are able move the job forward to enqueued again with new tokens
        update_job.transition_to!(:pending)
        log_failure_to_start("UpdateJob failed to start", e)
        raise
      end

      def repo
        @repo ||= update_job.update_config.repo
      end

      # Extract runner settings into a serializable hash for passing through ActiveJob
      def extract_runner_settings_hash
        repo_settings&.dependabot_runner_settings&.to_h
      end

      # TODO: Remove / Refine
      #
      # This is potentially contributing to jobs being stuck in processing,
      # by adding a transaction rollback when going from pending > enqueued
      # and enqueuing the job on line 94, we can likely be more confident
      # this doesn't happen.
      #
      # Consider using an early return to fast-fail cases where worker attempts
      # to pick up a job in a completed state and raise for an in progress state?
      def handle_transition_error(error)
        case error.from
        when "enqueued", "processing", "processed", "processed_with_errors"
          # Job is already in a later state
          nil
        else
          raise error
        end
      end

      def log_failure_to_start(msg, error)
        Dependabot::Logger.error(
          msg: msg,
          "code.namespace": self.class.name.to_s,
          "exception.type": error.class,
          "exception.message": error.message,
          **update_job.telemetry_attributes,
        )
      end
    end
  end
end
