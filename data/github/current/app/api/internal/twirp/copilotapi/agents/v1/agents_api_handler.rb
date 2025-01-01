# typed: true
# frozen_string_literal: true

require "monolith-twirp-copilotapi-agents"

module Api::Internal::Twirp::Copilotapi
  module Agents
    module V1
      # Handler for the MonolithTwirp::Copilotapi::Agents::V1::AgentsAPIService
      class AgentsAPIHandler < Api::Internal::Twirp::Handler
        include AvatarHelper
        include GitHub::RouteHelpers

        allow_access_for :client, allowed_clients: ["copilot_api"]
        handles_service MonolithTwirp::Copilotapi::Agents::V1::AgentsAPIService


        # Public: Implementation of the AgentConfigForIntegrationSlug Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Copilotapi::Agents::V1::AgentConfigForIntegrationSlugRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Copilotapi::Agents::V1::AgentConfigForIntegrationSlugResponse, or a Twirp::Error.
        def agent_config_for_integration_slug(req, _)
          user = User.find_by(id: req.user_id)
          return Twirp::Error.not_found("user does not exist", argument: "user_id") if user.nil?

          if Copilot::User.new(user).copilot_extensions_disabled?
            return Twirp::Error.not_found("integration does not exist", argument: "integration_slug")
          end

          # TODO: Integration lookup by slug does not work across Proxima stamps, as they are shared.
          # We'll need to specify which stamp to lookup the integration for.
          integration = Integration.find_by(slug: req.integration_slug)

          return Twirp::Error.not_found("integration does not exist", argument: "integration_slug") if integration.nil?
          return Twirp::Error.not_found("integration is not an agent", argument: "integration_slug") unless integration.agent_configured?

          MonolithTwirp::Copilotapi::Agents::V1::AgentConfigForIntegrationSlugResponse.new({
            app_config: integration_agent_config_hash(integration, user)
          })
        end

        def agent_config_for_integration_id(req, _)
          user = User.find_by(id: req.user_id)
          return Twirp::Error.not_found("user does not exist", argument: "user_id") if user.nil?

          if Copilot::User.new(user).copilot_extensions_disabled?
            return MonolithTwirp::Copilotapi::Agents::V1::AgentConfigForIntegrationIdResponse.new({ app_config: nil })
          end

          integration = Integration.find_by(id: req.integration_id)

          return Twirp::Error.not_found("integration does not exist", argument: "integration_slug") if integration.nil?
          return Twirp::Error.not_found("integration is not an agent", argument: "integration_slug") unless integration.agent_configured?

          MonolithTwirp::Copilotapi::Agents::V1::AgentConfigForIntegrationIdResponse.new({
            app_config: integration_agent_config_hash(integration, user)
          })
        end

        # Public: Implementation of the IsUserAuthorizedForAgent Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Copilotapi::Agents::V1::IsUserAuthorizedForAgentRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Copilotapi::Agents::V1::IsUserAuthorizedForAgentResponse, or a Twirp::Error.
        def is_user_authorized_for_agent(req, env)
          user = User.find_by(id: req.user_id)
          return Twirp::Error.not_found("user does not exist", argument: "user_id") if user.nil?

          return Twirp::Error.permission_denied("copilot extensions disabled") if Copilot::User.new(user).copilot_extensions_disabled?

          integration = Integration.find_by(id: req.integration_id)
          return Twirp::Error.not_found("integration does not exist", argument: "integration_id") if integration.nil? || !integration.readable_by?(user)

          return Twirp::Error.not_found("integration is not an agent", argument: "integration_id") unless integration.agent_configured?

          MonolithTwirp::Copilotapi::Agents::V1::IsUserAuthorizedForAgentResponse.new(
            decision: authorization_exists?(user, integration)
          )
        end

        # Public: Implementation of the MintUserToServerTokenForAgentAndUser Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Copilotapi::Agents::V1::MintUserToServerTokenForAgentAndUserRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Copilotapi::Agents::V1::MintUserToServerTokenForAgentAndUserResponse, or a Twirp::Error.
        def mint_user_to_server_token_for_agent_and_user(req, env)
          user = User.find_by(id: req.user_id)
          return Twirp::Error.not_found("user does not exist", argument: "user_id") if user.nil?

          return Twirp::Error.permission_denied("copilot extensions disabled") if Copilot::User.new(user).copilot_extensions_disabled?

          integration = Integration.find_by(id: req.integration_id)
          return Twirp::Error.not_found("integration does not exist", argument: "integration_id") if integration.nil? || !integration.readable_by?(user)

          return Twirp::Error.not_found("integration is not an agent", argument: "integration_id") unless integration.agent_configured?

          authorization = integration_authorization(user, integration)
          return Twirp::Error.permission_denied("user has not authorized this integration") unless authorization

          user_session = user.sessions.find_by(id: req.session_id)
          new_access = grant_access_to_integration(authorization, user, integration, user_session, Array(req.organization_sso_authorized_ids))
          token, _ = new_access.redeem

          MonolithTwirp::Copilotapi::Agents::V1::MintUserToServerTokenForAgentAndUserResponse.new(
            token: token
          )
        end

        # Public: Implementation of the ListAuthorizedAgentsForUser Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Copilotapi::Agents::V1::ListAuthorizedAgentsForUserRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Copilotapi::Agents::V1::ListAuthorizedAgentsForUserResponse, or a Twirp::Error.
        def list_authorized_agents_for_user(req, env)
          user = User.find_by(id: req.user_id)
          return Twirp::Error.not_found("user does not exist", argument: "user_id") if user.nil?

          if Copilot::User.new(user).copilot_extensions_disabled?
            return MonolithTwirp::Copilotapi::Agents::V1::ListAuthorizedAgentsForUserResponse.new(app_configs: [])
          end

          orgs = authorized_sso_orgs(user, req.session_id, req.request_ip, Array(req.organization_sso_authorized_ids))
          org_agents = IntegrationAgent.integrations_installed_for_orgs(orgs)

          authed_agents = IntegrationAgent.integrations_authorized_for_user(user)
          user_installed_agents = IntegrationAgent.integrations_installed_for_target(user)

          all_agents = (authed_agents + user_installed_agents + org_agents).uniq(&:id)
          app_configs = all_agents.map { |integration| integration_agent_config_hash(integration, user) }

          MonolithTwirp::Copilotapi::Agents::V1::ListAuthorizedAgentsForUserResponse.new(
            app_configs: app_configs
          )
        end

        private

        def authorized_sso_orgs(user, session_id, request_ip, org_sso_authorized_ids)
          return [] if session_id == 0 && org_sso_authorized_ids.empty?

          # We have some org ids already, just return those records
          return Organization.where(id: Array(org_sso_authorized_ids)) if org_sso_authorized_ids.any?

          # We are in session mode, create a cap filter and authorize the user's orgs
          begin
            user_session = user.sessions.find(session_id)
          # Edge case: CAPI uses a fake session id when developing locally, so the session won't exist.
          # This shouldn't trigger on production.
          # See https://github.com/github/copilot-api/blob/7bc17a1d5624a69543e25f757ad486958af48ab9/pkg/authnd/authnd.go#L268
          rescue ActiveRecord::RecordNotFound
            return []
          end

          cap_filter = ConditionalAccess::Model::Filter.new(self, # rubocop:todo GitHub/DoNotInstantiatePlatformObjects
            web_session: user_session,
            actor: user,
            location: :model,
            remote_ip: request_ip,
          )

          cap_filter.authorized_resources(user.organizations)
        end

        # grant_access_to_integration grants access to the given integration for the given user.
        # It will grant access to all organizations that the user has authorized for SSO, and that
        # the given session is authorized for. It also supports a list of organization IDs that
        # the user has authorized for SSO, but that the session is not authorized for, this is
        # the Oauth case.
        def grant_access_to_integration(authorization, user, integration, user_session, organization_sso_authorized_ids)
          new_access = integration.grant(user, {
            integration_version_number: authorization.integration_version.number,
            user_session: user_session,
            entry_point: :twirp_api_copilot_agent_handler
          })

          # Give priority to the user session, if it exists.
          return new_access if user_session.present?

          orgs = Organization.where(id: organization_sso_authorized_ids)
          return new_access unless orgs.any?

          orgs.each do |org|
            ActiveRecord::Base.connected_to(role: :writing) do
              authorization = Organization::CredentialAuthorization.grant(organization: org, credential: new_access, actor: user)
              raise "Could not create credential authorization grant. Org: #{org.display_login}, user: #{user.display_login}" if authorization.nil?
            end
          end

          new_access
        end

        def integration_agent_config_hash(integration, user)
          editor_context_enabled = integration.default_permissions["copilot_editor_context"].nil? ? false : true
          hostname = GitHub.url
          if Integration.not_in_marketplace.where(id: integration.id).count == 0
            integration_url = hostname + Rails.application.routes.url_helpers.marketplace_listing_path(integration.slug)
          else
            integration_url = hostname + gh_app_path(integration, user)
          end

          case integration.integration_agent.app_type
          when "agent"
            app_type = MonolithTwirp::Copilotapi::Agents::V1::CopilotAppConfig::AppType::APP_TYPE_AGENT
          when "skill"
            app_type = MonolithTwirp::Copilotapi::Agents::V1::CopilotAppConfig::AppType::APP_TYPE_SKILL
          else
            raise "Invalid app type: #{integration.integration_agent.app_type}"
          end

          skills = integration.integration_agent.skill_data.map do |skill|
            case skill.return_type
            when "string"
              return_type = MonolithTwirp::Copilotapi::Agents::V1::Skill::ReturnType::RETURN_TYPE_STRING
            when "github_reference_json"
              return_type = MonolithTwirp::Copilotapi::Agents::V1::Skill::ReturnType::RETURN_TYPE_GITHUB_REFERENCE_JSON
            else
              raise "Invalid return type: #{skill.return_type}"
            end

            {
              name: skill.name,
              description: skill.description,
              parameters: skill.parameters,
              endpoint: skill.url,
              return_type: return_type,
            }
          end
          {
            id: integration.integration_agent.id,
            app_type: app_type,
            agent_url: integration.integration_agent.url,
            client_authorization_url: integration.integration_agent.client_authorization_url,
            description: integration.integration_agent.description,
            editor_context: editor_context_enabled,
            skills: skills,

            # We can't use the API::Serializer integration_hash method here, because
            # the protobuf doesn't have the same fields as the JSON API serializer.
            integration: {
              id: integration.id,
              slug: integration.slug,
              name: integration.name,
              avatar_url: avatar_url_for(integration),
              client_id: integration.key,
              url: integration_url,
              owner: {
                id: integration.owner.id,
                login: integration.owner.display_login,
                avatar_url: avatar_url_for(integration.owner)
              }
            },
            is_token_exchange_enabled: integration.integration_agent.token_exchange_enabled?,
            token_exchange_url: integration.integration_agent.token_exchange_url,
            third_party_token_header_key: integration.integration_agent.third_party_token_header_key,
            third_party_token_header_value: integration.integration_agent.third_party_token_header_value,
          }
        end

        def authorization_exists?(user, integration)
          !integration_authorization(user, integration).nil?
        end

        def integration_authorization(user, integration)
          authorization = user.oauth_authorizations.where(application: integration).first
          return nil if authorization.nil?

          subject = user.resources.copilot_messages
          return nil unless Permissions::Service.has_direct_permission?(
            actor_type: authorization&.ability_type,
            actor_id: authorization&.ability_id,
            subject_type: subject.ability_type,
            subject_ids: [user.id],
            action: :read,
          )

          authorization
        end
      end
    end
  end
end
