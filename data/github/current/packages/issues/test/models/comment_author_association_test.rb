# typed: true
# frozen_string_literal: true

require "test_helper"

module CommentAuthorAssociationTestHelper
  include ExampleRepositories
  include FactoryBot::Syntax::Methods
  include Minitest::Assertions

  def assert_association_predicate(comment, viewer, predicate)
    assert_predicate CommentAuthorAssociation.new(comment: comment, viewer: viewer), predicate
  end

  def refute_association_predicate(comment, viewer, predicate)
    refute_predicate CommentAuthorAssociation.new(comment: comment, viewer: viewer), predicate
  end

  def setup_fixture_repo_and_users
    @owner = create(:user)
    @private_owner = create(:user)
    @member = create(:user)
    @private_member = create(:user)
    @collaborator = create(:user)
    @commenter = create(:user)
    @contributor = create(:user)
    @first_time_contributor = create(:user)
    @to_delete_user = create(:user)
    @mannequin = create(:mannequin)
    @user = create(:user)

    @organization = create(:organization, admin: @owner)

    @repository = create(:repository, owner: @organization, from_example: :commit_comments)

    @user_repository = create(:repository, owner: @user, from_example: :commit_comments)

    @organization.publicize_member(@owner)

    @organization.add_member(@member)
    @organization.publicize_member(@member)

    @organization.add_member(@private_owner, action: :admin)
    @organization.conceal_member(@private_owner)

    @organization.add_member(@private_member)
    @organization.conceal_member(@private_member)

    @repository.add_member(@collaborator)

    @repository.heads.find("master").append_commit({
      message: "change stuff",
      committer: @contributor,
      author: @contributor,
    }, @contributor)

    @fork = create(:fork_repository, forker: @first_time_contributor, fork_repo: @repository, from_example: :commit_comments)

    @fork.heads.find("master").append_commit({
      message: "change stuff",
      committer: @first_time_contributor,
      author: @first_time_contributor,
    }, @first_time_contributor) do |files|
      files.add("changes", "some\nchanged\ncontent\n")
    end

    @pull_request = PullRequest.create_for!(@repository, {
      base: "#{@repository.owner.login}:master",
      head: "#{@fork.owner.login}:master",
      user: @fork.owner,
      title: "Some changes",
      body: "Some changes",
    })

    @user_forker = create(:user)
    @user_forker_org = create(:organization, admin: @user_forker)

    @user_fork = create(:fork_repository, forker: @user_forker, fork_repo: @user_repository, organization: @user_forker_org, from_example: :commit_comments)

    @user_fork.heads.find("master").append_commit({
      message: "change stuff",
      committer: @user_forker,
      author: @user_forker,
    }, @user_forker) do |files|
      files.add("different-changes", "gotta add\nsomething\n")
    end

    @user_pull_request = PullRequest.create_for!(@user_repository, {
      base: "#{@user_repository.owner.login}:master",
      head: "#{@user_fork.owner.login}:master",
      user: @user_forker,
      title: "Some changes",
      body: "Some changes",
    })

    CommitContribution.backfill!(@repository)
  end
end

