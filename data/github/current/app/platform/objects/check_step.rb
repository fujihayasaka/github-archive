# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CheckStep < Platform::Objects::Base
      description "A single check step."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        object.async_check_run.then do |check_run|
          permission.async_repo_and_org_owner(check_run).then do |repo, org|
            permission.access_allowed?(:read_actions, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_check_run.then do |check_run|
          permission.load_repo_and_owner(check_run).then do |repo|
            repo.resources.actions.async_readable_by?(permission.viewer)
          end
        end
      end

      scopeless_tokens_as_minimum

      field :name, String, "The step's name.", null: false

      field :completed_log, Objects::CompletedLog, "The completed logs for this step.", null: true

      def completed_log
        return nil if object.completed_log_url.nil?
        { url: object.completed_log_url, lines: object.completed_log_lines }
      end

      field :started_at, Scalars::DateTime, description: "Identifies the date and time when the check step was started.", null: true

      field :completed_at, Scalars::DateTime, description: "Identifies the date and time when the check step was completed.", null: true

      field :number, Int, "The index of the step in the list of steps of the parent check run.", null: false

      field :status, Enums::CheckStatusState, description: "The current status of the check step.", null: false

      field :conclusion, Enums::CheckConclusionState, description: "The conclusion of the check step.", null: true

      field :seconds_to_completion, Int, description: "Number of seconds to completion.", null: true

      field :external_id, String, description: "A reference for the check step on the integrator's system.", null: true

    end
  end
end
