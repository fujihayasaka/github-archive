# typed: true
# frozen_string_literal: true

require "monolith-twirp-copilotapi-core"
require "copilot_api/access_control"

module Api::Internal::Twirp::Copilotapi
  module Core
    module V1
      # Handler for the MonolithTwirp::Copilotapi::Core::V1::AuthorizationAPIService
      class AuthorizationAPIHandler < Api::Internal::Twirp::Handler

        MAX_BATCH_CONTROL_ACCESS_SIZE = 50

        allow_access_for :client, allowed_clients: ["copilot_api"]
        handles_service MonolithTwirp::Copilotapi::Core::V1::AuthorizationAPIService

        # Public: Implementation of the ControlAccess Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Copilotapi::Core::V1::ControlAccessRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Copilotapi::Core::V1::ControlAccessResponse, or a Twirp::Error.
        sig do params(
          req: MonolithTwirp::Copilotapi::Core::V1::ControlAccessRequest,
          env: T.untyped,
        ).returns(T.any(MonolithTwirp::Copilotapi::Core::V1::ControlAccessResponse, Twirp::Error))
        end
        def control_access(req, env)
          ac = make_access_control(req)
          auth_req = T.must(req.authorization_request)
          decision, = control_access_decision(ac,
            action: auth_req.action.to_sym,
            resource_type: auth_req.resource_type,
            resource_id: auth_req.resource_id,
            organization_id: auth_req.organization_id,
            repository_id: auth_req.repository_id,
            repository_nwo: auth_req.repository_nwo,
          )

          MonolithTwirp::Copilotapi::Core::V1::ControlAccessResponse.new({
            decision: decision,
          })
        end

        # Public: Implementation of the BatchControlAccess Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Copilotapi::Core::V1::BatchControlAccessRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Copilotapi::Core::V1::BatchControlAccessResponse, or a Twirp::Error.
        sig do params(
          req: MonolithTwirp::Copilotapi::Core::V1::BatchControlAccessRequest,
          env: T.untyped,
        ).returns(T.any(MonolithTwirp::Copilotapi::Core::V1::BatchControlAccessResponse, Twirp::Error))
        end
        def batch_control_access(req, env)
          if req.authorization_requests.size > MAX_BATCH_CONTROL_ACCESS_SIZE
            Twirp::Error.new(:invalid_argument, "too many requests")
          end

          ac = make_access_control(req)
          copilot_user = Copilot::User::CopilotApi.new(ac.viewer,
            integration_id: "",
            session: nil,
            real_ip: nil,
            token: Copilot::DecryptedToken.from(req.access_token),
          )
          unauthorized_orgs = Set.new(unauthorized_orgs(copilot_user))
          missing_orgs = T.let(Set[], T::Set[Integer])

          decisions = req.authorization_requests.map do |r|
            action = r.action
            resource_type = r.resource_type
            resource_id = r.resource_id
            organization_id = r.organization_id
            repository_id = r.repository_id
            repository_nwo = r.repository_nwo

            if r.resource_type.to_s == "url"
              current_url = action.to_s
              repository_nwo = extract_repo_nwo(current_url)
              next if repository_nwo.nil?
              action = "get_repo"
              resource_type = "Repository"
            end

            decision, unauthorized_org_id = control_access_decision(ac,
              action: action.to_sym,
              resource_type: resource_type,
              resource_id: resource_id,
              organization_id: organization_id,
              repository_id: repository_id,
              repository_nwo: repository_nwo,
            )

            missing_orgs.add(unauthorized_org_id) if unauthorized_org_id && unauthorized_orgs.include?(unauthorized_org_id)

            {
              id: r.id,
              decision: decision,
            }
          end

          response = {
            decisions: decisions,
            missing_org_ids: missing_orgs.to_a,
          }

          MonolithTwirp::Copilotapi::Core::V1::BatchControlAccessResponse.new(response)
        end

        # Public: Implementation of the GetMemberships Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Copilotapi::Core::V1::GetMembershipsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a
        # MonolithTwirp::Copilotapi::Core::V1::GetMembershipsResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Copilotapi::Core::V1::GetMembershipsRequest,
            env: T.untyped,
          ).returns(T.any(MonolithTwirp::Copilotapi::Core::V1::GetMembershipsResponse, Twirp::Error))
        end
        def get_memberships(req, env)
          if GitHub::Authentication::SignedAuthToken.valid_format?(req.access_token)
            parsed_token = GitHub::Authentication::SignedAuthToken.verify(
              token: req.access_token,
              scope: Copilot::User::CopilotApi::SSAT_SCOPE_GITHUB_DOCSETS,
            )

            user = T.let(parsed_token.user, T.nilable(User))
            return Twirp::Error.new(:unauthenticated, "unauthenticated") unless user

            requested = T.let(User.find(req.user_id), T.nilable(User))
            return Twirp::Error.new(:not_found, "user not found") unless requested

            # For the time being, the requested user must line up with the session user. This may be expanded in the
            # future if we want to allow users (such as org admins) to request other users' memberships
            return Twirp::Error.new(:permission_denied, "permission denied") unless requested == user

            MonolithTwirp::Copilotapi::Core::V1::GetMembershipsResponse.new({
              org_ids: requested.organizations.map(&:id)
            })
          else # non SSATs
            user = GitHub::Authentication::TokenLookup.new(req.access_token).actor
            return Twirp::Error.new(:unauthenticated, "unauthenticated") unless user

            result = GitHub::Authentication::Attempt.new(
              login: user.login,
              token: req.access_token,
              from: :copilot_api,
              allow_integrations: true,
              allow_user_via_granular_actor: true,
            ).result

            return Twirp::Error.new(:not_found, "not found") unless result.success?

            orgs = user&.organizations
            copilot_user = Copilot::User::CopilotApi.new(user,
              integration_id: "",
              session: nil,
              real_ip: nil,
              token: Copilot::DecryptedToken.from(req.access_token),
            )

            org_ids = orgs.map(&:id) - copilot_user.cap_filter.unauthorized_resource_ids(orgs, only: :saml)
            MonolithTwirp::Copilotapi::Core::V1::GetMembershipsResponse.new({
              org_ids: org_ids
            })
          end
        end

        # Public: Implementation of the AuthorizeThreadSharing Twirp RPC.
        #
        # req  - The Twirp request as a MonolithTwirp::Copilotapi::Core::V1::AuthorizeThreadSharingRequest.
        # _env - The Twirp environment as a Hash.
        #
        # Returns a MonolithTwirp::Copilotapi::Core::V1::AuthorizeThreadSharingResponse
        # or a Twirp::Error.
        sig do params(
          req: MonolithTwirp::Copilotapi::Core::V1::AuthorizeThreadSharingRequest,
          _env: T.untyped,
        ).returns(T.any(MonolithTwirp::Copilotapi::Core::V1::AuthorizeThreadSharingResponse, Twirp::Error))
        end
        def authorize_thread_sharing(req, _env)
          authentication =
            GitHub::Authentication::Attempt.new(
              token: req.access_token,
              ip: req.request_ip,
              from: :copilot_api,
              allow_integrations: false,
              allow_user_via_granular_actor: true,
              password_auth_blocked: true,
            ).result
          return Twirp::Error.new(:unauthenticated, "unauthenticated") unless authentication.success?

          user = T.let(authentication.user, T.nilable(User))
          authorization = CopilotPLG.domain.authorize_thread_sharing(user:)
          MonolithTwirp::Copilotapi::Core::V1::AuthorizeThreadSharingResponse.new(**authorization)
        end

        private

        sig { params(copilot_user: T.nilable(Copilot::User::CopilotApi)).returns(T::Array[Integer]) }
        def unauthorized_orgs(copilot_user)
          return [] unless copilot_user
          orgs = copilot_user.user.organizations
          copilot_user.cap_filter.unauthorized_resource_ids(orgs, only: :saml)
        end

        def extract_repo_nwo(current_url)
          path_info = Rails.application.routes.recognize_path current_url
          if path_info.include?(:user_id) && path_info.include?(:repository)
            repo_nwo = path_info[:user_id] + "/" + path_info[:repository]
            return repo_nwo
          end
          nil
        end

        sig { params(ac: CopilotAPI::AccessControl, action: T.untyped, resource_type: T.untyped, resource_id: T.untyped, organization_id: T.untyped, repository_id: Integer, repository_nwo: T.untyped).returns([T::Boolean, T.nilable(Integer)]) }
        def control_access_decision(ac, action:, resource_type:, resource_id:, organization_id:, repository_id:, repository_nwo: nil)
          owner_org_id = nil

          # Look up the resource by type and ID
          if resource_type == "IssueNumber" || resource_type == "PullRequestNumber"
            resource = Issue.find_by(repository: Repository.nwo(repository_nwo), number: resource_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
            if resource && resource.pull_request?
              resource = resource.pull_request
            end
            owner_org_id = resource&.repository&.owner_id || 0
          else
            resource_type = resource_type.classify.constantize
            if resource_type == Repository && repository_nwo.present? && resource_id.zero? && repository_id.zero?
              resource = Repository.nwo(repository_nwo)
            else
              resource = resource_type.find_by(id: resource_id)
            end
          end
          return [false, 0] unless resource

          # Need to set this up for the access control call, it expects these to be explicitly nil
          extra_opts = {
            current_repo: T.let(nil, T.nilable(Repository)),
            current_org: T.let(nil, T.nilable(Organization)),
          }

          if resource.is_a?(Repository)
            return [false, 0] if resource.owner.nil?
            extra_opts[:current_repo] = resource
            extra_opts[:current_org] = T.cast(resource.owner, Organization) if resource.owner&.organization?
            extra_opts[:organization_id] = resource.owner_id if resource.owner&.organization?
          end

          # Check if the resource has a repository nwo attribute passed
          if repository_nwo.present? && repository_id == 0
            repo = Repository.nwo(repository_nwo)
            return [false, 0] unless repo
            extra_opts[:repo] = repo
            extra_opts[:current_repo] = repo
            extra_opts[:current_org] = T.cast(repo.owner, Organization) if repo.owner&.organization?
            extra_opts[:organization_id] = repo.owner_id if repo.owner&.organization?
          end

          # Include the repository if passed
          if repository_id > 0
            repo = T.cast(::Repositories.domain.by_id(repository_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
            return [false, 0] unless repo
            extra_opts[:repo] = repo
            extra_opts[:current_repo] = repo
            extra_opts[:current_org] = T.cast(repo.owner, Organization) if repo.owner&.organization?
            extra_opts[:organization_id] = repo.owner_id if repo.owner&.organization?
          end

          # Include the organization if passed
          if organization_id > 0
            org = Organization.find_by(id: organization_id)
            return [false, 0] unless org
            extra_opts[:organization] = org
            extra_opts[:current_org] = org
          end

          # If resource has a repository attribute, include it in request
          if !extra_opts[:repo].present? && resource.respond_to?(:repository)
            repo = resource.repository
            return [false, 0] unless repo
            extra_opts[:repo] = repo
            extra_opts[:current_repo] = repo
            extra_opts[:current_org] = T.cast(repo.owner, Organization) if repo.owner&.organization?
            extra_opts[:organization_id] = repo.owner_id if repo.owner&.organization?
          end

          owner_org_id ||= extra_opts[:organization_id] || extra_opts[:current_org]&.id || 0

          allowed = ac.access_allowed?(
            action.to_sym,
            {
              **extra_opts,
              resource: resource,
              allow_integrations: true,
              allow_user_via_granular_actor: true,
              raise_on_error: false,
            }
          )
          [allowed, allowed ? 0 : owner_org_id]
        end

        # This api is called from both GitHub chat and the knowledge base management
        # CRUD page, so we need to verify against both scopes
        sig { params(req: T.any(MonolithTwirp::Copilotapi::Core::V1::ControlAccessRequest, MonolithTwirp::Copilotapi::Core::V1::BatchControlAccessRequest, MonolithTwirp::Copilotapi::Core::V1::AuthorizeThreadSharingRequest)).returns(GitHub::Authentication::SignedAuthToken) }
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

        sig { params(req: T.any(MonolithTwirp::Copilotapi::Core::V1::ControlAccessRequest, MonolithTwirp::Copilotapi::Core::V1::BatchControlAccessRequest)).returns(CopilotAPI::AccessControl) }
        def make_access_control(req)
          ac_opts = {
            token: req.access_token,
            ip: req.request_ip,
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
      end
    end
  end
end