class CommentAuthorAssociationForACommitCommentTest < GitHub::TestCase
  fixtures do
    setup_fixture_repo_and_users

    @commit_oid = "c3956841a7cb7e8ba4a6fd923568d86958f01573"

    @owner_comment = create(:commit_comment, {
      user: @owner,
      repository: @repository,
      position: 0,
      path: "color.js",
      commit_id: @commit_oid,
    })

    @private_owner_comment = create(:commit_comment, {
      user: @private_owner,
      repository: @repository,
      position: 0,
      path: "color.js",
      commit_id: @commit_oid,
    })

    @member_comment = create(:commit_comment, {
      user: @member,
      repository: @repository,
      position: 0,
      path: "color.js",
      commit_id: @commit_oid,
    })

    @private_member_comment = create(:commit_comment, {
      user: @private_member,
      repository: @repository,
      position: 0,
      path: "color.js",
      commit_id: @commit_oid,
    })

    @collaborator_comment = create(:commit_comment, {
      user: @collaborator,
      repository: @repository,
      position: 0,
      path: "color.js",
      commit_id: @commit_oid,
    })

    @commenter_comment = create(:commit_comment, {
      user: @commenter,
      repository: @repository,
      position: 0,
      path: "color.js",
      commit_id: @commit_oid,
    })

    @contributor_comment = create(:commit_comment, {
      user: @contributor,
      repository: @repository,
      position: 0,
      path: "color.js",
      commit_id: @commit_oid,
    })

    @first_time_contributor_comment = create(:commit_comment, {
      user: @first_time_contributor,
      repository: @repository,
      position: 0,
      path: "color.js",
      commit_id: @commit_oid,
    })

    @mannequin_comment = create(:commit_comment, {
      user: @mannequin,
      repository: @repository,
      position: 0,
      path: "color.js",
      commit_id: @commit_oid,
    })

    @user_comment = create(:commit_comment, {
      user: @user,
      repository: @user_repository,
      position: 0,
      path: "color.js",
      commit_id: @commit_oid,
    })
  end

  include CommentAuthorAssociationTestHelper

  context "#owner?" do
    test "returns true if the comment author is a owner of the repo" do
      assert_association_predicate @user_comment, nil, :owner?

      refute_association_predicate @owner_comment, nil, :owner?
      refute_association_predicate @member_comment, nil, :owner?
      refute_association_predicate @collaborator_comment, nil, :owner?
      refute_association_predicate @contributor_comment, nil, :owner?
      refute_association_predicate @first_time_contributor_comment, nil, :owner?
      refute_association_predicate @commenter_comment, nil, :owner?
      refute_association_predicate @mannequin_comment, nil, :owner?
    end
  end

  context "#member?" do
    test "returns true if the comment author is a member of the repo's organization" do
      assert_association_predicate @member_comment, nil, :member?
      assert_association_predicate @owner_comment, nil, :member?

      refute_association_predicate @collaborator_comment, nil, :member?
      refute_association_predicate @contributor_comment, nil, :member?
      refute_association_predicate @first_time_contributor_comment, nil, :member?
      refute_association_predicate @commenter_comment, nil, :member?
      refute_association_predicate @mannequin_comment, nil, :member?
    end

    test "does not expose private organization members" do
      assert_association_predicate @private_member_comment, @owner, :member?
      assert_association_predicate @private_member_comment, @private_owner, :member?
      assert_association_predicate @private_member_comment, @member, :member?
      assert_association_predicate @private_member_comment, @private_member, :member?

      refute_association_predicate @private_owner_comment, nil, :member?
      refute_association_predicate @private_owner_comment, @collaborator, :member?
      refute_association_predicate @private_owner_comment, @contributor, :member?
      refute_association_predicate @private_owner_comment, @first_time_contributor, :member?
      refute_association_predicate @private_owner_comment, @commenter, :member?
      refute_association_predicate @private_owner_comment, @mannequin, :member?
    end
  end

  context "#collaborator?" do
    test "returns true if the comment author is a direct collaborator of the repo" do
      assert_association_predicate @collaborator_comment, nil, :collaborator?

      refute_association_predicate @owner_comment, nil, :collaborator?
      refute_association_predicate @member_comment, nil, :collaborator?
      refute_association_predicate @contributor_comment, nil, :collaborator?
      refute_association_predicate @first_time_contributor_comment, nil, :collaborator?
      refute_association_predicate @commenter_comment, nil, :collaborator?
      refute_association_predicate @mannequin_comment, nil, :collaborator?
    end
  end

  context "#contributor?" do
    test "returns true if the comment author is a contributor of the repo" do
      assert_association_predicate @contributor_comment, nil, :contributor?

      refute_association_predicate @owner_comment, nil, :contributor?
      refute_association_predicate @member_comment, nil, :contributor?
      refute_association_predicate @collaborator_comment, nil, :contributor?
      refute_association_predicate @first_time_contributor_comment, nil, :contributor?
      refute_association_predicate @commenter_comment, nil, :contributor?
      refute_association_predicate @mannequin_comment, nil, :contributor?
    end
  end

  context "#first_time_contributor?" do
    test "returns false" do
      refute_association_predicate @owner_comment, nil, :first_time_contributor?
      refute_association_predicate @member_comment, nil, :first_time_contributor?
      refute_association_predicate @collaborator_comment, nil, :first_time_contributor?
      refute_association_predicate @contributor_comment, nil, :first_time_contributor?
      refute_association_predicate @first_time_contributor_comment, nil, :first_time_contributor?
      refute_association_predicate @commenter_comment, nil, :first_time_contributor?
      refute_association_predicate @mannequin_comment, nil, :first_time_contributor?
    end
  end

  context "#mannequin?" do
    test "returns true if the comment author is a mannequin" do
      assert_association_predicate @mannequin_comment, nil, :mannequin?

      refute_association_predicate @owner_comment, nil, :mannequin?
      refute_association_predicate @member_comment, nil, :mannequin?
      refute_association_predicate @collaborator_comment, nil, :mannequin?
      refute_association_predicate @contributor_comment, nil, :mannequin?
      refute_association_predicate @first_time_contributor_comment, nil, :mannequin?
      refute_association_predicate @commenter_comment, nil, :mannequin?
    end
  end

  context "#to_sym" do
    test "returns a symbol representing the association" do
      assert_equal :owner, CommentAuthorAssociation.new(comment: @user_comment, viewer: nil).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @owner_comment, viewer: nil).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @member_comment, viewer: nil).to_sym
      assert_equal :collaborator, CommentAuthorAssociation.new(comment: @collaborator_comment, viewer: nil).to_sym
      assert_equal :contributor, CommentAuthorAssociation.new(comment: @contributor_comment, viewer: nil).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @first_time_contributor_comment, viewer: nil).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @commenter_comment, viewer: nil).to_sym
      assert_equal :mannequin, CommentAuthorAssociation.new(comment: @mannequin_comment, viewer: nil).to_sym
    end

    test "does not expose private organization members" do
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @owner).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @private_owner).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @member).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @private_member).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @owner).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @private_owner).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @member).to_sym

      assert_equal :none, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: nil).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @collaborator).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @contributor).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @first_time_contributor).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @commenter).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @mannequin).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: nil).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @collaborator).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @contributor).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @first_time_contributor).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @commenter).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @mannequin).to_sym
    end
  end

  context "to_s" do
    test "returns a string representing the association" do
      assert_equal "OWNER", CommentAuthorAssociation.new(comment: @user_comment, viewer: nil).to_s
      assert_equal "MEMBER", CommentAuthorAssociation.new(comment: @owner_comment, viewer: nil).to_s
      assert_equal "MEMBER", CommentAuthorAssociation.new(comment: @member_comment, viewer: nil).to_s
      assert_equal "COLLABORATOR", CommentAuthorAssociation.new(comment: @collaborator_comment, viewer: nil).to_s
      assert_equal "CONTRIBUTOR", CommentAuthorAssociation.new(comment: @contributor_comment, viewer: nil).to_s
      assert_equal "MANNEQUIN", CommentAuthorAssociation.new(comment: @mannequin_comment, viewer: nil).to_s
      assert_equal "NONE", CommentAuthorAssociation.new(comment: @first_time_contributor_comment, viewer: nil).to_s
      assert_equal "NONE", CommentAuthorAssociation.new(comment: @commenter_comment, viewer: nil).to_s
    end
  end
end

