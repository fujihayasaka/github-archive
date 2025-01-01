# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class LinkBranches < Platform::Mutations::Base
      description "Link branches to an issue"
      minimum_accepted_scopes ["public_repo"]

      visibility :under_development

      argument :issue_id, ID, "ID of the issue to link to.", required: true, loads: Objects::Issue
      argument :linking_ids, [ID], "IDs of the branches to link.", required: true, loads: Objects::Ref, as: :linked_branches

      field :issue,  Objects::Issue, "Issue that was linked to.", null: true
      error_fields

      extras [:execution_errors]

      def resolve(issue:, linked_branches:, execution_errors:, **inputs)
        current_linked_branches = issue.linked_branches
        current_linked_branches_identifiers = current_linked_branches.map { |branch| "#{branch.branch_repository_id}_#{branch.branch_name}" }
        linked_branches_identifiers = linked_branches.map { |branch| "#{branch.repository.id}_#{branch.name}" }

        branches_to_unlink = []
        current_linked_branches.each do |branch|
          branch_identifier = "#{branch.branch_repository_id}_#{branch.branch_name}"
          if !linked_branches_identifiers.include?(branch_identifier)
            branches_to_unlink.push(branch)
          end
        end

        branches_to_link = []
        linked_branches.each do |branch|
          branch_identifier = "#{branch.repository.id}_#{branch.name}"
          if !current_linked_branches_identifiers.include?(branch_identifier)
            branches_to_link.push(branch)
          end
        end


        branches_to_unlink.each do |branch|
          branch.destroy
        end

        branches_to_link.each do |branch|
          ref = BranchIssueReference.create!(
            issue: issue,
            branch_name: branch.name,
            branch_repository: branch.repository,
            creator: context[:viewer]
          )
        end

        {
          issue: issue,
          errors: []
        }
      end

      def self.async_api_can_modify?(permission, **inputs)
        object = inputs[:issue]

        permission.async_repo_and_org_owner(object).then do |repo, _org|
          repo.issues_and_prs_linkable_by?(permission.viewer)
        end
      end

    end
  end
end
