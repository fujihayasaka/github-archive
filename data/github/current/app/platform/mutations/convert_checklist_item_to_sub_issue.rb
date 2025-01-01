# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ConvertChecklistItemToSubIssue < Platform::Mutations::Base
      description "Converts a checklist item to a sub-issue."
      visibility :internal
      minimum_accepted_scopes ["public_repo"]

      # We can remove title and make body required when this ships out fully
      argument :title, String, "The title for the new sub-issue.", required: false
      argument :body, String, "The body for the new sub-issue.", required: false
      argument :repository_id, ID, "The Node ID of the repository.", required: true, loads: Objects::Repository
      argument :parent_issue_id, ID, "The Node ID of the parent issue to add this new issue to", required: true, loads: Objects::Issue, visibility: :public
      argument :position, [Integer], "The position of the list item to replace in the parent issue, formatted as [list_index, item_index]. Nested lists are treated as the next list in the sequence", required: true, visibility: :internal

      error_fields
      field :issue, Objects::Issue, "The new issue.", null: true

      extras [:execution_errors]

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, repository:, **inputs)
        issue = inputs[:parent_issue]

        permission.async_repo_and_org_owner(issue).then do |(repo, org)|
          permission.access_allowed?(
            :convert_checklist_item_to_sub_issue,
            resource: issue,
            repo: repo,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        end
      end

      def resolve(execution_errors:, repository:, **inputs)
        parent_issue = inputs[:parent_issue]
        viewer = context[:viewer]

        position = inputs[:position]
        unless position.present? && position.length == 2
          raise Platform::Errors::Validation.new("The position must be an array with two elements.")
        end

        if !repository.has_issues?
          raise Errors::Forbidden.new("Issues has been disabled in this repository.")
        end

        unless SubIssuesFeature.enabled?(repository, actor: viewer)
          raise Errors::Forbidden.new("You may not create sub-issues")
        end

        # We want to make sure the body hasn't changed since the user loaded the page, potentially causing them to
        # unknowingly create an issue from the wrong task list item, as the position could have changed.
        body = inputs[:body]
        if body && body.strip != parent_issue.body&.strip
          raise Platform::Errors::Validation.new("The body of the parent issue has changed. Please reload the page and try again.")
        end

        parsed_text, parsed_issue = parent_issue.get_issue_at_tasklist_position(position) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        unless parsed_text
          raise Platform::Errors::Validation.new("No parseable text found at the given position.")
        end

        issue_at_position = parsed_issue if parsed_issue && Platform::Objects::Issue.async_api_can_access?(context[:permission], parsed_issue).sync

        if issue_at_position&.pull_request?
          raise Platform::Errors::Validation.new("The issue at the given position is a pull request and cannot be converted to a sub-issue.")
        end

        if issue_at_position
          issue = issue_at_position
          create_sub_issue_relationship(parent_issue, issue, viewer)
        else
          issue = create_new_sub_issue(repository, parsed_text, parent_issue, viewer)
        end

        context[:recalculate_sub_issues_summary_issue_id] = parent_issue.id

        begin
          errors = []

          should_remove = viewer.feature_enabled?(:sub_issues_remove_on_tasklist_convert)
          unless inputs[:parent_issue].update_issue_body_after_convert_task(inputs[:position], issue, viewer, remove: should_remove)
            errors << {
              path: %w(input position),
              message: "The issue was successfully created but we are unable to update the parent issue at this time.",
            }
          end
          { issue: issue.reload, errors: errors } # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        rescue GitHub::Prioritizable::Context::LockedForRebalance
          raise Errors::Unprocessable.new("The parent sub-issue list is temporarily locked for maintenace. Please try again.")
        end
      end

      private

      def create_sub_issue_relationship(parent_issue, sub_issue, viewer)
        begin
          relationship = parent_issue.add_sub_issue!(sub_issue, viewer.id)

          if !relationship&.persisted?
            raise Platform::Errors::Validation.new("An error occurred while adding the sub-issue to the parent issue. #{relationship.errors.full_messages.to_sentence}")
          end
        rescue SubIssue::MaximumHeightError => e
          raise Platform::Errors::Validation.new("An error occurred while adding the sub-issue to the parent issue. #{e.message}")
        rescue GitHub::Prioritizable::Context::LockedForRebalance
          raise Errors::ServiceUnavailable.new("Parent sub-issue list is temporarily locked for maintenance. Please try again.")
        end
      end

      def create_new_sub_issue(repository, title, parent_issue, viewer)
        issue_attributes = Issues::CreateIssueAttributes.new(
          repository: repository,
          title: title,
          parent_issue: parent_issue,
        )

        integration = @context[:permission].integration_user_request? ? @context[:integration] : nil
        result = Issues.domain.create(issue_attributes, viewer, integration: integration, skip_permission_checks: true)

        case result
        when GH::Result::Ok
          result.value
        when GH::Result::Error::LockedForRebalance
          raise Errors::ServiceUnavailable.new("Parent sub-issue list is temporarily locked for maintenance. Please try again.")
        when GH::Result::Error::Validation
          raise Platform::Errors::Validation.new("An error occured while creating the sub-issue and adding it to the parent issue. #{result.message}")
        end
      end
    end
  end
end
