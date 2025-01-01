# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::TrustTiers
  module TrustTier
    module V1
      class GetTrustTier
        include Api::Internal::Twirp::TrustTiers::TrustTier::V1::ActorsDependency

        attr_reader :req, :env

        def self.call(req, env)
          ActiveRecord::Base.connected_to(role: :reading) do
            new(req, env).call
          end
        end

        def initialize(request, env)
          @req = request
          @env = env
        end

        def call
          if req.id.blank?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "id")
          end

          actor_type, actor_id = Platform::Helpers::NodeIdentification.from_global_id(req.id.global_id)
          actor = case actor_type
          when "User"
            User.find_by(id: actor_id)
          when "Organization"
            Organization.find_by(id: actor_id)
          when "Repository"
            Repository.find_by(id: actor_id)
          when "Enterprise"
            Business.find_by(id: actor_id)
          when "Bot"
            Bot.find_by(id: actor_id)
          end

          if actor.nil?
            return Twirp::Error.not_found("actor does not exist", argument: "id")
          end

          client_name = env[:client_name] || Api::Internal::Twirp::UNKNOWN_CLIENT_NAME

          trust_tier = get_tier_for_actor(actor, client_name)

          { trust_tier: trust_tier.tier }
        end
      end
    end
  end
end
