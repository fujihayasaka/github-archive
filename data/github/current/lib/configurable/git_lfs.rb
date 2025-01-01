# typed: true
# frozen_string_literal: true

module Configurable
  module GitLfs
    def enable_git_lfs(actor)
      if GitHub.git_lfs_enabled
        config.delete(KEY, actor)
        config.delete(OLDKEY, actor)
      else
        config.enable(KEY, actor)
      end
    end

    def disable_git_lfs(actor)
      config.disable(OLDKEY, actor) unless GitHub.git_lfs_enabled
      config.disable(KEY, actor)
    end

    def git_lfs_config_enabled?
      if GitHub.git_lfs_enabled
        config.get(Configurable::GitLfs::KEY) != false
      else
        config.enabled?(Configurable::GitLfs::KEY) || config.enabled?(Configurable::GitLfs::OLDKEY)
      end
    end

    def can_enable_lfs_in_archives?
      git_lfs_config_enabled? && !GitHub.enterprise?
    end

    def lfs_in_archives_enabled?
      return false unless can_enable_lfs_in_archives?
      config.enabled?(Configurable::GitLfs::ARCHIVE_KEY)
    end

    def enable_lfs_in_archives(actor)
      config.enable(ARCHIVE_KEY, actor)

      if GitHub.elm_internal_webhooks_enabled?
        GitHub.instrument("repo.archive_settings_update", {
          actor: actor,
          repo: self,
          changes: {
            git_lfs_enabled: true
          }
        })
      end
    end

    def disable_lfs_in_archives(actor)
      config.disable(ARCHIVE_KEY, actor)

      if GitHub.elm_internal_webhooks_enabled?
        GitHub.instrument("repo.archive_settings_update", {
          actor: actor,
          repo: self,
          changes: {
            git_lfs_enabled: false
          }
        })
      end
    end

    # Public: Gets the current setting for the timeout
    #
    # Returns Integer
    def lfs_integrity_check_timeout
      config.get(TIMEOUT_KEY).try(:to_i) || 0
    end

    # Public: set the LFS integrity check timeout for the repository
    #
    # Returns nothing
    def set_lfs_integrity_check_timeout(value, actor)
      v = value.to_i
      if v == 0
        config.delete(TIMEOUT_KEY, actor)
      else
        config.set!(TIMEOUT_KEY, v, actor)
      end
    end

    KEY = "git-lfs".freeze
    OLDKEY = "git-media".freeze
    ARCHIVE_KEY = "git-lfs-in-archives".freeze
    TIMEOUT_KEY = "git-lfs-integrity-check-timeout".freeze
  end
end
