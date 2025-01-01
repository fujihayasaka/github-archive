# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationHovercardDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @anon = create(:user)

    @org = create(:organization)
    @secret_team = create(:team, organization: @org, privacy: :secret)
    @closed_team = create(:team, organization: @org, privacy: :closed)

    @repo = create(:repository, owner: @org, from_example: :pull_request_source)
  end

  context "blocks context" do
    test "returns nil when the organization is not blocking the user" do
      @org.add_admin(@user)
      context = @org.user_hovercard_context_for(@anon, viewer: @user, limit: :blocks)
      assert_nil context
    end

    test "returns nil if the organization if blocking but the user is not an org admin" do
      @org.add_member(@user)
      @org.block(@anon)

      context = @org.user_hovercard_context_for(@anon, viewer: @user, limit: :blocks)

      assert_nil context
    end

    test "returns a context if the organization if blocking and the user is an org admin" do
      @org.add_admin(@user)
      @org.block(@anon)

      context = @org.user_hovercard_context_for(@anon, viewer: @user, limit: :blocks)

      refute_nil context
      assert_equal "The #{@org} organization has blocked this user", context.message
    end

    test "returns a context if the organization and viewer are both blocking and the user is an org admin" do
      @org.add_admin(@user)
      @org.block(@anon)
      @user.block(@anon)

      context = @org.user_hovercard_context_for(@anon, viewer: @user, limit: :blocks)

      refute_nil context
      assert_equal "You and the #{@org} organization have blocked this user", context.message
    end
  end

  context "user_hovercard_parent" do
    test "returns nil" do
      assert_nil @org.user_hovercard_parent
    end
  end

  context "teams context" do
    test "returns a status if the user is a member of a team" do
      @closed_team.add_member(@user)

      context = @org.user_hovercard_context_for(@user, viewer: @user, limit: :teams)

      assert_equal "Member of @#{@closed_team.combined_slug}", context.message

      # Returns nothing if the viewer is not a member of the organization
      assert_nil @org.user_hovercard_context_for(@user, viewer: @anon, limit: :teams)
      assert_nil @org.user_hovercard_context_for(@user, viewer: nil, limit: :teams)
    end

    test "returns a status if the user is a member of a secret team that the viewer is also a member of" do
      @secret_team.add_member(@user)
      @secret_team.add_member(@anon)

      context = @org.user_hovercard_context_for(@user, viewer: @anon, limit: :teams)

      assert_equal "Member of @#{@secret_team.combined_slug}", context.message
    end

    test "returns a status that includes visible teams" do
      normal_team = create(:team, organization: @org, privacy: :closed)
      normal_team.add_member(@user)
      important_team = create(:team, organization: @org, privacy: :closed)
      important_team.add_member(@user)
      important_team.add_repository(@repo, :push)

      # Create a repo with a PR
      pull_request = PullRequest.create_for(@repo, title: "hello", user: @user, base: "master", head: "topic-partial-merge")

      # Ensure that the context shows the reviewer first (and only) in the teams list
      subjects = [pull_request]
      context = @org.user_hovercard_context_for(@user, viewer: @user, descendant_subjects: subjects, limit: :teams)

      assert_equal "Member of @#{important_team.combined_slug} and @#{normal_team.combined_slug}", context.message
    end

    test "does not return a team that the user cannot see" do
      # Anon is in the org but cannot see the secret team
      @secret_team.add_member(@user)
      @secret_team.add_repository(@repo, :push)
      @closed_team.add_member(@user)
      @org.add_member(@anon)

      # Create a repo with a PR and mention a secret team
      pull_request = PullRequest.create_for(@repo, title: "hello", user: @user, base: "master", head: "topic-partial-merge")

      # Ensure that the context shows only the team the viewer can see
      subjects = [pull_request]
      context = @org.user_hovercard_context_for(@user, viewer: @anon, descendant_subjects: subjects, limit: :teams)

      assert_equal "Member of @#{@closed_team.combined_slug}", context.message
    end

    test "returns no status if the user is a member of a secret team that the viewer is not a member of" do
      @secret_team.add_member(@user)
      @org.add_member(@anon)

      context = @org.user_hovercard_context_for(@user, viewer: @anon, limit: :teams)

      assert_nil context
    end

    test "returns nil if the user is not a member of the org" do
      @closed_team.add_member(@user)

      context = @org.user_hovercard_context_for(@anon, viewer: @user, limit: :teams)

      assert_nil context
    end

    test "returns nil if the user's profile is private for the viewer" do
      viewer = create(:user)
      normal_team = create(:team, organization: @org, privacy: :closed)
      normal_team.add_member(@user)
      normal_team.add_member(viewer)

      @user.update!(private_profile: true)

      context = @org.user_hovercard_context_for(@user, viewer: viewer, limit: :teams)

      assert_nil context
    end
  end
end
