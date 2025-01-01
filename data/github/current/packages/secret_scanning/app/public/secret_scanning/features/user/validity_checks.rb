# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::User
  # We do not currently support any option for a user to enable validity checks
  # across all of their user-owned repos.
  # The only way that a user-owned repo can have this feature enabled is if:
  # - The user is an EMU and the business has enabled validity checks, or
  # - The user is on GHES and the business has enabled validity checks
  class ValidityChecks
    include SecretScanning::Features::EnterpriseManagedUsersHelper
    include SecretScanning::Features::FeatureFlagHelper

    CONFIG_KEY_ENABLED_FOR_NEW_REPOS = "token_scanning_validity_checks.new_repos_enable"

    sig { params(user: User).void }
    def initialize(user)
      @user = user
    end

    sig { returns(T::Boolean) }
    def feature_available?
      false
    end

    sig { returns(T::Boolean) }
    def enabled?
      false
    end

    sig { returns(T::Boolean) }
    def enabled_by_enterprise?
      business = get_business_for_user(@user)
      return false if business.nil?
      business_settings = SecretScanning::Features::Business::ValidityChecks.new(business)
      business_settings.enabled?
    end

    sig { params(actor: User).void }
    def enable(actor:)
    end

    sig { params(actor: User).void }
    def disable(actor:)
    end

    # Indicates whether automatic repository opt-in is enabled for this business
    sig { returns(T::Boolean) }
    def enabled_for_new_repos?
      return false unless self.feature_available?

      @user.config.enabled?(CONFIG_KEY_ENABLED_FOR_NEW_REPOS)
    end

    # Enable automatic repository opt-in
    sig { params(actor: User).void }
    def enable_for_new_repos(actor:)
      @user.config.enable(CONFIG_KEY_ENABLED_FOR_NEW_REPOS, actor)
    end

    # Disable automatic repository opt-in
    sig { params(actor: User).void }
    def disable_for_new_repos(actor:)
      @user.config.delete(CONFIG_KEY_ENABLED_FOR_NEW_REPOS, actor)
    end

    sig { returns(T::Boolean) }
    def show_security_config_ux?
      true
    end
  end
end
