# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class GistStafftoolsInfo < Platform::Objects::Base
      description "Gist information only visible to site admin"

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
        Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(permission.viewer,
                                                                      self.class.name)
      end

      visibility :internal

      minimum_accepted_scopes ["site_admin"]

      field :files, [Objects::GistFile, null: true], visibility: :internal,
        description: "Gist file previews", null: true do
        argument :limit, Integer, "The max number of files to return.", default_value: 10,
          required: false
      end

      def files(**arguments)
        gist = @object.gist
        tree_entries = ::Gist.limit_files(gist.files, arguments[:limit])
        tree_entries.map { |tree_entry| Platform::Models::GistFile.new(gist, tree_entry) }
      end

      field :access_disabled, Boolean, visibility: :internal,
        description: "Access to this gist has been disabled. ex. tos violation", null: false

      def access_disabled
        @object.gist.access.disabled?
      end
    end
  end
end
