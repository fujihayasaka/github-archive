# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class MergeBranch < Platform::Mutations::Base
      include Helpers::GitRefs

      description "Merge a head into a branch."
      minimum_accepted_scopes ["public_repo"]

      argument :repository_id, ID, "The Node ID of the Repository containing the base branch that will be modified.", required: true, loads: Objects::Repository
      argument :base, String, "The name of the base branch that the provided head will be merged into.", required: true
      argument :head, String, "The head to merge into the base branch. This can be a branch name or a commit GitObjectID.",  required: true
      argument :commit_message, String, "Message to use for the merge commit. If omitted, a default will be used.", required: false
      argument :author_email, String, "The email address to associate with this commit.", visibility: { public: { environments: [:dotcom] }, internal: { environments: [:enterprise] } }, required: false

      field :merge_commit, Objects::Commit, "The resulting merge Commit.", null: true

      def self.async_api_can_modify?(permission, repository:, **_)
        permission.async_owner_if_org(repository).then do |org|
          permission.access_allowed?(:merge_branch,
            resource: repository,
            current_repo: repository,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      def resolve(repository:, base:, head:, commit_message: nil, author_email: nil)
        base_branch = repository.heads.find(base)
        raise Errors::NotFound.new("No such base.") unless base_branch

        if author_email && GitHub.email_verification_enabled?
          raise Errors::Unprocessable.new("Unverified email address") unless UserEmail.verified.where(user_id: context[:viewer].id, email: author_email).exists?
        end

        merge_commit, error, error_message = base_branch.merge(context[:viewer], head, {
          author_email: author_email,
          commit_message: commit_message,
          reflog_data: build_reflog_hash(context: context, via: "MergeBranch mutation"),
        })
        if merge_commit
          { merge_commit: merge_commit }
        elsif error == :workflow_policy_update_error
          raise Errors::Unauthorized::Write.new("Failed to merge: #{error_message.inspect}")
        else
          raise Errors::Unprocessable.new("Failed to merge: #{error_message.inspect}")
        end
      end
    end
  end
end
