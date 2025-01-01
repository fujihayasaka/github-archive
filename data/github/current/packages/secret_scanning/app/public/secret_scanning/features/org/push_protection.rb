# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning::Features::Org
  # Org level enablement for Push Protection
  class PushProtection
    include SecretScanning::Features::FeatureFlagHelper

    CONFIG_KEY_ENABLED_FOR_NEW_REPOS = "secret_scanning_push_protection.new_repos_enable"
    CONFIG_KEY_CUSTOM_MESSAGE_ENABLED = "secret_scanning_push_protection.custom_message_enabled"

    def initialize(org)
      raise ArgumentError, "Invalid type: expected Organization but got #{org.class.name}" if !org.is_a?(Organization)

      @org = org
      @token_scanning = SecretScanning::Features::Org::TokenScanning.new(@org)
    end

    # Indicate whether the feature is available for this organization
    #
    # @return [Boolean] true if the feature is available, false otherwise
    sig { returns(T::Boolean) }
    def feature_available?
      # the org should have the GHAS license
      return false unless @org.advanced_security_purchased? ||
        feature_flag_enabled_in_hierarchy?(@org, FeatureFlags::PUSH_PROTECTION_FOR_FPR)

      # token scanning must be available
      @token_scanning.feature_available?
    end

    # Indicates whether automatic repository opt-in is enabled for this organization
    sig { returns(T::Boolean) }
    def enabled_for_new_repos?
      return false unless self.feature_available?

      @org.config.enabled?(CONFIG_KEY_ENABLED_FOR_NEW_REPOS)
    end

    # Enable automatic repository opt-in
    # @param actor [User]
    sig { params(actor: User).void }
    def enable_for_new_repos(actor:)
      @org.config.enable(CONFIG_KEY_ENABLED_FOR_NEW_REPOS, actor)
    end

    # Disable automatic repository opt-in
    # @param actor [User]
    sig { params(actor: User).void }
    def disable_for_new_repos(actor:)
      @org.config.delete(CONFIG_KEY_ENABLED_FOR_NEW_REPOS, actor)
    end

    # Indicates whether displaying a custom message on blocked pushes is enabled for this organization
    sig { returns(T::Boolean) }
    def custom_message_enabled?
      return false unless self.feature_available?
      @org.config.enabled?(CONFIG_KEY_CUSTOM_MESSAGE_ENABLED)
    end

    # Indicates whether or not the custom message should actually be displayed.
    # Returns true if the custom message is both enabled and not empty.
    sig { returns(T::Boolean) }
    def custom_message_active?
      return false if @org.nil?
      msg = @org.get_push_protection_custom_message
      self.custom_message_enabled? && !msg.nil? && !msg.empty?
    end

    # Enables displaying a custom message on blocked pushes for this organization
    # @param actor [User]
    sig { params(actor: User).void }
    def enable_custom_message(actor:)
      @org.config.enable(CONFIG_KEY_CUSTOM_MESSAGE_ENABLED, actor)
    end

    # Disables displaying a custom message on blocked pushes for this organization
    # @param actor [User]
    sig { params(actor: User).void }
    def disable_custom_message(actor:)
      @org.config.delete(CONFIG_KEY_CUSTOM_MESSAGE_ENABLED, actor)
    end
  end
end
