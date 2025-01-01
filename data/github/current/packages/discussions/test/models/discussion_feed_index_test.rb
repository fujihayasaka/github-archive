# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionIndexFeedTest < GitHub::TestCase
  include GitHub::DiscussionsComponentTestHelpers

  fixtures do
    @verified_user = create(:verified_user)

    @repo_owner = create(:user, :sponsorable)
    @public_repo = create(:repository, owner: @repo_owner, has_discussions: true)
    @category = create(:discussion_category, repository: @public_repo)
    @public_discussion = create(
      :discussion,
      :question,
      repository: @public_repo,
      category: @category,
    )

    @org = create(:business_plus_organization, :sponsorable)
    @org_repo = create(:repository, owner: @org, has_discussions: true)

    @rando_reader = create(:verified_user)
    @repo_reader = create(:verified_user)
    @org_repo.add_member(@repo_reader, action: :read)

    @repo_triager = create(:verified_user)
    @org_repo.add_member(@repo_triager, action: :triage)

    @repo_maintainer = create(:verified_user)
    @org_repo.add_member(@repo_maintainer, action: :maintain)

    @repo_writer = create(:verified_user)
    @org_repo.add_member(@repo_writer, action: :write)

    @repo_admin = create(:verified_user)
    @org_repo.add_member(@repo_admin, action: :admin)
  end

  context "#action_or_role_level_for" do
    test "returns :write when author has write access to the repository" do
      discussion = create(:discussion, repository: @org_repo, user: @repo_writer)
      feed = create_discussion_feed(@org_repo, [discussion], nil)

      assert_equal :write, feed.action_or_role_level_for(discussion)
    end

    test "returns :triage when author has triage access to the repository" do
      discussion = create(:discussion, repository: @org_repo, user: @repo_triager)
      feed = create_discussion_feed(@org_repo, [discussion], nil)

      assert_equal :triage, feed.action_or_role_level_for(discussion)
    end

    test "returns :admin when author is a repo admin" do
      discussion = create(:discussion, repository: @org_repo, user: @repo_admin)
      feed = create_discussion_feed(@org_repo, [discussion], nil)

      assert_equal :admin, feed.action_or_role_level_for(discussion)
    end

    test "returns :maintain when author is a repo maintainer" do
      discussion = create(:discussion, repository: @org_repo, user: @repo_maintainer)
      feed = create_discussion_feed(@org_repo, [discussion], nil)

      assert_equal :maintain, feed.action_or_role_level_for(discussion)
    end

    test "returns :read for author with no relation to the repository who has read access" do
      discussion = create(:discussion, repository: @org_repo, user: @repo_reader)
      feed = create_discussion_feed(@org_repo, [discussion], nil)

      assert_equal :read, feed.action_or_role_level_for(discussion)
    end
  end

  context "#body_html_for" do
    test "returns discussion body HTML" do
      discussion = create(:discussion, body: "This is the body")
      feed = create_discussion_feed(@public_repo, [discussion], nil)

      assert_equal "<p dir=\"auto\">This is the body</p>", feed.body_html_for(discussion)
    end
  end

  context "#fast_reactions_for" do
    test "returns reactions for discussion" do
      create(:discussion_reaction, discussion: @public_discussion, content: "smile")
      create(:discussion_reaction, discussion: @public_discussion, content: "heart")
      create(:discussion_reaction, discussion: @public_discussion, content: "heart")

      feed = create_discussion_feed(@public_repo, [@public_discussion], nil)
      assert_equal feed.fast_reactions_for(@public_discussion), { "heart" => 2, "smile" => 1 }
    end
  end

  context "#repo_name" do
    test "returns repo name" do
      feed = create_discussion_feed(@public_repo, [@public_discussion], nil)
      assert_equal @public_repo.name, feed.repo_name
    end
  end

  context "#repo_owner_login" do
    test "returns repo owner login" do
      feed = create_discussion_feed(@public_repo, [@public_discussion], nil)
      assert_equal @repo_owner.login, feed.repo_owner_login
    end
  end
end
