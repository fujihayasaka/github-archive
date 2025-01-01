# typed: true
# frozen_string_literal: true

module Configurable
  module CodespacesRepositoryAuthorization
    extend T::Helpers
    extend Configurable::Async

    requires_ancestor { Configurable }
    requires_ancestor { Kernel }

    class InvalidCodespacesRepositoryAuthorizationConfigType < ArgumentError; end

    KEY = "codespaces_repository_authorization"

    ALL_REPOSITORIES      = "all_repositories"
    SELECTED_REPOSITORIES = "selected_repositories"

    CONFIG_TYPES = [ALL_REPOSITORIES, SELECTED_REPOSITORIES]

    def codespaces_repository_authorization
      # For backwards compatibility, we need to check the old gpg_authorization setting.
      # Under the new feature flag, we only have ENABLED and DISABLED as options, so we
      # treat all other options as ENABLED.
      legacy_setting = config.get(Configurable::GpgAuthorization::KEY)
      if legacy_setting == Configurable::GpgAuthorization::ALL_REPOSITORIES
        return ALL_REPOSITORIES
      end
      if legacy_setting == Configurable::GpgAuthorization::SELECTED_REPOSITORIES
        return SELECTED_REPOSITORIES
      end
      value = config.get(KEY)
      return SELECTED_REPOSITORIES unless value
      value
    end

    def update_codespaces_repository_authorization(repository_authorization, force = false, actor:)
      raise InvalidCodespacesRepositoryAuthorizationConfigType unless CONFIG_TYPES.include?(repository_authorization)

      config.set!(KEY, repository_authorization, actor, force)
      CodespacesFlushSettingsSyncJob.perform_later(user: actor)
      # If the feature flag is enabled we can remove old gpg setting referring to all_repositories or selected_repositories.
      if config.get(Configurable::GpgAuthorization::KEY) == ALL_REPOSITORIES || config.get(Configurable::GpgAuthorization::KEY) == SELECTED_REPOSITORIES
        config.delete(Configurable::GpgAuthorization::KEY)
      end
    end
  end
end
