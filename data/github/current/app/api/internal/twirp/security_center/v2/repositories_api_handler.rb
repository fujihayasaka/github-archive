# typed: true
# frozen_string_literal: true

require "security_center_proto"

class Api::Internal::Twirp < ::Api::Internal
  module SecurityCenter
    module V2

      # Provides access to Repository data.
      class RepositoriesAPIHandler < SecurityCenterAPIHandler
        SECURITY_FEATURES = [:CODE_SCANNING].freeze

        handles_service(GitHub::Proto::SecurityCenter::Repositories::V2::RepositoryAPIService)

        allow_access_for :client, allowed_clients: ["turboscan"].freeze

        FIND_REPOSITORIES_HARD_LIMIT = 1000
        DEFAULT_BRANCH_RETRIABLE_ERRORS = [
          GitRPC::Timeout,
        ].freeze

        # This API is required to work cross multi-tenant since
        # it allows microservices to request repository data
        # from any batch of repository ids for data backfill.
        exempt_from_tenant_context_requirement

        def before_rpc(rack_env, env)
          Failbot.push(app: "github-security-center")

          # grab client name here for logs/stats; not available later
          if (client_key = rack_env[:request_hmac_key])
            env[:client_name] = GitHub.api_internal_twirp_hmac_settings[client_key]
          end
        end

        # Public: Implementation of the FindRepositories Twirp RPC.
        #
        # req - The Twirp request as a GitHub::Proto::SecurityCenter::Repositories::V2::FindRepositoriesRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response data, a list of repositories, suitable for use in
        # a GitHub::Proto::SecurityCenter::Repositories::V2::FindRepositoriesResponse.
        def find_repositories(req, env)
          GitHub.logger.with_named_tags("gh.request_id": GitHub.context[:request_id], "gh.security_center.api.client.name": env[:client_name]) do
            GitHub.logger.info("Fetching data for requested repos", "code.namespace": self.class.name, "code.function": __method__)

            if req.ids.empty?
              return Twirp::Error.invalid_argument("must be non-empty", argument: "ids")
            elsif req.ids.size > FIND_REPOSITORIES_HARD_LIMIT
              return Twirp::Error.invalid_argument("must have a length <= #{FIND_REPOSITORIES_HARD_LIMIT}", argument: "ids")
            else
              # req.ids is a Google::Protobuf::RepeatedField,
              # and we need to call #to_a to get a value usable
              # by ActiveRecord.
              repo_ids = req.ids.to_a

              GitHub.dogstats.count("security_center.repositories_api_handler.repo_ids.count", repo_ids.length)

              scope = Repository.active.where(id: repo_ids).preload(:owner)
              response = {
                repositoriesById: build_repository_list(scope, repo_ids, req.include_security_feature_configured, req.include_protected_branches),
              }

              GitHub.logger.info("Done finding repos", "code.namespace": self.class.name, "code.function": __method__)

              response
            end
          end
        end

        private

        # Private: Convert an array of Repository objects to the Twirp response FindRepositoriesResponse.
        #
        # repositories - The array of Repository objects.
        #
        # Returns an array of Hash objects with repository data that matches the
        # Twirp definition.
        def build_repository_list(repositories, repo_ids, include_security_feature_configured, include_protected_branches)
          security_features = SECURITY_FEATURES

          hash = repositories.each_with_object({}) do |repository, memo|
            GitHub.dogstats.distribution_time("security_center.repositories_api_handler.build_repository.dist") do
              owner_type = repository.owner.is_a?(Organization) ? "org" : "user"
              GitHub.logger.with_named_tags(
                "gh.repo.id": repository.id,
                "gh.repo.name": repository.name,
                "gh.owner.id": repository.owner_id,
                "gh.owner.login": repository.owner_display_login,
                "gh.#{owner_type}.id": repository.owner_id,
                "gh.#{owner_type}.login": repository.owner_display_login,
              ) do
                GitHub.logger.info(
                  "Building response for repo",
                  "code.namespace": self.class.name,
                  "code.function": __method__,
                )

                begin
                  # There is a known bug in which some repos are missing owners.
                  if repository.owner.blank?
                    GitHub.logger.warn(
                      "Repo has no owner",
                      "code.namespace": self.class.name,
                      "code.function": __method__,
                    )
                    memo[repository.id] = empty_repository(repository.id, security_features)
                    next
                  end

                  memo[repository.id] = {
                    id: repository.id,
                    organization_id: repository.owner.is_a?(Organization) ? repository.owner_id : 0,
                    security_feature_details: security_features.map do |feature|
                      {
                        security_feature: feature,
                        feature_visible: repository.security_feature_visible?(feature),
                        # only call helper if feature_configured is explicitly requested by client
                        feature_configured: include_security_feature_configured ? repository.security_feature_configured?(feature) : false
                      }
                    end,
                    default_branch_ref: get_default_branch_ref(repository),
                    visibility: get_repository_visibility(repository)
                  }
                  if include_protected_branches
                    memo[repository.id][:protected_branches] = repository.protected_branches.map do |b|
                      {
                        id: b.id,
                        pattern: b.name,
                      }
                    end
                  end
                rescue Repository::RpcDependency::UnroutedError, GitHub::DGit::NotFoundError, *DEFAULT_BRANCH_RETRIABLE_ERRORS => e
                  report_error(e)
                  memo[repository.id] = empty_repository(repository.id, security_features)
                end
              end
            end
          end

          # Fill in missing/deleted repos with empty data values.
          repo_ids.each do |repo_id|
            unless hash.key?(repo_id)
              GitHub.logger.info(
                "Building response for missing/deleted repo",
                "code.namespace": self.class.name,
                "code.function": __method__,
                "gh.repo.id": repo_id,
              )

              hash[repo_id] = empty_repository(repo_id, security_features)
            end
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

        # Parse repository.visibility and output values for
        # enum hydro.schemas.github.security_center.v1.entities.Repository.Visibility
        def get_repository_visibility(repository)
          return :VISIBILITY_UNKNOWN if repository.nil?

          case repository.visibility
          when Repository::PUBLIC_VISIBILITY
            :PUBLIC
          when Repository::PRIVATE_VISIBILITY
            :PRIVATE
          when Repository::INTERNAL_VISIBILITY
            :INTERNAL
          else
            :VISIBILITY_UNKNOWN
          end
        end

        def empty_repository(repo_id, security_features)
          {
            id: repo_id,
            organization_id: 0,
            security_feature_details: security_features.map do |feature|
              {
                security_feature: feature,
                feature_visible: false
              }
            end,
            default_branch_ref: "",
            visibility: get_repository_visibility(nil)
          }
        end

        def report_error(error)
          GitHub.dogstats.increment(
            "security_center.repositories_api_handler.repository_error",
            tags: ["exception:#{error.class.name.parameterize}"],
          )
          Failbot.report(error)
        end
      end
    end
  end
end
