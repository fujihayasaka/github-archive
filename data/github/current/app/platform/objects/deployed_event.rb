# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class DeployedEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents a 'deployed' event on a given pull request."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, deployed_event)
        permission.belongs_to_issue_event(deployed_event)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_issue(object)
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:rde, :repo_id, :issue_id, :deployed_event_id]
      ], as: "DEE", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |event|
        {
          prefix: :rde,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          deployed_event_id: event.id,
        }
      end

      implements Interfaces::TimelineEvent

      implements Interfaces::PerformableViaApp


      # TODO: remove this when the declaration in TimelineEvent becomes public
      database_id_field

      field :pull_request, Objects::PullRequest, "PullRequest referenced by event.", method: :async_issue_or_pull_request, null: false

      field :deployment, Objects::Deployment, "The deployment associated with the 'deployed' event.", null: false

      def deployment
        @object.async_issue_event_detail.then do |detail|
          Platform::Loaders::ActiveRecord.load(::Deployment, detail.deployment_id).then do |deployment|
            deployment || ::Deployment.new(repository: @object.repository, description: "destroyed deployment")
          end
        end
      end

      field :ref, Ref, description: "The ref associated with the 'deployed' event.", null: true

      def ref
        Promise.all([
          @object.async_issue_event_detail,
          @object.async_repository,
        ]).then do |issue_event_detail, repository|
          repository.async_network.then do
            repository.heads.find(issue_event_detail.ref)
          end
        end
      end

      url_fields description: "The HTTP URL for this deployed event.", visibility: :internal do |event|
        event.async_path_uri
      end
    end
  end
end
