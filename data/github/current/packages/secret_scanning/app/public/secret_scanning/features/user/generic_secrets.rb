# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning::Features::User
  # We don't support Generic Secrets on User-owned repos, this feature always returns false
  class GenericSecrets
    extend T::Sig

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
  end
end
