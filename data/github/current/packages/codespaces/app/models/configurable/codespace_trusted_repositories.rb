# typed: true
# frozen_string_literal: true

module Configurable

  module CodespaceTrustedRepositories
    extend T::Helpers
    extend Configurable::Async

    requires_ancestor { Configurable }
    requires_ancestor { Kernel }

    class InvalidRepoAccessArgumentError < ArgumentError; end

    KEY = "codespace_trusted_repositories_access"

    ALL_REPOS = "all"
    SELECTED_REPOS = "selected"
    DISABLED = "disabled"

    ACCESS_TYPES = [ALL_REPOS, SELECTED_REPOS, DISABLED]

    def codespace_trusted_repositories_access
      config.get(KEY) || DISABLED
    end

    # Allow organization codespaces by ensuring that the allowed key is present.
    def update_codespace_trusted_repositories_access(access, force = false, actor:)
      old_access = codespace_trusted_repositories_access
      raise InvalidRepoAccessArgumentError unless ACCESS_TYPES.include?(access)

      changed = config.set!(KEY, access, actor, force)
      return unless changed

      GitHub.dogstats.increment("codespaces.trusted_repositories_access_updated")

      accessor = case self
      when Organization
        { org: self, business: (self.business if self.business) }
      when User
        { user: self }
      else
        {}
      end

      GitHub.instrument(
        "codespaces.trusted_repositories_access_update", {
          new_access: access,
          old_access: old_access,
        }.merge(accessor)
      )
    end
  end
end
