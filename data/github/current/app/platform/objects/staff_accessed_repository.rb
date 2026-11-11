# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class StaffAccessedRepository < Platform::Objects::Base
      implements Platform::Interfaces::RepositoryInfo
      visibility :internal
      minimum_accepted_scopes ["site_admin"]

      description <<~MD
        This object may be fetched by GitHub staff, and it
        shows data about a repository, even if the repo is private.
        `Platform::Interfaces::RepositoryInfo` serves as an allowlist of fields
        which are visible to staff users, along with any extra fields added here.
      MD

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        if permission.origin == ORIGIN_INTERNAL || permission.origin == ORIGIN_MANUAL_EXECUTION
          true
        elsif !Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(permission.viewer, self.class.name)
          raise Errors::Forbidden.new("#{permission.viewer} does not have permission to query `staffAccessedRepository`.")
        else
          true
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(permission.viewer, self.class.name) &&
          permission.typed_can_see?("Repository", object)
      end

      field :id, ID, description: "The Node ID of the StaffAccessedRepository object", null: false, method: :global_relay_id

      field :database_id, Integer, description: "The database id of the repository.", null: false

      def database_id
        @object.id
      end

      field :stafftools_info, Objects::RepositoryStafftoolsInfo, null: true,
        description: "Fields that are only visible to site admins."

      def stafftools_info
        if self.class.viewer_is_site_admin?(context[:viewer], self.class.name)
          Models::RepositoryStafftoolsInfo.new(object)
        else
          nil
        end
      end
    end
  end
end
