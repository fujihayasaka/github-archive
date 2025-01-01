# frozen_string_literal: true
# typed: strict

require "vexi_management/adapter"
require "vexi/adapters/in_memory_adapter"
require "vexi/models/feature_flag_storage"

module VexiManagement
  module Adapters
    # Public: VexiManagement::Adapter extension logic for Vexi::Adapters::InMemoryAdapter.
    # This should only be used if the vexi gem is installed.
    class InMemoryAdapter
      extend T::Sig
      extend T::Helpers

      include Adapter

      sig { params(shared_storage: Vexi::FeatureFlagStorage).void }
      def initialize(shared_storage: Vexi::FeatureFlagStorage.new)
        @shared_storage = T.let(shared_storage, Vexi::FeatureFlagStorage)
      end

      sig { override.params(name: T.any(String, Symbol), actors: T::Array[T.any(Vexi::Actor, String)]).void }
      def add_actors(name, actors)
        actors.each do |actor|
          add_actor(name, actor)
        end
      end

      # Adds an actor to the feature flag. It will create the flag if it does not exist.
      sig { params(name: T.any(String, Symbol), actor: T.any(Vexi::Actor, String)).void }
      def add_actor(name, actor)
        feature_flag = get_feature_flag_with_default_false(name)

        actor_id = Vexi::Actor.get_actor_id(actor)
        raise ArgumentError, "Could not get actor id for #{actor.inspect}" if actor_id.nil?

        feature_flag.actors[actor_id] = true
      end

      sig { override.params(name: T.any(String, Symbol), actors: T::Array[T.any(Vexi::Actor, String)]).void }
      def remove_actors(name, actors)
        actors.each do |actor|
          remove_actor(name, actor)
        end
      end

      # Creates a new feature flag with the given name.
      sig { override.params(feature_flag: Vexi::FeatureFlag).void }
      def create(feature_flag)
        @shared_storage[feature_flag.name] = feature_flag
      end

      # Retrieves a feature flag by name.
      sig { override.params(name: T.any(String, Symbol)).returns(T.nilable(Vexi::FeatureFlag)) }
      def get(name)
        @shared_storage.get(name.to_s, create_if_not_exists: false)
      end

      # Deletes a feature flag from the adapter.
      sig { override.params(name: T.any(String, Symbol)).void }
      def delete(name)
        @shared_storage.delete(name.to_s)
      end

      # Fully enables the feature flag. It will create it if it does not exist.
      sig { override.params(name: T.any(String, Symbol)).void }
      def enable(name)
        feature_flag = @shared_storage[name.to_s]
        feature_flag.boolean_gate = true
      end

      # Disables the feature flag. It will create it if it does not exist.
      sig { override.params(name: T.any(String, Symbol)).void }
      def disable(name)
        feature_flag = @shared_storage[name.to_s]

        # disable boolean_gate and clear all other gates
        feature_flag.boolean_gate = false
        feature_flag.percentage_of_actors = 0.0
        feature_flag.percentage_of_calls = 0.0
        feature_flag.custom_gates = []
        feature_flag.actors = Vexi::HashActorCollection.new({})
        feature_flag.segments = []
      end

      # Removes an actor from the feature flag. It will create the flag if it does not exist.
      sig { params(name: T.any(String, Symbol), actor: T.any(Vexi::Actor, String)).void }
      def remove_actor(name, actor)
        feature_flag = get_feature_flag_with_default_false(name)

        actor_id = Vexi::Actor.get_actor_id(actor)
        raise ArgumentError, "Could not get actor id for #{actor.inspect}" if actor_id.nil?

        feature_flag.actors.delete(actor_id)
      end

      # Enables the feature flag for a percentage of calls. It will create it if it does not exist.
      sig { override.params(name: T.any(String, Symbol), percentage: Float).void }
      def enable_percentage_of_calls(name, percentage)
        feature_flag = get_feature_flag_with_default_false(name)

        feature_flag.percentage_of_calls = percentage
      end

      # Enables the feature flag for a percentage of actors. It will create it if it does not exist.
      sig { override.params(name: T.any(String, Symbol), percentage: Float).void }
      def enable_percentage_of_actors(name, percentage)
        feature_flag = get_feature_flag_with_default_false(name)

        feature_flag.percentage_of_actors = percentage
      end

      # Adds a custom gate to the feature flag. It will create it if it does not exist.
      sig { override.params(name: T.any(String, Symbol), custom_gate: String).void }
      def add_custom_gate(name, custom_gate)
        feature_flag = get_feature_flag_with_default_false(name)

        feature_flag.custom_gates << custom_gate unless feature_flag.custom_gates.include?(custom_gate)
      end

      # Removes a custom gate from the feature flag.
      sig { override.params(name: T.any(String, Symbol), custom_gate: String).void }
      def remove_custom_gate(name, custom_gate)
        feature_flag = @shared_storage.get(name.to_s, create_if_not_exists: false)
        return unless feature_flag

        feature_flag.custom_gates.delete(custom_gate)
      end

      private

      sig { params(name: T.any(String, Symbol)).returns(Vexi::FeatureFlag) }
      def get_feature_flag_with_default_false(name)
        # create_if_not_exists should ensure that this never returns nil
        T.must(@shared_storage.get(name.to_s, create_if_not_exists: true, default_enabled: false))
      end
    end
  end
end
