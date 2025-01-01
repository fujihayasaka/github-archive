# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module ProjectV2Event
      include Platform::Interfaces::Base

      description "Represents an event related to a project on the timeline of an issue or pull request."

      visibility :internal

      field :project, Platform::Objects::ProjectV2, "Project referenced by event.", null: true, method: :async_memex_project

      field :was_automated, Boolean, visibility: :internal, method: :automated?, description: "Did this event result from workflow automation?", null: false

      def self.load_from_next_global_id(parsed_id)
        issue_id = parsed_id.parts[:issue_id]
        entry_id = parsed_id.parts[:id]

        ::Timeline::EntryLoader.load_entry(issue_id, entry_id)
      end

      def self.load_from_global_id(id)
        issue_id, entry_id = id.split(":", 2)

        ::Timeline::EntryLoader.load_entry(issue_id.to_i, entry_id)
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, event)
        Promise.all([event.async_memex_project, event.async_issue]).then do |project, issue|
          next false if issue.nil?

          project.async_owner.then do |owner|
            current_org = owner if owner.organization?

            next false unless permission.access_allowed?(
              :project_v2_read,
              current_org: current_org,
              resource: project,
              current_repo: nil,
              allow_integrations: true,
              allow_user_via_granular_actor: true
            )

            permission.async_repo_and_org_owner(issue).then do |repo, org|
              permission.access_allowed?(:show_issue,
                resource: issue,
                repo: repo,
                current_org: org,
                allow_integrations: true,
                allow_user_via_granular_actor: true,
                # Allow issues on public repos to be returned even when the current GitHub app isn't installed on the repo
                approved_integration_required: false,
              )
            end
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, event)
        event.async_issue.then do |issue|
          next false if issue.nil? || issue.hide_from_user?(permission.viewer)

          Promise.all([
            permission.load_repo_and_owner(issue).then do
              issue.readable_by?(permission.viewer)
            end,

            event.async_memex_project.then do |project|
              project.deleted_at.nil? && project.async_readable_by?(permission.viewer)
            end
          ]).then do |issue_readable, project_readable|
            issue_readable && project_readable
          end
        end
      end
    end
  end
end
