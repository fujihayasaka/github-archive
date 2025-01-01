# frozen_string_literal: true
# typed: strict

module Vexi
  module Adapters
    class MonolithOptimizedFeatureFlagDataAdapter
      extend T::Sig
      include Adapter

      sig { params(hmac_key: String, url: String).returns(MonolithOptimizedFeatureFlagDataAdapter) }
      def self.new_from_url(hmac_key, url); end

      sig { params(conn: Faraday::Connection).returns(MonolithOptimizedFeatureFlagDataAdapter) }
      def self.new_from_connection(conn); end

      sig { params(hmac_key: String).returns(MonolithOptimizedFeatureFlagDataAdapter) }
      def self.new_from_env(hmac_key); end

      sig { override.params(names: T::Array[String]).returns(T::Array[GetFeatureFlagResponse]) }
      def get_feature_flags(names); end

      sig { override.params(names: T::Array[String]).returns(T::Array[GetSegmentResponse]) }
      def get_segments(names); end

      sig { override.returns(String) }
      def adapter_name; end

      private

      sig { params(hmac_key: String, url: String).returns(Faraday::Connection) }
      def self.connection(hmac_key, url); end

      private_class_method :connection

      sig { returns(String) }
      def self.feature_flag_data_url; end
      private_class_method :feature_flag_data_url

      sig { params(client: FFDV2::MonolithOptimizedChecksClient).void }
      def initialize(client); end

      sig { params(response: T::Hash[Symbol, T.untyped]).returns(FeatureFlag) }
      def convert_feature_flag_response(response); end

      sig { params(response: T::Hash[Symbol, T.untyped]).returns(Segment) }
      def convert_segment_response(response); end

      sig { params(data: T::Hash[Symbol, T.untyped]).returns(T::Hash[String, FeatureFlag]) }
      def create_feature_flags_found_hash(data); end

      sig { params(data: T::Hash[Symbol, T.untyped]).returns(T::Hash[String, Segment]) }
      def create_segments_found_hash(data); end
    end
  end
end
