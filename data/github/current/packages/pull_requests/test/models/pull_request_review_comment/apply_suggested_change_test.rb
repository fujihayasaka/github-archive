# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestReviewCommentApplySuggestedChangeTestBase < GitHub::TestCase
  include HydroTestHelpers
  include PullRequestSynchronizationTestHelpers

  setup do
    @owner = create(:user)
    @repo  = create(:repository, owner: @owner, from_example: :pull_request_source)
    @repo.enable_dco_signoff(actor: @owner)
    @branch = "topic"
    @filename = "README.txt"
    @filename2 = "LICENSE"

    base_ref = @repo.heads.find("master")
    head_ref = @repo.heads.create(@branch, base_ref.target, @repo.owner)

    head_ref.append_commit({
      message: "a change",
      committer: @repo.owner,
    }, @repo.owner) do |files|
      files.add(@filename, "one\ntwo\nthree\n")
      files.add(@filename2, "MIT\nfor\nme\n")
    end

    @pull = create(:pull_request,
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      head_repository: @repo,
      head_user: @repo.owner,
      head_ref: @branch,
      user: @repo.owner,
    )

    review = @pull.reviews.create!(
      user: @pull.user,
      head_sha: @pull.head_sha,
    )

    @comment = create(:pull_request_review_comment,
      pull_request: @pull,
      pull_request_review: review,
      user: @owner,
      commit_id: @pull.head_sha,
      path: @filename,
      original_position: 2,
      blob_position: 1,
      body: "ship it",
    )
    @comment.submit!

    @multi_line_comment = create(:pull_request_review_comment,
      pull_request: @pull,
      pull_request_review: review,
      user: @owner,
      commit_id: @pull.head_sha,
      path: @filename,
      original_position: 3,
      blob_position: 2,
      start_position_offset: 1,
      body: "ship it again",
    )
    @multi_line_comment.submit!
    review.comment!

    @inputs = {
      pull_request: @pull,
      current_oid: @pull.head_sha,
      message: nil,
      changes: [{
        comment: @comment,
        path: @filename,
        suggestion: ["four"],
      }],
      remote_ip: "127.0.0.1",
      user_agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
      viewer: @owner,
    }

    @suggester = create :user, login: "suggester"

    @suggestion = create(:pull_request_review_comment,
      pull_request: @pull,
      user: @suggester,
      body: "Apply this suggestion!",
      path: @filename,
      position: 2,
      blob_position: 1,
      diff_hunk: nil,
    )

    @suggestion.submit!

    WebFlowHelper.setup_webflow
    Spokesd.enable_spokesd
  end

  def assert_repository_push_enqueued(new_oid)
    # 1st job is triggered upon branch creation, e.g. @repo.heads.create
    # 2nd job is triggered upon appending a commit, e.g. head_ref.append_commit
    # The last job is triggered from applying the suggestion

    with_hydro_publisher(GitHub.sync_hydro_publisher) { assert_hydro_messages(count: 3, schema: "github.repositories.v1.Pushed") }


    push_event = decode_hydro_message(GitHub.sync_hydro_publisher.sink.messages.last.data).message
    assert_equal 1, push_event[:ref_updates].size
    assert_equal new_oid, push_event[:ref_updates].last[:after]
    assert_equal [@pull.id], push_event[:excluded_pull_ids]

  end

  def assert_correct_push_event_count(expected = 2)
    # 1st job is triggered upon branch creation, e.g. @repo.heads.create
    # 2nd job is triggered upon appending a commit, e.g. head_ref.append_commit
    with_hydro_publisher(GitHub.sync_hydro_publisher) { assert_hydro_messages(count: expected, schema: "github.repositories.v1.Pushed") }

  end

  def described_class
    PullRequestReviewComment::ApplySuggestedChange
  end

  def assert_blob_contents(repo, branch, filename, contents)
    ref  = repo.refs.read(branch)
    blob = repo.blob(ref.target_oid, filename)

    if contents.nil?
      assert_nil blob
    else
      assert_equal contents, blob.data
    end
  end
end

