# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module AuditLog
      class TeamChangeParentTeamAuditEntry < Platform::Objects::AuditLog::Base
        description "Audit log entry for a team.change_parent_team event."

        minimum_accepted_scopes ["admin:org", "admin:enterprise"]

        # Determine whether the viewer can access this object via the API (called internally).
        # This is where Egress checks for OAuth scopes and GitHub Apps go.
        # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
        def self.async_api_can_access?(permission, audit_entry)
          permission.async_api_can_access_audit_entry?(audit_entry)
        end

        # Determine whether the viewer can see this object (called internally).
        # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
        def self.async_viewer_can_see?(permission, audit_entry)
          permission.async_viewer_can_see_audit_entry?(audit_entry)
        end

        implements_node_with_document_id(prefix: "TCPTAE")
        implements Platform::Interfaces::AuditLog::AuditEntry
        implements Platform::Interfaces::AuditLog::OrganizationAuditEntryData
        implements Platform::Interfaces::AuditLog::TeamAuditEntryData

        # Fetch current team name from id. Returns nil wrapped in a promise
        # if no team is found for the given id.
        def self.team_name_from_id(team_id)
          Loaders::ActiveRecord.load(::Team, team_id).then do |team|
            if team.present?
              team.async_organization.then do |org|
                "#{T.must(org).display_login}/#{team.slug}"
              end
            end
          end
        end

        field :is_ldap_mapped, Boolean, null: true, description: "Whether the team was mapped to an LDAP Group.", deprecated: Helpers::AuditLog::DeprecationNotice
        def is_ldap_mapped
          !!@object.get(:ldap_mapped)
        end

        field :parent_team_name, String, null: true, description: "The name of the new parent team", deprecated: Helpers::AuditLog::DeprecationNotice
        def parent_team_name
          @object.get(:parent_team) || self.class.team_name_from_id(@object.get(:parent_team_id))
        end

        field :parent_team, Platform::Objects::Team, null: true, description: "The new parent team.", deprecated: Helpers::AuditLog::DeprecationNotice
        def parent_team
          Loaders::ActiveRecord.load(::Team, @object.get(:parent_team_id))
        end

        url_fields prefix: :parent_team, null: true, description: "The HTTP URL for the parent team", deprecated: Helpers::AuditLog::DeprecationNotice do |audit_entry|
          Loaders::ActiveRecord.load(::Team, audit_entry.get(:parent_team_id)).then do |parent_team|
            if parent_team.present?
              parent_team.async_organization.then do |_organization|
                parent_team.permalink(include_host: false)
              end
            end
          end
        end

        field :parent_team_name_was, String, null: true, description: "The name of the former parent team", deprecated: Helpers::AuditLog::DeprecationNotice
        def parent_team_name_was
          @object.get(:parent_team_was) || self.class.team_name_from_id(@object.get(:parent_team_id_was))
        end

        field :parent_team_was, Platform::Objects::Team, null: true, description: "The former parent team.", deprecated: Helpers::AuditLog::DeprecationNotice
        def parent_team_was
          Loaders::ActiveRecord.load(::Team, @object.get(:parent_team_id_was))
        end

        url_fields prefix: :parent_team_was, null: true, description: "The HTTP URL for the previous parent team", deprecated: Helpers::AuditLog::DeprecationNotice do |audit_entry|
          Loaders::ActiveRecord.load(::Team, audit_entry.get(:parent_team_id_was)).then do |parent_team|
            if parent_team.present?
              parent_team.async_organization.then do |_organization|
                parent_team.permalink(include_host: false)
              end
            end
          end
        end

        # internal only fields

        field :parent_team_database_id, Integer, null: true, visibility: :internal, description: "The ID of the new parent team", deprecated: Helpers::AuditLog::DeprecationNotice
        def parent_team_database_id
          @object.get(:parent_team_id)
        end

        field :parent_team_database_id_was, Integer, null: true, visibility: :internal, description: "The ID of the former parent team", deprecated: Helpers::AuditLog::DeprecationNotice
        def parent_team_database_id_was
          @object.get(:parent_team_id_was)
        end
      end
    end
  end
end
