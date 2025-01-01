# typed: strict
# frozen_string_literal: true

module Api::Internal::Twirp::Kredz
  module Core
    module V1
      class CanActorWriteSecrets

        NO_ACTOR_FOUND_MESSAGE = "no actor found for database id"

        sig { returns(MonolithTwirp::Kredz::Core::V1::CanActorWriteSecretsRequest) }
        attr_reader :req

        sig do
          params(req: MonolithTwirp::Kredz::Core::V1::CanActorWriteSecretsRequest)
          .returns(T.any(
            Twirp::Error,
            T::Hash[Symbol, T::Boolean]
          ))
        end
        def self.call(req)
          new(req).call
        end

        sig { params(request: MonolithTwirp::Kredz::Core::V1::CanActorWriteSecretsRequest).void }
        def initialize(request)
          @req = request
        end

        # Returns true if the actor has admin permissions (needed to write secrets)
        # on the passed list of owners.
        sig do
          returns(T.any(
            Twirp::Error,
            T::Hash[Symbol, T::Boolean]
          ))
        end
        def call
          return Twirp::Error.invalid_argument("must be non-empty", argument: "actor_global_id") if req.actor_global_id.blank?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "owner_global_ids") if req.owner_global_ids.empty?

          log_fields = {
              "code.namespace" => "CanActorWriteSecrets",
              "code.function" => "call",
              "gh.request_id" => GitHub.context[:request_id],
              "gh.catalog_service" => "github/kredz",
            }

          begin
            type, id = Platform::Helpers::NodeIdentification.from_global_id(req.actor_global_id&.id)
          rescue Platform::Errors::NotFound
            GitHub.logger.info("unresolvable actor type encountered", log_fields)
            return Twirp::Error.not_found("unresolvable actor global id")
          end

          unless actor = User.find_by(id:)
            GitHub.logger.info(NO_ACTOR_FOUND_MESSAGE, log_fields)
            return Twirp::Error.not_found(NO_ACTOR_FOUND_MESSAGE)
          end

          req.owner_global_ids.each do |owner|
            begin
              type, id = Platform::Helpers::NodeIdentification.from_global_id(owner&.id)
            rescue Platform::Errors::NotFound
              GitHub.logger.info("unresolvable owner_global_id encountered", log_fields)
              return Twirp::Error.not_found("unresolvable owner global id")
            end

            owner = case type
            when "Repository"
              if GitHub.flipper[:repos_domain_twirp].enabled?
                Repositories.domain.by_id(id)
              else
                Repository.find_by(id:)
              end
            when "Environment"
              Environment.find_by(id:)&.repository
            end

            if owner.nil?
              GitHub.logger.info("No owner of type found for given id", log_fields.merge({ "gh.kredz.owner.global_id.type" => type }))
              return Twirp::Error.not_found("No owner of type #{type} found for given id")
            end

            unless T.cast(owner, Repository).adminable_by?(actor) # rubocop:todo GitHub/AvoidCast
              return {
                can_write_secrets: false
              }
            end
          end

          {
            can_write_secrets: true
          }
        end
      end
    end
  end
end
