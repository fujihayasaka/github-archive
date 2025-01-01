# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UnmarkIssueAsDuplicate < Platform::Mutations::Base
      description "Unmark an issue as a duplicate of another issue."

      minimum_accepted_scopes ["public_repo"]

      argument :duplicate_id, ID, "ID of the issue or pull request currently marked as a duplicate.", required: true, loads: Unions::IssueOrPullRequest, as: :record
      argument :canonical_id, ID, "ID of the issue or pull request currently considered canonical/authoritative/original.", required: true, loads: Unions::IssueOrPullRequest, as: :canonical_record

      field :duplicate, Unions::IssueOrPullRequest, "The issue or pull request that was marked as a duplicate.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, record:, **inputs)
        issue = record
        permission.async_repo_and_org_owner(issue).then do |repo, org|
          access_type = issue.is_a?(::PullRequest) ? :update_pull_request : :edit_issue
          permission.access_allowed?(access_type, repo: repo, resource: issue, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def resolve(canonical_record:, record:, **inputs)
        duplicate_type = record.is_a?(PullRequest) ? "pull request" : "issue"
        issue = record.is_a?(PullRequest) ? record.issue : record

        canonical_type = canonical_record.is_a?(PullRequest) ? "pull request" : "issue"
        canonical_issue = if canonical_record.is_a?(PullRequest)
          canonical_record.issue
        else
          canonical_record
        end

        duplicate_issue = DuplicateIssue.with_duplicate_issue(issue).
          with_canonical_issue(canonical_issue).first

        success = if duplicate_issue.nil?
          # no DuplicateIssue record means the issue was never marked as a duplicate of the
          # canonical issue
          true
        elsif duplicate_issue.duplicate?
          if !context[:actor].can_have_granular_permissions? && !duplicate_issue.can_unmark_as_duplicate?(context[:viewer])
            raise Errors::Forbidden.new("#{context[:viewer].display_login} cannot unmark that " +
                                           "#{duplicate_type} as a duplicate of the " +
                                           "specified #{canonical_type}.")
          end

          event = issue.events.unmarked_as_duplicates.
            build(actor_id: context[:viewer].id, repository_id: issue.repository_id,
                  subject_type: canonical_issue.class.name, subject_id: canonical_issue.id)

          duplicate_issue.actor = context[:viewer]
          duplicate_issue.duplicate = false

          event.save && duplicate_issue.save
        else
          # No-op: the issue has already been marked as not a duplicate of the canonical issue
          true
        end

        if success
          { duplicate: record }
        else
          raise Errors::Unprocessable.
            new("Could not mark the #{duplicate_type} as not a duplicate of the specified " +
                "#{canonical_type}.")
        end
      end
    end
  end
end
