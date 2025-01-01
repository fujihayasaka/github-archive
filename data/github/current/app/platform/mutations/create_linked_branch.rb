# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateLinkedBranch < Platform::Mutations::Base
      include Helpers::GitRefs

      description "Create a branch linked to an issue."
      minimum_accepted_scopes ["public_repo"]
      extras [:execution_errors]

      argument :issue_id, ID, "ID of the issue to link to.", required: true, loads: Objects::Issue, as: :issue
      argument :oid, Scalars::GitObjectID, "The commit SHA to base the new branch on.", required: true
      argument :name, String, "The name of the new branch. Defaults to issue number and title.", required: false
      argument :repository_id, ID, "ID of the repository to create the branch in. Defaults to the issue repository.", required: false, loads: Objects::Repository, as: :repository

      field :linked_branch, Objects::LinkedBranch, "The new branch issue reference.", null: true
      field :issue,  Objects::Issue, "The issue that was linked to.", null: true
      error_fields

      def resolve(execution_errors:, issue:, repository: nil, **inputs)
        repository ||= issue.repository
        branch_name = inputs[:name] || BranchIssueReference.candidate_branch_name(issue: issue, repository: repository)

        begin
          branch_issue_reference = BranchIssueReference.create_with_new_branch!(
            issue: issue,
            repository: repository,
            creator: context[:viewer],
            new_branch_name: branch_name,
            source_branch_name: nil,
            reflog_data: build_reflog_hash(context: context, via: "CreateLinkedBranch mutation"),
            commit_oid: inputs[:oid]
          )
        rescue ActiveRecord::RecordInvalid => invalid
          return error_response(invalid.message, execution_errors)
        rescue Git::Ref::InvalidName => error
          return error_response("#{branch_name} is not a valid branch name.", execution_errors)
        rescue Git::Ref::HookFailed => error
          return error_response("Could not create ref because a Git pre-receive hook failed: #{error.message}.", execution_errors)
        rescue Git::Ref::UpdateError => error
          # We're not expecting to get here but in case something gets by validation let's catch it
          return error_response("Could not create linked branch.", execution_errors)
        end

        {
          linked_branch: branch_issue_reference,
          issue: issue,
          errors: []
        }
      end

      def error_response(message, execution_errors)
        Platform::UserErrors.append_legacy_mutation_error_messages_to_context(Array.wrap(message), execution_errors)
        client_error = {
          message: message,
          path: %w(input),
        }

        {
          linked_branch: nil,
          errors: [client_error],
        }
      end

      def self.async_api_can_modify?(permission, issue:, oid:, repository: nil, **inputs)
        branch_repository = repository || issue.repository
        permission.async_owner_if_org(branch_repository).then do |org|
          issue.repository.resources.issues.writable_by?(permission.viewer) && permission.access_allowed?(:create_ref_v2,
            repo: branch_repository,
            current_org: org,
            before_oid: GitHub::NULL_OID,
            after_oid: oid,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end
    end
  end
end