class CommentAuthorAssociationForAnIssueCommentTest < GitHub::TestCase
  fixtures do
    setup_fixture_repo_and_users

    @issue = @pull_request.issue
    @user_issue = @user_pull_request.issue

    @owner_comment = create(:issue_comment, user: @owner, issue: @issue)
    @private_owner_comment = create(:issue_comment, user: @private_owner, issue: @issue)
    @member_comment = create(:issue_comment, user: @member, issue: @issue)
    @private_member_comment = create(:issue_comment, user: @private_member, issue: @issue)
    @collaborator_comment = create(:issue_comment, user: @collaborator, issue: @issue)
    @commenter_comment = create(:issue_comment, user: @commenter, issue: @issue)
    @contributor_comment = create(:issue_comment, user: @contributor, issue: @issue)
    @first_time_contributor_comment = create(:issue_comment, user: @first_time_contributor, issue: @issue)
    @mannequin_comment = create(:issue_comment, user: @mannequin, issue: @issue)
    @user_comment = create(:issue_comment, user: @user, issue: @user_issue)
  end

  include CommentAuthorAssociationTestHelper

  context "#owner?" do
    test "returns true if the comment author is a owner of the repo" do
      assert_association_predicate @user_comment, nil, :owner?

      refute_association_predicate @owner_comment, nil, :owner?
      refute_association_predicate @member_comment, nil, :owner?
      refute_association_predicate @collaborator_comment, nil, :owner?
      refute_association_predicate @contributor_comment, nil, :owner?
      refute_association_predicate @first_time_contributor_comment, nil, :owner?
      refute_association_predicate @commenter_comment, nil, :owner?
      refute_association_predicate @mannequin_comment, nil, :owner?
    end
  end

  context "#member?" do
    test "returns true if the comment author is a member of the repo's organization" do
      assert_association_predicate @member_comment, nil, :member?
      assert_association_predicate @owner_comment, nil, :member?

      refute_association_predicate @collaborator_comment, nil, :member?
      refute_association_predicate @contributor_comment, nil, :member?
      refute_association_predicate @first_time_contributor_comment, nil, :member?
      refute_association_predicate @commenter_comment, nil, :member?
      refute_association_predicate @mannequin_comment, nil, :member?
    end

    test "does not expose private organization members" do
      assert_association_predicate @private_member_comment, @owner, :member?
      assert_association_predicate @private_member_comment, @private_owner, :member?
      assert_association_predicate @private_member_comment, @member, :member?
      assert_association_predicate @private_member_comment, @private_member, :member?

      refute_association_predicate @private_owner_comment, nil, :member?
      refute_association_predicate @private_owner_comment, @collaborator, :member?
      refute_association_predicate @private_owner_comment, @contributor, :member?
      refute_association_predicate @private_owner_comment, @first_time_contributor, :member?
      refute_association_predicate @private_owner_comment, @commenter, :member?
      refute_association_predicate @private_owner_comment, @mannequin, :member?
    end
  end

  context "#collaborator?" do
    test "returns true if the comment author is a direct collaborator of the repo" do
      assert_association_predicate @collaborator_comment, nil, :collaborator?

      refute_association_predicate @owner_comment, nil, :collaborator?
      refute_association_predicate @member_comment, nil, :collaborator?
      refute_association_predicate @contributor_comment, nil, :collaborator?
      refute_association_predicate @first_time_contributor_comment, nil, :collaborator?
      refute_association_predicate @commenter_comment, nil, :collaborator?
      refute_association_predicate @mannequin_comment, nil, :collaborator?
    end
  end

  context "#contributor?" do
    test "returns true if the comment author is a contributor of the repo" do
      assert_association_predicate @contributor_comment, nil, :contributor?

      refute_association_predicate @owner_comment, nil, :contributor?
      refute_association_predicate @member_comment, nil, :contributor?
      refute_association_predicate @collaborator_comment, nil, :contributor?
      refute_association_predicate @first_time_contributor_comment, nil, :contributor?
      refute_association_predicate @commenter_comment, nil, :contributor?
      refute_association_predicate @mannequin_comment, nil, :contributor?
    end
  end

  context "#first_time_contributor?" do
    test "returns false" do
      refute_association_predicate @owner_comment, nil, :first_time_contributor?
      refute_association_predicate @member_comment, nil, :first_time_contributor?
      refute_association_predicate @collaborator_comment, nil, :first_time_contributor?
      refute_association_predicate @contributor_comment, nil, :first_time_contributor?
      refute_association_predicate @first_time_contributor_comment, nil, :first_time_contributor?
      refute_association_predicate @commenter_comment, nil, :first_time_contributor?
      refute_association_predicate @mannequin_comment, nil, :first_time_contributor?
    end
  end

  context "#to_sym" do
    test "returns a symbol representing the association" do
      assert_equal :owner, CommentAuthorAssociation.new(comment: @user_comment, viewer: nil).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @owner_comment, viewer: nil).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @member_comment, viewer: nil).to_sym
      assert_equal :collaborator, CommentAuthorAssociation.new(comment: @collaborator_comment, viewer: nil).to_sym
      assert_equal :contributor, CommentAuthorAssociation.new(comment: @contributor_comment, viewer: nil).to_sym
      assert_equal :mannequin, CommentAuthorAssociation.new(comment: @mannequin_comment, viewer: nil).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @first_time_contributor_comment, viewer: nil).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @commenter_comment, viewer: nil).to_sym
    end

    test "does not expose private organization members" do
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @owner).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @private_owner).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @member).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @private_member).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @owner).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @private_owner).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @member).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @private_member).to_sym

      assert_equal :none, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: nil).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @collaborator).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @contributor).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @first_time_contributor).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @commenter).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @mannequin).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: nil).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @collaborator).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @contributor).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @first_time_contributor).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @commenter).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @mannequin).to_sym
    end
  end
end

