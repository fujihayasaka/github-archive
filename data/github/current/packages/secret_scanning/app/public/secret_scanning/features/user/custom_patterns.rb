# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning::Features::User
  class CustomPatterns
    extend T::Sig
    include SecretScanning::Features::FeatureFlagHelper

    sig { params(user: User).void }
    def initialize(user)
      @user = user
    end

    # Indicate whether the feature is enabled for this user
    sig { returns(T::Boolean) }
    def feature_available?
      false
    end
  end
end
