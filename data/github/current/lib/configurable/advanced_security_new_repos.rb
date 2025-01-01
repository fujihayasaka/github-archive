# typed: strict
# frozen_string_literal: true

# Whether a customer has configured GitHub Advanced Security to be
# enabled on new repos created on this org.
module Configurable
  module AdvancedSecurityNewRepos
    extend T::Sig
    include Kernel

    NEW_REPOS_ENABLED_KEY = "advanced_security.new_repos"

    sig { params(actor: T.nilable(T.any(User, Organization))).void }
    def enable_advanced_security_on_new_repos(actor:)
      T.bind(self, T.any(User, Organization))
      raise "Cannot enable advanced security on new repos for non organization owners" unless self.organization?

      if config.enable(NEW_REPOS_ENABLED_KEY, actor)
        self.instrument("advanced_security_enabled_for_new_repos", actor: actor)
      end
    end

    sig { params(actor: T.nilable(T.any(User, Organization))).void }
    def disable_advanced_security_on_new_repos(actor:)
      T.bind(self, T.any(User, Organization))
      raise "Cannot disable advanced security on new repos for non organization owners" unless self.organization?

      if config.delete(NEW_REPOS_ENABLED_KEY, actor)
        self.instrument("advanced_security_disabled_for_new_repos", actor: actor)
      end
    end

    # Indicates whether Advanced Security has been configured to be enabled on new repos in this org.
    # Considers whether advanced security has been purchased but doesn't consider
    # differences between Cloud/GHES for public repos
    sig { returns(T::Boolean) }
    def advanced_security_enabled_on_new_repos?
      T.bind(self, T.any(User, Organization))
      return false unless advanced_security_purchased?

      if self.organization?
        config.enabled?(NEW_REPOS_ENABLED_KEY)
      elsif self.user?
        ghas_for_users = ::AdvancedSecurity::Features::User::AdvancedSecurity.new(self)
        return false unless ghas_for_users.feature_available?

        business = self.enterprise_managed_business
        business ||= GitHub.global_business if GitHub.single_business_environment?

        business&.advanced_security_enabled_on_new_user_namespace_repos? == true
      else
        false
      end
    end
  end
end
