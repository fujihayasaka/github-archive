# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"

class PullRequestWithCommitsMergingMasterTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository, from_example: :rebase_pull_request)

    example_repo_snapshot
  end

  setup do
    reset_cache

    example_repo_restore
    merge_branch(target: "master", branch: "readme-title")

    @pull = create :pull_request,
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      base_ref: "master",
      head_repository: @repo,
      head_user: @repo.owner,
      head_ref: "contrib",
      issue: create(:issue, repository: @repo, user: @repo.owner)
  end

  def merge_branch(branch:, target: "master", repo: @repo, committer: @repo.owner)
    target_ref = repo.refs.find(target)
    branch_ref = repo.refs.find(branch)

    merge_commit, error = repo.commits.create_merge_commit(
      committer,
      target_ref.target_oid,
      branch_ref.target_oid,
    )

    target_ref.update(merge_commit, committer, clear_ref_cache: false,
      post_receive: false, backup: false, no_custom_hooks: true)

    target_ref.target_oid
  end
end
