# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module CloudEnvironments
  module IStatsTagger
    extend T::Sig
    extend T::Helpers
    interface!

    sig { abstract.returns(T::Array[String]) }
    def datadog_tags; end

    sig { abstract.returns(T::Hash[Symbol, T.any(Integer, String, T::Boolean)]) }
    def all_tags; end

    sig { abstract.returns(T::Hash[Symbol, T.any(Integer, String, T::Boolean)]) }
    def all_semconv_tags; end
  end
end
