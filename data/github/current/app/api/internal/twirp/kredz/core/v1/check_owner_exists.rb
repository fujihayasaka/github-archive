# typed: strict
# frozen_string_literal: true

module Api::Internal::Twirp::Kredz
  module Core
    module V1
      class CheckOwnerExists

        sig { returns(MonolithTwirp::Kredz::Core::V1::CheckOwnerExistsRequest) }
        attr_reader :req

        sig do
          params(
            req: MonolithTwirp::Kredz::Core::V1::CheckOwnerExistsRequest
          ).returns(T.any(
            Twirp::Error,
            T::Hash[Symbol, T::Boolean]
          ))
        end
        def self.call(req)
          new(req).call
        end

        sig { params(request: MonolithTwirp::Kredz::Core::V1::CheckOwnerExistsRequest).void }
        def initialize(request)
          @req = request
        end

        # Returns true if the owner exists, else false.
        sig do
          returns(T.any(
            Twirp::Error,
            T::Hash[Symbol, T::Boolean]
          ))
        end
        def call
          return Twirp::Error.invalid_argument("must not be empty", argument: "owner_global_id") if req.owner_global_id.blank?

          log_fields = {
            "code.namespace" => "CheckOwnerExists",
            "code.function" => "call",
            "gh.request_id" => GitHub.context[:request_id],
            "gh.catalog_service" => "github/kredz",
          }

          begin
            type, id = Platform::Helpers::NodeIdentification.from_global_id(req.owner_global_id&.id)
          rescue Platform::Errors::NotFound
            GitHub.logger.info("unresolvable owner_global_id encountered", log_fields)
            return Twirp::Error.not_found("unresolvable owner global id")
          end

          owner = case type
          when "Organization"
            Organization.find_by(id:)
          when "User"
            User.find_by(id:)
          when "Repository"
            Repository.find_by(id:)
          when "Environment"
            Environment.find_by(id:)&.repository
          end

          if owner.nil?
            GitHub.logger.info("No owner of type found for given id", log_fields.merge({ "gh.kredz.owner.global_id.type" => type }))
            return {
              owner_exists: false
            }
          end

          {
            owner_exists: true
          }
        end
      end
    end
  end
end
