# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ToggleableFeature < Platform::Objects::Base
      model_name "Feature"
      description "A feature that is toggleable by an actor"

      visibility :under_development
      implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject
      global_id_field :id, description: "The Node ID of the ToggleableFeature object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      scopeless_tokens_as_minimum

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, user)
        permission.access_allowed?(:read_toggleable_feature, resource: Platform::PublicResource.new, current_repo: nil, current_org: nil, allow_integrations: false, allow_user_via_granular_actor: false) # rubocop:disable GitHub/PublicResource
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        return true if permission.viewer&.site_admin?
        return true if permission.viewer&.github_developer?

        object.async_viewer_can_read?(permission.viewer)
      end

      field :public_name, String, "The public name for the toggleable feature.", null: false
      field :slug, String, "The slug for the toggleable feature.", null: false, visibility: :internal
      field :description, String, "The description for the toggleable feature.", null: true
      field :feedback_url, Scalars::URI, description: "A URL pointing to the feedback link for the toggleable feature.", null: false, method: :feedback_link
      field :enrolled_by_default, Boolean, description: "When true, all users who have access to the feature (via feature flag, or if no feature flag is associated) are enrolled by default and must opt out to turn off.", null: false, visibility: :internal
      field :image_url, Scalars::URI, description: "The associated image URL.", null: true, visibility: :internal, method: :image_link
      field :documentation_url, Scalars::URI, description: "The associated documentation URL.", null: true, visibility: :internal, method: :documentation_link
      field :viewer_is_enrolled, Boolean, "Whether the viewer is enrolled in the feature.", null: false
      field :viewer_opted_out, Boolean, "Whether the viewer has explicitly opted out of the feature.", null: false

      def viewer_is_enrolled
        @object.enrolled?(context[:viewer])
      end

      def viewer_opted_out
        !@object.enrollments.for_enrollee(context[:viewer]).where(enrolled: false).blank?
      end
    end
  end
end
