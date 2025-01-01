# typed: strict
# frozen_string_literal: true

module FeatureFlag
  module IFeatureTarget
    extend T::Helpers

    include Kernel

    requires_ancestor { Object }

    abstract!

    sig { abstract.params(feature_name: T.any(Symbol, String), memoize: T::Boolean).returns(T::Boolean) }
    def feature_enabled?(feature_name, memoize: true); end
  end
end
