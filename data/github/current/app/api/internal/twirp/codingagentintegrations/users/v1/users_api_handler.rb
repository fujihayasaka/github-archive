# typed: true
# frozen_string_literal: true

require "monolith-twirp-codingagentintegrations-users"
require "cgi"

module Api::Internal::Twirp::Codingagentintegrations
  module Users
    module V1
      # Handler for the CodingAgentIntegrations Users API.
      class UsersAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["coding_agent_integrations"]
        handles_service MonolithTwirp::CodingAgentIntegrations::Users::V1::UsersAPIService
        connected_to_writing_for :get_sso_authorization_urls

        # Public: Implementation of the GetUsers Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::CodingAgentIntegrations::V1::GetUsersRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::CodingAgentIntegrations::Users::V1::GetUsersResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::CodingAgentIntegrations::Users::V1::GetUsersRequest,
            env: Hash
          ).returns(T::Hash[MonolithTwirp::CodingAgentIntegrations::Users::V1::GetUsersResponse, Twirp::Error])
        end
        def get_users(req, env)
          users = User.where(id: req.ids.to_a).to_a

          res_users = users.map { |u| { id: u.id, analytics_tracking_id: u.analytics_tracking_id } }

          { users: res_users }
        end

        # Public: Implementation of the GetSsoAuthorizationUrls Twirp RPC.
        #
        # Generates signed SSO credential authorization URLs for the authenticated user
        # and a set of organization IDs. These URLs allow users to authorize their OAuth
        # credential for SAML SSO-protected organizations in a single step.
        #
        # req - The Twirp request as a MonolithTwirp::CodingAgentIntegrations::Users::V1::GetSsoAuthorizationUrlsRequest.
        # _env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a
        # MonolithTwirp::CodingAgentIntegrations::Users::V1::GetSsoAuthorizationUrlsResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::CodingAgentIntegrations::Users::V1::GetSsoAuthorizationUrlsRequest,
            _env: T.untyped,
          ).returns(T.any(T::Hash[Symbol, T.untyped], Twirp::Error))
        end
        def get_sso_authorization_urls(req, _env)
          user = GitHub::Authentication::TokenLookup.new(req.access_token).actor
          unless user
            return Twirp::Error.new(:unauthenticated, "unauthenticated")
          end

          result = GitHub::Authentication::Attempt.new(
            login: user.login,
            token: req.access_token,
            ip: req.request_ip,
            from: :copilot_jira,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          ).result

          unless result.success?
            return Twirp::Error.new(:unauthenticated, "unauthenticated")
          end

          credential = user.oauth_access
          unless credential
            return Twirp::Error.new(:failed_precondition, "no credential found for token")
          end

          org_id_values = req.org_ids.map(&:to_i)
          member_org_ids = Ability.direct_organization_memberships_for_user(actor_id: user.id)
            .where(subject_id: org_id_values).pluck(:subject_id)
          orgs = Organization.where(id: member_org_ids)
          results = orgs.filter_map do |org|
            target = org.external_identity_session_owner
            token = Organization::CredentialAuthorization.generate_request(
              organization: org,
              target: target,
              credential: credential,
              actor: user,
            )

            authorization_url = case target
            when ::Organization
              "#{GitHub.url}/orgs/#{target.display_login}/sso?authorization_request=#{CGI.escape(token)}"
            when ::Business
              "#{GitHub.url}/enterprises/#{target.slug}/sso?authorization_request=#{CGI.escape(token)}"
            end

            next unless authorization_url

            {
              org_id: org.id,
              org_login: org.login,
              authorization_url: authorization_url,
            }
          end

          {
            organizations: results,
          }
        end
      end
    end
  end
end