class CommentAuthorAssociationForAnIssueTest < GitHub::TestCase
  fixtures do
    setup_fixture_repo_and_users
    @pull_request.close

    @owner_comment = create(:issue, user: @owner, repository: @repository)
    @private_owner_comment = create(:issue, user: @private_owner, repository: @repository)
    @member_comment = create(:issue, user: @member, repository: @repository)
    @private_member_comment = create(:issue, user: @private_member, repository: @repository)
    @collaborator_comment = create(:issue, user: @collaborator, repository: @repository)
    @commenter_comment = create(:issue, user: @commenter, repository: @repository)
    @contributor_comment = create(:issue, user: @contributor, repository: @repository)
    @first_time_contributor_comment = create(:issue, user: @first_time_contributor, repository: @repository)
    @nil_contributor_comment = create(:issue, user: @to_delete_user, repository: @repository)
    @user_comment = create(:issue, user: @user, repository: @user_repository)
    @mannequin_comment = create(:issue, user: @mannequin, repository: @user_repository)
  end

  include CommentAuthorAssociationTestHelper

  context "#owner?" do
    test "returns true if the comment author is a owner of the repo" do
      assert_association_predicate @user_comment, nil, :owner?

      refute_association_predicate @owner_comment, nil, :owner?
      refute_association_predicate @member_comment, nil, :owner?
      refute_association_predicate @collaborator_comment, nil, :owner?
      refute_association_predicate @contributor_comment, nil, :owner?
      refute_association_predicate @first_time_contributor_comment, nil, :owner?
      refute_association_predicate @commenter_comment, nil, :owner?
      refute_association_predicate @mannequin_comment, nil, :owner?
    end
  end

  context "#member?" do
    test "returns true if the comment author is a member of the repo's organization" do
      assert_association_predicate @member_comment, nil, :member?
      assert_association_predicate @owner_comment, nil, :member?

      refute_association_predicate @collaborator_comment, nil, :member?
      refute_association_predicate @contributor_comment, nil, :member?
      refute_association_predicate @first_time_contributor_comment, nil, :member?
      refute_association_predicate @commenter_comment, nil, :member?
      refute_association_predicate @mannequin_comment, nil, :member?
    end

    test "does not expose private organization members" do
      assert_association_predicate @private_member_comment, @owner, :member?
      assert_association_predicate @private_member_comment, @private_owner, :member?
      assert_association_predicate @private_member_comment, @member, :member?
      assert_association_predicate @private_member_comment, @private_member, :member?

      refute_association_predicate @private_owner_comment, nil, :member?
      refute_association_predicate @private_owner_comment, @collaborator, :member?
      refute_association_predicate @private_owner_comment, @contributor, :member?
      refute_association_predicate @private_owner_comment, @first_time_contributor, :member?
      refute_association_predicate @private_owner_comment, @commenter, :member?
      refute_association_predicate @private_owner_comment, @mannequin, :member?
    end
  end

  context "#collaborator?" do
    test "returns true if the comment author is a direct collaborator of the repo" do
      assert_association_predicate @collaborator_comment, nil, :collaborator?

      refute_association_predicate @owner_comment, nil, :collaborator?
      refute_association_predicate @member_comment, nil, :collaborator?
      refute_association_predicate @contributor_comment, nil, :collaborator?
      refute_association_predicate @first_time_contributor_comment, nil, :collaborator?
      refute_association_predicate @commenter_comment, nil, :collaborator?
      refute_association_predicate @mannequin_comment, nil, :collaborator?
    end
  end

  context "#contributor?" do
    test "returns true if the comment author is a contributor of the repo" do
      assert_association_predicate @contributor_comment, nil, :contributor?

      refute_association_predicate @owner_comment, nil, :contributor?
      refute_association_predicate @member_comment, nil, :contributor?
      refute_association_predicate @collaborator_comment, nil, :contributor?
      refute_association_predicate @first_time_contributor_comment, nil, :contributor?
      refute_association_predicate @commenter_comment, nil, :contributor?
      refute_association_predicate @mannequin_comment, nil, :contributor?
    end
  end

  context "#first_time_contributor?" do
    context "for an issue belonging to a PullRequest" do
      test "returns whether the issue was authored by a first-time contributor" do
        pull_request = PullRequest.create_for!(@repository, {
          base: "#{@repository.owner.login}:master",
          head: "#{@fork.owner.login}:master",
          issue: @first_time_contributor_comment,
          user: @first_time_contributor,
        })

        @member = create(:user)
        @repository.owner.add_member @member

        assert_association_predicate @first_time_contributor_comment, @member, :first_time_contributor?
        assert_association_predicate @first_time_contributor_comment, @repository.owner, :first_time_contributor?
        assert_association_predicate @first_time_contributor_comment, @collaborator, :first_time_contributor?
        refute_association_predicate @first_time_contributor_comment, @contributor, :first_time_contributor?

        refute_association_predicate @owner_comment, nil, :first_time_contributor?
        refute_association_predicate @member_comment, nil, :first_time_contributor?
        refute_association_predicate @collaborator_comment, nil, :first_time_contributor?
        refute_association_predicate @contributor_comment, nil, :first_time_contributor?
        refute_association_predicate @first_time_contributor_comment, nil, :first_time_contributor?
        refute_association_predicate @commenter_comment, nil, :first_time_contributor?
        refute_association_predicate @mannequin_comment, nil, :first_time_contributor?

        refute_association_predicate @first_time_contributor_comment, nil, :first_time_contributor?
        refute_association_predicate @first_time_contributor_comment, @first_time_contributor, :first_time_contributor?
        refute_association_predicate @first_time_contributor_comment, @commenter, :first_time_contributor?
      end

      test "returns false if the issue was made by a bot" do
        integration = create(:integration)
        bot = integration.bot

        issue_from_bot = create(:issue, user: bot, repository: @repository)
        pull_request = PullRequest.create_for!(@repository, {
          base: "#{@repository.owner.login}:master",
          head: "#{@fork.owner.login}:master",
          issue: issue_from_bot,
          user: bot,
        })
        refute_association_predicate pull_request, @contributor, :first_time_contributor?
      end
    end

    context "for an issue without a PullRequest" do
      test "returns false" do
        refute_association_predicate @owner_comment, nil, :first_time_contributor?
        refute_association_predicate @member_comment, nil, :first_time_contributor?
        refute_association_predicate @collaborator_comment, nil, :first_time_contributor?
        refute_association_predicate @contributor_comment, nil, :first_time_contributor?
        refute_association_predicate @first_time_contributor_comment, nil, :first_time_contributor?
        refute_association_predicate @commenter_comment, nil, :first_time_contributor?
        refute_association_predicate @mannequin_comment, nil, :first_time_contributor?

        refute_association_predicate @first_time_contributor_comment, nil, :first_time_contributor?
        refute_association_predicate @first_time_contributor_comment, @collaborator, :first_time_contributor?
        refute_association_predicate @first_time_contributor_comment, @contributor, :first_time_contributor?
        refute_association_predicate @first_time_contributor_comment, @first_time_contributor, :first_time_contributor?
        refute_association_predicate @first_time_contributor_comment, @commenter, :first_time_contributor?
        refute_association_predicate @first_time_contributor_comment, @mannequin, :first_time_contributor?
      end
    end

    context "for a PullRequest" do
      test "returns whether the pull request was authored by a first-time contributor" do
        pull_request = PullRequest.create_for!(@repository, {
          base: "#{@repository.owner.login}:master",
          head: "#{@fork.owner.login}:master",
          issue: @first_time_contributor_comment,
          user: @first_time_contributor,
        })

        # we should show this to all users with push/merge access on the repo (eg: owner and collabs)
        assert_association_predicate pull_request, @repository.owner, :first_time_contributor?
        assert_association_predicate pull_request, @collaborator, :first_time_contributor?
        refute_association_predicate pull_request, @contributor, :first_time_contributor?
        refute_association_predicate pull_request, nil, :first_time_contributor?
        refute_association_predicate pull_request, @first_time_contributor, :first_time_contributor?
        refute_association_predicate pull_request, @commenter, :first_time_contributor?
        refute_association_predicate pull_request, @mannequin, :first_time_contributor?
      end

      test "returns false when the pull request was made by a bot" do
        bot = make_integration_installation(repository: @repository, permissions: { "pull_requests" => :write }).bot
        pull_request = PullRequest.create_for!(@repository, {
          base: "#{@repository.owner.login}:master",
          head: "#{@fork.owner.login}:master",
          issue: @first_time_contributor_comment,
          user: bot,
        })
        refute_association_predicate pull_request, @contributor, :first_time_contributor?
      end
    end
  end

  context "#first_timer?" do
    context "for an issue belonging to a PullRequest" do
      test "returns whether the issue was authored by a first-timer" do
        first_timer_comment = @pull_request.issue

        assert_association_predicate first_timer_comment, @collaborator, :first_timer?
        assert_association_predicate first_timer_comment, @repository.owner, :first_timer?

        refute_association_predicate @owner_comment, nil, :first_timer?
        refute_association_predicate @member_comment, nil, :first_timer?
        refute_association_predicate @collaborator_comment, nil, :first_timer?
        refute_association_predicate @contributor_comment, nil, :first_timer?
        refute_association_predicate @first_time_contributor_comment, nil, :first_timer?
        refute_association_predicate @commenter_comment, nil, :first_timer?
        refute_association_predicate @mannequin_comment, nil, :first_timer?

        refute_association_predicate first_timer_comment, @contributor, :first_timer?
        refute_association_predicate first_timer_comment, nil, :first_timer?
        refute_association_predicate first_timer_comment, @first_time_contributor, :first_timer?
        refute_association_predicate first_timer_comment, @commenter, :first_timer?
        refute_association_predicate first_timer_comment, @mannequin, :first_timer?
      end

      test "does not error for nil/deleted user" do
        pull_request = PullRequest.create_for!(@repository, {
          base: "#{@repository.owner.login}:master",
          head: "#{@fork.owner.login}:master",
          issue: @nil_contributor_comment,
          user: @to_delete_user,
        })

        @to_delete_user.destroy
        @nil_contributor_comment.reload

        refute_association_predicate @nil_contributor_comment, @contributor, :first_timer?
      end

      test "returns false if the issue was made by a bot" do
        integration = create(:integration)
        bot = integration.bot

        issue_from_bot = create(:issue, user: bot, repository: @repository)
        pull_request = PullRequest.create_for!(@repository, {
          base: "#{@repository.owner.login}:master",
          head: "#{@fork.owner.login}:master",
          issue: issue_from_bot,
          user: bot,
        })
        refute_association_predicate pull_request, @contributor, :first_timer?
      end
    end

    context "for an issue without a PullRequest" do
      test "returns false" do
        refute_association_predicate @owner_comment, nil, :first_timer?
        refute_association_predicate @member_comment, nil, :first_timer?
        refute_association_predicate @collaborator_comment, nil, :first_timer?
        refute_association_predicate @contributor_comment, nil, :first_timer?
        refute_association_predicate @first_time_contributor_comment, nil, :first_timer?
        refute_association_predicate @commenter_comment, nil, :first_timer?
        refute_association_predicate @mannequin_comment, nil, :first_timer?

        refute_association_predicate @first_time_contributor_comment, nil, :first_timer?
        refute_association_predicate @first_time_contributor_comment, @collaborator, :first_timer?
        refute_association_predicate @first_time_contributor_comment, @contributor, :first_timer?
        refute_association_predicate @first_time_contributor_comment, @first_time_contributor, :first_timer?
        refute_association_predicate @first_time_contributor_comment, @commenter, :first_timer?
        refute_association_predicate @first_time_contributor_comment, @mannequin, :first_timer?
      end
    end
  end

  context "#to_sym" do
    test "returns a symbol representing the association" do
      assert_equal :owner, CommentAuthorAssociation.new(comment: @user_comment, viewer: nil).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @owner_comment, viewer: nil).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @member_comment, viewer: nil).to_sym
      assert_equal :collaborator, CommentAuthorAssociation.new(comment: @collaborator_comment, viewer: nil).to_sym
      assert_equal :contributor, CommentAuthorAssociation.new(comment: @contributor_comment, viewer: nil).to_sym
      assert_equal :mannequin, CommentAuthorAssociation.new(comment: @mannequin_comment, viewer: nil).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @first_time_contributor_comment, viewer: nil).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @commenter_comment, viewer: nil).to_sym
    end

    test "does not expose private organization members" do
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @owner).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @private_owner).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @member).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @private_member).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @owner).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @private_owner).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @member).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @private_member).to_sym


      assert_equal :none, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: nil).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @collaborator).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @contributor).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @first_time_contributor).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @commenter).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @mannequin).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: nil).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @collaborator).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @contributor).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @first_time_contributor).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @commenter).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @mannequin).to_sym
    end
  end
