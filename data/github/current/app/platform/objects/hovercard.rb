# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Hovercard < Platform::Objects::Base
      description "Detail needed to display a hovercard for a user"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, hovercard)
        case hovercard.model
        when ::User
          business_promise = hovercard.subject_organization&.async_business || Promise.resolve(nil)
          business_promise.then do |business|
            saml_scope_enabled = business&.feature_enabled?(:saml_scope_private_resources_to_org) || GitHub.flipper[:saml_scope_private_resources_to_org].enabled?
            resource = saml_scope_enabled ? Platform::InternalResource.new(resource: hovercard.user) : hovercard.user
            permission.access_allowed?(:read_user_hovercard, {
              resource: resource,
              allow_integrations: false,
              allow_user_via_granular_actor: false,
              enforce_oauth_app_policy: true,
              organization: hovercard.subject_organization,
              repo: nil,
            })
          end
        when ::Issue, ::PullRequest
          hovercard.async_repository.then do |repo|
            hovercard.async_organization.then do |org|
              permission_name = hovercard.model.is_a?(::PullRequest) ? :read_pull_request_hovercard : :read_issue_hovercard
              permission.access_allowed?(permission_name, {
                resource: hovercard.issue_or_pull_request,
                allow_integrations: true,
                allow_user_via_granular_actor: true,
                enforce_oauth_app_policy: true,
                organization: org,
                repo: repo,
              })
            end
          end
        else
          raise Platform::Errors::Internal, "Unexpected hovercard.model: #{hovercard.model.class}"
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        model_type_name = Helpers::NodeIdentification.type_name_from_object(object.model)
        permission.typed_can_see?(model_type_name, object.model)
      end

      minimum_accepted_scopes ["repo"]

      field :contexts, [Interfaces::HovercardContext], description: "Each of the contexts for this hovercard", null: false

      field :organization, Objects::Organization, description: "The organization (if any) for the given subject", null: true, visibility: :internal, method: :subject_organization
    end
  end
end
