# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning::Features::User
  class PushProtection
    include SecretScanning::Features::FeatureFlagHelper
    CONFIG_KEY_ENABLED_FOR_NEW_REPOS = "secret_scanning_push_protection.new_repos_enable"
    CONFIG_KEY_ENABLED_FOR_USER_ANYWHERE = "secret_scanning_push_protection.user_enable"

    sig { params(user: T.any(User, PublicKey)).void }
    def initialize(user)
      return unless user.is_a?(User)
      @user = T.let(user, User)
      @user_token_scanning = SecretScanning::Features::User::TokenScanning.new(@user)
    end

    # Indicate whether the feature is available for this user
    sig { returns(T::Boolean) }
    def feature_available?
      return false unless GitHub.configuration_secret_scanning_enabled?
      return false unless @user.respond_to?(:flipper_id)
      return true if @user_token_scanning.available_for_private_repos?
      return feature_flag_enabled?(@user, FeatureFlags::PUSH_PROTECTION_FOR_FPR) if GitHub.dotcom_request?

      false
    end

    # Indicates whether automatic repository opt-in is enabled for this user
    sig { returns(T::Boolean) }
    def enabled_for_new_repos?
      return false unless self.feature_available?
      @user.config.enabled?(CONFIG_KEY_ENABLED_FOR_NEW_REPOS)
    end

    # Enable automatic repository opt-in
    # @param actor [User]
    sig { params(actor: User).void }
    def enable_for_new_repos(actor:)
      @user.config.enable(CONFIG_KEY_ENABLED_FOR_NEW_REPOS, actor)
    end

    # Disable automatic repository opt-in
    # @param actor [User]
    sig { params(actor: User).void }
    def disable_for_new_repos(actor:)
      @user.config.delete(CONFIG_KEY_ENABLED_FOR_NEW_REPOS, actor)
    end

    # Indicates whether push protection anywhere is enabled for this user
    sig { returns(T::Boolean) }
    def enabled?
      return false unless self.feature_available?
      return true if @user.config.enabled?(CONFIG_KEY_ENABLED_FOR_USER_ANYWHERE)
      return true if GitHub.flipper[FeatureFlags::PUSH_PROTECTION_FOR_USERS_OPT_OUT].enabled?(@user) && !self.disabled? && !@user.is_a?(Bot)
      false
    end

    # Indicates whether push protection has been explicitly disabled by the user
    sig { returns(T::Boolean) }
    def disabled?
      # config check will return proper false if value is "false", if the config entry doesnt exist this will be nil and we will return false here
      @user.config.get(CONFIG_KEY_ENABLED_FOR_USER_ANYWHERE) == false
    end

    # Enable push protection anywhere for the user
    # @param actor [User]
    sig { params(actor: User).void }
    def enable(actor:)
      @user.config.enable(CONFIG_KEY_ENABLED_FOR_USER_ANYWHERE, actor)
    end

    # Disable push protection anywhere for the user
    # @param actor [User]
    sig { params(actor: User).void }
    def disable(actor:)
      @user.config.disable(CONFIG_KEY_ENABLED_FOR_USER_ANYWHERE, actor)
      PushProtectionSurvey.disabled_push_protection(actor)
    end

    # Indicates whether the user bypass experience is being used (rather than the repo bypass experience)
    sig { params(repo: Repository).returns(T::Boolean) }
    def has_user_bypass_experience?(repo)
      self.enabled? ? !SecretScanning::Features::Repo::PushProtection.new(repo).enabled? : false
    end

    # Indicates whether displaying a custom message on blocked pushes is enabled for this user
    sig { returns(T::Boolean) }
    def custom_message_enabled?
      false
    end

    def custom_message_active; end
    def enable_custom_message; end
    def disable_custom_message; end
  end
end
