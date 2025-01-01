# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      class GetActorsInfo
        include Api::Internal::Twirp::Actions::Core::V1::ActorsDependency

        attr_reader :req

        def self.call(req, env)
          new(req, env).call
        end

        def initialize(request, env)
          @req = request
          @env = env
        end

        def call
          return Twirp::Error.invalid_argument("must be non-empty", argument: "actor_global_ids") if req.actor_global_ids.empty?

          actors = req.actor_global_ids.map do |identity|
            log_fields = {
              "code.namespace" => self.class.name,
              "code.function" => "call",
              "gh.request_id" => GitHub.context[:request_id],
              "gh.catalog_service" => "github/actions",
              "gh.actions.unresolvable_global_id" => identity.global_id,
            }

            begin
              type, id = Platform::Helpers::NodeIdentification.from_global_id(identity.global_id)
            rescue Platform::Errors::NotFound
              GitHub.logger.info("unresolvable actor type encountered", log_fields)
              next
            end

            actor = case type
            when "User"
              User.find_by(id: id)
            when "Organization"
              Organization.find_by(id: id)
            when "Repository"
              Repositories.domain.by_id(id.to_i)
            when "Enterprise"
              Business.find_by(id: id)
            when "Bot"
              Bot.find_by(id: id)
            end

            if actor.nil?
              GitHub.logger.info("no actor found for database id", log_fields)
              next
            end

            actor = build_actor(actor)
            if actor.nil? || actor["type"] == "TYPE_INVALID"
              GitHub.logger.info("could not build actor", log_fields)
            end

            actor
          end

          # Twirp doesn't serialize nil as an empty Actor, it omits it entirely
          {
            actors: actors.map do |a|
              if a.nil?
                {}
              else
                a
              end
            end
          }
        end
      end
    end
  end
end
