# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ContentWarning < Platform::Objects::Base
      description "The content warning for a repository"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.viewer.site_admin?
      end

      visibility :internal

      minimum_accepted_scopes ["site_admin"]

      field :type, String, description: "The type of content warning. E.g. 'interstitial'", null: false
      field :category, String, description: "The content warning' category. E.g. 'mis_dis_information'", null: false
      field :sub_category, String, description: "The content warning's sub category. E.g. 'medical_scientific'", null: true
      field :custom_sub_category, String, description: "The content warning's custom sub category text. E.g. 'dangerous stuff.'", null: true
    end
  end
end
