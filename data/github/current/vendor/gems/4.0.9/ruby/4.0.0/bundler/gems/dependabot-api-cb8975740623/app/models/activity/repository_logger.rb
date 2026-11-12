# frozen_string_literal: true

module Activity
  module RepoEvents
    CONFIGURATION_UPDATED = "configuration-updated"
    SECURITY_UPDATES_ENABLED = "configuration-updated.security-updates-enabled"
    SECURITY_UPDATES_DISABLED = "configuration-updated.security-updates-disabled"
    CONFIGURATION_DELETED = "configuration-deleted"
    PAUSED = "paused"
  end

  class RepositoryLogger < Activity::Logger
    attr_reader :repo

    def initialize(repo:, context_name: "repository")
      @repo = repo

      super(
        context_name: context_name,
        context: context_from_repo.merge(repo.telemetry_attributes)
      )
    end

    def context_from_repo
      {
        account_id: repo.account.id,
        repository_id: repo.id,
        repository_using_config_file: repo.using_config_file?,
        nwo: repo.nwo,
        will_pause_at: repo.will_pause_at,
        paused_at: repo.paused_at,
      }
    end
  end
end