end

class CommentAuthorAssociationForAPullRequestReviewTest < GitHub::TestCase
  fixtures do
    setup_fixture_repo_and_users

    @owner_comment = create(:pull_request_review, {
      user: @owner,
      pull_request: @pull_request,
    })

    @private_owner_comment = create(:pull_request_review, {
      user: @private_owner,
      pull_request: @pull_request,
    })

    @member_comment = create(:pull_request_review, {
      user: @member,
      pull_request: @pull_request,
    })

    @private_member_comment = create(:pull_request_review, {
      user: @private_member,
      pull_request: @pull_request,
    })

    @collaborator_comment = create(:pull_request_review, {
      user: @collaborator,
      pull_request: @pull_request,
    })

    @commenter_comment = create(:pull_request_review, {
      user: @commenter,
      pull_request: @pull_request,
    })

    @contributor_comment = create(:pull_request_review, {
      user: @contributor,
      pull_request: @pull_request,
    })

    @first_time_contributor_comment = create(:pull_request_review, {
      user: @first_time_contributor,
      pull_request: @pull_request,
    })

    @mannequin_comment = create(:pull_request_review, {
      user: @mannequin,
      pull_request: @pull_request,
    })

    @user_comment = create(:pull_request_review, {
      user: @user,
      pull_request: @user_pull_request,
    })
  end

  include CommentAuthorAssociationTestHelper

  context "#owner?" do
    test "returns true if the comment author is a owner of the repo" do
      assert_association_predicate @user_comment, nil, :owner?

      refute_association_predicate @owner_comment, nil, :owner?
      refute_association_predicate @member_comment, nil, :owner?
      refute_association_predicate @collaborator_comment, nil, :owner?
      refute_association_predicate @contributor_comment, nil, :owner?
      refute_association_predicate @first_time_contributor_comment, nil, :owner?
      refute_association_predicate @commenter_comment, nil, :owner?
      refute_association_predicate @mannequin_comment, nil, :owner?
    end
  end

  context "#member?" do
    test "returns true if the comment author is a member of the repo's organization" do
      assert_association_predicate @member_comment, nil, :member?
      assert_association_predicate @owner_comment, nil, :member?

      refute_association_predicate @collaborator_comment, nil, :member?
      refute_association_predicate @contributor_comment, nil, :member?
      refute_association_predicate @first_time_contributor_comment, nil, :member?
      refute_association_predicate @commenter_comment, nil, :member?
      refute_association_predicate @mannequin_comment, nil, :member?
    end

    test "does not expose private organization members" do
      assert_association_predicate @private_member_comment, @owner, :member?
      assert_association_predicate @private_member_comment, @private_owner, :member?
      assert_association_predicate @private_member_comment, @member, :member?
      assert_association_predicate @private_member_comment, @private_member, :member?
      assert_association_predicate @private_owner_comment, @owner, :member?
      assert_association_predicate @private_owner_comment, @private_owner, :member?
      assert_association_predicate @private_owner_comment, @member, :member?
      assert_association_predicate @private_owner_comment, @private_member, :member?

      refute_association_predicate @private_owner_comment, nil, :member?
      refute_association_predicate @private_owner_comment, @collaborator, :member?
      refute_association_predicate @private_owner_comment, @contributor, :member?
      refute_association_predicate @private_owner_comment, @first_time_contributor, :member?
      refute_association_predicate @private_owner_comment, @commenter, :member?
      refute_association_predicate @private_owner_comment, @mannequin, :member?
      refute_association_predicate @private_member_comment, nil, :member?
      refute_association_predicate @private_member_comment, @collaborator, :member?
      refute_association_predicate @private_member_comment, @contributor, :member?
      refute_association_predicate @private_member_comment, @first_time_contributor, :member?
      refute_association_predicate @private_member_comment, @commenter, :member?
      refute_association_predicate @private_member_comment, @mannequin, :member?
    end
  end

  context "#collaborator?" do
    test "returns true if the comment author is a direct collaborator of the repo" do
      assert_association_predicate @collaborator_comment, nil, :collaborator?

      refute_association_predicate @owner_comment, nil, :collaborator?
      refute_association_predicate @member_comment, nil, :collaborator?
      refute_association_predicate @contributor_comment, nil, :collaborator?
      refute_association_predicate @first_time_contributor_comment, nil, :collaborator?
      refute_association_predicate @commenter_comment, nil, :collaborator?
      refute_association_predicate @mannequin_comment, nil, :collaborator?
    end
  end

  context "#contributor?" do
    test "returns true if the comment author is a contributor of the repo" do
      assert_association_predicate @contributor_comment, nil, :contributor?

      refute_association_predicate @owner_comment, nil, :contributor?
      refute_association_predicate @member_comment, nil, :contributor?
      refute_association_predicate @collaborator_comment, nil, :contributor?
      refute_association_predicate @first_time_contributor_comment, nil, :contributor?
      refute_association_predicate @commenter_comment, nil, :contributor?
      refute_association_predicate @mannequin_comment, nil, :contributor?
    end
  end

  context "#first_time_contributor?" do
    test "returns false" do
      refute_association_predicate @owner_comment, nil, :first_time_contributor?
      refute_association_predicate @member_comment, nil, :first_time_contributor?
      refute_association_predicate @collaborator_comment, nil, :first_time_contributor?
      refute_association_predicate @contributor_comment, nil, :first_time_contributor?
      refute_association_predicate @first_time_contributor_comment, nil, :first_time_contributor?
      refute_association_predicate @commenter_comment, nil, :first_time_contributor?
      refute_association_predicate @mannequin_comment, nil, :first_time_contributor?
    end
  end

  context "#to_sym" do
    test "returns a symbol representing the association" do
      assert_equal :owner, CommentAuthorAssociation.new(comment: @user_comment, viewer: nil).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @owner_comment, viewer: nil).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @member_comment, viewer: nil).to_sym
      assert_equal :collaborator, CommentAuthorAssociation.new(comment: @collaborator_comment, viewer: nil).to_sym
      assert_equal :contributor, CommentAuthorAssociation.new(comment: @contributor_comment, viewer: nil).to_sym
      assert_equal :mannequin, CommentAuthorAssociation.new(comment: @mannequin_comment, viewer: nil).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @first_time_contributor_comment, viewer: nil).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @commenter_comment, viewer: nil).to_sym
    end

    test "does not expose private organization members" do
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @owner).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @private_owner).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @member).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @private_member).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @owner).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @private_owner).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @member).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @private_member).to_sym

      assert_equal :none, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: nil).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @collaborator).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @contributor).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @first_time_contributor).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @commenter).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @mannequin).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: nil).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @collaborator).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @contributor).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @first_time_contributor).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @commenter).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @mannequin).to_sym
    end
  end
