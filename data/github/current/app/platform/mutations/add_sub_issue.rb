# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddSubIssue < Platform::Mutations::Base
      # Metadata
      description "Adds a sub-issue to a given issue"
      visibility :public
      minimum_accepted_scopes ["public_repo"]
      # Inputs and loaders
      argument :issue_id, ID, "The id of the issue.", required: true, loads: Objects::Issue
      argument :sub_issue_id, ID, "The id of the sub-issue.", required: false, loads: Objects::Issue
      argument :sub_issue_url, String, "The url of the sub-issue.", required: false
      argument :replace_parent, Boolean, "Option to replace parent issue if one already exists", required: false
      # Outputs and errors
      field :issue, Objects::Issue, "The parent issue that the sub-issue was added to.", null: true
      field :sub_issue, Objects::Issue, "The sub-issue of the parent.", null: true
      error_fields

      # Authorization
      def self.async_api_can_modify?(permission, **inputs)
        issue = inputs[:issue]
        sub_issue = self.find_sub_issue(inputs[:sub_issue], inputs[:sub_issue_url], permission.viewer)

        Promise.all([
          permission.async_repo_and_org_owner(issue),
          permission.async_repo_and_org_owner(sub_issue),
        ]).then do |(repo, org), (sub_issue_repo, sub_issue_org)|
          permission.access_allowed?(
            :triage_issue,
            resource: issue,
            repo: repo,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          ) && permission.access_allowed?(
            :triage_issue,
            resource: sub_issue,
            repo: sub_issue_repo,
            current_org: sub_issue_org,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        end
      end

      # Body
      def resolve(**args)
        user = context[:viewer]
        issue = args[:issue]
        sub_issue = self.class.find_sub_issue(args[:sub_issue], args[:sub_issue_url], user)
        replace_parent = args[:replace_parent]

        unless SubIssuesFeature.enabled?(issue.repository)
          raise Platform::Errors::Forbidden.new("Sub-issues are not enabled for this repository.")
        end

        relationship = if replace_parent
          sub_issue.add_or_replace_parent!(issue, user)
        else
          issue.add_sub_issue!(sub_issue, user.id)
        end

        unless relationship&.persisted?
          raise Platform::Errors::Validation.new("An error occured while adding the sub-issue to the parent issue. #{relationship.errors.full_messages.to_sentence}")
        end

        context[:recalculate_sub_issues_summary_issue_id] = issue.id

        { issue: issue.reload, sub_issue: sub_issue.reload, errors: [] }
      rescue GitHub::Prioritizable::Context::LockedForRebalance
        raise Errors::ServiceUnavailable.new("Parent sub-issue list is temporarily locked for maintenance. Please try again.")
      # Unlike most sub-issues validations, max-height errors are raised in the `after_create` callback.
      rescue SubIssue::MaximumHeightError => e
        raise Platform::Errors::Validation.new("An error occured while adding the sub-issue to the parent issue. #{e.message}")
      end

      def self.find_sub_issue(sub_issue, sub_issue_url, user)
        sub_issue ||= DraftIssueReferenceFilter.new(text: sub_issue_url, viewer: user).first_reference if sub_issue_url.present?

        raise Errors::Validation.new("Could not find a sub-issue for the given arguments.") unless sub_issue.present?

        sub_issue
      end
    end
  end
end
