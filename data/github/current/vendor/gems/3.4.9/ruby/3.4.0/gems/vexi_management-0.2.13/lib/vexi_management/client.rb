# frozen_string_literal: true
# typed: strict

require "sorbet-runtime"

require "vexi/models/feature_flag"
require "vexi/actor"

require "vexi_management/adapter"
require "vexi_management/version"

# Public: The Vexi module for performing feature flag management operations.
module VexiManagement
  # Public: The Vexi Management Client class for performing feature flag management operations.
  class Client
    extend T::Sig
    extend T::Helpers

    sig { params(adapter: Adapter, notifications: Vexi::Notifications, vexi_client: T.nilable(Vexi::Client)).void }
    def initialize(adapter, notifications, vexi_client = nil)
      @adapter = T.let(adapter, Adapter)
      @notifications = T.let(notifications, Vexi::Notifications)
      @vexi_client = T.let(vexi_client, T.nilable(Vexi::Client))
    end

    sig { params(name: T.any(String, Symbol)).returns(T.nilable(Vexi::FeatureFlag)) }
    def get_feature_flag(name)
      name = name.to_s.downcase

      @notifications.instrument_timing("get_feature_flag", properties: { feature_flag_name: name }) do
        @adapter.get(name)
      end
    end

    sig { params(name: T.any(String, Symbol)).void }
    def enable_feature_flag(name)
      name = name.to_s.downcase

      @notifications.instrument_timing("enable_feature_flag", properties: { feature_flag_name: name }) do
        @adapter.enable(name)
        @vexi_client&.clear_feature_flag_memoization(name)
      end
    end

    sig { params(name: T.any(String, Symbol)).void }
    def disable_feature_flag(name)
      name = name.to_s.downcase

      @notifications.instrument_timing("disable_feature_flag", properties: { feature_flag_name: name }) do
        @adapter.disable(name)
        @vexi_client&.clear_feature_flag_memoization(name)
      end
    end

    sig { params(name: T.any(String, Symbol), actors: T::Array[T.any(String, Vexi::Actor)]).void }
    def add_feature_flag_actors(name, actors)
      name = name.to_s.downcase
      actors = actors.reject { |actor| actor.nil? || (actor.is_a?(String) && actor.empty?) }

      @notifications.instrument_timing("add_feature_flag_actors", properties: { feature_flag_name: name, number_of_actors: actors.size }) do
        @adapter.add_actors(name, actors)
        @vexi_client&.clear_feature_flag_memoization(name)
      end
    end

    sig { params(name: T.any(String, Symbol), actors: T::Array[T.any(String, Vexi::Actor)]).void }
    def remove_feature_flag_actors(name, actors)
      name = name.to_s.downcase
      actors = actors.reject { |actor| actor.nil? || (actor.is_a?(String) && actor.empty?) }

      @notifications.instrument_timing("remove_feature_flag_actors", properties: { feature_flag_name: name, number_of_actors: actors.size }) do
        @adapter.remove_actors(name, actors)
        @vexi_client&.clear_feature_flag_memoization(name)
      end
    end

    sig { params(name: T.any(String, Symbol), percentage: Float).void }
    def set_feature_flag_percentage_of_calls(name, percentage)
      name = name.to_s.downcase

      @notifications.instrument_timing("set_feature_flag_percentage_of_calls", properties: { feature_flag_name: name, percentage: percentage }) do
        @adapter.enable_percentage_of_calls(name, percentage)
        @vexi_client&.clear_feature_flag_memoization(name)
      end
    end

    sig { params(name: T.any(String, Symbol), percentage: Float).void }
    def set_feature_flag_percentage_of_actors(name, percentage)
      name = name.to_s.downcase

      @notifications.instrument_timing("set_feature_flag_percentage_of_actors", properties: { feature_flag_name: name, percentage: percentage }) do
        @adapter.enable_percentage_of_actors(name, percentage)
        @vexi_client&.clear_feature_flag_memoization(name)
      end
    end

    sig { params(name: T.any(String, Symbol), custom_gate: String).void }
    def add_feature_flag_custom_gate(name, custom_gate)
      name = name.to_s.downcase

      @notifications.instrument_timing("add_feature_flag_custom_gate", properties: { feature_flag_name: name, custom_gate: custom_gate }) do
        @adapter.add_custom_gate(name, custom_gate)
        @vexi_client&.clear_feature_flag_memoization(name)
      end
    end

    sig { params(name: T.any(String, Symbol), custom_gate: String).void }
    def remove_feature_flag_custom_gate(name, custom_gate)
      name = name.to_s.downcase

      @notifications.instrument_timing("remove_feature_flag_custom_gate", properties: { feature_flag_name: name, custom_gate: custom_gate }) do
        @adapter.remove_custom_gate(name, custom_gate)
        @vexi_client&.clear_feature_flag_memoization(name)
      end
    end
  end
end
