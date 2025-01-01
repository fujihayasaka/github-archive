# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      class GetEnvironmentRepository
        NO_REPO_FOUND_MESSAGE = "Could not find the repository for the given environment"

        attr_reader :req

        def self.call(req)
          new(req).call
        end

        def initialize(request)
          @req = request
        end

        # Returns the repository's database id for a given environment's global id
        def call
          return Twirp::Error.invalid_argument("must be non-empty", argument: "environment_id") if req.environment_id.blank?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "environment_id") if req.environment_id.global_id.blank?

          log_fields = {
            "code.namespace" => self.class.name,
            "code.function" => "call",
            "gh.request_id" => GitHub.context[:request_id],
            "gh.catalog_service" => "github/actions",
            "gh.actions.environment.global_id" => req.environment_id.global_id,
          }

          begin
            type, id = Platform::Helpers::NodeIdentification.from_global_id(req.environment_id&.global_id)
          rescue Platform::Errors::NotFound
            GitHub.logger.info("unresolvable environment_id encountered", log_fields)
            return Twirp::Error.not_found("unresolvable environment global id")
          end

          environment_repository = case type
          when "Environment"
            Environment.find_by(id: id)&.repository
          end

          if environment_repository.nil?
            GitHub.logger.info(NO_REPO_FOUND_MESSAGE, log_fields)
            return Twirp::Error.not_found(NO_REPO_FOUND_MESSAGE)
          end

          {
            repository_database_id: environment_repository.id
          }
        end
      end
    end
  end
end
