# typed: true
# frozen_string_literal: true

require "monolith-twirp-code_scanning-repositories"

module Api::Internal::Twirp::CodeScanning
  module Repositories
    module V1
      # Handler for the MonolithTwirp::CodeScanning::Repositories::V1::RepositoriesAPIService
      class RepositoriesAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["turboscan"]
        handles_service MonolithTwirp::CodeScanning::Repositories::V1::RepositoriesAPIService

        FIND_REPOSITORIES_HARD_LIMIT = 1000
        DEFAULT_BRANCH_RETRIABLE_ERRORS = [
          GitRPC::Timeout,
        ].freeze

        # Public: Implementation of the FindRepositories Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::CodeScanning::Repositories::V1::FindRepositoriesRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response, or a Twirp::Error.
        def find_repositories(req, env)
          GitHub.logger.with_named_tags("gh.request_id": GitHub.context[:request_id]) do
            return Twirp::Error.invalid_argument("must be non-empty", argument: "ids") if req.ids.empty?
            return Twirp::Error.invalid_argument("must have a length <= #{FIND_REPOSITORIES_HARD_LIMIT}", argument: "ids") if req.ids.size > FIND_REPOSITORIES_HARD_LIMIT

            repository_ids = req.ids.to_a
            GitHub.logger.info(
              "Fetching data for requested repositories.",
              "code.namespace": self.class.name,
              "code.function": __method__,
              "gh.repos.count": repository_ids.size,
            )

            response = MonolithTwirp::CodeScanning::Repositories::V1::FindRepositoriesResponse.new(
              repositories_by_id: build_repository_list(repository_ids),
            )

            GitHub.logger.info("Done finding repositories.", "code.namespace": self.class.name, "code.function": __method__)

            response
          end
        end

        private

        def build_repository_list(repository_ids)
          repositories = Repository.active.where(id: repository_ids).preload(:owner).index_by(&:id)
          hash = {}
          repository_ids.each do |repository_id|
            repository = repositories[repository_id]

            if repository.nil?
              GitHub.logger.info(
                "Repository does not exist.",
                "code.namespace": self.class.name,
                "code.function": __method__,
                "gh.repo.id": repository_id,
              )
              next
            end

            GitHub.logger.with_named_tags(
              "gh.repo.id": repository.id,
              "gh.repo.name": repository.name,
              "gh.owner.id": repository.owner_id,
              "gh.owner.login": repository.owner_display_login,
            ) do
              GitHub.logger.info(
                "Building response for repository.",
                "code.namespace": self.class.name,
                "code.function": __method__,
              )

              begin
                # There is a known bug in which some repos are missing owners.
                if repository.owner.blank?
                  GitHub.logger.warn(
                    "Repository has no owner.",
                    "code.namespace": self.class.name,
                    "code.function": __method__,
                  )
                  next
                end

                hash[repository_id] = MonolithTwirp::CodeScanning::Repositories::V1::Repository.new(
                  id: repository.id,
                  organization_id: repository.owner.is_a?(Organization) ? repository.owner_id : 0,
                  code_scanning_enabled: repository.security_feature_visible?(:CODE_SCANNING),
                  default_branch_ref: get_default_branch_ref(repository),
                  visibility: get_repository_visibility(repository),
                )
              rescue Repository::RpcDependency::UnroutedError, GitHub::DGit::NotFoundError, *DEFAULT_BRANCH_RETRIABLE_ERRORS => e
                Failbot.report(e)
                GitHub.logger.warn(
                  "Error while fetching default branch.",
                  "code.namespace": self.class.name,
                  "code.function": __method__,
                  "gh.exception.message": e.message,
                )
              end
            end
          end

          # Fill in values for repositories that could not be fetched.
          repository_ids.each do |repository_id|
            hash[repository_id] = empty_repository(repository_id) unless hash.key?(repository_id)
          end

          hash
        end

        def get_default_branch_ref(repository)
          attempts ||= 1
          repository.default_branch_ref&.qualified_name || ""
        rescue *DEFAULT_BRANCH_RETRIABLE_ERRORS => error
          attempts = T.must(attempts) + 1
          if attempts <= 3
            retry
          end
          raise error
        end

        def get_repository_visibility(repository)
          case repository&.visibility
          when Repository::PUBLIC_VISIBILITY
            MonolithTwirp::CodeScanning::Repositories::V1::Visibility::VISIBILITY_PUBLIC
          when Repository::PRIVATE_VISIBILITY
            MonolithTwirp::CodeScanning::Repositories::V1::Visibility::VISIBILITY_PRIVATE
          when Repository::INTERNAL_VISIBILITY
            MonolithTwirp::CodeScanning::Repositories::V1::Visibility::VISIBILITY_INTERNAL
          else
            MonolithTwirp::CodeScanning::Repositories::V1::Visibility::VISIBILITY_INVALID
          end
        end

        def empty_repository(repository_id)
          MonolithTwirp::CodeScanning::Repositories::V1::Repository.new(
            id: repository_id,
            organization_id: 0,
            code_scanning_enabled: false,
            default_branch_ref: "",
            visibility: :VISIBILITY_INVALID,
          )
        end
      end
    end
  end
end
