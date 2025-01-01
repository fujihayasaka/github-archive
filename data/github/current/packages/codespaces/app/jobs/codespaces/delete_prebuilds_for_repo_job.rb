# typed: true
# frozen_string_literal: true

module Codespaces
  # this job will delete prebuild templates for a repository in vscs and will disable the prebuild configuration
  class DeletePrebuildsForRepoJob < CodespacesJob
    locked_by timeout: 1.hour, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC
    retry_on_dirty_exit

    BATCH_SIZE = 100

    def perform(repository_id:, disable_prebuild_configurations: true, hard_delete_configurations: false)
      with_write do
        return unless FeatureFlag.vexi.enabled_or_raise?(:codespaces_delete_prebuilds_for_repo_job) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

        configuration_ids = []
        Codespaces::PrebuildConfiguration.where(repository_id: repository_id).find_each(batch_size: BATCH_SIZE) do |configuration|
          # create list of config ids that we are cleaning up to avoid duplicate clean up for template db
          configuration_ids.push(configuration.id)

          # queue template deletion in vscs
          Codespaces::DeletePrebuildTemplatesJob.perform_later(
            branch: configuration.branch,
            locations: configuration.region_names,
            repository_id: configuration.repository_id,
            vscs_target: configuration.vscs_target,
            vscs_target_url: configuration.vscs_target_url,
            devcontainer_path: configuration.devcontainer_path,
            configuration_id: configuration.id,
          )

          # if configuration is enabled, disable it
          if configuration.enabled? && disable_prebuild_configurations
            configuration.disable
            Codespaces::PrebuildConfiguration.throttle_with_retry { configuration.save }
          end

          if hard_delete_configurations
            Codespaces::PrebuildConfiguration.throttle_with_retry { configuration.destroy }
          end
        end

        # delete templates that will not be handled by the configuration delete or old templates that don't have a configuration id stored
        template_guids = []
        Codespaces::PrebuildTemplate.where(repository_id: repository_id)
                                      .and(Codespaces::PrebuildTemplate.where(codespace_prebuild_configuration_id: nil)
                                            .or(Codespaces::PrebuildTemplate.where.not(codespace_prebuild_configuration_id: configuration_ids))
                                          ).find_each(batch_size: BATCH_SIZE) do |template|
          Codespaces::DeletePrebuildTemplatesJob.perform_later(
            branch: template.branch,
            locations: [template.location],
            repository_id: template.repository_id,
            vscs_target: template.vscs_target,
            vscs_target_url: template.vscs_target_url,
            devcontainer_path: template.devcontainer_path,
            configuration_id: template.codespace_prebuild_configuration_id,
          )

          template_guids.push(template.guid)
        end

        GitHub.logger.info(
          "prebuild clean up for repository",
          "gh.catalog_service" => "github/codespaces",
          "gh.codespaces.prebuild_configuration.ids" => configuration_ids,
          "gh.codespaces.prebuild_template.guids" => template_guids,
          "gh.repo.id" => repository_id,
        )

      rescue Aqueduct::Worker::JobKilled => e
        GitHub.dogstats.increment("codespaces.delete_prebuild_templates_for_repo_job.dirty_exit")
        raise
      end
    end
  end
end
