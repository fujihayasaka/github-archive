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

        allow_access_for :client, allowed_clients: %w[copilot_api sweagentd]
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
            logging_enabled: FeatureFlag.vexi.enabled?(:copilot_spaces_control_access_logging, ac.viewer, default: false),
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
            return Twirp::Error.new(:invalid_argument, "too many requests")
          end

          ac = make_access_control(req)
          copilot_user = Copilot::User::CopilotApi.new(ac.viewer,
            integration_id: "",
            session: nil,
            real_ip: nil,
            token: Copilot::DecryptedToken.from(req.access_token),
          )
          unauthorized_orgs = Set.new(unauthorized_orgs(copilot_user))
          logging_enabled = FeatureFlag.vexi.enabled?(:copilot_spaces_control_access_logging, ac.viewer, default: false)

          GitHub.logger.with_named_tags("gh.user.id" => ac.viewer&.id) do
            if logging_enabled
              GitHub.logger.info("[BatchControlAccess] Starting: requests=#{req.authorization_requests.size}, viewer=#{ac.viewer&.login || 'nil'}, unauthorized_orgs=#{unauthorized_orgs.to_a.inspect}")
            end

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
                if logging_enabled
                  GitHub.logger.info("[BatchControlAccess] URL request: url=#{current_url}, extracted_nwo=#{repository_nwo || 'nil'}")
                end
                next if repository_nwo.nil?
                action = "get_repo"
                resource_type = "Repository"
              end

              if logging_enabled
                GitHub.logger.info("[BatchControlAccess] Request: id=#{r.id}, action=#{action}, type=#{resource_type}, resource_id=#{resource_id}, org_id=#{organization_id}, repo_id=#{repository_id}, repo_nwo=#{repository_nwo}")
              end

              decision, unauthorized_org_id = control_access_decision(ac,
                action: action.to_sym,
                resource_type: resource_type,
                resource_id: resource_id,
                organization_id: organization_id,
                repository_id: repository_id,
                repository_nwo: repository_nwo,
                logging_enabled: logging_enabled,
              )

              if logging_enabled
                GitHub.logger.info("[BatchControlAccess] Decision: allowed=#{decision}, unauthorized_org_id=#{unauthorized_org_id || 'nil'}")
              end

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

            if logging_enabled
              GitHub.logger.info("[BatchControlAccess] : response: #{response.inspect}")
            end
            MonolithTwirp::Copilotapi::Core::V1::BatchControlAccessResponse.new(response)
          end
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
            unless user
              emit_auth_failure_event(user_id: nil, reason: "unauthenticated", method: "get_memberships", token_type: "ssat")
              return Twirp::Error.new(:unauthenticated, "unauthenticated")
            end

            requested = T.let(User.find(req.user_id), T.nilable(User))
            unless requested
              emit_auth_failure_event(user_id: user.id, reason: "user_not_found", method: "get_memberships", requested_user_id: req.user_id, token_type: "ssat")
              return Twirp::Error.new(:not_found, "user not found")
            end

            # For the time being, the requested user must line up with the session user. This may be expanded in the
            # future if we want to allow users (such as org admins) to request other users' memberships
            unless requested == user
              emit_auth_failure_event(user_id: user.id, reason: "permission_denied", method: "get_memberships", requested_user_id: req.user_id, token_type: "ssat")
              return Twirp::Error.new(:permission_denied, "permission denied")
            end

            MonolithTwirp::Copilotapi::Core::V1::GetMembershipsResponse.new({
              org_ids: requested.organizations.map(&:id)
            })
          else # non SSATs
            user = GitHub::Authentication::TokenLookup.new(req.access_token).actor
            unless user
              emit_auth_failure_event(user_id: nil, reason: "unauthenticated", method: "get_memberships", token_type: "non_ssat")
              return Twirp::Error.new(:unauthenticated, "unauthenticated")
            end

            result = GitHub::Authentication::Attempt.new(
              login: user.login,
              token: req.access_token,
              from: :copilot_api,
              allow_integrations: true,
              allow_user_via_granular_actor: true,
            ).result

            unless result.success?
              emit_auth_failure_event(user_id: user&.id, reason: "not_found", method: "get_memberships", token_type: "non_ssat")
              return Twirp::Error.new(:not_found, "not found")
            end

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

        # Public: Implementation of the GetTeamMemberships Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Copilotapi::Core::V1::GetTeamMembershipsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a
        # MonolithTwirp::Copilotapi::Core::V1::GetTeamMembershipsResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Copilotapi::Core::V1::GetTeamMembershipsRequest,
            env: T.untyped,
          ).returns(T.any(MonolithTwirp::Copilotapi::Core::V1::GetTeamMembershipsResponse, Twirp::Error))
        end
        def get_team_memberships(req, env)
          if GitHub::Authentication::SignedAuthToken.valid_format?(req.access_token)
            parsed_token = GitHub::Authentication::SignedAuthToken.verify(
              token: req.access_token,
              scope: Copilot::User::CopilotApi::SSAT_SCOPE_GITHUB_DOCSETS,
            )

            user = T.let(parsed_token.user, T.nilable(User))
            unless user
              emit_auth_failure_event(user_id: nil, reason: "unauthenticated", method: "get_team_memberships", token_type: "ssat")
              return Twirp::Error.new(:unauthenticated, "unauthenticated")
            end

            requested = T.let(User.find(req.user_id), T.nilable(User))
            unless requested
              emit_auth_failure_event(user_id: user.id, reason: "user_not_found", method: "get_team_memberships", requested_user_id: req.user_id, token_type: "ssat")
              return Twirp::Error.new(:not_found, "user not found")
            end

            # For the time being, the requested user must line up with the session user. This may be expanded in the
            # future if we want to allow users (such as org admins) to request other users' memberships
            unless requested == user
              emit_auth_failure_event(user_id: user.id, reason: "permission_denied", method: "get_team_memberships", requested_user_id: req.user_id, token_type: "ssat")
              return Twirp::Error.new(:permission_denied, "permission denied")
            end

            MonolithTwirp::Copilotapi::Core::V1::GetTeamMembershipsResponse.new({
              team_ids: requested.teams.map(&:id)
            })
          else # non SSATs
            user = GitHub::Authentication::TokenLookup.new(req.access_token).actor
            unless user
              emit_auth_failure_event(user_id: nil, reason: "unauthenticated", method: "get_team_memberships", token_type: "non_ssat")
              return Twirp::Error.new(:unauthenticated, "unauthenticated")
            end

            result = GitHub::Authentication::Attempt.new(
              login: user.login,
              token: req.access_token,
              from: :copilot_api,
              allow_integrations: true,
              allow_user_via_granular_actor: true,
            ).result

            unless result.success?
              emit_auth_failure_event(user_id: user&.id, reason: "authentication_failed", method: "get_team_memberships", token_type: "non_ssat")
              return Twirp::Error.new(:not_found, "not found")
            end

            teams = user&.teams
            copilot_user = Copilot::User::CopilotApi.new(user,
              integration_id: "",
              session: nil,
              real_ip: nil,
              token: Copilot::DecryptedToken.from(req.access_token),
            )

            team_ids = teams.map(&:id) - copilot_user.cap_filter.unauthorized_resource_ids(teams, only: :saml)
            MonolithTwirp::Copilotapi::Core::V1::GetTeamMembershipsResponse.new({
              team_ids: team_ids
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
          unless authentication.success?
            emit_auth_failure_event(user_id: nil, reason: "unauthenticated", method: "authorize_thread_sharing")
            return Twirp::Error.new(:unauthenticated, "unauthenticated")
          end

          user = T.let(authentication.user, T.nilable(User))
          authorization = CopilotPLG.domain.authorize_thread_sharing(user:)
          MonolithTwirp::Copilotapi::Core::V1::AuthorizeThreadSharingResponse.new(**authorization)
        end

        # Public: Implementation of the GetAllMessageResourceOwners Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Copilotapi::Core::V1::GetAllMessageResourceOwnersRequest.
        # _env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Copilotapi::Core::V1::GetAllMessageResourceOwnersResponse, or a Twirp::Error.
        sig do params(
          req: MonolithTwirp::Copilotapi::Core::V1::GetAllMessageResourceOwnersRequest,
          _env: T.untyped,
        ).returns(T.any(MonolithTwirp::Copilotapi::Core::V1::GetAllMessageResourceOwnersResponse, Twirp::Error))
        end
        def get_all_message_resource_owners(req, _env)
          if req.resource_info.empty?
            return MonolithTwirp::Copilotapi::Core::V1::GetAllMessageResourceOwnersResponse.new({
              org_ids: [],
            })
          end

          # Convert resource_info to array of hashes for batch resolution
          resource_infos = req.resource_info.map do |resource_info|
            {
              resource_type: resource_info.resource_type,
              resource_id: resource_info.resource_id,
              organization_id: resource_info.organization_id,
              repository_id: resource_info.repository_id,
              repository_nwo: resource_info.repository_nwo,
            }
          end

          org_ids = CopilotChat::OrganizationOwnerResolver.resolve_organization_ids(resource_infos)
          return org_ids if org_ids.is_a?(Twirp::Error)

          MonolithTwirp::Copilotapi::Core::V1::GetAllMessageResourceOwnersResponse.new({
              org_ids: org_ids,
          })
        end

        private

        sig { params(user_id: T.nilable(Integer), reason: String, data: T.untyped).void }
        def emit_auth_failure_event(user_id:, reason:, **data)
          payload = {
            request_id: GitHub.context[:request_id],
            data: data.merge(reason: reason),
          }
          payload[:user_id] = user_id if user_id
          GlobalInstrumenter.instrument("copilot.chat.auth.restricted", payload)
        end

        sig { params(copilot_user: T.nilable(Copilot::User::CopilotApi)).returns(T::Array[Integer]) }
        def unauthorized_orgs(copilot_user)
          return [] unless copilot_user
          return [] unless copilot_user.user.respond_to?(:organizations) # May not always be present
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

        sig { params(ac: CopilotAPI::AccessControl, action: T.untyped, resource_type: T.untyped, resource_id: T.untyped, organization_id: T.untyped, repository_id: Integer, repository_nwo: T.untyped, logging_enabled: T::Boolean).returns([T::Boolean, T.nilable(Integer)]) }
        def control_access_decision(ac, action:, resource_type:, resource_id:, organization_id:, repository_id:, repository_nwo: nil, logging_enabled: false)
          owner_org_id = nil
          resource, repo_fallback = CopilotChat::ControlAccessHelper.resolve_resource(resource_type, repository_nwo, repository_id, resource_id, user: ac.viewer, logging_enabled: logging_enabled)
          return [false, 0] unless resource
          extra_opts = CopilotChat::ControlAccessHelper.extra_opts(resource, repository_nwo, repository_id, organization_id)
          return [false, 0] unless extra_opts

          owner_org_id ||= extra_opts[:organization_id] || extra_opts[:current_org]&.id || 0

          if logging_enabled
            GitHub.logger.info("[ControlAccessDecision] Checking: action=#{action}, resource=#{resource.class.name}:#{resource.id}, owner_org_id=#{owner_org_id}, repo=#{extra_opts[:current_repo]&.nwo || 'nil'}, org=#{extra_opts[:current_org]&.login || 'nil'}")
          end

          action = repo_fallback ? :get_repo : action
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

          if logging_enabled
            GitHub.logger.info("[ControlAccessDecision] Result: allowed=#{allowed}, org_id=#{allowed ? 0 : owner_org_id}")
          end

          unless allowed
            emit_auth_failure_event(
              user_id: ac.viewer&.id,
              reason: "access_denied",
              action: action.to_s,
              resource_type: resource.class.name,
              resource_id: resource.id,
              owner_org_id: owner_org_id
            )
          end

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

          # If the token is a signed auth token with valid SSAT scopes, set context needed to
          # treat the token as a web session. Fine-grained PATs have the same format as SSATs
          # but will fail scope verification, so they fall through to the standard token path.
          if GitHub::Authentication::SignedAuthToken.valid_format?(req.access_token)
            parsed_token = verified_token(req)
            # Only use SSAT code path if the token is actually valid with the required scopes
            # Feature flag controls whether we validate token scope or use legacy behavior
            should_validate_token = FeatureFlag.vexi.enabled?(:copilot_api_check_ssat_token_validity, default: false)
            if !should_validate_token || parsed_token.reason == :valid
              ac_opts[:authenticated_actor_using_web_session] = true
              ac_opts[:viewer] = parsed_token.user
              ac_opts[:user_session] = parsed_token.session
            end
          end

          CopilotAPI::AccessControl.new(ac_opts)
        end
      end
    end
  end
end
