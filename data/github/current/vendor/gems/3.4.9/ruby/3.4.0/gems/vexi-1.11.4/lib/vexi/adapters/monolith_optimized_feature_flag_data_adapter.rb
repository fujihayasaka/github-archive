# frozen_string_literal: true
#              


require "vexi/adapter"
require "vexi/array_actor_collection"
require "vexi/errors"
require "feature_management_feature_flags"

FFDV2 = FeatureManagement::FeatureFlags::Data::V2

module Vexi
  module Adapters
    class MonolithOptimizedFeatureFlagDataAdapter
      include Adapter
      DEFAULT_TIMEOUT = 1.0 # seconds
      DEFAULT_OPEN_TIMEOUT = 1.0 # seconds
      DEFAULT_MAX_RETRIES = 3

      def self.new_from_url(hmac_key, url)
        ffd_connection = connection(hmac_key, url)
        client =      (
          FFDV2::MonolithOptimizedChecksClient.new(ffd_connection)                                      
        )
        new(client)
      end

      def self.new_from_connection(conn)
        client =      (
          FFDV2::MonolithOptimizedChecksClient.new(conn)                                      
        )
        new(client)
      end

      def self.new_from_env(hmac_key)
        ffd_connection = connection(hmac_key, feature_flag_data_url)
        client =      (
          FFDV2::MonolithOptimizedChecksClient.new(ffd_connection)                                      
        )
        new(client)
      end

      def get_feature_flags(names)
        flags = []
        req = FFDV2::MonolithOptimizedGetFeatureFlagsRequest.new(names: names)
        resp = @client.get_feature_flags(req)

        # Check if resp is nil
        unless resp
          raise StandardError, "Error fetching feature flags. Response is nil."
        end

        unless resp.error.nil?
          error_message = resp.error.meta[:body]
          raise StandardError,
                "Error fetching feature flags with status #{resp.error&.code}. Error message: '#{error_message}'"
        end

        feature_flags_hash = !resp.data.nil? ? create_feature_flags_found_hash(resp.data.to_h) : {}

        names.each do |name|
          error = feature_flags_hash[name] ? nil : Errors::FeatureFlagNotFoundError.new(name)
          flags << GetFeatureFlagResponse.new(name: name, feature_flag: feature_flags_hash[name], error: error)
        end

        flags
      end

      def get_segments(names)
        segments = []

        req = FFDV2::GetSegmentsRequest.new(names: names)
        resp = @client.get_segments(req)

        # Check if resp is nil
        unless resp
          raise StandardError, "Error fetching segments. Response is nil."
        end

        unless resp.error.nil?
          error_message = resp.error.meta[:body]
          raise StandardError,
                "Error fetching segments with status #{resp.error&.code}. Error message: '#{error_message}'"
        end

        segments_hash = !resp.data.nil? ? create_segments_found_hash(resp.data.to_h) : {}

        names.each do |name|
          error = segments_hash[name] ? nil : Errors::SegmentNotFoundError.new(name)
          segments << GetSegmentResponse.new(name: name, segment: segments_hash[name], error: error)
        end

        segments
      end

      def adapter_name
        "monolith_optimized_feature_flag_data"
      end

      def self.connection(hmac_key, url)
        ts = Time.now.to_i.to_s
        digest = OpenSSL::Digest.new("sha256")
        sign_bytes = OpenSSL::HMAC.digest(digest, hmac_key, ts)
        sign_hex = sign_bytes.unpack1("H*")
        Faraday.new(url) do |conn|
          conn.headers["Request-HMAC"] = "#{ts}.#{sign_hex}"

          ## TODO: Add adapter version/sha to the user agent header?
          conn.headers["User-Agent"] = "monolith-optimized-feature-flag-data-adapter"
        end
      end

      def self.feature_flag_data_url
        stamp = ENV["KUBE_CLUSTER_STAMP"]

        raise Errors::ValidationError, "KUBE_CLUSTER_STAMP environment variable is not set" if stamp.nil?

        return "http://localhost:8010/twirp" if stamp == "development"

        # TODO: Add option to return the istio/cluster.local URL
        # return fmt.Sprintf("http://feature-flag-data.feature-flag-data-%s.svc.cluster.local:8010", stamp)

        # dotcom has a different url format
        return "https://feature-flag-data-dotcom.service.iad.github.net" if stamp == "dotcom"

        # proxima stamps
        "https://feature-flag-data-#{stamp}.service.#{stamp}.github.net"
      end

      def initialize(client)
        @client =      (
          client                                      
        )
      end

      def convert_feature_flag_response(response)
        state = FFDV2::FeatureFlagState.resolve(response[:state])
        FeatureFlag.new(
          response[:name].to_s,
          boolean_gate: state == FFDV2::FeatureFlagState::SHIPPED,
          percentage_of_actors: response[:percentage_of_actors].to_f,
          percentage_of_calls: response[:percentage_of_calls].to_f,
          segments: response[:segments] || [],
          custom_gates: response[:custom_gates] || [],
          actors: ArrayActorCollection.new(response[:default_segment_actors] || [])
        )
      end

      def convert_segment_response(response)
        segment = Segment.new(
          response[:name].to_s,
          actors: ArrayActorCollection.new(response[:actors] || [])
        )
        segment
      end

      def create_feature_flags_found_hash(data)
        feature_flags_hash = {}
        data[:feature_flags].each do |flag|
          feature_flags_hash[flag[:name]] = convert_feature_flag_response(flag)
        end
        feature_flags_hash
      end

      def create_segments_found_hash(data)
        data[:segments].each_with_object({}) do |segment, segments_hash|
          segments_hash[segment[:name]] = convert_segment_response(segment)
        end
      end
    end
  end
end