class PullRequestReviewCommentApplySuggestedChangeTest < PullRequestReviewCommentApplySuggestedChangeTestBase
  test "returns errors when the comment is pending" do
    pendingComment = create(:pull_request_review_comment,
      pull_request: @pull,
      user: @owner,
      body: "Apply this suggestion!",
      path: @filename,
      position: 3,
      blob_position: 2,
      diff_hunk: nil,
    )

    @inputs[:changes] = [{
      comment: @suggestion,
      path: @filename,
      suggestion: [@suggestion.body],
    }, {
      comment: pendingComment,
      path: @filename,
      suggestion: [@suggestion.body],
    }]

    error = assert_raises PullRequestReviewComment::ApplySuggestedChange::UnprocessableError do
      described_class.call(**@inputs)
    end
    assert_equal "Suggestions cannot be applied on pending reviews.", error.message

    assert_hydro_messages(count: 1, schema: "github.v1.SuggestedChangeApplied") unless GitHub.enterprise?
  end

  test "doesn't modify the file given an invalid line number" do
    PullRequestReviewThread.any_instance.stubs(:async_adjusted_blob_position).returns(Promise.resolve(10))

    error = assert_raises PullRequestReviewComment::ApplySuggestedChange::UnprocessableError do
      described_class.call(**@inputs)
    end
    assert_equal "Suggested changes can only be applied to valid lines.", error.message

    assert_blob_contents @repo, @branch, @filename, "one\ntwo\nthree\n"
    assert_correct_push_event_count
  end

  test "returns errors if the comment is outdated" do
    @comment.update!(outdated: true)

    error = assert_raises PullRequestReviewComment::ApplySuggestedChange::NotFoundError do
      described_class.call(**@inputs)
    end
    assert_equal "Comment is outdated.", error.message

    assert_blob_contents @repo, @branch, @filename, "one\ntwo\nthree\n"
    assert_correct_push_event_count

    assert_hydro_messages(count: 1, schema: "github.v1.SuggestedChangeApplied") unless GitHub.enterprise?
  end

  test "returns an error if the diff is outdated" do
    @inputs[:current_oid] = SecureRandom.hex(20)

    error = assert_raises PullRequestReviewComment::ApplySuggestedChange::UnprocessableError do
      described_class.call(**@inputs)
    end
    assert_equal "Sorry, the diff is outdated.", error.message

    assert_blob_contents @repo, @branch, @filename, "one\ntwo\nthree\n"
    assert_correct_push_event_count

    assert_hydro_messages(count: 1, schema: "github.v1.SuggestedChangeApplied") unless GitHub.enterprise?
  end

  test "returns an error if there are no changes" do
    @inputs[:changes] = []

    error = assert_raises PullRequestReviewComment::ApplySuggestedChange::UnprocessableError do
      described_class.call(**@inputs)
    end
    assert_equal "Sorry, you must apply one or more suggested changes.", error.message

    assert_blob_contents @repo, @branch, @filename, "one\ntwo\nthree\n"
    assert_correct_push_event_count
  end

  test "returns an error if default author email is invalid" do
    @owner.stubs(:default_author_email).returns("invalid@email.com")
    refute @owner.author_emails.include?("invalid@email.com")

    error = assert_raises PullRequestReviewComment::ApplySuggestedChange::UnprocessableError do
      described_class.call(**@inputs)
    end
    assert_equal "Invalid email for web commit.", error.message

    assert_blob_contents @repo, @branch, @filename, "one\ntwo\nthree\n"
    assert_correct_push_event_count
  end

  test "returns errors if the pull request is closed" do
    @pull.issue.update_attribute(:state, "closed")
    @comment.reload

    error = assert_raises PullRequestReviewComment::ApplySuggestedChange::UnprocessableError do
      described_class.call(**@inputs)
    end
    assert_equal "Suggested changes can only be applied to open pull requests.", error.message

    assert_blob_contents @repo, @branch, @filename, "one\ntwo\nthree\n"
    assert_correct_push_event_count

    assert_hydro_messages(count: 1, schema: "github.v1.SuggestedChangeApplied") unless GitHub.enterprise?
  end

  test "returns errors if two suggestions apply to the same line" do
    review = @pull.reviews.create!(
      user: @pull.user,
      head_sha: @pull.head_sha,
    )

    comment1 = create(:pull_request_review_comment,
      pull_request: @pull,
      pull_request_review: review,
      user: @owner,
      commit_id: @pull.head_sha,
      path: @filename,
      original_position: 2,
      blob_position: 1,
      body: "ship it",
    )
    comment1.submit!
    review.comment!

    comment2 = create(:pull_request_review_comment,
      pull_request: @pull,
      user: @suggester,
      body: "Apply this suggestion!",
      path: @filename2,
      original_position: 2,
      blob_position: 1,
      diff_hunk: nil,
    )
    comment2.submit!

    @inputs[:changes] = [{
      comment: comment2,
      path: @filename,
      suggestion: ["six"],
    }, {
      comment: comment1,
      path: @filename,
      suggestion: ["five", ""],
    }]

    error = assert_raises PullRequestReviewComment::ApplySuggestedChange::UnprocessableError do
      described_class.call(**@inputs)
    end
    assert_equal "Applying multiple suggestions to the same line is not supported.", error.message

    assert_blob_contents @repo, @branch, @filename, "one\ntwo\nthree\n"
    assert_correct_push_event_count

    assert_hydro_messages(count: 1, schema: "github.v1.SuggestedChangeApplied") unless GitHub.enterprise?
  end

  test "returns errors when multi-line suggestions overlap" do
    review1 = @pull.reviews.create!(
      user: @pull.user,
      head_sha: @pull.head_sha,
    )

    comment1 = create(:pull_request_review_comment,
      pull_request: @pull,
      pull_request_review: review1,
      user: @owner,
      commit_id: @pull.head_sha,
      path: @filename,
      original_position: 2,
      blob_position: 1,
      start_position_offset: 1,
      body: "ship this",
    )
    comment1.submit!
    review1.comment!

    review2 = @pull.reviews.create!(
      user: @pull.user,
      head_sha: @pull.head_sha,
    )

    comment2 = create(:pull_request_review_comment,
      pull_request: @pull,
      pull_request_review: review2,
      user: @owner,
      commit_id: @pull.head_sha,
      path: @filename,
      original_position: 3,
      blob_position: 2,
      start_position_offset: 1,
      body: "no, ship this",
    )
    comment2.submit!
    review2.comment!

    @inputs[:changes] = [{
      comment: comment1,
      path: @filename,
      suggestion: %w[four five],
    }, {
      comment: comment2,
      path: @filename,
      suggestion: %w[six seven],
    }]

    error = assert_raises PullRequestReviewComment::ApplySuggestedChange::UnprocessableError do
      described_class.call(**@inputs)
    end
    assert_equal "Applying multiple suggestions to the same line is not supported.", error.message

    assert_blob_contents @repo, @branch, @filename, "one\ntwo\nthree\n"
    assert_correct_push_event_count

    assert_hydro_messages(count: 1, schema: "github.v1.SuggestedChangeApplied") unless GitHub.enterprise?
  end

  test "returns errors if the comment is on a file" do
    @comment.update!(subject_type: :file)

    error = assert_raises PullRequestReviewComment::ApplySuggestedChange::UnprocessableError do
      described_class.call(**@inputs)
    end
    assert_equal "Applying suggestions on file-level comments is not supported.", error.message

    assert_blob_contents @repo, @branch, @filename, "one\ntwo\nthree\n"
    assert_correct_push_event_count

    assert_hydro_messages(count: 1, schema: "github.v1.SuggestedChangeApplied") unless GitHub.enterprise?
  end

  test "returns errors if the comment is on the left_blob (deleted line)" do
    @comment.update!(left_blob: true)

    error = assert_raises PullRequestReviewComment::ApplySuggestedChange::UnprocessableError do
      described_class.call(**@inputs)
    end
    assert_equal "Applying suggestions on deleted lines is currently not supported.", error.message

    assert_blob_contents @repo, @branch, @filename, "one\ntwo\nthree\n"
    assert_correct_push_event_count

    assert_hydro_messages(count: 1, schema: "github.v1.SuggestedChangeApplied") unless GitHub.enterprise?
  end

  test "prevents non-writers from applying a suggestion" do
    reader = create(:user)
    @repo.add_member(reader, action: :read)

    @inputs[:viewer] = reader
    error = assert_raises PullRequestReviewComment::ApplySuggestedChange::ForbiddenError do
      described_class.call(**@inputs)
    end
    assert_equal "You don't have permission to apply suggestions on this pull request.", error.message

    assert_blob_contents @repo, @branch, @filename, "one\ntwo\nthree\n"
    assert_correct_push_event_count

    assert_hydro_messages(count: 1, schema: "github.v1.SuggestedChangeApplied") unless GitHub.enterprise?
  end

  test "returns errors if the suggestion is identical to the original selection" do
    @inputs[:changes] = [{
      comment: @multi_line_comment,
      path: @filename,
      suggestion: %w[two three]
    }]

    error = assert_raises PullRequestReviewComment::ApplySuggestedChange::UnprocessableError do
      described_class.call(**@inputs)
    end
    assert_equal "Suggestion cannot be identical to original text.", error.message

    assert_correct_push_event_count
  end
