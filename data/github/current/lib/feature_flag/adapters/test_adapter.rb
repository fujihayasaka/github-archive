# typed: strict
# frozen_string_literal: true

require "vexi"
require "vexi_management"

module FeatureFlag
  module Adapters
    module TestAdapter
      extend T::Helpers
      include Vexi::Adapter
      include VexiManagement::Adapter

      requires_ancestor { Object }

      interface!

      # Adapter APIs
      # We have to define these here because we strip sorbet information from the Vexi gem, so Vexi::Adapter is empty.

      sig { abstract.params(_names: T::Array[String]).returns(T::Array[Vexi::GetFeatureFlagResponse]) }
      def get_feature_flags(_names); end

      sig { abstract.params(_names: T::Array[String]).returns(T::Array[Vexi::GetSegmentResponse]) }
      def get_segments(_names); end

      sig { abstract.returns String }
      def adapter_name; end

      # Test Adapter Specific APIs

      sig { abstract.returns(T::Array[FeatureFlag]) }
      def features; end

      sig { abstract.void }
      def reset; end
    end
  end
end
