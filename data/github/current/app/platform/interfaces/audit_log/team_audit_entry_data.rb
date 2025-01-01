# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module AuditLog
      module TeamAuditEntryData
        include Platform::Interfaces::Base

        description "Metadata for an audit entry with action team.*"

        field :team_name, String, null: true, description: "The name of the team"
        def team_name
          @object.get :team
        end

        field :team, Platform::Objects::Team, null: true, description: "The team associated with the action"
        def team
          Loaders::ActiveRecord.load(::Team, @object.get(:team_id))
        end

        url_fields prefix: "team", null: true, description: "The HTTP URL for this team" do |audit_entry|
          Loaders::ActiveRecord.load(::Team, audit_entry.get(:team_id)).then do |team|
            if team
              team.async_organization.then do |_organization|
                team.permalink(include_host: false)
              end
            end
          end
        end # url_fields

        # internal only

        field :team_database_id, Integer, null: true, visibility: :internal, description: "The database ID of the team"
        def team_database_id
          @object.get :team_id
        end
      end
    end
  end
end
