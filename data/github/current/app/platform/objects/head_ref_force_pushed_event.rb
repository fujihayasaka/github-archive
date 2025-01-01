# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    # Note: not yet a publicly available event type
    class HeadRefForcePushedEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents a 'head_ref_force_pushed' event on a given pull request."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, head_ref_forcepushed_event)
        permission.belongs_to_issue_event(head_ref_forcepushed_event)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_issue(object)
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:rhrfpe, :repo_id, :issue_id, :head_ref_force_pushed_event_id]
      ], as: "HRFPE", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |event|
        {
          prefix: :rhrfpe,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          head_ref_force_pushed_event_id: event.id,
        }
      end

      implements Interfaces::TimelineEvent

      implements Interfaces::PerformableViaApp


      field :pull_request, Objects::PullRequest, "PullRequest referenced by event.", method: :async_issue_or_pull_request, null: false

      field :before_commit, Objects::Commit, description: "Identifies the before commit SHA for the 'head_ref_force_pushed' event.", null: true

      def before_commit
        Promise.all([
          @object.async_issue_event_detail,
          @object.async_repository,
        ]).then do |issue_event_detail, repository|
          Loaders::GitObject.load(repository, issue_event_detail.before_commit_oid, expected_type: :commit)
        end
      end

      field :after_commit, Objects::Commit, description: "Identifies the after commit SHA for the 'head_ref_force_pushed' event.", null: true

      def after_commit
        Promise.all([
          @object.async_issue_event_detail,
          @object.async_repository,
        ]).then do |issue_event_detail, repository|
          Loaders::GitObject.load(repository, issue_event_detail.after_commit_oid, expected_type: :commit)
        end
      end

      field :ref_name, String, visibility: :internal, description: "Identifies the name of the ref of the force push.", method: :async_ref_name, null: false

      field :ref, Ref, description: "Identifies the fully qualified ref name for the 'head_ref_force_pushed' event.", null: true

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
    end
  end
end
