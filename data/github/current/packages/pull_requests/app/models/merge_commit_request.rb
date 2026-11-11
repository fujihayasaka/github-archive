# typed: true
# frozen_string_literal: true

class MergeCommitRequest < ApplicationRecord::Domain::IssuesPullRequests
  include PullRequests::MergeCommit::Enums

  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain class_name: "Repository"
  belongs_to :pull_request, class_name: "PullRequest"

  serialize :base_branch_sha, coder: GitHub::Hex
  serialize :head_branch_sha, coder: GitHub::Hex
  serialize :merge_sha, coder: GitHub::Hex
  serialize :merge_conflict, coder: JSON
  serialize :rebase_sha, coder: GitHub::Hex
  serialize :rebase_conflict, coder: JSON

  PAUSED_KV_KEY = "pull_requests/merge_commit_request/paused"

  sig { returns(T.nilable(CommitState)) }
  def merge_state_value
    case state = CommitState.safe_deserialize(merge_state)
    when CommitState::Conflict,
         CommitState::Created,
         CommitState::Failed,
         CommitState::Reused,
         CommitState::PendingDeletion
      state
    else
      nil
    end
  end

  sig { returns(T.nilable(CommitState)) }
  def rebase_state_value
    case state = CommitState.safe_deserialize(rebase_state)
    when CommitState::Conflict,
         CommitState::Created,
         CommitState::Failed,
         CommitState::Ineligible,
         CommitState::Reused,
         CommitState::Skipped,
         CommitState::PendingDeletion
      state
    else
      nil
    end
  end

  sig { returns(T::Boolean) }
  def pending_deletion?
    merge_state_value == CommitState::PendingDeletion
  end

  sig { params(repository: Repository).returns(T::Boolean) }
  def self.paused_for?(repository)
    merge_commit_request_paused_kv_for(repository).exists(PAUSED_KV_KEY).value!
  end

  sig { params(repository: Repository).void }
  def self.set_paused_for(repository)
    merge_commit_request_paused_kv_for(repository).set(PAUSED_KV_KEY, "true", expires: 3.months.from_now)
  end

  sig { params(repository: Repository).void }
  def self.clear_paused_for(repository)
    merge_commit_request_paused_kv_for(repository).del(PAUSED_KV_KEY)
  end

  sig { params(repository: Repository).returns(GitHub::KV) }
  private_class_method def self.merge_commit_request_paused_kv_for(repository)
    PullRequests::KV.for_repository(T.must(repository))
  end
end
