# frozen_string_literal: true
# typed: strict

require "feature_management_feature_flags"
require "vexi_management/adapter"
require "vexi_management/adapters/feature_flag_hub_adapter"

module VexiManagement
  module Adapters
    # Public: Adapter that supports the management API for FM-Lite.
    class FeatureManagementLiteAdapter < FeatureFlagHubAdapter
      extend T::Sig
      extend T::Helpers

      include Adapter

      FFMV4 = FeatureManagement::FeatureFlags::Management::V4

      # FM-Lite uses "everywhere" internally as the default name of it's single node
      # https://github.com/github/feature-management-lite/blob/main/internal/featureflag/feature_flag.go#L39
      DEFAULT_STAMP = "everywhere"

      sig { params(conn: Faraday::Connection).returns(FeatureManagementLiteAdapter) }
      def self.new_from_connection(conn)
        features_client = T.let(FFMV4::FeatureFlagsClient.new(conn), FFMV4::FeatureFlagsClient)
        segments_client = T.let(FFMV4::SegmentMembersClient.new(conn), FFMV4::SegmentMembersClient)

        new(features_client, segments_client)
      end

      sig { override.params(feature_flag: Vexi::FeatureFlag).void }
      def create(feature_flag)
        req = FFMV4::CreateFeatureFlagRequest.new(
          feature: FFMV4::FeatureFlag.new(
            name: feature_flag.name,
            nodes: [
              FFMV4::Node.new(
                name: DEFAULT_STAMP,
                result_override: FFMV4::ResultOverride.new(enabled: feature_flag.boolean_gate, value: feature_flag.boolean_gate),
                percentage_of_calls: FFMV4::PercentageOfCalls.new(
                  enabled: true,
                  value: feature_flag.percentage_of_calls,
                ),
                percentage_of_actors: FFMV4::PercentageOfActors.new(
                  enabled: true,
                  value: feature_flag.percentage_of_actors,
                ),
                custom_gates: FFMV4::CustomGates.new(
                  enabled: true,
                  values: feature_flag.custom_gates,
                ),
              ),
            ]
          ),
        )

        resp = @features_client.create_feature_flag(req)

        handle_response(resp, "creating feature flag")

        unless feature_flag.actors.empty?
          add_actors(feature_flag.name, feature_flag.actors.keys, skip_exists: true)
        end
      end

      sig { override.params(name: T.any(String, Symbol)).void }
      def enable(name)
        ensure_feature_flag_exists(name)
        super(name)
      end

      sig { override.params(name: T.any(String, Symbol)).void }
      def disable(name)
        # Delete the feature flag in order to clear all gates and actors
        req = FFMV4::DeleteFeatureFlagRequest.new(name: name.to_s)
        resp = @features_client.delete_feature_flag(req)
        handle_response(resp, "deleting feature flag")

        # Then recreate it as disabled
        ensure_feature_flag_exists(name, fully_enabled: false)
      end

      sig { override.params(name: T.any(String, Symbol)).void }
      def remove_result_override(name)
        ensure_feature_flag_exists(name)
        super(name)
      end

      sig { override.params(name: T.any(String, Symbol), actors: T::Array[T.any(Vexi::Actor, String)], skip_exists: T::Boolean).void }
      def add_actors(name, actors, skip_exists: false)
        ensure_feature_flag_exists(name) unless skip_exists
        super(name, actors)
      end

      sig { override.params(name: T.any(String, Symbol), actors: T::Array[T.any(Vexi::Actor, String)]).void }
      def remove_actors(name, actors)
        ensure_feature_flag_exists(name)
        super(name, actors)
      end

      sig { override.params(name: T.any(String, Symbol), percentage: Float).void }
      def enable_percentage_of_calls(name, percentage)
        ensure_feature_flag_exists(name)
        super(name, percentage)
      end

      sig { override.params(name: T.any(String, Symbol), percentage: Float).void }
      def enable_percentage_of_actors(name, percentage)
        ensure_feature_flag_exists(name)
        super(name, percentage)
      end

      sig { override.params(name: T.any(String, Symbol), custom_gate: String).void }
      def add_custom_gate(name, custom_gate)
        ensure_feature_flag_exists(name)
        super(name, custom_gate)
      end

      sig { override.params(name: T.any(String, Symbol), custom_gate: String).void }
      def remove_custom_gate(name, custom_gate)
        ensure_feature_flag_exists(name)
        super(name, custom_gate)
      end

      sig { override.params(name: T.any(String, Symbol)).returns(T.nilable(Vexi::FeatureFlag)) }
      def get(name)
        req = FFMV4::GetFeatureFlagRequest.new(name: name.to_s)

        flag_resp = @features_client.get_feature_flag(req)
        handle_response(flag_resp, "fetching feature flag")

        segment_req = FFMV4::ListMembersRequest.new(segment_name: default_segment_name(name), page: 1, page_size: 1000)

        segment_resp = @segments_client.list_members(segment_req)
        handle_response(segment_resp, "fetching segment members")

        feature_flag = T.let(flag_resp.data, FFMV4::FeatureFlag)
        members_resp = T.let(segment_resp.data, FFMV4::ListMembersResponse)

        convert_proto_to_feature(feature_flag, members_resp.member_ids.to_a)
      end

      sig { override.params(name: T.any(String, Symbol)).void }
      def delete(name)
        req = FFMV4::DeleteFeatureFlagRequest.new(name: name.to_s)

        resp = @features_client.delete_feature_flag(req)

        handle_response(resp, "deleting feature flag")
      end

      private

      sig { params(proto: FFMV4::FeatureFlag, actors: T::Array[String]).returns(Vexi::FeatureFlag) }
      def convert_proto_to_feature(proto, actors)
        node = proto.nodes.find { |node| node&.name == DEFAULT_STAMP }
        actors = Vexi::ArrayActorCollection.new(actors.sort)

        Vexi::FeatureFlag.new(
          proto.name,
          boolean_gate: node&.state == FFMV4::FeatureFlagState::FULLY_ENABLED || false,
          percentage_of_actors: node&.percentage_of_actors&.value || 0.0,
          percentage_of_calls: node&.percentage_of_calls&.value || 0.0,
          segments: [],
          custom_gates: node&.custom_gates&.values.to_a,
          actors: actors,
        )
      end

      private

      sig { params(name: T.any(String, Symbol), fully_enabled: T::Boolean).void }
      def ensure_feature_flag_exists(name, fully_enabled: false)
        req = FFMV4::CreateFeatureFlagRequest.new(
          feature: FFMV4::FeatureFlag.new(
            name: name.to_s,
            nodes: [
              FFMV4::Node.new(
                name: DEFAULT_STAMP,
                result_override: FFMV4::ResultOverride.new(enabled: fully_enabled, value: fully_enabled),
              ),
            ]
          ),
        )

        resp = @features_client.create_feature_flag(req)
        if resp.nil?
          raise StandardError, "Error ensuring feature flag exists. Response is nil."
        end

        if !resp.error.nil? && resp.error.code != :already_exists
          error_message = resp.error.msg
          raise StandardError,
            "Error ensuring feature flag exists with status #{resp.error&.code}. Error message: '#{error_message}'"
        end
      end
    end
  end
end
