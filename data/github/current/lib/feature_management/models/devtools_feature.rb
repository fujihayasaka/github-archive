# typed: strict
# frozen_string_literal: true

module FeatureManagement
  module Models
    class DevtoolsFeature
      PERCENTAGES = [0, 1, 5, 10, 25, 50, 75, 100].freeze
      BIG_FEATURE_WARNING_THRESHOLD = 100

      delegate :name, :state, to: :raw_feature

      sig { returns(FeatureManagement::FeatureFlags::Management::V4::FeatureFlag) }
      attr_reader :raw_feature

      sig { params(raw_feature: FeatureManagement::FeatureFlags::Management::V4::FeatureFlag).void }
      def initialize(raw_feature)
        @raw_feature = raw_feature
      end

      sig { returns(T.nilable(Time)) }
      def last_updated_at
        timestamp = raw_feature.last_updated
        return nil unless timestamp

        # Convert Google::Protobuf::Timestamp to Ruby Time
        if timestamp.respond_to?(:seconds) && timestamp.respond_to?(:nanos)
          Time.at(timestamp.seconds, timestamp.nanos, :nanosecond)
        elsif timestamp.respond_to?(:to_time)
          timestamp.to_time
        else
          # If it's already a Time object or similar, return as-is
          timestamp
        end
      end

      sig { returns(T::Boolean) }
      def fully_enabled?
        return true if raw_feature.state == :FULLY_ENABLED
        percentage_of_calls_value == 100.0
      end

      sig { returns(T::Boolean) }
      def fully_disabled?
        raw_feature.state == :DISABLED
      end

      sig { returns(FeatureManagement::FeatureFlags::Management::V4::Node) }
      private def node
        # fm-lite should have only one node but if it doesn't exist then return a new node
        nodes = raw_feature.nodes
        return FeatureManagement::FeatureFlags::Management::V4::Node.new if nodes.empty?
        nodes.first
      end

      sig { returns(Float) }
      def percentage_of_actors_value
        percentage_of_actors = node.percentage_of_actors
        percentage_of_actors&.enabled ? percentage_of_actors.value : 0.0
      end

      sig { returns(Float) }
      def percentage_of_calls_value
        percentage_of_calls = node.percentage_of_calls
        percentage_of_calls&.enabled ? percentage_of_calls.value : 0.0
      end

      sig { returns(T::Array[GitHub::VexiActor]) }
      def actors
        vexi_feature = FeatureFlag.vexi_management.get_feature_flag(raw_feature.name)
        return [] if vexi_feature.nil?

        vexi_feature.actors.to_a.map { |actor_id| GitHub::VexiActor.from_vexi_id(actor_id) }.compact
      end

      sig { returns(T::Array[String]) }
      def actor_types
        actors.map { |actor| actor.vexi_actor_type }.uniq
      end

      sig { params(actor_type: T.nilable(String)).returns(T::Array[GitHub::VexiActor]) }
      def filtered_actors(actor_type = nil)
        return actors if actor_type.blank?

        actors.select { |actor| actor.vexi_actor_type == actor_type }
      end

      sig { returns(T::Boolean) }
      def show_big_feature_warning?
        actors.size > BIG_FEATURE_WARNING_THRESHOLD
      end

      sig { returns(T::Array[String]) }
      def available_groups
        FeatureFlagsCommon::CustomGates::CUSTOM_GATES.keys.to_a - custom_gates_values
      end

      sig { returns(T::Array[String]) }
      def custom_gates_values
        custom_gates = node.custom_gates
        return [] if custom_gates.nil? || !custom_gates.enabled
        custom_gates.values.to_a
      end

      sig { returns(T::Boolean) }
      def custom_actor_percentage?
        !PERCENTAGES.include?(percentage_of_actors_value)
      end

      sig { returns(T::Boolean) }
      def custom_call_percentage?
        !PERCENTAGES.include?(percentage_of_calls_value)
      end

      sig { returns(T::Array[String]) }
      def code_usage
        feature_name_in_code = name.underscore
        GitHub::Grep.new.code_use(/["':]#{feature_name_in_code}/,
                                  /#{feature_name_in_code}_enabled\?/,
                                  /#{feature_name_in_code}_required/,
                                  dirs: %w[app config jobs lib packages :(exclude)packages/*/test/* :(exclude)config/schema*.graphql])
      end

      # -- For dom_id compatibility --
      sig { returns(String) }
      def id
        name
      end

      sig { returns(T::Array[String]) }
      def to_key
        [id]
      end

      sig { returns(ActiveModel::Name) }
      def model_name
        ActiveModel::Name.new(self.class, nil, "Feature")
      end

      sig { returns(T::Boolean) }
      def persisted?
        false
      end

      sig { returns(String) }
      def to_param
        name
      end
      # --- end ---

      # For compatibility with Devtools::GateLabelComponent
      # Delegate methods that the component expects
      sig { returns(T::Boolean) }
      def prelude_fully_enabled?
        raw_feature.state == :FULLY_ENABLED
      end

      sig { returns(T::Boolean) }
      def prelude_staff_shipped?
        return false if raw_feature.nodes.empty?
        custom_gates = node.custom_gates
        return false if custom_gates.nil?

        custom_gates.enabled && custom_gates.values.any? { |gate| gate == "preview_features" }
      end

      sig { returns(T::Boolean) }
      def prelude_actor_or_percentage?
        vexi_feature = FeatureFlag.vexi_management.get_feature_flag(raw_feature.name)
        return false if vexi_feature.nil?
        return true if vexi_feature.actors.any?
        return false if raw_feature.nodes.empty?

        percentage_of_actors = node.percentage_of_actors
        percentage_of_calls = node.percentage_of_calls
        (percentage_of_actors.present? && percentage_of_actors.enabled && percentage_of_actors.value.positive?) ||
          (percentage_of_calls.present? && percentage_of_calls.enabled && percentage_of_calls.value.positive?)
      end
    end
  end
end
