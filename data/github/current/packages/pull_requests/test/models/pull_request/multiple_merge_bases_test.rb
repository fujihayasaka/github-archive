# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestMultipleMergesBaseTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @repo = create(:repository, owner: @owner, from_example: :multiple_merge_bases)


    @pull = create(:pull_request,
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      base_ref: "master",
      head_repository: @repo,
      head_user: @repo.owner,
      head_ref: "m2",
      user: @repo.owner
    )
  end

  setup do
    reset_repo_root
    example_repo :multiple_merge_bases, @repo
  end

  test "doesn't include malicious commit with feature flag enabled" do
    assert @pull.merge
    merge_commit = @pull.repository.commits.find(@pull.merge_commit_sha)
    refute merge_commit.diff["m.txt"]
  end
end
