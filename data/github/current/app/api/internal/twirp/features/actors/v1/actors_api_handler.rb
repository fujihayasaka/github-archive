# typed: true
# frozen_string_literal: true

require "monolith-twirp-features-actors"

module Api::Internal::Twirp::Features
  module Actors
    module V1
      # Handler for the MonolithTwirp::Features::Actors::V1::ActorsAPIService
      class ActorsAPIHandler < Api::Internal::Twirp::Handler
        handles_service MonolithTwirp::Features::Actors::V1::ActorsAPIService
        allow_access_for :client, allowed_clients: %w[
          dev_portal_actors
        ].freeze

        # get_actors_by_id does not need the tenant context to function since it
        # it uses id to search for the underlying actor class and that isn't tenant-scoped.
        exempt_from_tenant_context_requirement(only: %i[get_actors_by_id])

        ACTOR_REQUEST_LIMIT = 1000

        # Public: Implementation of the GetActorsById Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Features::Actors::V1::GetActorsByIdRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Features::Actors::V1::GetActorsByIdResponse, or a Twirp::Error.
        sig { params(req: MonolithTwirp::Features::Actors::V1::GetActorsByIdRequest, env: T.untyped).returns(T.any(MonolithTwirp::Features::Actors::V1::GetActorsByIdResponse, Twirp::Error)) }
        def get_actors_by_id(req, env)
          if req.actor_ids.length > ACTOR_REQUEST_LIMIT
            return Twirp::Error.invalid_argument("only #{ACTOR_REQUEST_LIMIT} ids allowed at a time", argument: "actors")
          end

          # A global hash for storing req.actor_ids to their result.
          # This allows us to return the response actors in the same order as the request.
          # This contains ids for all actors, even if they are invalid.
          all_actor_ids = {}

          # Map actor classes to their ids and req.actor_id. Contains only valid actor classes and ids.
          # For exampe: {User: [1, 2, 3], Organization: [4, 5, 6]}
          actor_ids_by_class_map = req.actor_ids.each_with_object({}) do |actor_id, hash|
            actor_class = extract_actor_class_from_actor_id(actor_id)
            id = extract_id_from_actor_id(actor_id)
            all_actor_ids[actor_id] = nil
            if invalid_actor_class?(actor_class) || invalid_actor_id?(id)
              next
            else
              hash[actor_class] ||= []
              hash[actor_class] << id
            end
          end

          actor_ids_by_class_map.each do |actor_class, ids|
            if actor_class.ancestors.include?(ActiveRecord::Base)
              # If actor_class is a subclass of ActiveRecord::Base we can use ActiveRecord methods to look up the actors by id.
              actor_class.where(id: ids).each do |actor|
                actor_id = GitHub::FlipperActor.to_flipper_id(actor_class, actor.id)
                # This check is due to the edge case of https://github.com/github/feature-management/issues/562.
                # Classes like Bot and Organization inherit from User. Polymorphism allows ActiveRecord to properly look up the record,
                # but the Flipper id would be different. For example, if User:11 is really a Bot, the actual Flipper id would be Bot:11.
                # The Feature Flag Hub would see User:11 and Bot:11 as two different actors, but they are the same actor.
                # To avoid this issue with the Feature Flag Hub, we do not allow this behavior. You must provide the actual class you need in the id.
                if actor.class != actor_class
                  all_actor_ids[actor_id.to_s] = { id:  actor_id }
                else
                  tenant = actor.actor_tenant
                  actor_response = MonolithTwirp::Features::Actors::V1::Actor.new id: actor_id, name: actor.flipper_actor_name
                  actor_response.tenant = MonolithTwirp::Features::Actors::V1::Tenant.new name: tenant.name, id: tenant.id if tenant
                  actor_response.type = actor.class.to_s
                  display_name = actor.flipper_actor_display_name
                  actor_response.display_name = display_name if display_name
                  all_actor_ids[actor_id] = actor_response
                end
              end
            else
              # If actor_class is not a subclass of ActiveRecord::Base, we will just use the id portion of the Flipper id as the name.
              # This just assumes that the provided id is correct, since there is nothing the query against.
              ids.each do |id|
                actor_id = GitHub::FlipperActor.to_flipper_id(actor_class, id)
                actor_response = MonolithTwirp::Features::Actors::V1::Actor.new id: actor_id, name: id
                actor_response.type = actor_class.to_s
                all_actor_ids[actor_id] = actor_response
              end
            end
          end

          results = all_actor_ids.map do |actor_id, actor_info|
            if actor_info.nil?
              { id: actor_id }
            else
              actor_info
            end
          end
          MonolithTwirp::Features::Actors::V1::GetActorsByIdResponse.new actors: results
        end

        # Public: Implementation of the GetActorsByName Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Features::Actors::V1::GetActorsByNameRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Features::Actors::V1::GetActorsByNameResponse, or a Twirp::Error.
        sig { params(req: MonolithTwirp::Features::Actors::V1::GetActorsByNameRequest, env: T.untyped).returns(T.any(MonolithTwirp::Features::Actors::V1::GetActorsByNameResponse, Twirp::Error)) }
        def get_actors_by_name(req, env)
          if req.query.length > ACTOR_REQUEST_LIMIT
            return Twirp::Error.invalid_argument("only #{ACTOR_REQUEST_LIMIT} actors allowed to be queried at a time", argument: "query")
          end

          results = req.query.map do |q|
            query = T.cast(q, MonolithTwirp::Features::Actors::V1::GetActorsByNameQuery)
            result = MonolithTwirp::Features::Actors::V1::Actor.new name: query.name

            begin
              actor_class = query.type.constantize
              if actor_class.respond_to?(:from_flipper_actor_name)
                begin
                  actor = actor_class.from_flipper_actor_name(query.name)
                rescue ArgumentError
                  # If we fail to find the actor via from_flipper_actor_name, check if the actor_class is not a subclass of ActiveRecord::Base
                  # and try find by id using the name. This is to support the behaviour for these actor types defined in get_actors_by_id, where the
                  # name returned is the id.
                  if !actor && !actor_class.ancestors.include?(ActiveRecord::Base) && actor_class.respond_to?(:find_by_id)
                    actor = actor_class.find_by_id(query.name)
                  else
                    raise
                  end
                end

                # The actor.class.to_s == query.type check is due to the edge case of https://github.com/github/feature-management/issues/562.
                # Classes like Bot and Organization inherit from User. Polymorphism allows ActiveRecord to properly look up the record,
                # but the Flipper id would be different. For example, if User:11 is really a Bot, the actual Flipper id would be Bot:11.
                # The Feature Flag Hub would see User:11 and Bot:11 as two different actors, but they are the same actor.
                # To avoid this issue with the Feature Flag Hub, we do not allow this behavior. You must provide the actual class you need in the query.type.
                if actor && actor.class.to_s == query.type
                  result.id = actor.flipper_id
                  tenant = actor.actor_tenant
                  result.tenant = MonolithTwirp::Features::Actors::V1::Tenant.new name: tenant.name, id: tenant.id if tenant
                  result.type = actor.class.to_s
                  display_name = actor.flipper_actor_display_name
                  result.display_name = display_name if display_name
                end
              else
                GitHub.logger.info("query.type is not a valid FlipperActor class", "gh.actor.type" => query.type)
              end
            rescue NameError
              GitHub.logger.info("query.type is not a valid class name", "gh.actor.type" => query.type)
            rescue => e
              GitHub.logger.info("error getting actor of type #{query.type} with name #{query.name}: #{e.message}")
            end
            result
          end

          MonolithTwirp::Features::Actors::V1::GetActorsByNameResponse.new actors: results
        end

        sig { params(actor_id: String).returns(T.any(NilClass, Class)) }
        def extract_actor_class_from_actor_id(actor_id)
          GitHub::FlipperActor.class_name_from_flipper_id(actor_id).constantize
        rescue ArgumentError, NameError
          # The actor_id is invalid
          #   ArgumentError: doesn't contain a `:` separator. e.g. User1234 instead of User:1234
          # NameError: class_name is not a valid class. e.g. FakeClass:1234 instead of User:1234
          GitHub.logger.info(
            "Actor ID is invalid",
          )
          nil
        end

        sig { params(actor_id: String).returns(T.any(NilClass, String)) }
        def extract_id_from_actor_id(actor_id)
          GitHub::FlipperActor.id_from_flipper_id(actor_id)
        rescue ArgumentError
          # The actor_id is invalid
          #   ArgumentError: doesn't contain a `:` separator. e.g. User1234 instead of User:1234
          GitHub.logger.info(
            "Actor ID is invalid",
          )
          nil
        end

        sig { params(actor_class: T.any(NilClass, Class)).returns(T::Boolean) }
        def invalid_actor_class?(actor_class)
          # Actor class must be non-nil, and be a subclass of GitHub::FlipperActor (otherwise it isn't an actor)
          actor_class.nil? || !actor_class.ancestors.include?(GitHub::FlipperActor)
        end

        sig { params(id: T.any(NilClass, String)).returns(T::Boolean) }
        def invalid_actor_id?(id)
          id.nil? || id.empty?
        end
      end
    end
  end
end
