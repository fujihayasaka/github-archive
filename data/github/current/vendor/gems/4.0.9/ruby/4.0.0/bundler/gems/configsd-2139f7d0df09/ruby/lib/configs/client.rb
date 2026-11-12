# frozen_string_literal: true

require "faraday"
require_relative "proto/configs/configs_pb"
require_relative "proto/configs/configs_twirp"
require_relative "errors"

module Configs
  # Main client for interacting with the Configsd service
  class Client
    # Initialize a new Configs client
    #
    # As this client will be almost exclusively used by the monolith which will
    # need full control over the configuration of the Faraday connection, it is
    # simplest to just accept a Faraday connection directly.
    #
    # The connection be configured with the following:
    #
    # - URL set to the Configsd service endpoint (ex: https://configsd.example.com:8080/twirp)
    # - HMAC middleware for authorization using the federated shared secret
    # - Any other desired Faraday middleware (logging, timeouts, statter metrics etc)

    # @param connection [Faraday::Connection] custom Faraday connection
    def initialize(connection)
      @connection = connection
    end

    # Resolve configurations by target
    #
    # @param target_id [Integer] The target ID
    # @param target_type [Symbol] The target type (e.g., "Repository", "User")
    # @return [Hash{String => Configs::Entry}] Map of config names to Config objects
    # @raise [Faraday::Error] If the HTTP request fails
    # @raise [Configs::RpcError] If the response is invalid
    def resolve_configs_by_target(target_id:, target_type:)
      target = Configs::Twirp::ConfigTarget.new(id: target_id, type: resolve_target_type(target_type))
      request = Configs::Twirp::ResolveConfigsByTargetRequest.new(target: target)
      response = twirp_client.resolve_configs_by_target(request)
      raise_if_error(response) || response.data.configs.configs.to_h.transform_values { |c| Configs::Entry.from_twirp_config(c) }
    end

    # Resolve configurations by target with owner information
    #
    # @param repo_id [Integer, nil] The repository ID (optional)
    # @param owner_id [Integer, nil] The owner/user ID (optional)
    # @param business_id [Integer, nil] The business ID (optional)
    # @return [Hash{String => Configs::Entry}] Map of config names to Config objects
    # @raise [Faraday::Error] If the HTTP request fails
    # @raise [Configs::RpcError] If the response is invalid
    def resolve_configs_by_target_with_owners(repo_id: nil, owner_id: nil, business_id: nil)
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
    def resolve_configs_by_targets_with_owners(targets:)
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

    private

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