end

class CommentAuthorAssociationForAPullRequestReviewCommentTest < GitHub::TestCase
  fixtures do
    setup_fixture_repo_and_users

    @owner_comment = create(:pull_request_review_comment, {
      user: @owner,
      pull_request: @pull_request,
      pull_request_review: create(:pull_request_review, {
        user: @owner,
        pull_request: @pull_request,
      }),
    })

    @private_owner_comment = create(:pull_request_review_comment, {
      user: @private_owner,
      pull_request: @pull_request,
      pull_request_review: create(:pull_request_review, {
        user: @private_owner,
        pull_request: @pull_request,
      }),
    })

    @member_comment = create(:pull_request_review_comment, {
      user: @member,
      pull_request: @pull_request,
      pull_request_review: create(:pull_request_review, {
        user: @member,
        pull_request: @pull_request,
      }),
    })

    @private_member_comment = create(:pull_request_review_comment, {
      user: @private_member,
      pull_request: @pull_request,
      pull_request_review: create(:pull_request_review, {
        user: @private_member,
        pull_request: @pull_request,
      }),
    })

    @collaborator_comment = create(:pull_request_review_comment, {
      user: @collaborator,
      pull_request: @pull_request,
      pull_request_review: create(:pull_request_review, {
        user: @collaborator,
        pull_request: @pull_request,
      }),
    })

    @commenter_comment = create(:pull_request_review_comment, {
      user: @commenter,
      pull_request: @pull_request,
      pull_request_review: create(:pull_request_review, {
        user: @commenter,
        pull_request: @pull_request,
      }),
    })

    @contributor_comment = create(:pull_request_review_comment, {
      user: @contributor,
      pull_request: @pull_request,
      pull_request_review: create(:pull_request_review, {
        user: @contributor,
        pull_request: @pull_request,
      }),
    })

    @first_time_contributor_comment = create(:pull_request_review_comment, {
      user: @first_time_contributor,
      pull_request: @pull_request,
      pull_request_review: create(:pull_request_review, {
        user: @first_time_contributor,
        pull_request: @pull_request,
      }),
    })

    @mannequin_comment = create(:pull_request_review_comment, {
      user: @mannequin,
      pull_request: @pull_request,
      pull_request_review: create(:pull_request_review, {
        user: @mannequin,
        pull_request: @pull_request,
      }),
    })

    @user_comment = create(:pull_request_review_comment, {
      user: @user,
      pull_request: @user_pull_request,
      pull_request_review: create(:pull_request_review, {
        user: @user,
        pull_request: @user_pull_request,
      }),
    })
  end

  include CommentAuthorAssociationTestHelper

  context "#owner?" do
    test "returns true if the comment author is a owner of the repo" do
      assert_association_predicate @user_comment, nil, :owner?

      refute_association_predicate @owner_comment, nil, :owner?
      refute_association_predicate @member_comment, nil, :owner?
      refute_association_predicate @collaborator_comment, nil, :owner?
      refute_association_predicate @contributor_comment, nil, :owner?
      refute_association_predicate @first_time_contributor_comment, nil, :owner?
      refute_association_predicate @commenter_comment, nil, :owner?
      refute_association_predicate @mannequin_comment, nil, :owner?
    end
  end

  context "#member?" do
    test "returns true if the comment author is a member of the repo's organization" do
      assert_association_predicate @member_comment, nil, :member?
      assert_association_predicate @owner_comment, nil, :member?

      refute_association_predicate @collaborator_comment, nil, :member?
      refute_association_predicate @contributor_comment, nil, :member?
      refute_association_predicate @first_time_contributor_comment, nil, :member?
      refute_association_predicate @commenter_comment, nil, :member?
      refute_association_predicate @mannequin_comment, nil, :member?
    end

    test "does not expose private organization members" do
      assert_association_predicate @private_member_comment, @owner, :member?
      assert_association_predicate @private_member_comment, @private_owner, :member?
      assert_association_predicate @private_member_comment, @member, :member?
      assert_association_predicate @private_member_comment, @private_member, :member?
      assert_association_predicate @private_owner_comment, @owner, :member?
      assert_association_predicate @private_owner_comment, @private_owner, :member?
      assert_association_predicate @private_owner_comment, @member, :member?
      assert_association_predicate @private_owner_comment, @private_member, :member?

      refute_association_predicate @private_owner_comment, nil, :member?
      refute_association_predicate @private_owner_comment, @collaborator, :member?
      refute_association_predicate @private_owner_comment, @contributor, :member?
      refute_association_predicate @private_owner_comment, @first_time_contributor, :member?
      refute_association_predicate @private_owner_comment, @commenter, :member?
      refute_association_predicate @private_owner_comment, @mannequin, :member?
      refute_association_predicate @private_member_comment, nil, :member?
      refute_association_predicate @private_member_comment, @collaborator, :member?
      refute_association_predicate @private_member_comment, @contributor, :member?
      refute_association_predicate @private_member_comment, @first_time_contributor, :member?
      refute_association_predicate @private_member_comment, @commenter, :member?
      refute_association_predicate @private_member_comment, @mannequin, :member?
    end
  end

  context "#collaborator?" do
    test "returns true if the comment author is a direct collaborator of the repo" do
      assert_association_predicate @collaborator_comment, nil, :collaborator?

      refute_association_predicate @owner_comment, nil, :collaborator?
      refute_association_predicate @member_comment, nil, :collaborator?
      refute_association_predicate @contributor_comment, nil, :collaborator?
      refute_association_predicate @first_time_contributor_comment, nil, :collaborator?
      refute_association_predicate @commenter_comment, nil, :collaborator?
      refute_association_predicate @mannequin_comment, nil, :collaborator?
    end
  end

  context "#contributor?" do
    test "returns true if the comment author is a contributor of the repo" do
      assert_association_predicate @contributor_comment, nil, :contributor?

      refute_association_predicate @owner_comment, nil, :contributor?
      refute_association_predicate @member_comment, nil, :contributor?
      refute_association_predicate @collaborator_comment, nil, :contributor?
      refute_association_predicate @first_time_contributor_comment, nil, :contributor?
      refute_association_predicate @commenter_comment, nil, :contributor?
      refute_association_predicate @mannequin_comment, nil, :contributor?
    end
  end

  context "#first_time_contributor?" do
    test "returns false" do
      refute_association_predicate @owner_comment, nil, :first_time_contributor?
      refute_association_predicate @member_comment, nil, :first_time_contributor?
      refute_association_predicate @collaborator_comment, nil, :first_time_contributor?
      refute_association_predicate @contributor_comment, nil, :first_time_contributor?
      refute_association_predicate @first_time_contributor_comment, nil, :first_time_contributor?
      refute_association_predicate @commenter_comment, nil, :first_time_contributor?
      refute_association_predicate @mannequin_comment, nil, :first_time_contributor?
    end
  end

  context "#to_sym" do
    test "returns a symbol representing the association" do
      assert_equal :owner, CommentAuthorAssociation.new(comment: @user_comment, viewer: nil).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @owner_comment, viewer: nil).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @member_comment, viewer: nil).to_sym
      assert_equal :collaborator, CommentAuthorAssociation.new(comment: @collaborator_comment, viewer: nil).to_sym
      assert_equal :contributor, CommentAuthorAssociation.new(comment: @contributor_comment, viewer: nil).to_sym
      assert_equal :mannequin, CommentAuthorAssociation.new(comment: @mannequin_comment, viewer: nil).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @first_time_contributor_comment, viewer: nil).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @commenter_comment, viewer: nil).to_sym
    end

    test "does not expose private organization members" do
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @owner).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @private_owner).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @member).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @private_member).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @owner).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @private_owner).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @member).to_sym
      assert_equal :member, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @private_member).to_sym

      assert_equal :none, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: nil).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @collaborator).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @contributor).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @first_time_contributor).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @commenter).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_member_comment, viewer: @mannequin).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: nil).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @collaborator).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @contributor).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @first_time_contributor).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @commenter).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @private_owner_comment, viewer: @mannequin).to_sym
    end
  end
