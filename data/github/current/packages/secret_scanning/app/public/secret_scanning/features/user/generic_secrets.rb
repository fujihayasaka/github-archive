# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning::Features::User
  # We don't support Generic Secrets on User-owned repos, this feature always returns false
  class GenericSecrets
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
