# typed: true
# frozen_string_literal: true

require "test_helper"

class CommitContributionStatusTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
    @commit_info = {
      "oid"       => "3572d83ba062076f6a740379463d0f3f770d7fc5",
      "type"      => "commit",
      "message"   => "space change",
      "parents"   => ["c3956841a7cb7e8ba4a6fd923568d86958f01573"],
      "tree"      => "d9d67f971d948d0b43f1d91ead123e0b969556fe",
      "committer" => ["rick", "technoweenie@gmail.com", "2010-04-28T16:20:56Z"],
      "author"    => ["rick", "technoweenie@gmail.com", "2010-04-28T16:20:56Z"],
      "encoding"  => "UTF-8",
    }
  end

  setup do
    example_repo :commit_test, @repo
  end

  def make_status
    commit = Commit.new @repo, @commit_info
    CommitContributionStatus.new commit
  end

  test "knows when the commit email is linked to a user" do
    create :user, email: "technoweenie@gmail.com", name: "rick"
    status = make_status
    assert status.email_linked?
  end

  test "knows when the commit email is not linked to a user" do
    status = make_status
    refute status.email_linked?
  end

  test "knows when the commit is in the default branch" do
    status = make_status
    assert status.in_upstream_default?
  end

  test "knows when the commit repository is valid" do
    author = create :user, email: "technoweenie@gmail.com", name: "rick"
    create(:issue, user: author, repository: @repo)

    status = make_status
    assert status.repo_valid?
  end

  test "knows when the commit repository is invalid" do
    author = create :user, email: "technoweenie@gmail.com", name: "rick"

    status = make_status
    refute status.repo_valid?
  end

  test "all repositories are invalid if the author is unknown" do
    status = make_status

    refute status.repo_valid?
  end

  context "internal_repo?" do
    test "returns true if the repo is internal" do
      @repo = create(:internal_repository)
      assert_equal true, make_status.internal_repo?
    end

    test "returns false if the repo is not internal" do
      assert_equal false, make_status.internal_repo?
    end
  end
end
