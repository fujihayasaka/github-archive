# typed: true
# frozen_string_literal: true

module Codespaces
  class UpdatePrebuildTemplateVersionsJob < CodespacesJob
    locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    def perform(
      prebuild_configuration_id:,
      repository:,
      location:,
      vscs_target: Codespaces::Vscs.default_target
    )
      Codespaces::UpdatePrebuildTemplateVersions.call(
        prebuild_configuration_id: prebuild_configuration_id,
        location: location
      )

    rescue Aqueduct::Worker::JobKilled => e
      GitHub.dogstats.increment("codespaces.update_prebuild_template_versions_job.dirty_exit", tags: stats_tags)
      raise
    end

    def stats_tags
      location = arguments.first&.fetch(:location)
      vscs_target = arguments.first&.fetch(:vscs_target, Codespaces::Vscs.default_target)
      Codespaces::StatsTagger.new(location: location, vscs_target: vscs_target).datadog_tags
    end
  end
end
