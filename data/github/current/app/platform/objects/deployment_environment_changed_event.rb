# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class DeploymentEnvironmentChangedEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents a 'deployment_environment_changed' event on a given pull request."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, event)
        permission.belongs_to_issue_event(event)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_issue(object)
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:rdece, :repo_id, :issue_id, :deployment_environment_changed_event_id]
      ], as: "DECE", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |event|
        {
          prefix: :rdece,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          deployment_environment_changed_event_id: event.id,
        }
      end

      implements Interfaces::TimelineEvent

      implements Interfaces::PerformableViaApp


      field :pull_request, Objects::PullRequest, "PullRequest referenced by event.", method: :async_issue_or_pull_request, null: false

      field :deployment_status, Objects::DeploymentStatus, "The deployment status that updated the deployment environment.", null: false

      def deployment_status
        @object.async_issue_event_detail.then do |detail|
          Platform::Loaders::ActiveRecord.load(::DeploymentStatus, detail.deployment_status_id)
        end
      end

      url_fields description: "The HTTP URL for this deployment_environment_changed event.", visibility: :internal do |event|
        event.async_path_uri
      end
    end
  end
end
