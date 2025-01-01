# frozen_string_literal: true
# typed: strict

require "feature_management_feature_flags"
require "vexi_management/adapter"

module VexiManagement
  module Adapters
    # Public: Adapter that supports the management API for Feature Flag Hub and FM-Lite.
    class FeatureFlagHubAdapter
      extend T::Sig
      extend T::Helpers

      include Adapter

      FFMV3 = FeatureManagement::FeatureFlags::Management::V3

      sig { params(conn: Faraday::Connection).returns(FeatureFlagHubAdapter) }
      def self.new_from_connection(conn)
        features_client = T.let(FFMV3::FeatureFlagsClient.new(conn), FFMV3::FeatureFlagsClient)
        segments_client = T.let(FFMV3::SegmentMembersClient.new(conn), FFMV3::SegmentMembersClient)

        new(features_client, segments_client)
      end

      sig { params(features_client: FFMV3::FeatureFlagsClient, segments_client: FFMV3::SegmentMembersClient).void }
      def initialize(features_client, segments_client)
        @features_client = T.let(features_client, FFMV3::FeatureFlagsClient)
        @segments_client = T.let(segments_client, FFMV3::SegmentMembersClient)
      end

      sig { override.params(feature_flag: Vexi::FeatureFlag).void }
      def create(feature_flag)
        raise NotImplementedError, "Create operation is not supported in #{self.class.name}"
      end

      sig { override.params(name: T.any(String, Symbol)).returns(T.nilable(Vexi::FeatureFlag)) }
      def get(name)
        raise NotImplementedError, "Get operation is not supported in #{self.class.name}"
      end

      sig { override.params(name: T.any(String, Symbol)).void }
      def delete(name)
        raise NotImplementedError, "Delete operation is not supported in #{self.class.name}"
      end

      sig { override.params(name: T.any(String, Symbol)).void }
      def enable(name)
        req = FFMV3::UpdateFeatureFlagNodeGatesRequest.new(
          name: name.to_s,
          result_override: FFMV3::ResultOverride.new(enabled: true, value: true),
        )

        resp = @features_client.update_feature_flag_node_gates(req)

        handle_response(resp, "enabling feature flag")
      end

      sig { override.params(name: T.any(String, Symbol)).void }
      def disable(name)
        req = FFMV3::UpdateFeatureFlagNodeGatesRequest.new(
          name: name.to_s,
          result_override: FFMV3::ResultOverride.new(enabled: true, value: false),
        )

        resp = @features_client.update_feature_flag_node_gates(req)

        handle_response(resp, "disabling feature flag")
      end

      sig { override.params(name: T.any(String, Symbol), actors: T::Array[T.any(Vexi::Actor, String)]).void }
      def add_actors(name, actors)
        segment_name = default_segment_name(name)
        actor_ids = actors.map { |actor| to_actor_id(actor) }

        req = FFMV3::AddMembersRequest.new(
          segment_name: segment_name,
          member_ids: actor_ids,
        )

        resp = @segments_client.add_members(req)

        handle_response(resp, "adding actor to segment")
      end

      sig { override.params(name: T.any(String, Symbol), actors: T::Array[T.any(Vexi::Actor, String)]).void }
      def remove_actors(name, actors)
        segment_name = default_segment_name(name)
        actor_ids = actors.map { |actor| to_actor_id(actor) }

        req = FFMV3::RemoveMembersRequest.new(
          segment_name: segment_name,
          member_ids: actor_ids,
        )

        resp = @segments_client.remove_members(req)

        handle_response(resp, "removing actor from segment")
      end

      sig { override.params(name: T.any(String, Symbol), percentage: Float).void }
      def enable_percentage_of_calls(name, percentage)
        req = FFMV3::UpdateFeatureFlagNodeGatesRequest.new(
          name: name.to_s,
          percentage_of_calls: FFMV3::PercentageOfCalls.new(enabled: true, value: percentage),
        )

        resp = @features_client.update_feature_flag_node_gates(req)

        handle_response(resp, "enabling percentage of calls")
      end

      sig { override.params(name: T.any(String, Symbol), percentage: Float).void }
      def enable_percentage_of_actors(name, percentage)
        req = FFMV3::UpdateFeatureFlagNodeGatesRequest.new(
          name: name.to_s,
          percentage_of_actors: FFMV3::PercentageOfActors.new(enabled: true, value: percentage),
        )

        resp = @features_client.update_feature_flag_node_gates(req)

        handle_response(resp, "enabling percentage of actors")
      end

      sig { override.params(name: T.any(String, Symbol), custom_gate: String).void }
      def add_custom_gate(name, custom_gate)
        gate_change = FFMV3::CustomGateChange.new(name: custom_gate.to_s, enabled: true)
        req = FFMV3::UpdateFeatureFlagNodeGatesRequest.new(
          name: name.to_s,
          custom_gates: FFMV3::CustomGateChanges.new(disable_unspecified: false, changes: [gate_change]),
        )

        resp = @features_client.update_feature_flag_node_gates(req)

        handle_response(resp, "adding custom gate")
      end

      sig { override.params(name: T.any(String, Symbol), custom_gate: String).void }
      def remove_custom_gate(name, custom_gate)
        req = FFMV3::UpdateFeatureFlagNodeGatesRequest.new(
          name: name.to_s,
          custom_gates: FFMV3::CustomGateChanges.new(
            disable_unspecified: false,
            changes: [
              FFMV3::CustomGateChange.new(name: custom_gate.to_s, enabled: false),
            ]
          )
        )

        resp = @features_client.update_feature_flag_node_gates(req)

        handle_response(resp, "removing custom gate")
      end

      private

      sig { params(resp: T.untyped, operation: String).void }
      def handle_response(resp, operation)
        unless resp
          raise StandardError, "Error #{operation}. Response is nil."
        end

        unless resp.error.nil?
          error_message = resp.error.meta[:body]
          raise StandardError,
            "Error #{operation} with status #{resp.error&.code}. Error message: '#{error_message}'"
        end
      end

      sig { params(actor: T.any(Vexi::Actor, String)).returns(String) }
      def to_actor_id(actor)
        actor.is_a?(Vexi::Actor) ? actor.vexi_id : actor.to_s
      end

      sig { params(feature_name: T.any(String, Symbol)).returns(String) }
      def default_segment_name(feature_name)
        Vexi::DEFAULT_SEGMENT_PREFIX + feature_name.to_s
      end
    end
  end
end
