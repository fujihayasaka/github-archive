# typed: false
# frozen_string_literal: true

class Repository
  # this module overrides and expands upon Configurable::AnonymousGitAccess
  module AnonymousGitAccess
    extend ActiveSupport::Concern

    include Configurable::AnonymousGitAccess

    FORK_ERROR = "Forked repositories cannot change anonymous Git access.".freeze
    LOCKED_ERROR = "Anonymous Git access is locked for this repository.".freeze

    class Error < StandardError; end

    included do
      scope :with_anonymous_git_access, -> {
        if GitHub.anonymous_git_access_enabled?
          ids_with_anon_git_access = Configuration::Entry.targeting_repositories
            .named(Configurable::AnonymousGitAccess::KEY)
            .with_true_value
            .pluck(:target_id)

          public_active_repos_with_public_active_root = public_scope.active.joins(network: :root).
            where(roots_repository_networks: { public: true, active: true })

          public_active_repos_with_public_active_root.where(roots_repository_networks: { id: ids_with_anon_git_access })
        else
          Repository.default_scoped.none
        end
      }
    end

    def enable_anonymous_git_access(actor)
      raise Error, FORK_ERROR if fork?
      raise Error, LOCKED_ERROR if anonymous_git_access_locked?(actor)

      super(actor)
    end

    def disable_anonymous_git_access(actor)
      raise Error, FORK_ERROR if fork?
      raise Error, LOCKED_ERROR if anonymous_git_access_locked?(actor)

      super(actor)
    end

    # Determine whether anonymous git access is allowed on this repository
    # For anonymous git access to be enabled on a repository it must be enabled
    # for both the global (GitHub) and local (Repository) configurable properties
    def anonymous_git_access_enabled?
      return false unless anonymous_git_access_available?

      # forks use the roots configuration value
      return root.anonymous_git_access_enabled? if fork?

      # verify the configuration is enabled locally on this repository
      super && !!config.local?(Configurable::AnonymousGitAccess::KEY)
    end

    # Determine whether the anonymous git access feature is available for this repository
    def anonymous_git_access_available?
      # anonymous git access is only available for public repositories
      # when the setting is enabled globally
      GitHub.anonymous_git_access_enabled? && public?
    end

    private

    # Instrument anonymous git access changes
    #
    # type - the event type
    # actor - the User changing the access level
    #
    # Returns: nothing
    def instrument_anonymous_git_access(type, actor)
      payload = {
        actor: actor,
        repo: self,
        prefix: "repo.config",
      }

      payload[:org] = organization if in_organization?
      instrument type, payload
    end
  end
end
