# frozen_string_literal: true

module UpdateConfigsService
  module V1
    class Handler
      def deactivate_update_configs(req, _env)
        repo = find_repo(req.repository_github_id)

        return repo_not_found_error unless repo

        repo.event_stream.record_event(Activity::RepoEvents::CONFIGURATION_DELETED,
                                       tags: { source: "update-config-service" })
        ResetConfigFileJob.perform_later(repo: repo)

        {} # We just return an empty message for success
      end

      # rubocop:disable Metrics/MethodLength
      def list_update_configs(req, _env)
        repo = find_repo(req.repository_github_id)

        unless repo
          # If the GitHub UI is making this query and it indicates a config file is present, Dependabot should
          # be set up on this repo. Let's try to remediate that so a future request will succeed. We'll do it
          # the the background here because parsing the config file to get a corrected response would be too
          # much work for this request.
          if req.config_file_exists
            RemediateAccountAndRepoActivationJob.perform_later(
              github_repo_id: req.repository_github_id,
              github_account_id: req.owner_github_id,
              event_source: "twirp.update_configs_service.list_update_configs",
            )
          end

          return repo_not_found_error
        end

        unless repo.using_config_file?
          # If the repository is not using a configuration file, any active
          # configs are either out of sync or Dependabot-internal. However, if the
          # UI has detected a config file we may have missed detecting it and should
          # retry

          if req.config_file_exists
            ResyncRepoConfigFileJob.perform_later(
              account: repo.account,
              repo_name: repo.name,
              repo_github_id: repo.github_id,
              event_source: "twirp.update_configs_service.list_update_configs",
            )
          end

          return empty_response
        end

        update_configs = active_configs(repo).map(&method(:serialize_config))

        # Update the status of update jobs run on actions
        update_last_job_status(update_configs)

        {
          config_file: {
            path: repo.config_file_path,
            error: serialize_config_error(repo.config_file_error),
          },
          update_configs: update_configs,
        }
      end
      # rubocop:enable Metrics/MethodLength

      def repository_status(req, _env)
        repo = find_repo(req.repository_github_id)

        return repo_not_found_error unless repo

        {
          repository_github_id: repo.github_id,
          using_config_file: repo.using_config_file?,
          # In future version updates may be enabled without a config file, but for now
          # this is how we distinguish from someone who is using an ephemeral Security Update
          # config.
          version_updates_enabled: repo.using_config_file? && repo.active?,
          paused: repo.paused_at?,
        }
      end

      def resync_config_file(req, _env)
        repo = find_repo(req.repository_github_id)

        # If the GitHub UI is making this query, it thinks Dependabot should be set up on this repo.
        # Let's try to remediate that so this request will succeed. We'll do it inline here so we can
        # return an error if something prevents the activation.
        repo ||= remediate_repo_activation(
          github_repo_id: req.repository_github_id,
          github_account_id: req.owner_github_id,
          event_source: "twirp.update_configs_service.resync_config_file",
        )

        return Twirp::Error.failed_precondition("Repository is not registered with the service.") unless repo

        ResyncRepoConfigFileJob.perform_later(
          account: repo.account,
          repo_name: repo.name,
          repo_github_id: repo.github_id,
          event_source: "twirp.update_configs_service.resync_config_file",
        )

        {} # We just return an empty message for success
      end

      def trigger_update_job(req, _env)
        repo = find_repo(req.repository_github_id)
        return repo_not_found_error unless repo

        update_config = repo.active_update_configs.scheduled.find_by(
          id: req.update_config_id
        )
        return update_config_not_found_error unless update_config

        # Even if we do not run a new update, we should still record that it was requested
        update_config.event_stream.record_event(Activity::UpdateConfigEvents::MANUAL_VERSION_UPDATE_REQUESTED,
                                                tags: { source: "update-config-service" })

        return last_scheduled_job_for(update_config) if last_scheduled_job_is_running(update_config)
        return last_scheduled_job_for(update_config) if update_config.recently_triggered_scheduled_update_job?

        job = start_update_job(update_config)
        { update_job: serialize_job(job) }
      end

      private

      def last_scheduled_job_is_running(update_config)
        return false unless update_config.repo.config_feature_enabled?(:last_scheduled_job_still_running)

        job = update_config.last_scheduled_job
        return false unless job

        !job.completed? && !job.expired?
      end

      def update_last_job_status(update_configs)
        update_configs.each do |update_config|
          next unless !update_config.dig(:last_full_update_run, :finished_at) && \
                      update_config.dig(:last_full_update_run, :actions_workflow_run_id)

          UpdateJobActionsStatusJob.perform_later(
            update_job_id: update_config.dig(:last_full_update_run, :id)
          )
        end
      end

      def find_repo(github_id)
        Repo.find_by(github_id: github_id)
      end

      def repo_not_found_error
        Twirp::Error.not_found("Repository ID not found.")
      end

      def update_config_not_found_error
        Twirp::Error.not_found("UpdateConfig ID not found.")
      end

      def last_scheduled_job_for(update_config)
        { update_job: serialize_job(update_config.last_scheduled_job) }
      end

      def empty_response
        {
          update_configs: [],
        }
      end

      def active_configs(repo)
        active_scheduled_configs = repo.active_update_configs.scheduled.includes(
          :update_config_transitions,
          last_scheduled_job: %i(update_job_transitions update_job_errors)
        ).limit(Repo::MAXIMUM_CONFIGS_ALLOWED)
        active_scheduled_configs.select(&:version_updates_enabled?)
      end

      def serialize_config(update_config)
        UpdateConfigsService::V1::UpdateConfigSerializer.new(update_config).to_h
      end

      def serialize_job(update_job)
        UpdateConfigsService::V1::UpdateJobStatusSerializer.new(update_job).to_h
      end

      def serialize_config_error(config_file_error)
        return unless config_file_error

        UpdateConfigsService::V1::ErrorSerializer.new(config_file_error).to_h
      end

      def start_update_job(update_config)
        job = UpdateJob.create!(
          update_config_id: update_config.id,
          trigger_type: :manual_version_update
        )

        PrioritizedJobs::StartUpdateJob.perform_later(job)
        RefreshOpenGroupPullRequestsJob.perform_later(update_config: update_config)

        job
      end

      def remediate_repo_activation(github_repo_id:, github_account_id:, event_source:)
        return unless github_account_id&.nonzero?

        RemediateAccountAndRepoActivation.new(
          github_repo_id: github_repo_id,
          github_account_id: github_account_id,
          event_source: event_source,
        ).run
      rescue RemediateAccountAndRepoActivation::RepoNotAccessible
        nil
      end
    end
  end
end
