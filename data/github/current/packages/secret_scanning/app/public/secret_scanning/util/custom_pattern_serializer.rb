# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Util
    # Serializer for custom patterns to ensure API responses match OpenAPI schema
    # and don't expose unintended fields from protobuf evolution.
    module CustomPatternSerializer
      sig { params(pattern: T.any(GitHub::Proto::SecretScanning::Api::V2::SecretScanCustomPattern, GitHub::Proto::SecretScanning::Api::V3::SecretScanCustomPattern)).returns(T::Hash[Symbol, T.untyped]) }
      def self.serialize_api(pattern)
        result = {
          id: pattern.id,
          name: pattern.display_name,
          pattern: pattern.expression,
          slug: pattern.slug,
          state: pattern.state.to_s.downcase,
          push_protection_enabled: pattern.push_protection_enabled,
          custom_pattern_version: pattern.row_version.presence,
          created_at: format_timestamp(pattern.created_at),
          updated_at: format_timestamp(pattern.updated_at),
        }

        # Post-processing fields (flat, not nested per ADR)
        pp = pattern.post_processing
        if pp
          result[:start_delimiter] = pp.start_delimiter
          result[:end_delimiter] = pp.end_delimiter
          result[:must_match] = pp.must_match.to_a
          result[:must_not_match] = pp.must_not_match.to_a
        end

        result
      end

      sig { params(patterns: T::Array[GitHub::Proto::SecretScanning::Api::V3::SecretScanCustomPattern]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def self.serialize_api_list(patterns)
        patterns.map { |p| serialize_api(p) }
      end

      sig { params(timestamp: T.nilable(Google::Protobuf::Timestamp)).returns(T.nilable(String)) }
      def self.format_timestamp(timestamp)
        return nil if timestamp.nil?
        # Protobuf timestamps have seconds and nanos
        Time.at(timestamp.seconds, timestamp.nanos, :nsec).utc.iso8601
      end

      private_class_method :format_timestamp
    end
  end
end
