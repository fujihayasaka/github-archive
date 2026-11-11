# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module AuditLog
      module OauthApplicationAuditEntryData
        include Platform::Interfaces::Base

        description "Metadata for an audit entry with action oauth_application.*"


        field :oauth_application_name, String, null: true, description: "The name of the OAuth application."
        def oauth_application_name
          @object.get(:oauth_application) ||
            @object.get(:application_name)
        end

        field :oauth_application_database_id, Integer, null: true, visibility: :internal, description: "The database ID of the OAuth application."
        def oauth_application_database_id
          @object.get(:oauth_application_id) ||
            @object.get(:application_id)
        end

        field :oauth_application, Platform::Objects::OauthApplication, null: true, visibility: :internal, description: "The OAuth application associated with the Audit Entry."
        def oauth_application
          oauth_application_database_id =
            @object.get(:oauth_application_id) ||
              @object.get(:application_id)

          Loaders::ActiveRecord.load(::OauthApplication, oauth_application_database_id)
        end

        url_fields prefix: :oauth_application, null: true, description: "The HTTP URL for the OAuth application" do |audit_entry|
          oauth_application_database_id =
            audit_entry.get(:oauth_application_id) ||
              audit_entry.get(:application_id)

          Loaders::ActiveRecord.load(::OauthApplication, oauth_application_database_id).then do |oauth_application|
            if oauth_application.present?
              oauth_application.async_user.then do |user|
                if T.must(user).organization?
                  template = Addressable::Template.new("/organizations/{org}/settings/applications/{oauth_application_id}")
                  template.expand(
                    org: T.must(user).display_login,
                    oauth_application_id: oauth_application_database_id,
                  )
                else
                  template = Addressable::Template.new("/settings/applications/{oauth_application_id}")
                  template.expand(
                    oauth_application_id: oauth_application_database_id,
                  )
                end
              end
            end
          end
        end # url_fields
      end
    end
  end
end