end

class CommentAuthorAssociationForAGistCommentTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @commenter = create(:user)

    @gist = GistHelpers.generate(contents: [
      { name: "1", value: "random content" },
    ], user: @owner)

    @owner_comment = @gist.comments.create(body: "Comment by owner", user: @owner)
    @commenter_comment = @gist.comments.create(body: "Comment by user", user: @commenter)
  end

  include CommentAuthorAssociationTestHelper

  context "#member?" do
    test "returns false" do
      refute_association_predicate @owner_comment, nil, :member?
      refute_association_predicate @commenter_comment, nil, :member?

      refute_association_predicate @owner_comment, @owner, :member?
      refute_association_predicate @commenter_comment, @owner, :member?

      refute_association_predicate @owner_comment, @commenter, :member?
      refute_association_predicate @commenter_comment, @commenter, :member?
    end
  end

  context "#owner?" do
    test "returns whether the comment author is also the Gist owner" do
      assert_association_predicate @owner_comment, nil, :owner?
      refute_association_predicate @commenter_comment, nil, :owner?

      assert_association_predicate @owner_comment, @owner, :owner?
      refute_association_predicate @commenter_comment, @owner, :owner?

      assert_association_predicate @owner_comment, @commenter, :owner?
      refute_association_predicate @commenter_comment, @commenter, :owner?
    end
  end

  context "#collaborator?" do
    test "returns false" do
      refute_association_predicate @owner_comment, nil, :collaborator?
      refute_association_predicate @commenter_comment, nil, :collaborator?

      refute_association_predicate @owner_comment, @owner, :collaborator?
      refute_association_predicate @commenter_comment, @owner, :collaborator?

      refute_association_predicate @owner_comment, @commenter, :collaborator?
      refute_association_predicate @commenter_comment, @commenter, :collaborator?
    end
  end

  context "#contributor?" do
    test "returns false" do
      refute_association_predicate @owner_comment, nil, :contributor?
      refute_association_predicate @commenter_comment, nil, :contributor?

      refute_association_predicate @owner_comment, @owner, :contributor?
      refute_association_predicate @commenter_comment, @owner, :contributor?

      refute_association_predicate @owner_comment, @commenter, :contributor?
      refute_association_predicate @commenter_comment, @commenter, :contributor?
    end
  end

  context "#first_time_contributor?" do
    test "returns false" do
      refute_association_predicate @owner_comment, nil, :first_time_contributor?
      refute_association_predicate @commenter_comment, nil, :first_time_contributor?

      refute_association_predicate @owner_comment, @owner, :first_time_contributor?
      refute_association_predicate @commenter_comment, @owner, :first_time_contributor?

      refute_association_predicate @owner_comment, @commenter, :first_time_contributor?
      refute_association_predicate @commenter_comment, @commenter, :first_time_contributor?
    end
  end

  context "#to_sym" do
    test "returns a symbol representing the association" do
      assert_equal :owner, CommentAuthorAssociation.new(comment: @owner_comment, viewer: nil).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @commenter_comment, viewer: nil).to_sym

      assert_equal :owner, CommentAuthorAssociation.new(comment: @owner_comment, viewer: @owner).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @commenter_comment, viewer: @owner).to_sym

      assert_equal :owner, CommentAuthorAssociation.new(comment: @owner_comment, viewer: @commenter).to_sym
      assert_equal :none, CommentAuthorAssociation.new(comment: @commenter_comment, viewer: @commenter).to_sym
    end
  end
