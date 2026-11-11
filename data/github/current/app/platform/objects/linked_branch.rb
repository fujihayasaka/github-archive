# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class LinkedBranch < Platform::Objects::Base
      description "A branch linked to an issue."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, branch_reference_issue)
        Platform::Loaders::ActiveRecordAssociation.load(branch_reference_issue, :issue).then do |issue|
          Platform::Loaders::ActiveRecordAssociation.load(branch_reference_issue, :branch_repository).then do |repository|
            repository.async_network.then do
              permission.typed_can_access?("Issue", issue) && permission.typed_can_access?("Ref", repository.refs.find(branch_reference_issue.branch_name))
            end
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        Platform::Loaders::ActiveRecordAssociation.load(object, :branch_repository).then do |repository|
          permission.typed_can_see?("Repository", repository) && permission.belongs_to_issue(object)
        end
      end

      def self.load_from_global_id(parsed_id)
        Platform::Objects.async_find_record_by_id(BranchIssueReference, parsed_id)
      end

      implements_node templates: [[:lb, :issue_id, :linked_branch_id]], as: "LB", ready_date: "1970-01-01" do |linked_branch|
        {
          prefix: :lb,
          issue_id: linked_branch.issue_id,
          linked_branch_id: linked_branch.id
        }
      end

      scopeless_tokens_as_minimum

      field :ref, Objects::Ref, "The branch's ref.", null: true

      def ref
        Platform::Loaders::ActiveRecordAssociation.load(@object, :branch_repository).then do |repository|
          repository.async_network.then do
            repository.refs.find(@object.branch_name)
          end
        end
      end
    end
  end
end
