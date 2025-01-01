# typed: strict
# frozen_string_literal: true

module FeatureManagement
  class FeatureFlagHubClientError < StandardError
    sig { returns(Symbol) }
    attr_reader :code

    sig { returns(T.nilable(String)) }
    attr_reader :message

    sig { returns(T::Hash[String, String]) }
    attr_reader :metadata

    sig { params(code: Symbol, message: T.nilable(String), metadata: T::Hash[String, String]).void }
    def initialize(code, message, metadata = {})
      @code = T.let(code, Symbol)
      @message = T.let(message, T.nilable(String))
      @metadata = T.let(metadata, T::Hash[String, String])
    end
  end
end
