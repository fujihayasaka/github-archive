# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::User
  # We do not currently support any option for a user to enable lower confidence patterns
  # (AKA non-provider patterns) across all of their user-owned repos.
  # The only way that a user-owned repo can have this feature enabled is if:
  # - The user is an EMU and the business has enabled lower confidence patterns, or
  # - The user is on GHES and the business has enabled lower confidence patterns
  class LowerConfidencePatterns
    extend T::Sig
    include SecretScanning::Features::EnterpriseManagedUsersHelper

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
      business_settings = SecretScanning::Features::Business::LowerConfidencePatterns.new(business)
      business_settings.enabled?
    end

    sig { params(actor: User).void }
    def enable(actor:)
    end

    sig { params(actor: User).void }
    def disable(actor:)
    end

    sig { returns(T::Boolean) }
    def enabled_by_owner?
      false
    end

    # Indicates whether automatic repository opt-in is enabled for this business
    sig { returns(T::Boolean) }
    def enabled_for_new_repos?
      false
    end

    # Enable automatic repository opt-in
    sig { params(actor: User).void }
    def enable_for_new_repos(actor:)
    end

    # Disable automatic repository opt-in
    sig { params(actor: User).void }
    def disable_for_new_repos(actor:)
    end

    sig { returns(T::Boolean) }
    def show_security_config_ux?
      false
    end
  end
end
