# typed: strict
# frozen_string_literal: true

module PullRequests
  module BatchRefUpdate
    module Enums
      class Failures < T::Enum
        enums do
          NotRun = new(:not_run)
          Success = new(:success)
          AlreadyUpdated = new(:already_updated)
          HeadCommitNotFound = new(:head_commit_not_found)
          BaseCommitNotFound = new(:base_commit_not_found)
          PendingRefUpdate = new(:pending_ref_update)
          GitFailure = new(:git_failure)
          GitError = new(:git_error)
        end
      end
    end
  end
end
