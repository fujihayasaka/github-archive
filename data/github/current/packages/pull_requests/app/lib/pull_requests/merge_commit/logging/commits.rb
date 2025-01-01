# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module Logging
      class Commits
        CommitTypes = T.type_alias do
          T.any(
            Entity::Commits,
            PullRequests::GitSystems::Commit::Failed,
            PullRequests::GitSystems::Errors,
            ICommand::Result::Error,
            ICommand::Result::Timeout,
          )
        end

        sig { params(commit: CommitTypes).returns(T::Hash[T.untyped, T.untyped]) }
        def self.to_hash(commit)
          type = commit.class.name.to_s.demodulize.underscore
          case commit
          when Entity::Commits::Created, Entity::Commits::Reused, Entity::Commits::Conflict, Entity::Commits::Found
            commit.serialize.merge(type: commit.state_name)
          when Entity::Commits::Skipped, Entity::Commits::Ineligible, Entity::Commits::Pending, Entity::Commits::Failed, Entity::Commits::PendingDeletion
            { type: }
          when PullRequests::GitSystems::Commit::Failed
            { type:, code: commit.code.to_s }
          when PullRequests::GitSystems::Errors, ICommand::Result::Error, ICommand::Result::Timeout
            { type:, exception: commit.exception&.class&.name, message: commit.exception&.message }
          else
            T.absurd(commit)
          end
        end
      end
    end
  end
end
