# frozen_string_literal: true

require "faraday"
require_relative "proto/configs_pb"
require_relative "proto/configs_twirp"
require_relative "errors"
require_relative "target"

module Configs
  # Main client for interacting with the Configsd service
  class Client
    extend T::Sig

    # Initialize a new Configs client
    #
    # As this client will be almost exclusively used by the monolith which will
    # need full control over the configuration of the Faraday connection, it is
    # simplest to just accept a Faraday connection directly.
    #
    # The connection should be configured with the following:
    #
    # - URL set to the Configsd service endpoint (ex: https://configsd.example.com:8080/twirp)
    # - Any other desired Faraday middleware (logging, timeouts, statter metrics etc)
    sig { params(connection: Faraday::Connection).void }
    def initialize(connection)
      @connection = connection
    end

    # Resolve configurations by target with owner information
    #
    # @raise [Faraday::Error] If the HTTP request fails
    # @raise [Configs::RpcError] If the response is invalid
    sig { params(repo_id: T.nilable(Integer), owner_id: T.nilable(Integer), business_id: T.nilable(Integer)).returns(T::Hash[String, Configs::Entry]) }
    def resolve_configs_by_target(repo_id: nil, owner_id: nil, business_id: nil)
      target = Configs::Twirp::ConfigTargetWithOwners.new(repo_id:, owner_id:, business_id:)
      request = Configs::Twirp::ResolveConfigsByTargetWithOwnersRequest.new(target: target)
      response = twirp_client.resolve_configs_by_target_with_owners(request)
      raise_if_error(response) || response.data.configs.configs.to_h.transform_values { |c| Configs::Entry.from_twirp_config(c) }
    end

    # Resolve configurations for multiple targets with owner information
    #
    # @param targets [Array<Hash>] Array of target hashes with :repo_id, :owner_id, and/or :business_id keys
    #   Example: [{repo_id: 123}, {owner_id: 456, business_id: 789}]
    # @return [Hash{String => Hash{Integer => Hash{String => Configs::Entry}}]
    #   Nested map: target_type -> target_id -> config_name -> Configs::Entry
    # @raise [Faraday::Error] If the HTTP request fails
    # @raise [Configs::RpcError] If the response is invalid
    # @raise [ArgumentError] If targets is empty or invalid
    sig { params(targets: T::Array[T::Hash[Symbol, T.nilable(Integer)]]).returns(T::Hash[String, T::Hash[Integer, T::Hash[String, Configs::Entry]]]) }
    def resolve_configs_by_targets(targets:)
      if targets.nil? || targets.empty?
        raise ArgumentError, "At least one target must be provided"
      end

      target_messages = targets.map do |target|
        Configs::Twirp::ConfigTargetWithOwners.new(
          repo_id: target[:repo_id],
          owner_id: target[:owner_id],
          business_id: target[:business_id]
        )
      end

      request = Configs::Twirp::ResolveConfigsByTargetsWithOwnersRequest.new(targets: target_messages)
      response = twirp_client.resolve_configs_by_targets_with_owners(request)

      raise_if_error(response)

      response.data.configs_by_type.each_with_object({}) do |(type, configs_by_id), result|
        type_name = Configs::Twirp::TargetType.lookup(type).name
        result[type_name] = configs_by_id.configs_by_id.to_h.transform_values do |v|
          v[:configs].transform_values { |config| Configs::Entry.from_twirp_config(config) }
        end
      end
    end

    # Resolve a single config name for a single target.
    # Returns [value, found] where found is a boolean indicating whether the name was resolved.
    #
    # @param target [Configs::Target] The target to resolve for
    # @param name [String] The config name to resolve
    # @return [Array(String, Boolean)] The value and whether it was found
    # @raise [Faraday::Error] If the HTTP request fails
    # @raise [Configs::RpcError] If the response is invalid
    sig { params(target: Configs::Target, name: String).returns([String, T::Boolean]) }
    def resolve_value_for_name(target:, name:)
      result = resolve_configs_by_names(targets: [target], names: [name])
      if (entries = result[target]) && (entry = entries[name])
        [entry.value, true]
      else
        ["", false]
      end
    end

    # Resolve a single config name across multiple targets.
    # Returns a hash from each target to the config's value. Targets where the name
    # is not found are omitted from the result.
    #
    # @param targets [Array<Configs::Target>] Array of targets
    # @param name [String] The config name to resolve
    # @return [Hash{Configs::Target => String}] Map from target to resolved value
    # @raise [ArgumentError] If targets is empty or contains duplicate most-specific targets
    # @raise [Faraday::Error] If the HTTP request fails
    # @raise [Configs::RpcError] If the response is invalid
    sig { params(targets: T::Array[Configs::Target], name: String).returns(T::Hash[Configs::Target, String]) }
    def resolve_values_for_name(targets:, name:)
      result = resolve_configs_by_names(targets: targets, names: [name])
      values = {}
      result.each do |target, entries|
        if (entry = entries[name])
          values[target] = entry.value
        end
      end
      values
    end

    # Resolve multiple config names across multiple targets.
    # Returns a nested hash from each target to config name to value string.
    # Config names not found for a target are omitted. Targets with no results are omitted.
    #
    # @param targets [Array<Configs::Target>] Array of targets
    # @param names [Array<String>] The config names to resolve
    # @return [Hash{Configs::Target => Hash{String => String}}] Nested map: target -> config_name -> value
    # @raise [ArgumentError] If targets is empty or contains duplicate most-specific targets
    # @raise [Faraday::Error] If the HTTP request fails
    # @raise [Configs::RpcError] If the response is invalid
    sig { params(targets: T::Array[Configs::Target], names: T::Array[String]).returns(T::Hash[Configs::Target, T::Hash[String, String]]) }
    def resolve_values_for_names(targets:, names:)
      result = resolve_configs_by_names(targets: targets, names: names)
      values = {}
      result.each do |target, entries|
        next if entries.empty?

        m = {}
        entries.each { |n, entry| m[n] = entry.value }
        values[target] = m
      end
      values
    end

    # List all targets that have a configuration entry with the given name and value.
    #
    # @param name [String] The config entry name to search for
    # @param value [String] The config entry value to match
    # @return [Hash{Symbol => Object}] A hash with :targets (Array<Configs::ConfigTarget>) and :truncated (Boolean)
    # @raise [ArgumentError] If name or value is empty
    # @raise [Faraday::Error] If the HTTP request fails
    # @raise [Configs::RpcError] If the response is invalid
    sig { params(name: String, value: String).returns({ targets: T::Array[Configs::ConfigTarget], truncated: T::Boolean }) }
    def list_targets_by_config_value(name:, value:)
      raise ArgumentError, "name must be provided" if name.nil? || name.empty?
      raise ArgumentError, "value must be provided" if value.nil? || value.empty?

      request = Configs::Twirp::ListTargetsByConfigValueRequest.new(name: name, value: value)
      response = twirp_client.list_targets_by_config_value(request)
      raise_if_error(response)

      targets = response.data.targets.map { |t| Configs::ConfigTarget.from_proto(t) }

      { targets: targets, truncated: response.data.truncated }
    end

    private

    # Resolve configurations for multiple targets, filtered to the given config names.
    # This is the shared implementation backing the public resolve_value* methods.
    #
    # Returns a hash from each input Target to its resolved config entries.
    # Raises ArgumentError if targets is empty or contains duplicate most-specific targets.
    def resolve_configs_by_names(targets:, names:)
      if targets.nil? || targets.empty?
        raise ArgumentError, "At least one target must be provided"
      end

      seen = {}
      target_messages = targets.map do |target|
        type_val, id = target.most_specific_target
        key = [type_val, id]
        if seen.key?(key)
          type_name = Configs::Twirp::TargetType.lookup(type_val)&.name || type_val.to_s
          raise ArgumentError, "Duplicate most-specific target: type #{type_name} id #{id}"
        end
        seen[key] = true

        target.to_proto
      end

      request = Configs::Twirp::ResolveConfigsByNamesRequest.new(targets: target_messages, names: names)
      response = twirp_client.resolve_configs_by_names(request)
      raise_if_error(response)

      # Map each input target to its resolved entries via most_specific_target lookup
      result = {}
      targets.each do |target|
        type_key, id = target.most_specific_target
        entries = {}
        if (by_id = response.data.configs_by_type[type_key])
          if (resolved = by_id.configs_by_id[id])
            resolved.configs.each do |name, config|
              entries[name] = Configs::Entry.from_twirp_config(config)
            end
          end
        end
        result[target] = entries
      end
      result
    end

    def twirp_client
      @twirp_client ||= Configs::Twirp::ConfigsClient.new(@connection)
    end

    def resolve_target_type(target_type)
      Configs::Twirp::TargetType.const_get(target_type)
    rescue NameError
      raise ArgumentError, "Unknown target type: #{target_type}. Valid types are: #{Configs::Twirp::TargetType.constants.join(", ")}"
    end

    def raise_if_error(response)
      return unless response.error

      raise RpcError.new(status: response.error.code, response_body: response.error.msg)
    end
  end
end
