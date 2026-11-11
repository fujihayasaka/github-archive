# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class TopicStafftoolsInfo < Platform::Objects::Base
      description "Topic information only visible to site admins"

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
        Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(permission.viewer, self.class.name)
      end

      visibility :internal

      minimum_accepted_scopes ["site_admin"]

      field :is_flagged, Boolean, description: "Indicates whether the topic is flagged.", null: false

      def is_flagged
        @object.topic.flagged
      end
    end
  end
end
