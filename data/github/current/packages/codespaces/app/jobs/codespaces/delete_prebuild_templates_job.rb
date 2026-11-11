# typed: true
# frozen_string_literal: true

module Codespaces
  # Deletes vscs prebuild templates
  class DeletePrebuildTemplatesJob < CodespacesJob
    locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
    retry_on_dirty_exit

    # todo: delete repository and require repository_id instead
    def perform(branch:, locations:, repository_id:, vscs_target: Codespaces::Vscs.default_target, vscs_target_url: nil, devcontainer_path: nil, configuration_id: nil, multi_dev_container_enabled: true)
      with_write do
        Codespaces::DeletePrebuildTemplates.call(
          branch: branch,
          locations: locations,
          repository_id: repository_id,
          vscs_target: vscs_target,
          vscs_target_url: vscs_target_url,
          devcontainer_path: devcontainer_path,
          configuration_id: configuration_id
        )
      end

    rescue Aqueduct::Worker::JobKilled => e
      GitHub.dogstats.increment("codespaces.delete_prebuild_templates_job.dirty_exit", tags: stats_tags)
      raise
    end

    def stats_tags
      vscs_target = arguments.first&.fetch(:vscs_target, Codespaces::Vscs.default_target)
      Codespaces::StatsTagger.new(vscs_target: vscs_target).datadog_tags
    end
  end
end
