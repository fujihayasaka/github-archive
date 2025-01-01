# typed: true
# frozen_string_literal: true

module Codespaces
  class CreatePrebuildTemplateDynamicWorkflowJob < CodespacesJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
    locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC

    def perform(repository:, branch:, locations:, commit_sha:, concurrency_modifier:, devcontainer_path: nil, vscs_target: Codespaces::Vscs.default_target, vscs_target_url: nil, configuration: nil, previous_sha: nil)
      return if repository.blank? || repository.deleted?

      if configuration.present? && configuration&.trigger.to_sym == :configuration && previous_sha.present?
        # only trigger template creation if prebuild hash changed
        unless Codespaces::Prebuilds.prebuild_hash_change?(repository: repository, current_oid: commit_sha, new_oid: previous_sha, devcontainer_path: devcontainer_path)
          return
        end
      end

      # Check if usage limits have been exceeded
      return unless Codespaces::Prebuilds.prebuild_usage_allowed?(repository.owner)

      # Perform a check to see if the configuration's permissions_granted field needs to be updated
      if FeatureFlag.vexi.enabled_or_raise?(:codespaces_prebuilds_show_permissions_granted, repository) && configuration.present? # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
        with_write { update_permission_granted!(repository: repository, devcontainer_path: devcontainer_path, branch: branch, id: configuration.id) }
      end

      with_write do
        Codespaces::CreatePrebuildTemplateDynamicWorkflow.call(
          repository: repository,
          locations: locations,
          vscs_target: vscs_target,
          vscs_target_url: vscs_target_url,
          branch: branch,
          commit_sha: commit_sha,
          concurrency_modifier: concurrency_modifier,
          configuration: configuration,
          devcontainer_path: devcontainer_path,
        )
      end

    rescue Aqueduct::Worker::JobKilled => e
      GitHub.dogstats.increment("codespaces.create_prebuild_template_dynamic_workflow_job.dirty_exit", tags: stats_tags)
      raise
    rescue Codespaces::CreatePrebuildTemplateDynamicWorkflow::InvalidBranchError => e
      # This is an edge case, we can log the error but not raise it
      GitHub.dogstats.increment("codespaces.create_prebuild_template_dynamic_workflow_job.invalid_branch", tags: stats_tags)
    end

    def stats_tags
      vscs_target = arguments.first&.fetch(:vscs_target, Codespaces::Vscs.default_target)
      Codespaces::StatsTagger.new(vscs_target: vscs_target).datadog_tags
    end

    def update_permission_granted!(repository:, devcontainer_path:, branch:, id:)
      ref = repository.refs.find(branch)
      oid = ref&.target_oid
      devcontainer = Codespaces::DevContainer.new(
        repository: repository,
        oid: oid,
        filepath: devcontainer_path,
        is_prebuild: true,
      )
      permissions_diff = devcontainer.diff_all_permissions(prebuild_configuration_id: id)
      configuration = Codespaces::PrebuildConfiguration.find(id)
      configuration.update(permission_granted: !devcontainer.permissions_need_allowance?)
    end
  end
end
