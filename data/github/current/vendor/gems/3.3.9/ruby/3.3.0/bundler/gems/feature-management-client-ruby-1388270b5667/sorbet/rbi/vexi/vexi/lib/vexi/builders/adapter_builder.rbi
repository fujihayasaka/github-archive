# frozen_string_literal: true
# typed: strict

module Vexi
  module Builders
    class AdapterBuilder
      extend T::Sig

      sig { params(config: Configuration).void }
      def initialize(config)
        @config = T.let(config, Configuration)
      end

      sig { params(hmac_key: String, url: String).returns(Adapter) }
      def monolith_optimized_feature_flag_data_from_url(hmac_key, url); end

      sig { params(conn: Faraday::Connection).returns(Adapter) }
      def monolith_optimized_feature_flag_data_from_connection(conn); end

      sig { params(hmac_key: String).returns(Adapter) }
      def monolith_optimized_feature_flag_data_from_env(hmac_key); end

      sig { params(adapter: Adapter).void }
      def custom(adapter); end

      sig { params(mode: Integer, exception_feature_flags: T::Array[String]).void }
      def in_memory(mode, exception_feature_flags: []); end

      sig { params(feature_flag_base_path: String, segments_base_path: String).void }
      def file(feature_flag_base_path, segments_base_path); end
    end
  end
end
