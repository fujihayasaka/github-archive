# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PinnedIssue < Platform::Objects::Base
      description "A Pinned Issue is a issue pinned to a repository's index page."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        Loaders::ActiveRecord.load(::Issue, object.issue_id).then do |issue|
          permission.async_repo_and_org_owner(issue).then do |repo, org|
            permission.access_allowed?(:show_issue, resource: issue, repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        Loaders::ActiveRecord.load(::Issue, object.issue_id).then do |issue|
          return false if T.must(issue).hide_from_user?(permission.viewer)
          permission.load_repo_and_owner(issue).then do
            T.must(issue).readable_by?(permission.viewer)
          end
        end
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
          [:urrpi, :user_id, :repository_id, :pinned_issue_id],
          [:orrpi, :organization_id, :repository_id, :pinned_issue_id],
          # ^^ these were added before we decided to remove repo owner from the ID,
          # but they have to stay here for compatibility.
          [:pi, :repository_id, :pinned_issue_id],
        ], as: "PIN", ready_date: "2021-05-15" do |pinned_issue|
        {
          prefix: :pi,
          repository_id: pinned_issue.repository_id,
          pinned_issue_id: pinned_issue.id
        }
      end

      database_id_field
      full_database_id_field

      field :issue, Objects::Issue, method: :async_issue, description: "The issue that was pinned.", null: false
      field :repository, Objects::Repository, method: :async_repository, description: "The repository that this issue was pinned to.", null: false
      field :pinned_by, Interfaces::Actor, method: :async_pinned_by, description: "The actor that pinned this issue.", null: false
    end
  end
end
