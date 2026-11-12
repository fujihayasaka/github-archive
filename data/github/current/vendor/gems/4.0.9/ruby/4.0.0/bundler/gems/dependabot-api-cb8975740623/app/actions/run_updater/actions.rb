# frozen_string_literal: true

module RunUpdater
  # Executes an UpdateJob using a GitHub Actions' Dynamic Workflow
  class Actions
    def initialize(job, runner_settings = nil)
      @job = job
      @runner_settings = runner_settings
    end

    def run
      repo = job.update_config.repo

      Dependabot::Logger.info(
        msg: "Dependabot Action dispatch",
        "code.namespace": "RunUpdater::Actions",
        **job.telemetry_attributes,
      )
      response = if repo.monolith_feature_enabled?(:dependabot_use_internal_dynamic_workflow_endpoint)
                   hmac_key = Prius.get(:api_internal_actions_dynamic_workflows_hmac_client_key)
                   client = GitHubHelpers::ClientWithRetries.new(account: repo.account, hmac_key: hmac_key)
                   client.post("internal/repositories/#{repo.github_id}/actions/dynamic",
                               workflow_args.merge(prevent_reruns: true))
                 else
                   client = GitHubHelpers::ClientWithRetries.new(account: repo.account)
                   client.post("repositories/#{repo.github_id}/actions/dynamic", workflow_args)
                 end
      job.update!(actions_external_id: response[:execution_id], actions_workflow_run_id: response[:workflow_run_id])
    end

    private

    attr_reader :job

    def workflow_args
      {
        workflow: workflow.to_yaml,
        ref: ref,
        inputs: inputs,
        workflow_name: workflow.workflow_name,
        slug: workflow.slug,
      }
    end

    def ref
      # Workflow ref must be a branch (`find_ref!` rejects raw SHAs).
      job.update_config.target_branch || job.update_config.repo.default_branch
    end

    def inputs
      payload = {
        jobId: job.id.to_s,
        dependabotApiUrl: Dependabot::Application.dependabot_actions_api_endpoint(job.repo.account),
        workingDirectory: workflow.update_job_dir,
      }

      unless job.config_feature_enabled?(:ghes_mode) # rubocop:disable Dependabot/NoLocalFeatureFlags
        payload[:updaterImage] = UpdaterVersion.find_by(
          env: job.runner_environment,
          ecosystem: ParseConfigFile.token_for(package_manager: job.package_manager)
        )&.actions_image.to_s
      end

      payload
    end

    def workflow
      @workflow ||= RunUpdater::Actions::Workflow.new(update_job: job, runner_settings: @runner_settings)
    end
  end
end
