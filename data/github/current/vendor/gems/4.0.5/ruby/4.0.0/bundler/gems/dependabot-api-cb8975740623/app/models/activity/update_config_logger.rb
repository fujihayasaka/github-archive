# frozen_string_literal: true

module Activity
  module UpdateConfigEvents
    MANUAL_VERSION_UPDATE_REQUESTED = "manual-version-update-requested"
    MANUAL_SECURITY_UPDATE_REQUESTED = "manual-security-update-requested"
    CREATE_SCHEDULED_JOB_SKIPPED = "create-scheduled-job.skipped"
  end

  class UpdateConfigLogger < Activity::Logger
    attr_reader :update_config

    def initialize(update_config:, context_name: "update_config")
      @update_config = update_config

      super(
        context_name: context_name,
        context: context_from_update_config.merge(update_config.telemetry_attributes)
      )
    end

    def context_from_update_config
      context_from_repository.merge(
        {
          update_config_version_updates_enabled: update_config.version_updates_enabled?,
        }
      )
    end

    private

    def context_from_repository
      Activity::RepositoryLogger.new(repo: update_config.repo).context_from_repo
    end
  end
end
