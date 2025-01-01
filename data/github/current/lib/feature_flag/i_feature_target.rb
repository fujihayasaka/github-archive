# typed: strict
# frozen_string_literal: true

require "vexi"

module FeatureFlag
  module IFeatureTarget
    extend T::Helpers

    include Kernel
    include Vexi::Actor

    requires_ancestor { Object }

    abstract!

    # Public: Returns the result of a feature flag check for this actor.
    #
    # feature_name - The name of the feature flag to check
    sig { abstract.params(feature_name: T.any(Symbol, String), memoize: T::Boolean).returns(T::Boolean) }
    def feature_flag_enabled_or_raise?(feature_name, memoize: true); end

    # Public: Returns the result of a feature flag check for this actor.
    #
    # feature_name - The name of the feature flag to check
    # default - The default value to return if the feature check fails
    # memoize - Whether to memoize the result of the feature flag check (default: true)
    sig { abstract.params(feature_name: T.any(Symbol, String), default: T::Boolean, memoize: T::Boolean).returns(T::Boolean) }
    def feature_flag_enabled?(feature_name, default:, memoize: true); end
  end
end
