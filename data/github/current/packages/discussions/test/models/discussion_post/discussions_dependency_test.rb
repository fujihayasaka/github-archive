# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionPost::DiscussionsDependencyTest < GitHub::TestCase
  fixtures do
    team = create(:team, privacy: :closed)
    @team_member = create(:user, :verified)
    team.add_member(@team_member)
    @org = team.organization
    @org_member = create(:verified_user)
    @org.add_member(@org_member)
    @post = create(:discussion_post, team: team)
  end

  context "#can_be_transferred_to_discussion?" do
    test "returns true if repo has discussions and owned by team org and actor is on team" do
      repo = create(:repository, :minimal, owner: @org, has_discussions: true)
      assert @post.can_be_transferred_to_discussion?(@team_member, repo)
    end

    test "returns true if repo doesn't have discussions but actor has write access to repo" do
      repo = create(:repository, :minimal, owner: @org, has_discussions: false)
      repo.add_member(@team_member, action: :write)
      assert @post.can_be_transferred_to_discussion?(@team_member, repo)
    end

    test "returns true if actor is an admin of the organization" do
      org_admin = create(:verified_user)
      @org.add_admin(org_admin)
      repo = create(:repository, :minimal, owner: @org, has_discussions: false)
      assert @post.can_be_transferred_to_discussion?(org_admin, repo)
    end

    test "returns false if target repo is not owned by team organization" do
      new_repo = create(:repository, :minimal)
      refute @post.can_be_transferred_to_discussion?(@team_member, new_repo)
    end

    test "returns false if repo doesn't have discussion on and actor only has read access on repo" do
      non_discussion_repo = create(:repository, :minimal, owner: @org, has_discussions: false)
      non_discussion_repo.add_member(@team_member, action: :read)
      refute @post.can_be_transferred_to_discussion?(@team_member, non_discussion_repo)
    end

    test "returns false if user is not on the team owning team discussion" do
      repo = create(:repository, :minimal, owner: @org, has_discussions: true)
      refute @post.can_be_transferred_to_discussion?(@org_member, repo)
    end

    test "returns false for nil actor" do
      repo = create(:repository, :minimal, owner: @org, has_discussions: true)
      refute @post.can_be_transferred_to_discussion?(nil, repo)
    end

    test "returns false for nil repo" do
      refute @post.can_be_transferred_to_discussion?(@team_member, nil)
    end
  end

  context "#mark_as_converted_to_discussion" do
    test "marks the post as converted to a discussion" do
      assert_nil @post.discussion
      discussion = create(:discussion, team_discussion: @post)
      assert @post.mark_as_converted_to_discussion
      @post.reload
      assert_equal discussion, @post.discussion
    end

    test "does not mark post as converted to discussion" do
      assert_nil @post.discussion
      refute @post.mark_as_converted_to_discussion
      @post.reload
      assert_nil @post.discussion
    end
  end
end
