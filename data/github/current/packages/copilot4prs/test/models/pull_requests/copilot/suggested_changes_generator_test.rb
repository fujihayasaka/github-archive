# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequests::Copilot::SuggestedChangesGeneratorTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @viewer = create(:user)

    @repo = create(:repository, owner: @owner, from_example: :simple)
    example_repo_snapshot

    ref = @repo.heads.create("topic", @repo.heads.find("master").target, @repo.owner)
    commit = ref.append_commit({ message: "Add file1", committer: @repo.owner }, @repo.owner) do |files|
      files.add("file1.txt", "line1\nline2\nline3\n")
    end

    @issue = create(:issue, repository: @repo)
    @pull = PullRequest.create_for(
      @repo,
      base: "master",
      head: ref.name,
      user: @owner,
      issue: @issue,
    )

    @review = @pull.reviews.create!(user: @owner, head_sha: @pull.head_sha)
    @thread = @review.review_threads.create!(
      pull_request: @pull,
      commit_id: @pull.head_sha,
      path: "file1.txt",
      original_position: 1,
    )
    @comment = create(:pull_request_review_comment,
      pull_request_review_thread: @thread,
      body: "just commented",
      user: create(:user),
      pull_request_id: @pull.id,
      pull_request_review_id: @review.id,
    )
    @review.comment!

    make_trusted_oauth_apps_owner
    integration = Apps::Privileged::CopilotPullRequestReviewer.seed_database!
    PrivilegedAppHelper.reconfigure_privileged_app(app_alias: :copilot_pull_request_reviewer, app: integration)
    @bot = ::Apps::Privileged.integration(:copilot_pull_request_reviewer).bot
  end

  test "send request to CAPI", skip_enterprise: true do
    Failbot.expects(:report).never

    classify_response = {
      choices: nil,
      copilot_references: [
        {
          type: "github.classify.result",
          data: { actionable: true },
          id: "",
          metadata: { display_name: "", display_icon: "" }
        }
      ]
    }

    changes_response = {
      choices: nil,
      copilot_references: []
    }

    fake_capi_user = mock("capi user", classify_code_comment: classify_response, suggested_changes: changes_response)
    Copilot::User::CopilotApi.expects(:new).once.returns(fake_capi_user)

    generator = PullRequests::Copilot::SuggestedChangesGenerator.new(
      repo: @repo,
      pull: @pull,
      requestor: @owner,
      comment: @pull.review_comments.first,
    )
    generator.generate
  end
end
