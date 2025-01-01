# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module AuditLog
      module EnterpriseAuditEntryData
        include Platform::Interfaces::Base

        description "Metadata for an audit entry containing enterprise account information."

        field :enterprise, "Platform::Objects::Enterprise", null: true, visibility: :under_development, description: "The enterprise associated with the action."
        def enterprise
          Loaders::ActiveRecord.load(::Business, @object.get(:business_id))
        end

        field :enterprise_slug, String, null: true, description: "The slug of the enterprise."
        def enterprise_slug
          @object.get :business
        end

        url_fields prefix: "enterprise", null: true, description: "The HTTP URL for this enterprise." do |audit_entry|
          Loaders::ActiveRecord.load(::Business, audit_entry.get(:business_id)).then do |business|
            if business.present?
              template = Addressable::Template.new("/enterprises/{slug}")
              template.expand(slug: business.to_param)
            end
          end
        end

        # internal only

        field :enterprise_database_id, Integer, null: true, visibility: :internal, description: "The database ID of the enterprise (Business model)."
        def enterprise_database_id
          @object.get :business_id
        end

        field :enterprise_name, String, null: true, visibility: :internal, description: "The name of the enterprise."
        def enterprise_name
          @object.get(:name) || @object.get(:business)
        end
      end
    end
  end
end
