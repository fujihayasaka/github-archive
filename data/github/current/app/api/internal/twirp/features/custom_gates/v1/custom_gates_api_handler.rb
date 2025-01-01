# typed: true
# frozen_string_literal: true

require "feature_management_feature_flags"

module Api::Internal::Twirp::Features
  module CustomGates
    module V1
      # Handler for the FeatureManagement::FeatureFlags::Data::V1::MonolithCustomGatesService
      class CustomGatesAPIHandler < Api::Internal::Twirp::Handler
        extend T::Sig

        # TODO: Using vigilance for now for testing, but this should be changed to the actual client(s) that will use it
        allow_access_for :client, allowed_clients: %w[
          vigilance
        ].freeze

        handles_service FeatureManagement::FeatureFlags::Data::V1::MonolithCustomGatesService

        ACTOR_REQUEST_LIMIT = 1000
        CUSTOM_GATE_REQUEST_LIMIT = 20

        # Public: Implementation for the MonolithCustomGates Twirp RPC.
        #
        # req - The Twirp request as a FeatureManagement::FeatureFlags::Data::V1::MonolithCustomGatesRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp FeatureManagement::FeatureFlags::Data::V1::MonolithCustomGatesResponse containing the enabled result for each actor,
        # or a Twirp::Error.
        sig { params(req: FeatureManagement::FeatureFlags::Data::V1::MonolithCustomGateRequest, env: T.untyped).returns(T.any(FeatureManagement::FeatureFlags::Data::V1::MonolithCustomGateResponse, Twirp::Error)) } # rubocop:disable Layout/LineLength
        def monolith_custom_gate(req, env)
          if req.actor_ids.length == 0
            return Twirp::Error.invalid_argument("at least 1 actor_id expected", argument: "actors")
          end

          if req.actor_ids.length > ACTOR_REQUEST_LIMIT
            return Twirp::Error.invalid_argument("only #{ACTOR_REQUEST_LIMIT} actor_ids allowed at a time", argument: "actors")
          end

          if req.custom_gate_names.length == 0
            return Twirp::Error.invalid_argument("at least 1 custom_gate_name expected", argument: "custom_gate_names")
          end

          if req.custom_gate_names.length > CUSTOM_GATE_REQUEST_LIMIT
            return Twirp::Error.invalid_argument("only #{CUSTOM_GATE_REQUEST_LIMIT} custom_gate_names allowed at a time", argument: "custom_gate_names")
          end

          custom_gates = req.custom_gate_names.map do |custom_gate_name|
            group = Flipper.groups_registry.get(custom_gate_name)
            if group.nil?
              # Fire a metric to track the number of times a custom gate is requested that doesn't exist
              GitHub.dogstats.increment("feature_flags.monolith_custom_gates.invalid_custom_gate.count", tags: ["custom_gate_name:#{custom_gate_name}"])
              next
            end
            group
          end

          custom_gates.compact!

          actors = req.actor_ids.map do |actor_id|
            result = FeatureManagement::FeatureFlags::Data::V1::Actor.new actor_id: actor_id, enabled: false
            begin
              actor = GitHub::FlipperActor.from_flipper_id(actor_id)
              custom_gates.each do |custom_gate|
                result.enabled = custom_gate.match?(actor, nil)
                break if result.enabled # short circuit if enabled since we don't need to check any other custom gates
              end
            rescue NameError, ArgumentError
              # The actor_id is invalid
              #   NameError: the class name part of the actor id is not a valid class. e.g. FakeClass:1234 instead of User:1234
              #   ArgumentError: the actor id doesn't contain a `:` separator. e.g. User1234 instead of User:1234
              # Log this information, but don't raise or return an error and just leave the result as false
              GitHub.logger.info(
                "Actor ID is invalid",
              )
            end

            result
          end

          FeatureManagement::FeatureFlags::Data::V1::MonolithCustomGateResponse.new actors: actors
        end
      end
    end
  end
end
