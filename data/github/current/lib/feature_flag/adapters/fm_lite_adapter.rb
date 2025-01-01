# typed: strict
# frozen_string_literal: true

require "fm_lite_process_helper"

module FeatureFlag
  module Adapters
    class FeatureManagementLiteAdapter
      include TestAdapter

      sig { params(data_client: GitHub::FaradayClient::Internal, default_enabled: T::Boolean, exception_feature_flags: T::Array[String]).void }
      def initialize(data_client, default_enabled: false, exception_feature_flags: [])
        if GitHub.feature_management_feature_flag_hub_url.nil?
          raise FeatureManagement::FeatureFlagHubClientError.new(:environment_error, "Feature Flag Hub url cannot be nil")
        end

        @default_enabled = T.let(default_enabled, T::Boolean)
        @exception_feature_flags = T.let(exception_feature_flags, T::Array[String])

        @data_adapter = T.let(Vexi::Adapters::MonolithOptimizedFeatureFlagDataAdapter.new_from_connection(data_client), Vexi::Adapters::MonolithOptimizedFeatureFlagDataAdapter)

        @feature_management_client = T.let(FeatureManagement::FeatureFlagHubFeatureManagementClient.new, FeatureManagement::FeatureFlagHubFeatureManagementClient)
        @segment_member_management_client = T.let(FeatureManagement::FeatureFlagHubSegmentMemberManagementClient.new, FeatureManagement::FeatureFlagHubSegmentMemberManagementClient)

        FeatureManagementLiteProcessHelper.ensure_fm_lite_ready
      end

      # Vexi::Adapter

      sig { override.returns(String) }
      def adapter_name
        "fm_lite"
      end

      sig { override.params(names: T::Array[String]).returns(T::Array[Vexi::GetFeatureFlagResponse]) }
      def get_feature_flags(names)
        flag_responses = T.let(@data_adapter.get_feature_flags(names), T::Array[Vexi::GetFeatureFlagResponse])
        flag_responses = flag_responses.select { |flag_response| flag_response.feature_flag }

        missing_flag_names = names - flag_responses.map(&:name)
        missing_flag_names.each do |name|
          is_exception = @exception_feature_flags.include?(name)
          enabled = is_exception ? !@default_enabled : @default_enabled
          flag_responses << Vexi::GetFeatureFlagResponse.new(
            name: name,
            feature_flag: Vexi::FeatureFlag.new(name, boolean_gate: enabled)
          )
        end

        flag_responses
      end

      sig { override.params(names: T::Array[String]).returns(T::Array[Vexi::GetSegmentResponse]) }
      def get_segments(names)
        []
      end

      # VexiManagement::Adapter

      sig { override.params(name: T.any(String, Symbol)).returns(T.nilable(Vexi::FeatureFlag)) }
      def get(name)
        feature_flag_responses = get_feature_flags([name.to_s])
        first_response = feature_flag_responses.first

        return nil unless first_response&.feature_flag

        first_response.feature_flag
      end

      sig { override.params(feature_flag: Vexi::FeatureFlag).void }
      def create(feature_flag)
        ensure_feature_flag_exists(feature_flag.name)

        flag = FeatureManagement::Management::FeatureFlag.new(feature_flag.name)
        node_state = feature_flag.boolean_gate ? FeatureManagement::Management::Node::NODE_SHIPPED : FeatureManagement::Management::Node::NODE_DISABLED
        flag.nodes = [FeatureManagement::Management::Node.new("everywhere", node_state, nil)]
        @feature_management_client.update_feature_flag(flag, "nodes")

        if feature_flag.actors.any?
          @segment_member_management_client.add_members(feature_flag.name, feature_flag.actors.map { |actor| get_actor_id(actor) })
        end
      end

      sig { override.params(name: T.any(String, Symbol)).void }
      def delete(name)
        @feature_management_client.delete_feature_flag(name.to_s)
      end

      sig { override.params(name: T.any(String, Symbol)).void }
      def enable(name)
        ensure_feature_flag_exists(name)
        flag = FeatureManagement::Management::FeatureFlag.new(name.to_s)
        flag.nodes = [FeatureManagement::Management::Node.new("everywhere", FeatureManagement::Management::Node::NODE_SHIPPED, nil)]
        @feature_management_client.update_feature_flag(flag, "nodes")
      end

      sig { override.params(name: T.any(String, Symbol)).void }
      def disable(name)
        ensure_feature_flag_exists(name)
        @segment_member_management_client.remove_all_members(name.to_s)
        flag = FeatureManagement::Management::FeatureFlag.new(name.to_s)
        flag.nodes = [FeatureManagement::Management::Node.new("everywhere", FeatureManagement::Management::Node::NODE_DISABLED, nil)]
        @feature_management_client.update_feature_flag(flag, "nodes")
      end

      sig { override.params(name: T.any(String, Symbol), actor: T.any(String, Vexi::Actor)).void }
      def add_actor(name, actor)
        ensure_feature_flag_exists(name)
        @segment_member_management_client.add_members(name.to_s, [get_actor_id(actor)])
      end

      sig { override.params(name: T.any(String, Symbol), actor: T.any(String, Vexi::Actor)).void }
      def remove_actor(name, actor)
        ensure_feature_flag_exists(name)
        @segment_member_management_client.remove_members(name.to_s, [get_actor_id(actor)])
      end

      sig { override.params(name: T.any(String, Symbol), percentage: Float).void }
      def enable_percentage_of_actors(name, percentage)
        ensure_feature_flag_exists(name)

        feature = @feature_management_client.get_feature_flag(name.to_s)

        node = find_node(feature.nodes)
        node.percentage_of_actors.enabled = (percentage.to_f > 0)
        node.percentage_of_actors.value = percentage.to_f

        feature.nodes = [node]
        @feature_management_client.update_feature_flag(feature, "nodes")
      end

      sig { override.params(name: T.any(String, Symbol), percentage: Float).void }
      def enable_percentage_of_calls(name, percentage)
        ensure_feature_flag_exists(name)

        feature = @feature_management_client.get_feature_flag(name.to_s)

        node = find_node(feature.nodes)
        node.percentage_of_calls.enabled = (percentage.to_f > 0)
        node.percentage_of_calls.value = percentage.to_f

        feature.nodes = [node]
        @feature_management_client.update_feature_flag(feature, "nodes")
      end

      sig { override.params(name: T.any(String, Symbol), custom_gate: String).void }
      def add_custom_gate(name, custom_gate)
        ensure_feature_flag_exists(name)

        feature = @feature_management_client.get_feature_flag(name.to_s)

        node = find_node(feature.nodes)
        node.custom_gates.enabled = true
        if !node.custom_gates.values.include?(custom_gate)
          node.custom_gates.values << custom_gate
        end

        feature.nodes = [node]
        @feature_management_client.update_feature_flag(feature, "nodes")
      end

      sig { override.params(name: T.any(String, Symbol), custom_gate: String).void }
      def remove_custom_gate(name, custom_gate)
        ensure_feature_flag_exists(name)

        feature = @feature_management_client.get_feature_flag(name.to_s)

        node = find_node(feature.nodes)
        if node.custom_gates.values.include?(custom_gate)
          node.custom_gates.values.delete(custom_gate)
        end
        node.custom_gates.enabled = (node.custom_gates.values.length > 0)

        feature.nodes = [node]
        @feature_management_client.update_feature_flag(feature, "nodes")
      end

      # FeatureFlag::Adapters::TestAdapter

      sig { override.returns(T::Array[FeatureFlag]) }
      def features
        # We can get the data for via the List API on the Management V3 spec,
        # but FeatureManagement::FeatureFlagHubFeatureManagementClient doesn't
        # implement that API currently, so we're skipping it for now.
        raise NotImplementedError
      end

      sig { override.void }
      def reset
        # Do Nothing
      end

      # Private
      private

      sig { params(name: T.any(String, Symbol), enabled: T::Boolean).void }
      def ensure_feature_flag_exists(name, enabled: false)
        begin
          flag = FeatureManagement::Management::FeatureFlag.new(name.to_s)
          node_state = enabled ? FeatureManagement::Management::Node::NODE_SHIPPED : FeatureManagement::Management::Node::NODE_DISABLED
          flag.nodes = [FeatureManagement::Management::Node.new("everywhere", node_state, nil)]
          @feature_management_client.create_feature_flag(flag)
        rescue FeatureManagement::FeatureFlagHubAsyncOperationError => e
          # 409 is returned when the flag already exists.
          if e.status_code != 409
            raise
          end
        end
      end

      sig { params(actor: T.any(String, Vexi::Actor)).returns(String) }
      def get_actor_id(actor)
        case actor
        when String
          actor
        when Vexi::Actor
          # We're stripping sorbet information from the Vexi gem, so we have to use unsafe.
          # https://github.com/github/feature-management-client-ruby/blob/main/sorbet/rbi/vexi/vexi/lib/vexi/actor.rbi
          T.unsafe(actor).vexi_id
        end
      end

      sig { params(nodes: T::Array[FeatureManagement::Management::Node]).returns(FeatureManagement::Management::Node) }
      def find_node(nodes)
        if nodes.length == 1 && node = nodes.first
          return node
        end

        nodes.each do |node|
          return node if node.name == "everywhere"
        end

        FeatureManagement::Management::Node.new("everywhere", FeatureManagement::Management::Node::NODE_PARTIALLY_SHIPPED, nil)
      end
    end
  end
end
