# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module AuditLog
      module OrganizationAuditEntryData
        include Platform::Interfaces::Base

        description "Metadata for an audit entry with action org.*"

        field :organization_name, String, null: true, description: "The name of the Organization.", deprecated: Helpers::AuditLog::DeprecationNotice
        def organization_name
          @object.get(:org)
        end

        field :organization_database_id, Integer, null: true, visibility: :internal, description: "The database ID of the Organization.", deprecated: Helpers::AuditLog::DeprecationNotice
        def organization_database_id
          @object.get(:org_id)
        end

        field :organization, Platform::Objects::Organization, null: true, description: "The Organization associated with the Audit Entry.", deprecated: Helpers::AuditLog::DeprecationNotice
        def organization
          Loaders::ActiveRecord.load(::Organization, @object.get(:org_id))
        end

        url_fields prefix: :organization, null: true, description: "The HTTP URL for the organization", deprecated: Helpers::AuditLog::DeprecationNotice do |audit_entry|
          Loaders::ActiveRecord.load(::Organization, audit_entry.get(:org_id)).then do |org|
            org&.permalink(include_host: false)
          end
        end
      end
    end
  end
end
