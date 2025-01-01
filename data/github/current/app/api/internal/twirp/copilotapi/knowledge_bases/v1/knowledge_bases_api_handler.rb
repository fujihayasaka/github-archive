# typed: true
# frozen_string_literal: true

require "monolith-twirp-copilotapi-knowledge_bases"

module Api::Internal::Twirp::Copilotapi
  extend T::Helpers

  module KnowledgeBases
    module V1
      # Handler for the MonolithTwirp::Copilotapi::KnowledgeBases::V1::KnowledgeBasesAPIService
      class KnowledgeBasesAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["copilot_api"]
        handles_service MonolithTwirp::Copilotapi::KnowledgeBases::V1::KnowledgeBasesAPIService

        # Public: Implementation of the ListKnowledgeBases Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Copilotapi::KnowledgeBases::V1::ListKnowledgeBasesRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Copilotapi::KnowledgeBases::V1::ListKnowledgeBasesResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Copilotapi::KnowledgeBases::V1::ListKnowledgeBasesRequest,
            env: Hash
          ).returns(T.any(MonolithTwirp::Copilotapi::KnowledgeBases::V1::ListKnowledgeBasesResponse, Twirp::Error))
        end
        def list_knowledge_bases(req, env)
          api_method = "list_knowledge_bases"
          GitHub.tracer.in_span("copilot.twirp.#{api_method}", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.#{api_method}") do
              # check required arguments
              return access_token_not_found(api_method) if req.access_token.blank?

              # check access control
              ac = make_access_control(req)
              current_user = ac.viewer
              return user_not_found(api_method) unless current_user.present?

              begin
                allowed = ac.access_allowed?(
                  :list_current_user_accessible_knowledge_bases,
                  {
                    resource: current_user,
                    current_repo: nil,
                    current_org: nil,
                    allow_integrations: true,
                    allow_user_via_granular_actor: true,
                  }
                )
              rescue Platform::Errors::Forbidden
                ip_restricted(req, current_user, nil, api_method)
              end

              return permission_denied(api_method) unless allowed

              copilot_api = copilot_api(req, current_user)

              # get knowledge bases
              response = copilot_api.list_knowledge_bases
              knowledge_bases = response[:kbs].map { |kb| convert(kb) }

              MonolithTwirp::Copilotapi::KnowledgeBases::V1::ListKnowledgeBasesResponse.new(
                knowledge_bases: knowledge_bases
              )
            end
          end
        end

        # Public: Implementation of the ListKnowledgeBasesForOrganization Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Copilotapi::KnowledgeBases::V1::ListKnowledgeBasesForOrganizationRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Copilotapi::KnowledgeBases::V1::ListKnowledgeBasesForOrganizationResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Copilotapi::KnowledgeBases::V1::ListKnowledgeBasesForOrganizationRequest,
            env: Hash
          ).returns(T.any(MonolithTwirp::Copilotapi::KnowledgeBases::V1::ListKnowledgeBasesForOrganizationResponse, Twirp::Error))
        end
        def list_knowledge_bases_for_organization(req, env)
          api_method = "list_knowledge_bases_for_organization"
          GitHub.tracer.in_span("copilot.twirp.#{api_method}", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.#{api_method}") do
              # check required arguments
              return access_token_not_found(api_method) if req.access_token.blank?

              # check access control
              ac = make_access_control(req)
              current_user = ac.viewer
              return user_not_found(api_method) unless current_user.present?

              org = Organization.find_by(id: req.organization_id)
              return org_not_found(api_method) if org.nil?

              begin
                allowed = ac.access_allowed?(
                  :administer_knowledge_base,
                  {
                    resource: org,
                    current_repo: nil,
                    current_org: org,
                    allow_integrations: true,
                    allow_user_via_granular_actor: true,
                  }
                )
              rescue Platform::Errors::Forbidden
                return ip_restricted(req, current_user, org, api_method)
              end

              return permission_denied(api_method) unless allowed

              copilot_api = copilot_api(req, current_user)

              # get knowledge bases
              response = copilot_api.list_org_knowledge_bases(org_id: T.must(org.id))
              knowledge_bases = response[:kbs].map { |kb| convert(kb) }

              MonolithTwirp::Copilotapi::KnowledgeBases::V1::ListKnowledgeBasesForOrganizationResponse.new(knowledge_bases: knowledge_bases)
            end
          end
        end

        # Public: Implementation of the ListKnowledgeBaseDistinctRepos Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Copilotapi::KnowledgeBases::V1::ListKnowledgeBaseDistinctReposRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Copilotapi::KnowledgeBases::V1::ListKnowledgeBaseDistinctReposResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Copilotapi::KnowledgeBases::V1::ListKnowledgeBaseDistinctReposRequest,
            env: Hash
          ).returns(T.any(MonolithTwirp::Copilotapi::KnowledgeBases::V1::ListKnowledgeBaseDistinctReposResponse, Twirp::Error))
        end
        def list_knowledge_base_distinct_repos(req, env)
          api_method = "list_knowledge_base_distinct_repos"
          GitHub.tracer.in_span("copilot.twirp.#{api_method}", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.#{api_method}") do
              # check required arguments
              return access_token_not_found(api_method) if req.access_token.blank?

              # check access control
              ac = make_access_control(req)
              current_user = ac.viewer
              return user_not_found(api_method) unless current_user.present?

              begin
                allowed = ac.access_allowed?(
                  :list_current_user_accessible_knowledge_bases,
                  {
                    resource: current_user,
                    current_repo: nil,
                    current_org: nil,
                    allow_integrations: true,
                    allow_user_via_granular_actor: true,
                  }
                )
              rescue Platform::Errors::Forbidden
                return ip_restricted(req, current_user, nil, api_method)
              end

              return permission_denied(api_method) unless allowed

              copilot_api = copilot_api(req, current_user)

              # get knowledge bases
              response = copilot_api.list_knowledge_bases

              source_repos_map = response[:kbs].map { |kb| kb[:sourceRepos] }
                                          .flatten
                                          .filter { |repo| repo[:description].present? }
                                          .to_h { |repo| [repo[:id], repo] }

              repos_set = Repositories::Public.load_repositories(source_repos_map.keys)
              repo_details = repos_set.map do |repo|
                source_repo = source_repos_map[repo.id]
                MonolithTwirp::Copilotapi::KnowledgeBases::V1::RepoDetails.new(
                  id: repo.id,
                  owner_id: repo.owner_id,
                  name_with_owner: repo.nwo,
                  description: source_repo[:description],
                  paths: source_repo[:paths],
                )
              end

              MonolithTwirp::Copilotapi::KnowledgeBases::V1::ListKnowledgeBaseDistinctReposResponse.new(
                repos: repo_details
              )
            end
          end
        end

        # Public: Implementation of the GetKnowledgeBase Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Copilotapi::KnowledgeBases::V1::GetKnowledgeBaseRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Copilotapi::KnowledgeBases::V1::GetKnowledgeBaseResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Copilotapi::KnowledgeBases::V1::GetKnowledgeBaseRequest,
            env: Hash
          ).returns(T.any(MonolithTwirp::Copilotapi::KnowledgeBases::V1::GetKnowledgeBaseResponse, Twirp::Error))
        end
        def get_knowledge_base(req, env)
          api_method = "get_knowledge_base"
          GitHub.tracer.in_span("copilot.twirp.#{api_method}", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.#{api_method}") do
              # check required arguments
              return access_token_not_found(api_method) if req.access_token.blank?

              return blank_knowledge_base(api_method) if req.knowledge_base_id.blank?

              # check access control
              ac = make_access_control(req)
              current_user = ac.viewer

              return user_not_found(api_method) unless current_user.present?

              copilot_api = copilot_api(req, current_user)

              # get knowledge base
              begin
                response = copilot_api.get_knowledge_base(knowledge_base_id: req.knowledge_base_id)
              rescue CopilotAPI::NotFoundError
                return kb_not_found(api_method)
              end

              knowledge_base = convert(response[:kb])

              org = Organization.find_by(id: knowledge_base.owner_id)
              return org_not_found(api_method) if org.nil?

              begin
                allowed = ac.access_allowed?(
                  :get_knowledge_base,
                  {
                    resource: org,
                    current_repo: nil,
                    current_org: org,
                    allow_integrations: true,
                    allow_user_via_granular_actor: true,
                  }
                )
              rescue Platform::Errors::Forbidden
                ip_restricted(req, current_user, org, api_method)
              end

              return permission_denied(api_method) unless allowed

              MonolithTwirp::Copilotapi::KnowledgeBases::V1::GetKnowledgeBaseResponse.new(
                knowledge_base: knowledge_base
              )
            end
          end
        end

        # Public: Implementation of the CreateKnowledgeBase Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Copilotapi::KnowledgeBases::V1::CreateKnowledgeBaseRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Copilotapi::KnowledgeBases::V1::CreateKnowledgeBaseResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Copilotapi::KnowledgeBases::V1::CreateKnowledgeBaseRequest,
            env: Hash
          ).returns(T.any(MonolithTwirp::Copilotapi::KnowledgeBases::V1::CreateKnowledgeBaseResponse, Twirp::Error))
        end
        def create_knowledge_base(req, env)
          api_method = "create_knowledge_base"
          GitHub.tracer.in_span("copilot.twirp.#{api_method}", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.#{api_method}") do
              # check required arguments
              return access_token_not_found(api_method) if req.access_token.blank?
              return Twirp::Error.invalid_argument("must be non-empty", argument: "name") if req.name.blank?
              return Twirp::Error.invalid_argument("must be non-empty", argument: "source_repos") if req.source_repos.blank?
              return Twirp::Error.invalid_argument("must be non-empty", argument: "repos") if req.repos.blank?

              # check that owner type is not invalid
              return Twirp::Error.invalid_argument("must be organization or user", argument: "owner_type") if owner_type_to_string(req.owner_type).nil?

              # check that visibility is not invalid
              return Twirp::Error.invalid_argument("must be private, internal, or public", argument: "visibility") if visibility_to_string(req.visibility).nil?

              # check access control
              ac = make_access_control(req)
              current_user = ac.viewer
              return user_not_found(api_method) unless current_user.present?

              org = Organization.find_by(id: req.owner_id)
              return org_not_found(api_method) if org.nil?

              begin
                allowed = ac.access_allowed?(
                  :administer_knowledge_base,
                  {
                    resource: org,
                    current_repo: nil,
                    current_org: org,
                    allow_integrations: true,
                    allow_user_via_granular_actor: true,
                  }
                )
              rescue Platform::Errors::Forbidden
                return ip_restricted(req, current_user, org, api_method)
              end

              return permission_denied(api_method) unless allowed

              input_repo_ids = Repository.with_names_with_owners(req.repos).pluck(:id)
              return Twirp::Error.not_found("repository not found") if req.repos.size != input_repo_ids.size

              accessible_repo_ids = user_accessible_repo_ids(input_repo_ids, current_user)
              return Twirp::Error.permission_denied("knowledge base not created") if accessible_repo_ids.sort != input_repo_ids.sort

              input_source_repo_ids = req.source_repos.map { |repo| repo["id"] }
              accessible_input_repo_ids = user_accessible_repo_ids(input_source_repo_ids, current_user)
              return Twirp::Error.permission_denied("knowledge base not created") if accessible_input_repo_ids.sort != input_source_repo_ids.sort

              copilot_api = copilot_api(req, current_user)

              # create knowledge base
              response = copilot_api.create_knowledge_base({
                name: req.name,
                description: req.description,
                source_repos: req.source_repos,
                owner_id: req.owner_id,
                owner_type: owner_type_to_string(req.owner_type),
                repos: req.repos,
                visibility: visibility_to_string(req.visibility),
              })

              MonolithTwirp::Copilotapi::KnowledgeBases::V1::CreateKnowledgeBaseResponse.new(
                id: response[:id]
              )
            end
          end
        end

        # Public: Implementation of the UpdateKnowledgeBase Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Copilotapi::KnowledgeBases::V1::UpdateKnowledgeBaseRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Copilotapi::KnowledgeBases::V1::UpdateKnowledgeBaseResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Copilotapi::KnowledgeBases::V1::UpdateKnowledgeBaseRequest,
            env: Hash
          ).returns(T.any(MonolithTwirp::Copilotapi::KnowledgeBases::V1::UpdateKnowledgeBaseResponse, Twirp::Error))
        end
        def update_knowledge_base(req, env)
          api_method = "update_knowledge_base"
          GitHub.tracer.in_span("copilot.twirp.#{api_method}", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.#{api_method}") do
              # check for existing token
              return access_token_not_found(api_method) if req.access_token.blank?

              # check for knowledge base id
              return blank_knowledge_base(api_method) if req.knowledge_base_id.blank?

              # check access control
              ac = make_access_control(req)
              current_user = ac.viewer

              return user_not_found(api_method) unless current_user.present?

              copilot_api = copilot_api(req, current_user)

              # get knowledge base
              begin
                response = copilot_api.get_knowledge_base(knowledge_base_id: req.knowledge_base_id)
                knowledge_base = convert(response[:kb])
              rescue CopilotAPI::NotFoundError
                return kb_not_found(api_method)
              end

              org = Organization.find_by(id: knowledge_base.owner_id)
              return org_not_found(api_method) if org.nil?

              begin
                allowed = ac.access_allowed?(
                  :administer_knowledge_base,
                  {
                    resource: org,
                    current_repo: nil,
                    current_org: org,
                    allow_integrations: true,
                    allow_user_via_granular_actor: true,
                  }
                )
              rescue Platform::Errors::Forbidden
                return ip_restricted(req, current_user, org, api_method)
              end

              return permission_denied(api_method) unless allowed

              input_repo_ids = Repository.with_names_with_owners(req.repos).pluck(:id)
              return Twirp::Error.not_found("repository not found") if req.repos.size != input_repo_ids.size

              accessible_repo_ids = user_accessible_repo_ids(input_repo_ids, current_user)
              return Twirp::Error.permission_denied("knowledge base not updated") if accessible_repo_ids.sort != input_repo_ids.sort

              input_source_repo_ids = req.source_repos.map { |repo| repo["id"] }
              accessible_input_repo_ids = user_accessible_repo_ids(input_source_repo_ids, current_user)
              return Twirp::Error.permission_denied("knowledge base not updated") if accessible_input_repo_ids.sort != input_source_repo_ids.sort

              copilot_api.update_knowledge_base(req.knowledge_base_id, {
                name: req.name.blank? ? knowledge_base.name : req.name,
                description: req.description.blank? ? knowledge_base.description : req.description,
                source_repos: req.source_repos.blank? ? knowledge_base.source_repos : req.source_repos,
                repos: req.repos.blank? ? knowledge_base.repos : req.repos,
                visibility: visibility_to_string(req.visibility).nil? ? visibility_to_string(knowledge_base.visibility) : visibility_to_string(req.visibility),
              })

              MonolithTwirp::Copilotapi::KnowledgeBases::V1::UpdateKnowledgeBaseResponse.new
            end
          end
        end

        # Public: Implementation of the DeleteKnowledgeBase Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Copilotapi::KnowledgeBases::V1::DeleteKnowledgeBaseRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Copilotapi::KnowledgeBases::V1::DeleteKnowledgeBaseResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Copilotapi::KnowledgeBases::V1::DeleteKnowledgeBaseRequest,
            env: Hash
          ).returns(T.any(MonolithTwirp::Copilotapi::KnowledgeBases::V1::DeleteKnowledgeBaseResponse, Twirp::Error))
        end
        def delete_knowledge_base(req, env)
          api_method = "delete_knowledge_base"
          GitHub.tracer.in_span("copilot.twirp.#{api_method}", kind: :internal) do
            GitHub.dogstats.distribution_time("copilot.twirp.#{api_method}") do
              # check required arguments
              return access_token_not_found(api_method) if req.access_token.blank?
              return blank_knowledge_base(api_method) if req.knowledge_base_id.blank?

              # check access control
              ac = make_access_control(req)
              current_user = ac.viewer
              return user_not_found(api_method) unless current_user.present?

              copilot_api = copilot_api(req, current_user)

              begin
                response = copilot_api.get_knowledge_base(knowledge_base_id: req.knowledge_base_id)
                kb = response[:kb]
              rescue CopilotAPI::NotFoundError
                return kb_not_found(api_method)
              end

              org = Organization.find_by(id: kb[:ownerID])
              return org_not_found(api_method) unless org.present?

              begin
                allowed = ac.access_allowed?(
                  :administer_knowledge_base,
                  {
                    resource: org,
                    current_repo: nil,
                    current_org: org,
                    allow_integrations: true,
                    allow_user_via_granular_actor: true,
                  }
                )
              rescue Platform::Errors::Forbidden
                return ip_restricted(req, current_user, org, api_method)
              end

              return permission_denied(api_method) unless allowed

              # delete knowledge base
              copilot_api.delete_knowledge_base(knowledge_base_id: req.knowledge_base_id)

              MonolithTwirp::Copilotapi::KnowledgeBases::V1::DeleteKnowledgeBaseResponse.new
            end
          end
        end

        private

        sig { params(req: T.untyped, user: User).returns(Copilot::User::CopilotApi) }
        def copilot_api(req, user)
          user.copilot_api(
            integration_id: CopilotAPI::COPILOT_KNOWLEDGE_BASE_INTEGRATION_ID,
            real_ip: req.ip_address
          )
        end

        sig { params(req: T.untyped).returns(CopilotAPI::AccessControl) }
        def make_access_control(req)
          ac_opts = {
            token: req.access_token,
            ip: req.ip_address,
          }

          # If the token is a signed auth token, set context needed to
          # treat the token as a web session
          if GitHub::Authentication::SignedAuthToken.valid_format?(req.access_token)
            parsed_token = verified_token(req)
            ac_opts[:authenticated_actor_using_web_session] = true
            ac_opts[:viewer] = parsed_token.user
            ac_opts[:user_session] = parsed_token.session
          end

          CopilotAPI::AccessControl.new(ac_opts)
        end

        # This api is called from both GitHub chat and the knowledge base management
        # CRUD page, so we need to verify against both scopes
        def verified_token(req)
          chat_scope_token = GitHub::Authentication::SignedAuthToken.verify(
            token: req.access_token,
            scope: Copilot::User::CopilotApi::SSAT_SCOPE_GITHUB_CHAT,
          )

          kb_scope_token = GitHub::Authentication::SignedAuthToken.verify(
            token: req.access_token,
            scope: Copilot::User::CopilotApi::SSAT_SCOPE_GITHUB_DOCSETS,
          )

          [chat_scope_token, kb_scope_token].find(&:valid?) || chat_scope_token
        end

        sig { params(kb: Hash).returns(MonolithTwirp::Copilotapi::KnowledgeBases::V1::KnowledgeBase) }
        def convert(kb)
          kb = kb.with_indifferent_access
          scoping_query = KnowledgeBase::ScopingQuery.from_source_repositories(source_repos: kb[:sourceRepos])

          GitHub.logger.info("CopilotApi::KnowledgeBases scoping query",
            "gh.copilotapi.knowledge_base.id": kb[:id],
            "gh.copilotapi.knowledge_base.scoping_query": scoping_query
          )

          MonolithTwirp::Copilotapi::KnowledgeBases::V1::KnowledgeBase.new(
            created_at: Google::Protobuf::Timestamp.new(seconds: DateTime.parse(kb[:createdAt]).to_i),
            created_by_id: kb[:createdByID],
            description: kb[:description],
            id: kb[:id],
            name: kb[:name],
            owner_id: kb[:ownerID],
            owner_type: owner_type(kb[:ownerType]),
            repos: kb[:repos],
            scoping_query: scoping_query,
            source_repos: kb[:sourceRepos].present? ? kb[:sourceRepos].map { |repo| convert_source_repo(repo) } : [],
            updated_at: Google::Protobuf::Timestamp.new(seconds: DateTime.parse(kb[:updatedAt]).to_i),
            visibility: visibility(kb[:visibility]),
          )
        end

        def convert_source_repo(repo)
          MonolithTwirp::Copilotapi::KnowledgeBases::V1::Repo.new(id: repo[:id], owner_id: repo[:ownerID], paths: repo[:paths])
        end

        def owner_type(value)
          case value
          when "organization"
            MonolithTwirp::Copilotapi::KnowledgeBases::V1::OwnerType::OWNER_TYPE_ORG
          when "user"
            MonolithTwirp::Copilotapi::KnowledgeBases::V1::OwnerType::OWNER_TYPE_USER
          else
            MonolithTwirp::Copilotapi::KnowledgeBases::V1::OwnerType::OWNER_TYPE_INVALID
          end
        end

        def owner_type_to_string(value)
          case MonolithTwirp::Copilotapi::KnowledgeBases::V1::OwnerType.resolve(value)
          when MonolithTwirp::Copilotapi::KnowledgeBases::V1::OwnerType::OWNER_TYPE_ORG
            "organization"
          when MonolithTwirp::Copilotapi::KnowledgeBases::V1::OwnerType::OWNER_TYPE_USER
            "user"
          else
            nil
          end
        end

        def visibility(value)
          case value
          when "private"
            MonolithTwirp::Copilotapi::KnowledgeBases::V1::Visibility::VISIBILITY_PRIVATE
          when "internal"
            MonolithTwirp::Copilotapi::KnowledgeBases::V1::Visibility::VISIBILITY_INTERNAL
          when "public"
            MonolithTwirp::Copilotapi::KnowledgeBases::V1::Visibility::VISIBILITY_PUBLIC
          else
            MonolithTwirp::Copilotapi::KnowledgeBases::V1::Visibility::VISIBILITY_INVALID
          end
        end

        def visibility_to_string(value)
          case MonolithTwirp::Copilotapi::KnowledgeBases::V1::Visibility.resolve(value)
          when MonolithTwirp::Copilotapi::KnowledgeBases::V1::Visibility::VISIBILITY_PRIVATE
            "private"
          when MonolithTwirp::Copilotapi::KnowledgeBases::V1::Visibility::VISIBILITY_INTERNAL
            "internal"
          when MonolithTwirp::Copilotapi::KnowledgeBases::V1::Visibility::VISIBILITY_PUBLIC
            "public"
          else
            nil
          end
        end

        def user_accessible_repo_ids(repo_ids, current_user)
          # Filter repos associated with the user
          associated_repository_ids = current_user.associated_repository_ids(
            repository_ids: repo_ids,
          )

          # Get the user accessible repos
          accessible_repositories = Repositories::Public.accessible_repositories(
            repository_ids: repo_ids,
            associated_repository_ids: associated_repository_ids
          )

          accessible_repositories.pluck(:id)
        end

        def access_token_not_found(api_method)
          GitHub.dogstats.increment("copilot.twirp.#{api_method}.errors", tags: ["error:access_token"])
          Twirp::Error.invalid_argument("must be non-empty", argument: "access_token")
        end

        def blank_knowledge_base(api_method)
          GitHub.dogstats.increment("copilot.twirp.#{api_method}.errors", tags: ["error:kb_id_blank"])
          Twirp::Error.invalid_argument("must be non-empty", argument: "knowledge_base_id")
        end

        def user_not_found(api_method)
          GitHub.dogstats.increment("copilot.twirp.#{api_method}.errors", tags: ["error:user_not_found"])
          Twirp::Error.not_found("user not found")
        end

        def org_not_found(api_method)
          GitHub.dogstats.increment("copilot.twirp.#{api_method}.errors", tags: ["error:org_not_found"])
          Twirp::Error.not_found("organization not found")
        end

        def permission_denied(api_method)
          GitHub.dogstats.increment("copilot.twirp.#{api_method}.errors", tags: ["error:permission_denied"])
          Twirp::Error.not_found("permission denied")
        end

        def kb_not_found(api_method)
          GitHub.dogstats.increment("copilot.twirp.#{api_method}.errors", tags: ["error:kb_not_found"])
          Twirp::Error.not_found("knowledge base not found")
        end

        def ip_restricted(req, current_user, org, api_method)
          GitHub.dogstats.increment("copilot.twirp.#{api_method}.errors", tags: ["error:ip_restricted"])
          GitHub.logger.info("CopilotApi::KnowledgeBases access control failed",
            "gh.copilotapi.control_access.action": api_method.to_sym,
            "gh.copilotapi.control_access.viewer_id": current_user.id,
            "gh.copilotapi.knowledge_base.id": req.respond_to?(:knowledge_base_id) ? req.knowledge_base_id : nil,
            "gh.copilotapi.knowledge_base.ip_address": req.ip_address,
            "gh.copilotapi.knowledge_base.organization_id": org&.id,
          )
          Twirp::Error.not_found("permission denied")
        end
      end
    end
  end
end
