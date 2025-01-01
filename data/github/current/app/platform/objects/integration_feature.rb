# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class IntegrationFeature < Platform::Objects::Base
      description "A description of an Integration category."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        return true if permission.viewer && (permission.viewer.site_admin? || permission.viewer.biztools_user?)
        return true if object.visible?
        false
      end

      minimum_accepted_scopes ["repo"]
      visibility :internal

      field :name, String, "The category's full name.", null: false
      field :slug, String, "The category's URL name.", null: false
      field :body, String, "The description of the category", null: false
      field :state, Enums::IntegrationFeatureState, "The state of the category", null: false
      def state
        @object.state.upcase
      end

      url_fields description: "The HTTP URL for this category." do |category|
        template = Addressable::Template.new("/works-with/category/{slug}")
        template.expand slug: category.slug
      end
    end
  end
end
