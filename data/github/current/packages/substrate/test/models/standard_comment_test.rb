# typed: true
# frozen_string_literal: true

require "test_helper"

module StandardCommentTestHelpers
  extend T::Helpers
  requires_ancestor { GitHub::TestCase }

  def set_up_fixtures
    @owner  = create :user, login: "owner"
    @forker = create :user, login: "forker"

    @source = create :repository, owner: @owner, from_example: :pull_request_source
    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :pull_request_fork)

    @pr_issue = create :issue, repository: @source, user: @forker
    @pr = create :pull_request,
        repository: @source,
        base_repository: @source,
        base_user: @source.owner,
        base_ref: "master",
        head_repository: @fork,
        head_user: @fork.owner,
        head_ref: "topic",
        issue: @pr_issue,
        user: @forker
    @commit_id = @source.heads.find("master").target_oid
  end

  def comment_attrs(attrs)
    defaults = { user: @owner, body: "body" }
    # We made out bed, now we can lie in it
    if @klass == PullRequestReviewComment
      defaults[:pull_request] = @pr
    elsif @klass == CommitComment
      defaults.merge! commit_id: @commit_id, repository: @source
    end
    defaults.merge! attrs
    defaults
  end
end

module StandardCommentSharedTests
  extend T::Helpers
  requires_ancestor { GitHub::TestCase }
  requires_ancestor { StandardCommentTestHelpers }

  def test_body_is_validated_to_be_less_than_65536_characters
    # We want to validate on bytelength and return a human readable error
    # message with a pessimistic character limit for MYSQL_UNICODE_BLOB_LIMIT

    expected_bytes = 262144
    expected_characters = expected_bytes / 4
    content = "a" * (expected_bytes + 1)
    if @klass == IssueComment
      comment = build(:issue_comment, comment_attrs(body: content))
    elsif @klass == PullRequestReviewComment
      comment = build(:pull_request_review_comment, comment_attrs(body: content))
    elsif @klass == CommitComment
      comment = build(:commit_comment, comment_attrs(body: content))
    else
      raise "Unsupported class: #{@klass}"
    end
    refute comment.valid?, "#{comment} should be invalid due to a body exceeding the field length"
    assert_equal comment.errors[:body][0], "is too long (maximum is #{expected_characters} characters)"
  end

  def test_body_allows_and_scrubs_invalid_unicode_characters
    content = "\xE5blah"
    if @klass == IssueComment
      comment = build(:issue_comment, comment_attrs(body: content))
    elsif @klass == PullRequestReviewComment
      comment = build(:pull_request_review_comment, comment_attrs(body: content))
    elsif @klass == CommitComment
      comment = build(:commit_comment, comment_attrs(body: content))
    else
      raise "Unsupported class: #{@klass}"
    end
    assert comment.valid?, "comment is invalid #{comment.errors.full_messages}"
  end
end

class CommitCommentConsistentBehaviorTest < GitHub::TestCase
  include StandardCommentTestHelpers

  fixtures do
    set_up_fixtures
  end

  setup do
    example_repo :pull_request_source, @source
    example_repo :pull_request_fork,   @fork
    @klass = CommitComment
  end

  include StandardCommentSharedTests
end

class IssueCommentConsistentBehaviorTest < GitHub::TestCase
  include StandardCommentTestHelpers

  fixtures do
    set_up_fixtures
  end

  setup do
    example_repo :pull_request_source, @source
    example_repo :pull_request_fork,   @fork
    @klass = IssueComment
  end

  include StandardCommentSharedTests
end

class PullRequestReviewCommentConsistentBehaviorTest < GitHub::TestCase
  include StandardCommentTestHelpers

  fixtures do
    set_up_fixtures
  end

  setup do
    example_repo :pull_request_source, @source
    example_repo :pull_request_fork,   @fork
    @klass = PullRequestReviewComment
  end

  include StandardCommentSharedTests
end
