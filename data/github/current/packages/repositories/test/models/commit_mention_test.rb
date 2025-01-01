# typed: true
# frozen_string_literal: true

require "test_helper"

class CommitMentionsTest < GitHub::TestCase
  include BackgroundDeletesTestHelpers

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user, from_example: :simple)
    @committer = create(:user, login: "rsanheim", email: "rsanheim@gmail.com")
  end

  setup do
    @commit = @repo.commits.find("cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24")
    @mention = CommitMention.create(repository: @repo, commit_id: @commit.oid)
  end

  test "repo_id" do
    assert_equal @repo.id, @mention.repo_id
  end

  test "repo_name" do
    assert_equal @repo.name, @mention.repo_name
  end

  test "short_id" do
    assert_equal "cdf4526", @mention.short_id
  end

  test "commit" do
    assert_equal @commit.oid, @mention.commit.oid
  end

  test "user" do
    assert_equal @committer, @mention.user
  end

  test "its target for notifications is the commit" do
    assert_equal @commit, @mention.notifications_thread
  end

  test "mentioned_users" do
    assert_equal [], @mention.mentioned_users
  end

  test "mentioned_teams" do
    assert_equal [], @mention.mentioned_teams
  end

  test "uniqueness" do
    other_repo = create(:repository, owner: @user, from_example: :simple)

    assert_raises(ActiveRecord::RecordInvalid) do
      CommitMention.create!(repository: other_repo, commit_id: @commit.oid)
    end

    assert CommitMention.processed?(@commit)
    assert !CommitMention.processed?(
      @repo.commits.find("2c6363c328126bdee83e9f8dd55ad1db3a2aa160"),
    )
  end

  context "notifications" do
    test "author" do
      assert_equal @committer, @mention.notifications_author
    end

    test "thread" do
      assert_equal @commit, @mention.notifications_thread
    end

    test "list" do
      assert_equal @repo, @mention.notifications_list
    end
  end

  test "is deleted with repository" do
    other_repo = create(:repository, owner: @user, from_example: :simple)
    other_commit = other_repo.commits.find("2c6363c328126bdee83e9f8dd55ad1db3a2aa160")
    other_mention = CommitMention.create!(repository: other_repo, commit_id: other_commit.oid)

    assert_destroyed_in_background_with_parent do |config|
      config.parent_record = @repo
      config.expect_destroyed = [@mention]
      config.expect_not_destroyed = [other_mention]
    end
  end
end
