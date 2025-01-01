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
          # check required arguments
          return Twirp::Error.invalid_argument("must be non-empty", argument: "access_token") if req.access_token.blank?

          # check access control
          ac = make_access_control(req)
          current_user = ac.viewer
          return Twirp::Error.not_found("user not found") unless current_user.present?

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

          return Twirp::Error.not_found("user not found") unless allowed

          copilot_api = copilot_api(req, current_user)

          # get knowledge bases
          response = copilot_api.list_knowledge_bases
          knowledge_bases = response[:kbs].map { |kb| convert(kb) }

          MonolithTwirp::Copilotapi::KnowledgeBases::V1::ListKnowledgeBasesResponse.new(
            knowledge_bases: knowledge_bases
          )
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
          # check required arguments
          return Twirp::Error.invalid_argument("must be non-empty", argument: "access_token") if req.access_token.blank?

          # check access control
          ac = make_access_control(req)
          current_user = ac.viewer
          return Twirp::Error.not_found("user not found") unless current_user.present?

          org = Organization.find_by(id: req.organization_id)
          return Twirp::Error.not_found("organization not found") if org.nil?

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

          return Twirp::Error.not_found("organization not found") unless allowed

          copilot_api = copilot_api(req, current_user)

          # get knowledge bases
          response = copilot_api.list_org_knowledge_bases(org_id: T.must(org.id))
          knowledge_bases = response[:kbs].map { |kb| convert(kb) }

          MonolithTwirp::Copilotapi::KnowledgeBases::V1::ListKnowledgeBasesForOrganizationResponse.new(knowledge_bases: knowledge_bases)
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
          # check required arguments
          return Twirp::Error.invalid_argument("must be non-empty", argument: "access_token") if req.access_token.blank?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "knowledge_base_id") if req.knowledge_base_id.blank?

          # check access control
          ac = make_access_control(req)
          current_user = ac.viewer
          return Twirp::Error.not_found("user not found") unless current_user.present?

          copilot_api = copilot_api(req, current_user)

          # get knowledge base
          response = copilot_api.get_knowledge_base(knowledge_base_id: req.knowledge_base_id)
          knowledge_base = convert(response[:kb])

          org = Organization.find_by(id: knowledge_base.owner_id)
          return Twirp::Error.not_found("organization not found") if org.nil?

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

          return Twirp::Error.not_found("knowledge base not found") unless allowed

          MonolithTwirp::Copilotapi::KnowledgeBases::V1::GetKnowledgeBaseResponse.new(
            knowledge_base: knowledge_base
          )
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
          # check required arguments
          return Twirp::Error.invalid_argument("must be non-empty", argument: "access_token") if req.access_token.blank?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "name") if req.name.blank?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "scoping_query") if req.scoping_query.blank?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "source_repos") if req.source_repos.blank?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "repos") if req.repos.blank?

          # check that owner type is not invalid
          return Twirp::Error.invalid_argument("must be organization or user", argument: "owner_type") if owner_type_to_string(req.owner_type).nil?

          # check that visibility is not invalid
          return Twirp::Error.invalid_argument("must be private, internal, or public", argument: "visibility") if visibility_to_string(req.visibility).nil?

          # check access control
          ac = make_access_control(req)
          current_user = ac.viewer
          return Twirp::Error.not_found("user not found") unless current_user.present?

          org = Organization.find_by(id: req.owner_id)
          return Twirp::Error.not_found("organization not found") if org.nil?

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

          return Twirp::Error.not_found("knowledge base not created") unless allowed

          # return specific twirp error if any repos are not found or not readable by user
          user_access_to_repos_error = verify_user_access_to_repos(req.repos, req.source_repos, current_user)
          return user_access_to_repos_error if user_access_to_repos_error.present?

          copilot_api = copilot_api(req, current_user)

          # create knowledge base
          response = copilot_api.create_knowledge_base({
            name: req.name,
            description: req.description,
            scoping_query: req.scoping_query,
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
          # check for existing token
          return Twirp::Error.invalid_argument("must be non-empty", argument: "access_token") if req.access_token.blank?

          # check for knowledge base id
          return Twirp::Error.invalid_argument("must be non-empty", argument: "knowledge_base_id") if req.knowledge_base_id.blank?

          # check access control
          ac = make_access_control(req)
          current_user = ac.viewer

          return Twirp::Error.not_found("user not found") unless current_user.present?

          copilot_api = copilot_api(req, current_user)

          # get knowledge base
          begin
            response = copilot_api.get_knowledge_base(knowledge_base_id: req.knowledge_base_id)
            knowledge_base = convert(response[:kb])
          rescue CopilotAPI::NotFoundError
            return Twirp::Error.not_found("knowledge base not found")
          end

          org = Organization.find_by(id: knowledge_base.owner_id)
          return Twirp::Error.not_found("organization not found") if org.nil?

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

          return Twirp::Error.not_found("knowledge base not found") unless allowed

          # return specific twirp error if any repos are not found or not readable by user
          user_access_to_repos_error = verify_user_access_to_repos(req.repos, req.source_repos, current_user)
          return user_access_to_repos_error if user_access_to_repos_error.present?

          copilot_api.update_knowledge_base(req.knowledge_base_id, {
            name: req.name.blank? ? knowledge_base.name : req.name,
            description: req.description.blank? ? knowledge_base.description : req.description,
            scoping_query: req.scoping_query.blank? ? knowledge_base.scoping_query : req.scoping_query,
            source_repos: req.source_repos.blank? ? knowledge_base.source_repos : req.source_repos,
            repos: req.repos.blank? ? knowledge_base.repos : req.repos,
            visibility: visibility_to_string(req.visibility).nil? ? visibility_to_string(knowledge_base.visibility) : visibility_to_string(req.visibility),
          })

          MonolithTwirp::Copilotapi::KnowledgeBases::V1::UpdateKnowledgeBaseResponse.new
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
          # check required arguments
          return Twirp::Error.invalid_argument("must be non-empty", argument: "access_token") if req.access_token.blank?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "knowledge_base_id") if req.knowledge_base_id.blank?

          # check access control
          ac = make_access_control(req)
          current_user = ac.viewer
          return Twirp::Error.not_found("user not found") unless current_user.present?

          copilot_api = copilot_api(req, current_user)

          begin
            response = copilot_api.get_knowledge_base(knowledge_base_id: req.knowledge_base_id)
            kb = response[:kb]
          rescue CopilotAPI::NotFoundError
            return Twirp::Error.not_found("knowledge base not found")
          end

          org = Organization.find_by(id: kb[:ownerID])
          return Twirp::Error.not_found("organization not found") unless org.present?

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
          return Twirp::Error.not_found("knowledge base not found") unless allowed

          # delete knowledge base
          copilot_api.delete_knowledge_base(knowledge_base_id: req.knowledge_base_id)

          MonolithTwirp::Copilotapi::KnowledgeBases::V1::DeleteKnowledgeBaseResponse.new
        end

        private

        sig { params(req: T.untyped, user: User).returns(Copilot::User::CopilotApi) }
        def copilot_api(req, user)
          user.copilot_api(
            integration_id: CopilotAPI::COPILOT_KNOWLEDGE_BASE_INTEGRATION_ID,
            token: Copilot::DecryptedToken.from(req.access_token),
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

          MonolithTwirp::Copilotapi::KnowledgeBases::V1::KnowledgeBase.new(
            created_at: Google::Protobuf::Timestamp.new(seconds: DateTime.parse(kb[:createdAt]).to_i),
            created_by_id: kb[:createdByID],
            description: kb[:description],
            id: kb[:id],
            name: kb[:name],
            owner_id: kb[:ownerID],
            owner_type: owner_type(kb[:ownerType]),
            repos: kb[:repos],
            scoping_query: kb[:scopingQuery],
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

        def user_authorized_to_view_repos?(repos, current_user)
          repos.all? { |repo| repo.readable_by?(current_user) }
        end

        def verify_user_access_to_repos(input_repos, input_source_repos, current_user)
          # return not found error if any repos are not found
          repos = Repository.with_names_with_owners(input_repos)
          return Twirp::Error.not_found("repository does not exist") unless repos.size == input_repos.size

          # return permission denied error if any repos are not viewable
          repos_authorized = user_authorized_to_view_repos?(repos, current_user)
          return Twirp::Error.permission_denied("knowledge base not created") unless repos_authorized

          # return not found error if any source repos are not found
          source_repos = Repository.from_ids(input_source_repos.map { |repo| repo["id"] })
          return Twirp::Error.not_found("repository does not exist") unless source_repos.size == input_source_repos.size

          # return permission denied error if any source repos are not viewable or do not exist
          source_repos_authorized = user_authorized_to_view_repos?(source_repos, current_user)
          Twirp::Error.permission_denied("knowledge base not created") unless source_repos_authorized
        end
      end
    end
  end
end
