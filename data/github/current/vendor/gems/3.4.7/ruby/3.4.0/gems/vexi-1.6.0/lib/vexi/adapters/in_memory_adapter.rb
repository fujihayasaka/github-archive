# frozen_string_literal: true
#              


require "vexi/adapter"

module Vexi
  module Adapters
    # Public: In memory adapter mode enum
    class InMemoryAdapterMode
      DisabledByDefault = 0
      EnabledByDefault = 1
    end

    # Public: In memory adapter for Vexi.
    class InMemoryAdapter
      include Adapter

      def initialize(mode, exception_feature_flags: [])
        @exception_feature_flags =      (exception_feature_flags                  )

        @default_enabled =      (case mode
                                 when InMemoryAdapterMode::DisabledByDefault then false
                                 when InMemoryAdapterMode::EnabledByDefault then true
                                 else raise ArgumentError, "Invalid mode: #{mode}"
                                 end            )

        @feature_flags =      ({}                              )

        reset
      end

      def features
        @feature_flags.values
      end

      def get_feature_flags(names)
        feature_flags = []
        names.each do |name|
          feature_flag = @feature_flags[name] || FeatureFlag.create_boolean_feature_flag(name, @default_enabled)
          feature_flags << GetFeatureFlagResponse.new(
            name: name,
            feature_flag: feature_flag
          )
        end
        feature_flags
      end

      def get_segments(_names)
        []
      end

      def adapter_name
        "in_memory"
      end

      # Below is the implementation of VexiManagement::Adapter to support using it with vexi_management,
      # but that is not included directly here to avoid adding gem dependencies.
      # For testing this can be used with vexi_management if desired, but alternatively
      # the methods can be used directly on the InMemoryAdapter class.

      # Creates a new feature flag with the given name.
      def create(feature_flag)
        @feature_flags[feature_flag.name] = feature_flag
      end

      def get(name)
        feature_flag_responses = get_feature_flags([name.to_s])
        first_response = feature_flag_responses.first

        return nil unless first_response&.feature_flag

        first_response.feature_flag
      end

      # Deletes a feature flag from the adapter.
      def delete(name)
        @feature_flags.delete(name.to_s)
      end

      # Fully enables the feature flag. It will create it if it does not exist.
      def enable(name)
        feature_flag = @feature_flags[name.to_s] ||= FeatureFlag.create_boolean_feature_flag(name.to_s, true)
        feature_flag.boolean_gate = true
      end

      # Disables the feature flag. It will create it if it does not exist.
      def disable(name)
        feature_flag = @feature_flags[name.to_s]
        if feature_flag
          # disable boolean_gate and clear all other gates
          feature_flag.boolean_gate = false
          feature_flag.percentage_of_actors = 0.0
          feature_flag.percentage_of_calls = 0.0
          feature_flag.custom_gates = []
          feature_flag.actors = HashActorCollection.new({})
          feature_flag.segments = []
        else
          feature_flag = FeatureFlag.create_boolean_feature_flag(name.to_s, false)
          @feature_flags[name.to_s] = feature_flag
        end
      end

      # Adds an actor to the feature flag. It will create the flag if it does not exist.
      def add_actor(name, actor)
        feature_flag = @feature_flags[name.to_s] ||= FeatureFlag.create_boolean_feature_flag(name.to_s, false)

        actor_id = Actor.get_actor_id(actor)
        raise ArgumentError, "Could not get actor id for #{actor.inspect}" if actor_id.nil?

        feature_flag.actors[actor_id] = true
      end

      # Removes an actor from the feature flag. It will create the flag if it does not exist.
      def remove_actor(name, actor)
        feature_flag = @feature_flags[name.to_s] ||= FeatureFlag.create_boolean_feature_flag(name.to_s, false)

        actor_id = Actor.get_actor_id(actor)
        raise ArgumentError, "Could not get actor id for #{actor.inspect}" if actor_id.nil?

        feature_flag.actors.delete(actor_id)
      end

      # Enables the feature flag for a percentage of calls. It will create it if it does not exist.
      def enable_percentage_of_calls(name, percentage)
        feature_flag = @feature_flags[name.to_s] ||= FeatureFlag.create_boolean_feature_flag(name.to_s, false)

        feature_flag.percentage_of_calls = percentage
      end

      # Enables the feature flag for a percentage of actors. It will create it if it does not exist.
      def enable_percentage_of_actors(name, percentage)
        feature_flag = @feature_flags[name.to_s] ||= FeatureFlag.create_boolean_feature_flag(name.to_s, false)

        feature_flag.percentage_of_actors = percentage
      end

      # Adds a custom gate to the feature flag. It will create it if it does not exist.
      def add_custom_gate(name, custom_gate)
        feature_flag = @feature_flags[name.to_s] ||= FeatureFlag.create_boolean_feature_flag(name.to_s, false)

        feature_flag.custom_gates << custom_gate unless feature_flag.custom_gates.include?(custom_gate)
      end

      # Removes a custom gate from the feature flag.
      def remove_custom_gate(name, custom_gate)
        feature_flag = @feature_flags[name.to_s]
        return unless feature_flag

        feature_flag.custom_gates.delete(custom_gate)
      end

      # Resets the adapter to its initial state.
      def reset
        # Add all the exception feature flags to a new hash with the inverse of the default value
        @feature_flags = @exception_feature_flags.each_with_object({}) do |name, hash|
          hash[name] = FeatureFlag.create_boolean_feature_flag(name, !@default_enabled)
        end
      end
    end
  end
end
