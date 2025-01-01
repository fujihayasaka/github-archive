# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateCommitOnBranch < Platform::Mutations::Base
      include Helpers::GitRefs

      description <<~MARKDOWN
        Appends a commit to the given branch as the authenticated user.

        This mutation creates a commit whose parent is the HEAD of the provided
        branch and also updates that branch to point to the new commit.
        It can be thought of as similar to `git commit`.

        ### Locating a Branch

        Commits are appended to a `branch` of type `Ref`.
        This must refer to a git branch (i.e.  the fully qualified path must
        begin with `refs/heads/`, although including this prefix is optional.

        Callers may specify the `branch` to commit to either by its global node
        ID or by passing both of `repositoryNameWithOwner` and `refName`.  For
        more details see the documentation for `CommittableBranch`.

        ### Describing Changes

        `fileChanges` are specified as a `FilesChanges` object describing
        `FileAdditions` and `FileDeletions`.

        Please see the documentation for `FileChanges` for more information on
        how to use this argument to describe any set of file changes.

        ### Authorship

        Similar to the web commit interface, this mutation does not support
        specifying the author or committer of the commit and will not add
        support for this in the future.

        A commit created by a successful execution of this mutation will be
        authored by the owner of the credential which authenticates the API
        request.  The committer will be identical to that of commits authored
        using the web interface.

        If you need full control over author and committer information, please
        use the Git Database REST API instead.

        ### Commit Signing

        Commits made using this mutation are automatically signed by GitHub if
        supported and will be marked as verified in the user interface.
      MARKDOWN

      minimum_accepted_scopes ["public_repo"]

      argument :branch, Inputs::CommittableBranch, "The Ref to be updated.  Must be a branch.", required: true
      argument :file_changes, Inputs::FileChanges, "A description of changes to files in this commit.", required: false
      argument :message, Inputs::CommitMessage, "The commit message the be included with the commit.", required: true
      argument :expected_head_oid, Scalars::GitObjectID, "The git commit oid expected at the head of the branch prior to the commit", required: true

      error_fields
      field :commit, Objects::Commit, "The new commit.", null: true
      field :ref, Objects::Ref, "The ref which has been updated to point to the new commit.", null: true

      def load_branch(input)
        if input.id
          ref = Helpers::NodeIdentification.typed_object_from_id([Objects::Ref], input.id, @context)
          unless ref && ref.branch?
            raise Errors::NotFound, "Could not resolve to a node with the global id of '#{input.id}'"
          end
          return ref
        end
        async_repository_name_with_owner(input.repository_name_with_owner).then do |repo|
          repo.heads.find(input.branch_name).tap do |ref|
            raise(Errors::NotFound, "Branch not found") unless ref&.branch?
          end
        end
      end

      def self.async_api_can_modify?(permission, branch:, file_changes: nil, **_)
        repository = branch.repository

        files = Array.new
        file_changes.additions.each do |addition|
          oid = Rugged::Repository.hash_data(addition.contents, :blob)
          file = RefUpdates::WorkflowUpdatesPolicy::FileUpdate.new(addition.path, oid)
          files.append(file)
        end

        permission.async_owner_if_org(repository).then do |org|
          allowed = permission.access_allowed?(:append_commit_to_ref,
            resource: repository,
            current_repo: repository,
            current_org: org,
            ref_name: branch.name,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
          allowed &= permission.access_allowed?(:write_files,
            resource: repository,
            current_repo: repository,
            current_org: org,
            files: files,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
          allowed
        end
      end

      def resolve(branch:, message:, expected_head_oid:, file_changes: nil)
        repository = branch.repository

        begin
          # We don't need the commit object, just to make sure it exists.
          repository.commits.find(expected_head_oid)
        rescue GitRPC::ObjectMissing, GitRPC::InvalidObject
          raise Errors::NotFound.new("No commit exists with specified expectedHeadOid '#{expected_head_oid}'.")
        end

        commit_metadata = {
          author: context[:viewer],
          message: message,
        }

        reflog_data = build_reflog_hash(context: context, via: "CreateCommitOnBranch mutation")

        begin
          commit = branch.append_commit(
            commit_metadata,
            context[:viewer],
            reflog_data:,
            target_oid: expected_head_oid,
            sign: true,
            force: false,
          ) do |files|
            next unless file_changes

            file_changes.additions.each do |addition|
              files.add(addition.path, addition.contents)
            end

            file_changes.deletions.each do |deletion|
              files.remove(deletion.path)
            end
          end

          { ref: branch, commit: commit, errors: [] }
        rescue GitRPC::BadObjectState => e
          fail Errors::NotFound, <<~ERROR.squish
            A path was requested for deletion which does not
            exist as of commit oid `#{branch.target_oid}`
          ERROR
        rescue Git::Ref::NotFastForward
          fail Errors::StaleData, "Expected branch to point to #{expected_head_oid.inspect} but it did not.  Pull and try again."
        rescue Git::Ref::ProtectedBranchUpdateError => e
          raise Errors::BranchProtectionRuleViolation.new(e.message)
        rescue Git::Ref::RepositoryRuleViolationError => e
          fail Errors::Forbidden, e.detailed_message
        rescue Git::Ref::UpdateError => e
          fail Errors::Forbidden, e.message
        rescue GitRPC::RequestTooLarge
          fail Errors::Unprocessable, "The commit is too large to be processed. " \
            "Consider creating creating the commit in a local clone and pushing it to GitHub."
        end
      end

      private

      def async_repository_name_with_owner(name_with_owner)
        login, name = name_with_owner.split("/", 2)
        Platform::Helpers::RepositoryByNwo.async_repository_with_owner(
          permission: context[:permission],
          viewer: context[:viewer],
          login: login,
          name: name,
          follow_repo_redirect: false,
        ).then do |repo|
          if !repo
            raise Errors::NotFound.new("Could not resolve to a Repository with the name '#{name_with_owner}'.")
          end
          context[:permission].typed_can_access?("Repository", repo).then do |accessible|
            unless accessible
              raise Errors::NotFound.new("Could not resolve to a Repository with the name '#{name_with_owner}'.")
            end
            context[:permission].typed_can_see?("Repository", repo).then do |readable|
              if !readable || repo.hide_from_user?(context[:permission].viewer)
                raise Errors::NotFound.new("Could not resolve to a Repository with the name '#{name_with_owner}'.")
              end
            end

            repo
          end
        end
      end
    end
  end
end
