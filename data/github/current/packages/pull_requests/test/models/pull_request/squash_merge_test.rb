# typed: true
# frozen_string_literal: true

require "test_helper"

class SquashMergeTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @repo = create(:repository, owner: @owner, from_example: :branch_and_tag_refs)
  end

  setup do
    example_repo :branch_and_tag_refs, @repo

    master = @repo.refs.find("master")
    @repo.refs.find("other").append_commit({
      message: "A commit to topic branch",
      committer: @owner,
    }, @owner) do |files|
      files.add("file1.txt", "Contents of the file")
    end

    @repo.refs.find("other").append_commit({
      message: "Another commit to topic branch",
      committer: @owner,
    }, @owner) do |files|
      files.add("file2.txt", "Different file contents")
    end

    @merge_commit, _, _ = @repo.commits.create_merge_commit(
      @owner,
      master.target_oid,
      @repo.refs.find("other").target_oid
    )
  end

  test "rewrites the commit object with the passed parameters" do
    author_email = "dr.squash@example.edu"
    author_name = "Professor Squash"
    time_zone = @owner.time_zone
    title = "A squashed merge commit"
    message = "Sure looks squashed to me."

    squash_merge = PullRequest::SquashMerge.new(
      repository: @repo,
      commit_oid: @merge_commit.oid,
      require_signature: false
    )
    commit_oid = squash_merge.perform(
      author_email: author_email,
      author_name: author_name,
      time_zone: time_zone,
      title: title,
      message: message,
    )

    assert squashed_commit = @repo.commits.find(commit_oid)

    assert_equal author_email, squashed_commit.author_email
    assert_equal author_name, squashed_commit.author_name
    assert_equal time_zone.name, squashed_commit.authored_date.zone
    assert_equal "#{title}\n\n#{message}", squashed_commit.message

    assert_equal GitHub.web_committer_email, squashed_commit.committer_email
    assert_equal GitHub.web_committer_name, squashed_commit.committer_name

    assert_equal 1, squashed_commit.parent_count
    assert_equal @merge_commit.tree_oid, squashed_commit.tree_oid
  end

  test "succeeds despite signature failure if signature is not requred" do
    author_email = "dr.squash@example.edu"
    author_name = "Professor Squash"
    time_zone = @owner.time_zone
    title = "A squashed merge commit"
    message = "Sure looks squashed to me."

    Repository.stubs(:find_by).returns(@repo)
    @repo.stubs(:sign_commit).returns(nil)

    squash_merge = PullRequest::SquashMerge.new(
      repository: @repo,
      commit_oid: @merge_commit.oid,
      require_signature: false
    )
    commit_oid = squash_merge.perform(
      author_email: author_email,
      author_name: author_name,
      time_zone: time_zone,
      title: title,
      message: message,
    )

    assert squashed_commit = @repo.commits.find(commit_oid)
    refute squashed_commit.has_signature?
  end

  test "raises Repositories::Error::SignatureError if signature is required but fails" do
    author_email = "dr.squash@example.edu"
    author_name = "Professor Squash"
    time_zone = @owner.time_zone
    title = "A squashed merge commit"
    message = "Sure looks squashed to me."

    Repository.stubs(:find_by).returns(@repo)
    @repo.stubs(:sign_commit).returns(nil)
    squash_merge = PullRequest::SquashMerge.new(
      repository: @repo,
      commit_oid: @merge_commit.oid,
      require_signature: true
    )

    assert_raises Repositories::Error::SignatureError do
      squash_merge.perform(
        author_email: author_email,
        author_name: author_name,
        time_zone: time_zone,
        title: title,
        message: message,
      )
    end
  end
end