end

class CommentAuthorAssociationForOrganizationWithInternalRepositoryTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, login: "owner")
    @org_member = create(:user)

    @business = create(:business)
    @org = create(:organization, admin: @owner, business: @business)

    @org.add_member(@org_member)

    @org_internal_repo = create(:internal_repository, owner: @org)
    @org_internal_issue = create(:issue, repository: @org_internal_repo, user: @owner)

    @org_private_repo = create(:private_repository, owner: @org)
    @org_private_issue = create(:issue, repository: @org_private_repo, user: @owner)

    @owner_comment = create(:issue_comment, user: @owner, issue: @org_internal_issue)
    @private_owner_comment = create(:issue_comment, user: @owner, issue: @org_private_issue)

    @member_comment = create(:issue_comment, user: @org_member, issue: @org_internal_issue)
  end

  include CommentAuthorAssociationTestHelper

  context "#member?" do
    test "returns true if the comment author is a member of the organization", feature_enabled: :author_association_internal_repository do
      assert_association_predicate @owner_comment, @owner, :member?
      assert_association_predicate @owner_comment, @org_member, :member?

      assert_association_predicate @member_comment, @owner, :member?
      assert_association_predicate @member_comment, @org_member, :member?

      refute_association_predicate @private_owner_comment, @org_member, :member?
    end
  end
end
