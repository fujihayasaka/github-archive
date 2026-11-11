# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CodeqlDatabase < Platform::Objects::Base
      description "A CodeQL database that has been uploaded for use with remote queries"

      def self.async_api_can_access?(permission, _object)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      def self.async_viewer_can_see?(permission, codeql_database)
        Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(permission.viewer, self.class.name)
      end

      visibility :internal
      minimum_accepted_scopes ["security_events"]

      field :id, ID, "The ID of the CodeQL database", null: false
      field :uploader, Objects::User, "The user that uploaded the CodeQL database", null: true
      field :language, String, "The CodeQL language of the CodeQL database", null: false
      field :size, Integer, "The size in bytes of the uploaded CodeQL database zip file", null: false
      field :state, String, "Identifies whether the upload was successful or not", null: false
      field :guid, String, "Identifies the path of the upload in file storage", null: false
      field :created_at, Scalars::DateTime, "The time that the CodeQL database started uploading", null: false
    end
  end
end
