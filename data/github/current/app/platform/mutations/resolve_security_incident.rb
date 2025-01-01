# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ResolveSecurityIncident < Platform::Mutations::Base
      SIZE_LIMIT = 1_000
      VALID_OAUTH_APPS = [
        647267,  # GitHub Spamurai Next
        728921,  # GitHub Spamurai Next Staging
        1124433, # GitHub Spamurai Next Remix
        645898,  # GitHub Spamurai Next Development
      ]

      description "Resolves security incidents. See SecurityIncidentResponse for all possible remediations."
      visibility :internal, environments: [:dotcom]
      minimum_accepted_scopes ["site_admin"]

      argument :incident_responses, [Inputs::SecurityIncidentResponse], "The responses to take for this incident.", required: true
      argument :incident_response_id, String, "Optional ID to keep track of this response. If not specified one is generated.", required: false

      field :incident_response_id, ID, "The unique ID that will tie this response to its log data.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        viewer = permission.viewer
        valid_auth = viewer.using_personal_access_token? || VALID_OAUTH_APPS.include?(viewer.oauth_application_id)
        valid_auth && viewer.security_incident_response_access?
      end

      def resolve(**inputs)
        # To make sure the actor is not visible to the user. See IssueComment#modifying_user
        GitHub.context.push(staff_actor: true)

        # Only allow requests originating from an internal IP or a "base IP", which is
        # from one of our datacenters (i.e., could be a Hubber VPN'd in)
        unless context[:internal_ip_request] || context[:base_ip_request]
          raise Errors::Forbidden.new "Field 'resolveSecurityIncident' doesn't exist on type 'Mutation'"
        end

        if inputs[:incident_responses].size > SIZE_LIMIT
          raise Errors::Unprocessable.new("Request exceeded limit of #{SIZE_LIMIT} incident responses.")
        end

        incident_response_id = inputs[:incident_response_id] || SecureRandom.uuid

        SecurityIncidentResponseJob.perform_later(
          actor: context[:viewer],
          id: incident_response_id,
          incident_responses: inputs[:incident_responses].map(&:to_h),
        )

        { incident_response_id: incident_response_id }
      end
    end
  end
end
