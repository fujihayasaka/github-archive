# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"

class PullRequestWithPrBodyEnabledMergeCommitMessageTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository, from_example: :pull_request_source)


    example_repo_snapshot
  end

  setup do
    reset_cache

    @issue = create(:issue,
                    repository: @repo,
                    user: @repo.owner,
                    body: "hey @vince look at this real quick<!-- Exclude from commit message --> DONT INCLUDE THIS!",
                  )

    @pull =
    PullRequest.new(
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      base_ref: "master",
      head_user: @repo.owner,
      head_repository: @repo,
      head_ref: "master-forward-2",
      head_sha: "64da3859d3860776d4a4514a1b9704268ff0c740",
      issue: @issue,
      user: @repo.owner,
    )
    @issue.pull_request = @pull
    example_repo_snapshot
  end

  context "when defaults to PR body are enabled" do
    test "default commit messages exclude anything in the PR body after the line '<!-- Exclude from commit message -->'" do
      @repo.set_squash_merge_commit_message_setting(setting: Configurable::SquashMergeCommitMessage::PR_BODY, actor: @repo.owner)
      @repo.set_merge_commit_message_setting(setting: Configurable::MergeCommitMessage::PR_BODY, actor: @repo.owner)

      assert_equal "hey @vince look at this real quick", @pull.default_squash_commit_message
      assert_equal "hey @vince look at this real quick", @pull.default_merge_commit_message
    end
  end
end
