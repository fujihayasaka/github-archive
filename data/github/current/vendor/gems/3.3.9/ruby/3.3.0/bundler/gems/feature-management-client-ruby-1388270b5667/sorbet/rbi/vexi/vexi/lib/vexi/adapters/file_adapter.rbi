# frozen_string_literal: true
# typed: strict

module Vexi
  module Adapters
    # Public: File adapter for Vexi.
    class FileAdapter
      include Adapter

      sig { returns(String) }
      attr_reader :feature_flag_base_path

      sig { returns(String) }
      attr_reader :segments_base_path

      sig { params(feature_flag_base_path: String, segments_base_path: String).void }
      def initialize(feature_flag_base_path, segments_base_path); end

      sig { override.params(names: T::Array[String]).returns(T::Array[GetFeatureFlagResponse]) }
      def get_feature_flags(names); end

      sig { override.params(names: T::Array[String]).returns(T::Array[GetSegmentResponse]) }
      def get_segments(names); end

      sig { override.returns(String) }
      def adapter_name; end

      sig { params(name: String).returns(Segment) }
      def load_segment(name); end

      sig { params(feature_flag: FeatureFlag).void }
      def create(feature_flag); end

      sig { params(name: T.any(String, Symbol)).returns(T.nilable(FeatureFlag)) }
      def get_feature_flag(name); end

      sig { params(name: T.any(String, Symbol)).void }
      def delete(name); end

      sig { params(name: T.any(String, Symbol)).void }
      def enable(name); end

      sig { params(name: T.any(String, Symbol)).void }
      def disable(name); end

      sig { params(name: T.any(String, Symbol), actor: T.any(String, Actor)).void }
      def add_actor(name, actor); end

      sig { params(name: T.any(String, Symbol), actor: T.any(String, Actor)).void }
      def remove_actor(name, actor); end

      sig { params(name: T.any(String, Symbol), percentage: Float).void }
      def enable_percentage_of_actors(name, percentage); end

      sig { params(name: T.any(String, Symbol), percentage: Float).void }
      def enable_percentage_of_calls(name, percentage); end

      sig { params(name: T.any(String, Symbol), custom_gate: String).void }
      def add_custom_gate(name, custom_gate); end

      sig { params(name: T.any(String, Symbol), custom_gate: String).void }
      def remove_custom_gate(name, custom_gate); end

      private

      sig { params(name: String).returns(FeatureFlag) }
      def load_feature_flag(name); end

      sig { params(name: T.any(String, Symbol)).returns(String) }
      def feature_flag_file_path(name); end

      sig { params(feature_flag: FeatureFlag).void }
      def write_feature_flag(feature_flag); end
    end
  end
end
