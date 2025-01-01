# typed: true
# frozen_string_literal: true

# A fix to allow anonymous access to specific repositories in GHE when
# private mode is enabled (making public repositories effectively "internal")
module Configurable
  module AnonymousGitAccess
    extend T::Helpers

    requires_ancestor { Configurable }

    KEY = "anonymous_git_access".freeze

    def enable_anonymous_git_access(actor)
      return unless config.enable(KEY, actor)
      instrument_anonymous_git_access(:enable_anonymous_git_access, actor)
    end

    def disable_anonymous_git_access(actor)
      return unless config.delete(KEY, actor)
      instrument_anonymous_git_access(:disable_anonymous_git_access, actor)
    end

    # Determine whether anonymous git access is allowed
    def anonymous_git_access_enabled?
      return false unless GitHub.anonymous_git_access_available?
      config.enabled?(KEY)
    end

    private

    # Instrument anonymous git access changes
    #
    # type - the event type
    # actor - the User changing the access level
    #
    # Returns: nothing
    def instrument_anonymous_git_access(type, actor)
      GitHub.instrument("enterprise.config.#{type}", { actor: actor })
    end
  end
end
