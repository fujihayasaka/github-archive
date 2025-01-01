# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AssignAppToIssue < Platform::Mutations::Base
      include Platform::Helpers::ReadFromSelectedReplicas

      description "Assign apps to an issue."
      visibility :internal

      minimum_accepted_scopes ["public_repo"]

      argument :issue_id, ID, "The Node ID of the issue to modify.", required: true, loads: Objects::Issue, as: :issue
      argument :app_ids, [ID], "The apps IDs to assign to an issue.", required: true

      field :success, Boolean, "Did the operation succeed?", null: true
      field :issue, Objects::Issue, "The issue that is assigned to the app.", null: true
      field :actor, Interfaces::Actor, "Identifies the actor who performed the event.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, issue:, **inputs)
        permission.async_repo_and_org_owner(issue).then do |repo, org|
          permission.access_allowed?(
            :triage_issue,
            repo: repo,
            resource: issue,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true)
        end
      end

      def resolve(issue:, app_ids:)
        # convert the global id into database ids
        ids = app_ids.map do |global_app_id|
          type, app_id = Platform::Helpers::NodeIdentification.from_global_id(global_app_id)
          raise Errors::Validation.new("Invalid app ID: #{global_app_id}.") if type != "App" || app_id.nil?
          app_id.to_i
        end

        read_from_selected_replicas([ApplicationRecord::Repositories]) do
          repo = issue.repository
          apps_by_id = Integration.includes(:bot).where(id: ids).index_by(&:id)

          ids.each do |app_id|
            app = apps_by_id[app_id]

            if app.nil?
              raise Errors::ServiceUnavailable.new("App is not configured for app id: #{app_id}.")
            end

            installation = app.installations_on(repo.owner)&.first
            if installation.nil? || installation.repository_ids(repository_ids: [repo.id]).none?
              raise Errors::Forbidden.new("App does not have access to the repository.")
            end

            bot = app.bot
            if bot
              begin
                issue.assignees << bot unless issue.assignees.include?(bot)
              rescue => e
                raise Errors::ServiceUnavailable.new("Failed to assign app: #{e.message}.")
              end
            else
              return { success: false }
            end
          end
        end

        issue.save!

        { success: true, issue: issue, actor: context[:viewer] }
      end
    end
  end
end
