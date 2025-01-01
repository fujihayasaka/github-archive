# typed: strict
# frozen_string_literal: true

module FeatureManagement
  class FeatureFlagHubValidationError < StandardError
    extend T::Sig

    sig { returns(T.nilable(String)) }
    attr_reader :message

    sig { params(message: T.nilable(String)).void }
    def initialize(message)
      @message = T.let(message, T.nilable(String))
    end
  end
end