end

# These tests call share_spokesdb, which disables transactional tests. Calling this slows tests down drastically,
# so isolate the tests which need it to their own class.
class PullRequestReviewCommentApplySuggestedChangeTestSharedSpokes < PullRequestReviewCommentApplySuggestedChangeTestBase
  Spokesd.share_spokesdb(self)

  test "applies a single line patch" do
    described_class.call(**@inputs)
    new_oid = @repo.refs.read(@branch).target_oid

    assert_blob_contents @repo, @branch, @filename, "one\nfour\nthree\n"
    assert_repository_push_enqueued(new_oid)
  end

  # Regression test for: https://github.com/github/coding/issues/2033
  test "preserves trailing newlines at the end of the file" do
    @repo.heads.find(@branch).append_commit({
      message: "Add files with various numbers of trailing newlines",
      committer: @repo.owner,
    }, @repo.owner) do |files|
      files.add("sample-0.txt", "foo\nbar\nbaz\nqux")
      files.add("sample-1.txt", "foo\nbar\nbaz\nqux\n")
      files.add("sample-2.txt", "foo\nbar\nbaz\nqux\n\n")
      files.add("sample-3.txt", "foo\nbar\nbaz\nqux\n\n\n")
      files.add("sample-4.txt", "foo\nbar\nbaz\nqux\n\n\n\n")
    end

    # 0 trailing newlines.
    @inputs[:current_oid] = @repo.heads.find(@branch).target_oid
    @inputs[:changes] = [{
      comment: @comment,
      path: "sample-0.txt",
      suggestion: ["***"]
    }]
    described_class.call(**@inputs)
    assert_blob_contents @repo, @branch, "sample-0.txt",
      "foo\n***\nbaz\nqux"

    # 1 trailing newline.
    @inputs[:current_oid] = @repo.heads.find(@branch).target_oid
    @inputs[:changes] = [{
      comment: @comment,
      path: "sample-1.txt",
      suggestion: ["***"]
    }]
    described_class.call(**@inputs)
    assert_blob_contents @repo, @branch, "sample-1.txt",
      "foo\n***\nbaz\nqux\n"

    # 2 trailing newlines.
    @inputs[:current_oid] = @repo.heads.find(@branch).target_oid
    @inputs[:changes] = [{
      comment: @comment,
      path: "sample-2.txt",
      suggestion: ["***"]
    }]
    described_class.call(**@inputs)
    assert_blob_contents @repo, @branch, "sample-2.txt",
      "foo\n***\nbaz\nqux\n\n"

    # 3 trailing newlines.
    @inputs[:current_oid] = @repo.heads.find(@branch).target_oid
    @inputs[:changes] = [{
      comment: @comment,
      path: "sample-3.txt",
      suggestion: ["***"]
    }]
    described_class.call(**@inputs)
    assert_blob_contents @repo, @branch, "sample-3.txt",
      "foo\n***\nbaz\nqux\n\n\n"

    # 4 trailing newlines.
    @inputs[:current_oid] = @repo.heads.find(@branch).target_oid
    @inputs[:changes] = [{
      comment: @comment,
      path: "sample-4.txt",
      suggestion: ["***"]
    }]
    described_class.call(**@inputs)
    assert_blob_contents @repo, @branch, "sample-4.txt",
      "foo\n***\nbaz\nqux\n\n\n\n"
  end

  # Regression test for: https://github.com/github/coding/issues/2033
  test "preserves trailing CRLFs at the end of the file" do
    @repo.heads.find(@branch).append_commit({
      message: "Add files with various numbers of trailing newlines",
      committer: @repo.owner,
    }, @repo.owner) do |files|
      files.add("sample-0.txt", "foo\r\nbar\r\nbaz\r\nqux")
      files.add("sample-1.txt", "foo\r\nbar\r\nbaz\r\nqux\r\n")
      files.add("sample-2.txt", "foo\r\nbar\r\nbaz\r\nqux\r\n\r\n")
      files.add("sample-3.txt", "foo\r\nbar\r\nbaz\r\nqux\r\n\r\n\r\n")
      files.add("sample-4.txt", "foo\r\nbar\r\nbaz\r\nqux\r\n\r\n\r\n\r\n")
    end

    # 0 trailing CRLFs.
    @inputs[:current_oid] = @repo.heads.find(@branch).target_oid
    @inputs[:changes] = [{
      comment: @comment,
      path: "sample-0.txt",
      suggestion: ["***"]
    }]
    described_class.call(**@inputs)
    assert_blob_contents @repo, @branch, "sample-0.txt",
      "foo\r\n***\r\nbaz\r\nqux"

    # 1 trailing CRLF.
    @inputs[:current_oid] = @repo.heads.find(@branch).target_oid
    @inputs[:changes] = [{
      comment: @comment,
      path: "sample-1.txt",
      suggestion: ["***"]
    }]
    described_class.call(**@inputs)
    assert_blob_contents @repo, @branch, "sample-1.txt",
      "foo\r\n***\r\nbaz\r\nqux\r\n"

    # 2 trailing CRLFs.
    @inputs[:current_oid] = @repo.heads.find(@branch).target_oid
    @inputs[:changes] = [{
      comment: @comment,
      path: "sample-2.txt",
      suggestion: ["***"]
    }]
    described_class.call(**@inputs)
    assert_blob_contents @repo, @branch, "sample-2.txt",
      "foo\r\n***\r\nbaz\r\nqux\r\n\r\n"

    # 3 trailing CRLFs.
    @inputs[:current_oid] = @repo.heads.find(@branch).target_oid
    @inputs[:changes] = [{
      comment: @comment,
      path: "sample-3.txt",
      suggestion: ["***"]
    }]
    described_class.call(**@inputs)
    assert_blob_contents @repo, @branch, "sample-3.txt",
      "foo\r\n***\r\nbaz\r\nqux\r\n\r\n\r\n"

    # 4 trailing CRLFs.
    @inputs[:current_oid] = @repo.heads.find(@branch).target_oid
    @inputs[:changes] = [{
      comment: @comment,
      path: "sample-4.txt",
      suggestion: ["***"]
    }]
    described_class.call(**@inputs)
    assert_blob_contents @repo, @branch, "sample-4.txt",
      "foo\r\n***\r\nbaz\r\nqux\r\n\r\n\r\n\r\n"
  end

  test "works when changing the last non-blank line in a file (newlines)" do
    @repo.heads.find(@branch).append_commit({
      message: "Add files with various numbers of trailing newlines",
      committer: @repo.owner,
    }, @repo.owner) do |files|
      files.add("sample-0.txt", "foo\nbar")
      files.add("sample-1.txt", "foo\nbar\n")
      files.add("sample-2.txt", "foo\nbar\n\n")
      files.add("sample-3.txt", "foo\nbar\n\n\n")
      files.add("sample-4.txt", "foo\nbar\n\n\n\n")
    end

    # 0 trailing newlines.
    @inputs[:current_oid] = @repo.heads.find(@branch).target_oid
    @inputs[:changes] = [{
      comment: @comment,
      path: "sample-0.txt",
      suggestion: ["***"]
    }]
    described_class.call(**@inputs)
    assert_blob_contents @repo, @branch, "sample-0.txt",
      "foo\n***"

    # 1 trailing newline.
    @inputs[:current_oid] = @repo.heads.find(@branch).target_oid
    @inputs[:changes] = [{
      comment: @comment,
      path: "sample-1.txt",
      suggestion: ["***"]
    }]
    described_class.call(**@inputs)
    assert_blob_contents @repo, @branch, "sample-1.txt",
      "foo\n***\n"

    # 2 trailing newlines.
    @inputs[:current_oid] = @repo.heads.find(@branch).target_oid
    @inputs[:changes] = [{
      comment: @comment,
      path: "sample-2.txt",
      suggestion: ["***"]
    }]
    described_class.call(**@inputs)
    assert_blob_contents @repo, @branch, "sample-2.txt",
      "foo\n***\n\n"

    # 3 trailing newlines.
    @inputs[:current_oid] = @repo.heads.find(@branch).target_oid
    @inputs[:changes] = [{
      comment: @comment,
      path: "sample-3.txt",
      suggestion: ["***"]
    }]
    described_class.call(**@inputs)
    assert_blob_contents @repo, @branch, "sample-3.txt",
      "foo\n***\n\n\n"

    # 4 trailing newlines.
    @inputs[:current_oid] = @repo.heads.find(@branch).target_oid
    @inputs[:changes] = [{
      comment: @comment,
      path: "sample-4.txt",
      suggestion: ["***"]
    }]
    described_class.call(**@inputs)
    assert_blob_contents @repo, @branch, "sample-4.txt",
      "foo\n***\n\n\n\n"
  end

  test "works when changing the last non-blank line in a file (CRLFs)" do
    @repo.heads.find(@branch).append_commit({
      message: "Add files with various numbers of trailing CRLFs",
      committer: @repo.owner,
    }, @repo.owner) do |files|
      files.add("sample-0.txt", "foo\r\nbar")
      files.add("sample-1.txt", "foo\r\nbar\r\n")
      files.add("sample-2.txt", "foo\r\nbar\r\n\r\n")
      files.add("sample-3.txt", "foo\r\nbar\r\n\r\n\r\n")
      files.add("sample-4.txt", "foo\r\nbar\r\n\r\n\r\n\r\n")
    end

    # 0 trailing CRLFs.
    @inputs[:current_oid] = @repo.heads.find(@branch).target_oid
    @inputs[:changes] = [{
      comment: @comment,
      path: "sample-0.txt",
      suggestion: ["***"]
    }]
    described_class.call(**@inputs)
    assert_blob_contents @repo, @branch, "sample-0.txt",
      "foo\r\n***"

    # 1 trailing CRLF.
    @inputs[:current_oid] = @repo.heads.find(@branch).target_oid
    @inputs[:changes] = [{
      comment: @comment,
      path: "sample-1.txt",
      suggestion: ["***"]
    }]
    described_class.call(**@inputs)
    assert_blob_contents @repo, @branch, "sample-1.txt",
      "foo\r\n***\r\n"

    # 2 trailing CRLFs.
    @inputs[:current_oid] = @repo.heads.find(@branch).target_oid
    @inputs[:changes] = [{
      comment: @comment,
      path: "sample-2.txt",
      suggestion: ["***"]
    }]
    described_class.call(**@inputs)
    assert_blob_contents @repo, @branch, "sample-2.txt",
      "foo\r\n***\r\n\r\n"

    # 3 trailing CRLFs.
    @inputs[:current_oid] = @repo.heads.find(@branch).target_oid
    @inputs[:changes] = [{
      comment: @comment,
      path: "sample-3.txt",
      suggestion: ["***"]
    }]
    described_class.call(**@inputs)
    assert_blob_contents @repo, @branch, "sample-3.txt",
      "foo\r\n***\r\n\r\n\r\n"

    # 4 trailing CRLFs.
    @inputs[:current_oid] = @repo.heads.find(@branch).target_oid
    @inputs[:changes] = [{
      comment: @comment,
      path: "sample-4.txt",
      suggestion: ["***"]
    }]
    described_class.call(**@inputs)
    assert_blob_contents @repo, @branch, "sample-4.txt",
      "foo\r\n***\r\n\r\n\r\n\r\n"
  end

  test "applies a multi-line patch" do
    @inputs[:changes] = [{
      comment: @multi_line_comment,
      path: @filename,
      suggestion: %w[five eight],
    }]
    described_class.call(**@inputs)
    new_oid = @repo.refs.read(@branch).target_oid

    assert_blob_contents @repo, @branch, @filename, "one\nfive\neight\n"
    assert_repository_push_enqueued(new_oid)
  end

  test "applies a single suggestion without DCO sign-off" do
    @repo.reset_dco_signoff(actor: @owner)
    @inputs[:changes] = [{
      comment: @suggestion,
      path: @filename,
      suggestion: [@suggestion.body],
    }]
    @inputs[:message] = "\nThis is a title\n\nThis is a body\n\n"
    described_class.call(**@inputs)

    last_commit_id = @repo.refs.read(@branch).target_oid
    last_commit = @repo.commits.find(last_commit_id)

    assert_equal @pull.user.name, last_commit.author_name
    assert_equal @pull.user.git_author_email, last_commit.author_email

    message = "This is a title\n\nThis is a body"
    message += "\n\nCo-authored-by: #{@suggester.name} <#{@suggester.git_author_email}>"
    assert_equal message, last_commit.message

    assert_equal GitHub.web_committer_name, last_commit.committer_name

    assert_repository_push_enqueued(last_commit_id)
  end

  # Regression test for https://github.com/github/repos/issues/2206
  test "applies a single suggestion with DCO sign-off for fork to source PR" do
    forker = create(:user)
    forked_repo = create(:fork_repository, forker: forker, fork_repo: @repo, from_example: :pull_request_source)

    forked_repo.reset_dco_signoff(actor: forker)

    base_ref = forked_repo.heads.find("master")
    head_ref = forked_repo.heads.create(@branch, base_ref.target, forked_repo.owner)

    head_ref.append_commit({
      message: "a change",
      committer: forked_repo.owner,
    }, forked_repo.owner) do |files|
      files.add(@filename, "one\ntwo\nthree\n")
    end

    forked_pull = create(:pull_request,
      repository:      @repo,
      base_repository: @repo,
      base_user:       @repo.owner,
      head_repository: forked_repo,
      head_user:       forked_repo.owner,
      head_ref:        @branch,
      user:            forked_repo.owner,
    )

    review = forked_pull.reviews.create!(
      user:     forked_pull.user,
      head_sha: forked_pull.head_sha,
    )

    comment = create(:pull_request_review_comment,
      pull_request:        forked_pull,
      pull_request_review: review,
      user:                forker,
      commit_id:           forked_pull.head_sha,
      path:                @filename,
      original_position:   2,
      blob_position:       1,
      body:                "ship it",
    )
    review.comment!
    comment.submit!

    @inputs[:pull_request] = forked_pull
    @inputs[:current_oid] = forked_pull.head_sha
    @inputs[:changes] = [{
      comment: comment,
      path: @filename,
      suggestion: ["four"],
    }]
    @inputs[:viewer]  = forker
    @inputs[:message] = "\nThis is a title\n\nThis is a body\n\n"
    described_class.call(**@inputs)

    assert_blob_contents forked_repo, @branch, @filename, "one\nfour\nthree\n"

    last_commit_id = forked_repo.refs.read(@branch).target_oid
    last_commit = forked_repo.commits.find(last_commit_id)

    assert_equal forked_pull.user.name, last_commit.author_name
    assert_equal forked_pull.user.git_author_email, last_commit.author_email

    message = "This is a title\n\nThis is a body"
    message += "\n\nSigned-off-by: #{forker.name} <#{forker.git_author_email}>"
    assert_equal message, last_commit.message

    assert_equal GitHub.web_committer_name, last_commit.committer_name
  end

  test "applies a single suggestion with the viewer as the author of the commit and suggester as co-author" do
    @inputs[:changes] = [{
      comment: @suggestion,
      path: @filename,
      suggestion: [@suggestion.body],
    }]
    @inputs[:message] = "\nThis is a title\n\nThis is a body\n\n"
    described_class.call(**@inputs)

    last_commit_id = @repo.refs.read(@branch).target_oid
    last_commit = @repo.commits.find(last_commit_id)

    assert_equal @pull.user.name, last_commit.author_name
    assert_equal @pull.user.git_author_email, last_commit.author_email

    message = "This is a title\n\nThis is a body"
    message += "\n\nCo-authored-by: #{@suggester.name} <#{@suggester.git_author_email}>"
    message += "\nSigned-off-by: #{@owner.git_author_name} <#{@owner.git_author_email}>"
    assert_equal message, last_commit.message

    assert_equal GitHub.web_committer_name, last_commit.committer_name

    assert_repository_push_enqueued(last_commit_id)
  end

  if GitHub.choose_commit_email_enabled?
    test "uses non-primary emails for viewer and suggester if they committed with them last" do
      viewer = @pull.user

      # set up email for suggester by committing to the master branch
      suggester_email = create(:user_email, user: @suggester).email
      @suggester.emails.map(&:verify!)
      metadata = {
        message: "making a change",
        committer: @suggester,
        author: { name: "suggester", email: suggester_email },
      }
      ref = @repo.heads.find("master")
      commit = ref.append_commit(metadata, @suggester) do |files|
        files.add("README.txt", "something else")
      end
      CommitContribution.create!(repository: @repo, user: @suggester, committed_date: Time.now.to_date)
      assert_equal @suggester.default_author_email(@repo, ref.sha), suggester_email

      # set up default email for viewer by committing to the master branch
      viewer_email = create(:user_email, user: viewer).email
      viewer.emails.map(&:verify!)
      metadata = {
        message: "making a change",
        committer: viewer,
        author: { name: "viewer", email: viewer_email },
      }
      ref = @repo.heads.find("master")
      commit = ref.append_commit(metadata, viewer) do |files|
        files.add("README.txt", "something else")
      end
      CommitContribution.create!(repository: @repo, user: viewer, committed_date: Time.now.to_date)
      assert_equal viewer.default_author_email(@repo, ref.sha), viewer_email

      # have viewer apply suggestion
      @inputs[:changes] = [{
        comment: @suggestion,
        path: @filename,
        suggestion: [@suggestion.body],
      }]
      @inputs[:message] = "\nThis is a title\n\nThis is a body\n\n"
      described_class.call(**@inputs)

      # check that we used the emails each user last used to commit
      last_commit_id = @repo.refs.read(@branch).target_oid
      last_commit = @repo.commits.find(last_commit_id)

      assert_equal @pull.user.name, last_commit.author_name
      assert_equal viewer_email, last_commit.author_email

      message = "This is a title\n\nThis is a body"
      message += "\n\nCo-authored-by: #{@suggester.name} <#{suggester_email}>"
      message += "\nSigned-off-by: #{@owner.git_author_name} <#{@owner.git_author_email}>"
      assert_equal message, last_commit.message

      assert_equal GitHub.web_committer_name, last_commit.committer_name
    end
  end

  test "does not include the viewer as co-author if they are the suggester" do
    comment = create(:pull_request_review_comment,
      pull_request: @pull,
      user: @pull.user,
      body: "Apply this suggestion!",
      path: @filename,
      position: 2,
      blob_position: 1,
      diff_hunk: nil,
    )

    comment.submit!

    @inputs[:changes] = [{
      comment: comment,
      path: @filename,
      suggestion: [comment.body],
    }]
    @inputs[:message] = "\nThis is a title\n\nThis is a body\n\n"
    described_class.call(**@inputs)

    last_commit_id = @repo.refs.read(@branch).target_oid
    last_commit = @repo.commits.find(last_commit_id)

    assert_equal @pull.user.name, last_commit.author_name
    assert_equal @pull.user.git_author_email, last_commit.author_email

    message = "This is a title\n\nThis is a body"
    message += "\n\nSigned-off-by: #{@owner.git_author_name} <#{@owner.git_author_email}>"
    assert_equal message, last_commit.message

    assert_equal GitHub.web_committer_name, last_commit.committer_name

    assert_repository_push_enqueued(last_commit_id)
  end

  test "uses anonymous email for authorship and co-authorship if suggester and viewer's emails are private" do
    @pull.user.primary_user_email.toggle_visibility

    @suggester.primary_user_email.toggle_visibility

    @inputs[:changes] = [{
      comment: @suggestion,
      path: @filename,
      suggestion: ["four"],
    }]
    described_class.call(**@inputs)

    last_commit_id = @repo.refs.read(@branch).target_oid
    last_commit = @repo.commits.find(last_commit_id)

    assert_equal @pull.user.name, last_commit.author_name
    assert_equal StealthEmail.new(@pull.user).email, last_commit.author_email

    message = "Update README.txt"
    message += "\n\nCo-authored-by: #{@suggester.name} <#{StealthEmail.new(@suggester).email}>"
    message += "\nSigned-off-by: #{@owner.git_author_name} <#{@owner.git_author_email}>"
    assert_equal message, last_commit.message

    assert_equal GitHub.web_committer_name, last_commit.committer_name

    assert_repository_push_enqueued(last_commit_id)
  end

  test "applies multiple single line patches" do
    review = @pull.reviews.create!(
      user: @pull.user,
      head_sha: @pull.head_sha,
    )

    comment1 = create(:pull_request_review_comment,
      pull_request: @pull,
      pull_request_review: review,
      user: @owner,
      commit_id: @pull.head_sha,
      path: @filename,
      original_position: 2,
      blob_position: 1,
      body: "ship it",
    )
    comment1.submit!
    comment2 = create(:pull_request_review_comment,
      pull_request: @pull,
      pull_request_review: review,
      user: @owner,
      commit_id: @pull.head_sha,
      path: @filename,
      original_position: 3,
      blob_position: 2,
      body: "ship it good",
    )
    comment2.submit!
    review.comment!

    comment3 = create(:pull_request_review_comment,
      pull_request: @pull,
      user: @suggester,
      body: "Apply this suggestion!",
      path: @filename2,
      original_position: 3,
      blob_position: 2,
      diff_hunk: nil,
    )
    comment3.submit!

    @inputs[:changes] = [{
      comment: comment2,
      path: @filename,
      suggestion: ["six"],
    }, {
      comment: comment1,
      path: @filename,
      suggestion: ["five", ""],
    }, {
      comment: comment3,
      path: @filename2,
      suggestion: ["me!"],
    }]

    described_class.call(**@inputs)
    new_oid = @repo.refs.read(@branch).target_oid

    assert_blob_contents @repo, @branch, @filename, "one\nfive\n\nsix\n"
    assert_blob_contents @repo, @branch, @filename2, "MIT\nfor\nme!\n"
    assert_repository_push_enqueued(new_oid)
  end

  test "includes multiple suggesters as co-authors and uses the viewer as the author" do
    reviewer = create :user, login: "reviewer"
    review = @pull.reviews.create!(
      user: reviewer,
      head_sha: @pull.head_sha,
    )

    comment1 = create(:pull_request_review_comment,
      pull_request: @pull,
      pull_request_review: review,
      user: reviewer,
      commit_id: @pull.head_sha,
      path: @filename,
      original_position: 2,
      blob_position: 1,
      body: "ship it",
    )
    comment1.submit!
    comment2 = create(:pull_request_review_comment,
      pull_request: @pull,
      pull_request_review: review,
      user: reviewer,
      commit_id: @pull.head_sha,
      path: @filename,
      original_position: 3,
      blob_position: 2,
      body: "ship it good",
    )
    comment2.submit!
    review.comment!

    comment3 = create(:pull_request_review_comment,
      pull_request: @pull,
      user: @suggester,
      body: "Apply this suggestion!",
      path: @filename2,
      position: 3,
      blob_position: 2,
      diff_hunk: nil,
    )
    comment3.submit!

    @inputs[:changes] = [{
      comment: comment2,
      path: @filename,
      suggestion: ["six"],
    }, {
      comment: comment1,
      path: @filename,
      suggestion: ["five", ""],
    }, {
      comment: comment3,
      path: @filename2,
      suggestion: ["me!"],
    }]
    @inputs[:message] = "\nThis is a title\n\nThis is a body\n\n\n\n\n"

    described_class.call(**@inputs)

    last_commit_id = @repo.refs.read(@branch).target_oid
    last_commit = @repo.commits.find(last_commit_id)

    message = "This is a title\n\nThis is a body"
    message += "\n\nCo-authored-by: #{reviewer.name} <#{reviewer.git_author_email}>"
    message += "\nCo-authored-by: #{@suggester.name} <#{@suggester.git_author_email}>"
    message += "\nSigned-off-by: #{@owner.git_author_name} <#{@owner.git_author_email}>"
    assert_equal message, last_commit.message
  end

  test "does not include the viewer as a co-author when they're also a suggester" do
    review = @pull.reviews.create!(
      user: @pull.user,
      head_sha: @pull.head_sha,
    )

    comment1 = create(:pull_request_review_comment,
      pull_request: @pull,
      pull_request_review: review,
      user: @owner,
      commit_id: @pull.head_sha,
      path: @filename,
      original_position: 2,
      blob_position: 1,
      body: "ship it",
    )
    comment1.submit!
    comment2 = create(:pull_request_review_comment,
      pull_request: @pull,
      pull_request_review: review,
      user: @owner,
      commit_id: @pull.head_sha,
      path: @filename,
      original_position: 3,
      blob_position: 2,
      body: "ship it good",
    )
    comment2.submit!
    review.comment!

    suggester1 = create :user, login: "suggester1"
    suggester1.primary_user_email.toggle_visibility
    comment3 = create(:pull_request_review_comment,
      pull_request: @pull,
      user: suggester1,
      body: "Apply this suggestion!",
      path: @filename2,
      original_position: 3,
      blob_position: 2,
      diff_hunk: nil,
    )
    comment3.submit!

    suggester2 = create :user, login: "suggester2"
    comment4 = create(:pull_request_review_comment,
      pull_request: @pull,
      user: suggester2,
      body: "Apply this suggestion!",
      path: @filename2,
      original_position: 2,
      blob_position: 1,
      diff_hunk: nil,
    )
    comment4.submit!

    @inputs[:changes] = [{
      comment: comment2,
      path: @filename,
      suggestion: ["six"],
    }, {
      comment: comment1,
      path: @filename,
      suggestion: ["five", ""],
    }, {
      comment: comment3,
      path: @filename2,
      suggestion: ["me!"],
    }, {
      comment: comment4,
      path: @filename2,
      suggestion: ["you!"],
    }]
    @inputs[:message] = "\nThis is a title\n\nThis is a body\n\n\n\n\n"

    described_class.call(**@inputs)

    last_commit_id = @repo.refs.read(@branch).target_oid
    last_commit = @repo.commits.find(last_commit_id)

    message = "This is a title\n\nThis is a body"
    message += "\n\nCo-authored-by: #{suggester1.name} <#{StealthEmail.new(suggester1).email}>"
    message += "\nCo-authored-by: #{suggester2.name} <#{suggester2.git_author_email}>"
    message += "\nSigned-off-by: #{@owner.git_author_name} <#{@owner.git_author_email}>"
    assert_equal message, last_commit.message
  end

  if GitHub.web_commit_signing_enabled?
    test "doesn't sign commits by default" do
      described_class.call(**@inputs)
      last_commit_id = @repo.refs.read(@branch).target_oid
      last_commit = @repo.commits.find(last_commit_id)
      refute_predicate last_commit, :has_signature?
    end

    test "can sign commits" do
      described_class.call(**@inputs.merge(sign: true))
      last_commit_id = @repo.refs.read(@branch).target_oid
      last_commit = @repo.commits.find(last_commit_id)
      assert_predicate last_commit, :verified_signature?
    end
  end

  test "instruments a SuggestedChangeApplied event" do
    described_class.call(**@inputs)

    assert_hydro_messages(count: 1, schema: "github.v1.SuggestedChangeApplied") unless GitHub.enterprise?
  end

  test "allows users with write access to apply a suggestion" do
    writer = create(:user)

    @repo.add_member(writer, action: :write)

    @inputs[:viewer] = writer
    described_class.call(**@inputs)
    new_oid = @repo.refs.read(@branch).target_oid

    assert_blob_contents @repo, @branch, @filename, "one\nfour\nthree\n"
    assert_repository_push_enqueued(new_oid)
  end

  test "allows a PR author of a forked repo to apply a suggestion to a PR created against the base repo" do
    forker = create(:user)
    forked_repo = create(:fork_repository, forker: forker, fork_repo: @repo, from_example: :pull_request_source)

    base_ref = forked_repo.heads.find("master")
    head_ref = forked_repo.heads.create(@branch, base_ref.target, forked_repo.owner)

    head_ref.append_commit({
      message: "a change",
      committer: forked_repo.owner,
    }, forked_repo.owner) do |files|
      files.add(@filename, "one\ntwo\nthree\n")
    end

    forked_pull = create(:pull_request,
      repository:      @repo,
      base_repository: @repo,
      base_user:       @repo.owner,
      head_repository: forked_repo,
      head_user:       forked_repo.owner,
      head_ref:        @branch,
      user:            forked_repo.owner,
    )

    review = forked_pull.reviews.create!(
      user:     forked_pull.user,
      head_sha: forked_pull.head_sha,
    )

    comment = create(:pull_request_review_comment,
      pull_request:        forked_pull,
      pull_request_review: review,
      user:                forker,
      commit_id:           forked_pull.head_sha,
      path:                @filename,
      original_position:   2,
      blob_position:       1,
      body:                "ship it",
    )
    review.comment!
    comment.submit!

    @inputs[:pull_request] = forked_pull
    @inputs[:current_oid] = forked_pull.head_sha
    @inputs[:changes] = [{
      comment: comment,
      path: @filename,
      suggestion: ["four"],
    }]
    @inputs[:viewer] = forker
    described_class.call(**@inputs)

    assert_blob_contents forked_repo, @branch, @filename, "one\nfour\nthree\n"
  end

  test "allows a maintainer of a repo that was forked to apply a suggestion to a PR created against the base repo if maintainer edits allowed" do
    forker = create(:user)
    forked_repo = create(:fork_repository, forker: forker, fork_repo: @repo, from_example: :pull_request_source)

    base_ref = forked_repo.heads.find("master")
    head_ref = forked_repo.heads.create(@branch, base_ref.target, forked_repo.owner)

    head_ref.append_commit({
      message: "a change",
      committer: forked_repo.owner,
    }, forked_repo.owner) do |files|
      files.add(@filename, "one\ntwo\nthree\n")
    end

    forked_pull = create(:pull_request,
      repository:      @repo,
      base_repository: @repo,
      base_user:       @repo.owner,
      head_repository: forked_repo,
      head_user:       forked_repo.owner,
      head_ref:        @branch,
      user:            forked_repo.owner,
      issue: create(:issue, repository: @repo, user: forked_repo.owner)
    )

    forked_pull.fork_collab_allowed!

    review = forked_pull.reviews.create!(
      user:     forked_pull.user,
      head_sha: forked_pull.head_sha,
    )

    comment = create(:pull_request_review_comment,
      pull_request:        forked_pull,
      pull_request_review: review,
      user:                forker,
      commit_id:           forked_pull.head_sha,
      path:                @filename,
      original_position:   2,
      blob_position:       1,
      body:                "ship it",
    )
    review.comment!
    comment.submit!

    @inputs[:pull_request] = forked_pull
    @inputs[:current_oid] = forked_pull.head_sha
    @inputs[:changes] = [{
      comment: comment,
      path: @filename,
      suggestion: ["four"],
    }]
    @inputs[:viewer] = @owner
    described_class.call(**@inputs)

    assert_blob_contents forked_repo, @branch, @filename, "one\nfour\nthree\n"
  end

  test "deletes a line when an empty value is provided" do
    @inputs[:changes] = [{
      comment: @comment,
      path: @filename,
      suggestion: [],
    }]
    described_class.call(**@inputs)
    new_oid = @repo.refs.read(@branch).target_oid

    assert_blob_contents @repo, @branch, @filename, "one\nthree\n"
    assert_repository_push_enqueued(new_oid)
  end

  test "deletes all commented lines when an empty value is provided for multi-line comment" do
    @inputs[:changes] = [{
      comment: @multi_line_comment,
      path: @filename,
      suggestion: [],
    }]
    described_class.call(**@inputs)
    new_oid = @repo.refs.read(@branch).target_oid

    assert_blob_contents @repo, @branch, @filename, "one\n"
    assert_repository_push_enqueued(new_oid)
  end

  test "returns errors if the pull request is merged" do
    @pull.merge(@owner)
    @comment.reload

    error = assert_raises PullRequestReviewComment::ApplySuggestedChange::UnprocessableError do
      described_class.call(**@inputs)
    end
    assert_equal "Suggested changes can only be applied to open pull requests.", error.message

    assert_blob_contents @repo, @branch, @filename, "one\ntwo\nthree\n"
    assert_correct_push_event_count(3)

    assert_hydro_messages(count: 1, schema: "github.v1.SuggestedChangeApplied") unless GitHub.enterprise?
  end

  test "returns errors if any of the lines in a multi-line suggestions are deletions" do
    filename = "new_file.txt"
    @repo.heads.find("master").append_commit({ message: "a new file", committer: @repo.owner }, @repo.owner) do |files|
      files.add(filename, "one\ntwo\nthree\n")
    end

    base_ref = @repo.heads.find("master")
    branch = "change"
    head_ref = @repo.heads.create(branch, base_ref.target, @repo.owner)

    head_ref.append_commit({
      message: "a change",
      committer: @repo.owner,
    }, @repo.owner) do |files|
      files.add(filename, "one\ntwo\nfour\n")
    end

    pull = create(:pull_request,
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      head_repository: @repo,
      head_user: @repo.owner,
      head_ref: branch,
      user: @repo.owner,
    )

    review = pull.reviews.create!(
      user: pull.user,
      head_sha: pull.head_sha,
    )

    comment = create(:pull_request_review_comment,
      pull_request: pull,
      pull_request_review: review,
      user: @owner,
      commit_id: pull.head_sha,
      path: filename,
      original_position: 4,
      blob_position: 2,
      start_position_offset: 1,
      body: "ship it",
    )
    comment.submit!
    review.comment!

    inputs = {
      pull_request: pull,
      current_oid: pull.head_sha,
      message: nil,
      changes: [{
        comment: comment,
        path: filename,
        suggestion: ["five"],
      }],
      remote_ip: "127.0.0.1",
      user_agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
      viewer: @owner,
    }

    error = assert_raises PullRequestReviewComment::ApplySuggestedChange::UnprocessableError do
      described_class.call(**inputs)
    end
    assert_equal "Applying suggestions on deleted lines is currently not supported.", error.message

    assert_blob_contents @repo, branch, filename, "one\ntwo\nfour\n"
    assert_correct_push_event_count(5) # we do a lot of pushes in test setup

    assert_hydro_messages(count: 1, schema: "github.v1.SuggestedChangeApplied") unless GitHub.enterprise?
  end

  test "calls `PullRequest.synchronize_requests_for_ref`" do
    PullRequest.expects(:synchronize_requests_for_ref).with(
      anything,
      "refs/heads/topic",
      anything,
      has_entry(excluded_pull_ids: [@pull.id]),
    ).once
    with_enqueued_pr_sync_jobs do
      described_class.call(**@inputs)
    end
  end

  test "calls `PullRequest#synchronize!` for the pull request exactly once" do
    @pull.expects(:synchronize!).once
    with_enqueued_pr_sync_jobs do
      described_class.call(**@inputs)
    end
  end
end
