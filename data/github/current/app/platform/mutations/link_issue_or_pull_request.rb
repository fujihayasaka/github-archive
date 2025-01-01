# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class LinkIssueOrPullRequest < Platform::Mutations::Base
      description "Link an issue to a pull request or a pull request to an issue."
      required_capabilities [:mobile_only_schema_mask]
      minimum_accepted_scopes ["public_repo"]

      argument :base_issue_or_pull_request_id, ID, "ID of the issue or pull request to link to.", required: true, loads: Unions::IssueOrPullRequest
      argument :linking_ids, [ID], "IDs of the issue or pull request to link.", required: true, loads: Unions::IssueOrPullRequest, as: :linked_issue_or_pull_requests

      field :base_issue_or_pull_request, Unions::IssueOrPullRequest, "Issue or pull request that was linked to.", null: true
      field :linked_issues_or_pull_requests, [Unions::IssueOrPullRequest], "Issues or pull requests linked to the base object.", null: true
      error_fields

      extras [:execution_errors]

      def resolve(base_issue_or_pull_request:, linked_issue_or_pull_requests:, execution_errors:, **inputs)
        is_pull_request = pull_request?(base_issue_or_pull_request)
        connected_by_key = is_pull_request ? :issue_id : :pull_request_id

        references = base_issue_or_pull_request.close_issue_references.manual
        connected_ids = references.pluck(connected_by_key)

        ids_to_remove = connected_ids - linked_issue_or_pull_requests.map(&:id)

        refs_to_remove = CloseIssueReference.where(connected_by_key => ids_to_remove)
        refs_to_remove.destroy_all

        ids_to_add = linked_issue_or_pull_requests.map(&:id) - connected_ids
        refs_to_add = linked_issue_or_pull_requests.select { |item| ids_to_add.include?(item.id) }

        refs_to_add.each do |ref|
          base_issue_or_pull_request.close_issue_references
            .create(connected_by_key => ref.id, :source => :manual, :actor_id => context[:viewer].id)
        end

        connected_ids = base_issue_or_pull_request.close_issue_references.pluck(connected_by_key)

        {
          base_issue_or_pull_request: base_issue_or_pull_request,
          linked_issues_or_pull_requests: viewable_xrefed_items(connected_ids, is_pull_request),
          errors: []
        }
      end

      def self.async_api_can_modify?(permission, **inputs)
        object = inputs[:base_issue_or_pull_request]

        permission.async_repo_and_org_owner(object).then do |repo, _org|
          repo.issues_and_prs_linkable_by?(permission.viewer)
        end
      end

      private

      # These two methods -- `pull_request?` and `viewable_xrefed_items` -- have been borrowed from:
      # app/controllers/closing_references_controller.rb
      def pull_request?(issue_or_pull_request)
        issue_or_pull_request.is_a?(PullRequest)
      end

      # Given a set of issue or PR ids, returns the ones the user is permitted to view
      def viewable_xrefed_items(ids, is_pull_request)
        scope = is_pull_request ? Issue : PullRequest

        scope.where(id: ids).select do |object|
          next if object.spammy? && !context[:viewer]&.site_admin?
          object.repository&.public? || object.repository&.visible_and_readable_by?(context[:viewer])
        end
      end
    end
  end
end
