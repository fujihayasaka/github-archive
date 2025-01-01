# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorshipsLoaderTest < GitHub::TestCase
  fixtures do
    @sponsorable_user = create(:user, :sponsorable)
    @user_repo = create(:repository, owner: @sponsorable_user)
    @user_issue = create(:issue, repository: @user_repo, user: @sponsorable_user)

    @sponsorable_org = create(:organization, :sponsorable)
    @org_repo = create(:repository, owner: @sponsorable_org)
    @org_issue = create(:issue, repository: @org_repo, user: @sponsorable_org.admin)

    @random_user = create(:user)

    @user_public_sponsor = create(
      :credit_card_user,
      plan_subscription: create(:billing_plan_subscription),
      plan: GitHub::Plan.free_with_addons,
    )
    @org_public_sponsor = create(
      :credit_card_org,
      plan_subscription: create(:billing_plan_subscription),
      plan: GitHub::Plan.free_with_addons,
    )
    @user_private_sponsor = create(
      :credit_card_user,
      plan_subscription: create(:billing_plan_subscription),
      plan: GitHub::Plan.free_with_addons,
    )
    @org_private_sponsor = create(
      :credit_card_org,
      plan_subscription: create(:billing_plan_subscription),
      plan: GitHub::Plan.free_with_addons,
    )

    @user_to_user_public_sponsorship = create(:sponsorship, sponsor: @user_public_sponsor, sponsorable: @sponsorable_user)
    @user_to_org_public_sponsorship = create(:sponsorship, sponsor: @user_public_sponsor, sponsorable: @sponsorable_org)
    @org_to_org_public_sponsorship = create(:sponsorship, sponsor: @org_public_sponsor, sponsorable: @sponsorable_org)
    @org_to_user_public_sponsorship = create(:sponsorship, sponsor: @org_public_sponsor, sponsorable: @sponsorable_user)

    @user_to_user_private_sponsorship = create(:sponsorship, :private, sponsor: @user_private_sponsor, sponsorable: @sponsorable_user)
    @user_to_org_private_sponsorship = create(:sponsorship, :private, sponsor: @user_private_sponsor, sponsorable: @sponsorable_org)
    @org_to_org_private_sponsorship = create(:sponsorship, :private, sponsor: @org_private_sponsor, sponsorable: @sponsorable_org)
    @org_to_user_private_sponsorship = create(:sponsorship, :private, sponsor: @org_private_sponsor, sponsorable: @sponsorable_user)
  end

  if GitHub.sponsors_enabled?
    test "loads sponsors for when viewer is sponsored" do
      user_public_sponsor_comment = create(:issue_comment, user: @user_public_sponsor, issue: @user_issue, body: "test comment")
      private_public_sponsor_comment = create(:issue_comment, user: @user_private_sponsor, issue: @user_issue, body: "test comment")
      random_user_comment = create(:issue_comment, user: @random_user, issue: @user_issue, body: "test comment")

      @context = Issue::Adapter::Context.new(@user_issue, @user_repo, @sponsorable_user)

      assert_max_query_count(TestEnv.test_all_features? ? 10 : 9, ignore_feature_flags: true) do
        Issue::Loader::Sponsorships.load_for(
          @context,
          issue: @user_issue,
          issue_comments: [user_public_sponsor_comment, private_public_sponsor_comment, random_user_comment]
        )
      end

      sponsorship_hash = @context.author_to_repo_owner_sponsorships_by_author_id
      assert_equal @user_to_user_public_sponsorship, sponsorship_hash[@user_public_sponsor.id]
      assert_equal @user_to_user_private_sponsorship, sponsorship_hash[@user_private_sponsor.id]
      assert_nil sponsorship_hash[@sponsorable_user.id]
      assert_nil sponsorship_hash[@random_user.id]
    end

    test "empty sponsors for when viewer is not sponsored" do
      user_public_sponsor_comment = create(:issue_comment, user: @user_public_sponsor, issue: @user_issue, body: "test comment")
      org_public_sponsor_comment = create(:issue_comment, user: @org_public_sponsor, issue: @user_issue, body: "test comment")
      random_user_comment = create(:issue_comment, user: @random_user, issue: @user_issue, body: "test comment")

      @context = Issue::Adapter::Context.new(@user_issue, @user_repo, @random_user)

      assert_max_query_count(TestEnv.test_all_features? ? 10 : 9, ignore_feature_flags: true) do
        Issue::Loader::Sponsorships.load_for(
          @context,
          issue: @user_issue,
          issue_comments: [user_public_sponsor_comment, org_public_sponsor_comment, random_user_comment]
        )
      end

      sponsorship_hash = @context.author_to_repo_owner_sponsorships_by_author_id
      assert_equal @user_to_user_public_sponsorship, sponsorship_hash[@user_public_sponsor.id]
      assert_equal @org_to_user_public_sponsorship, sponsorship_hash[@org_public_sponsor.id]
      assert_nil sponsorship_hash[@sponsorable_user.id]
      assert_nil sponsorship_hash[@random_user.id]
    end

    test "loads sponsorships for when the sponsorable is a user and viewer is the sponsorable" do
      user_public_sponsor_comment = create(:issue_comment, user: @user_public_sponsor, issue: @user_issue, body: "test comment")
      org_public_sponsor_comment = create(:issue_comment, user: @org_public_sponsor, issue: @user_issue, body: "test comment")
      user_private_sponsor_comment = create(:issue_comment, user: @user_private_sponsor, issue: @user_issue, body: "test comment")
      org_private_sponsor_comment = create(:issue_comment, user: @org_private_sponsor, issue: @user_issue, body: "test comment")
      random_comment = create(:issue_comment, user: @random_user, issue: @user_issue, body: "test comment")

      @context = Issue::Adapter::Context.new(@user_issue, @user_repo, @sponsorable_user)

      assert_max_query_count(TestEnv.test_all_features? ? 10 : 9, ignore_feature_flags: true) do
        Issue::Loader::Sponsorships.load_for(
          @context,
          issue: @user_issue,
          issue_comments: [user_public_sponsor_comment, org_public_sponsor_comment, user_private_sponsor_comment, org_private_sponsor_comment, random_comment]
        )
      end

      sponsorship_hash = @context.author_to_repo_owner_sponsorships_by_author_id
      assert_equal @user_to_user_public_sponsorship, sponsorship_hash[@user_public_sponsor.id]
      assert_equal @org_to_user_public_sponsorship, sponsorship_hash[@org_public_sponsor.id]
      assert_equal @user_to_user_private_sponsorship, sponsorship_hash[@user_private_sponsor.id]
      assert_equal @org_to_user_private_sponsorship, sponsorship_hash[@org_private_sponsor.id]

      assert_nil sponsorship_hash[@sponsorable_user.id]
      assert_nil sponsorship_hash[@random_user.id]
    end

    test "loads sponsorships for when the sponsorable is a user and viewer is a user private sponsor" do
      user_public_sponsor_comment = create(:issue_comment, user: @user_public_sponsor, issue: @user_issue, body: "test comment")
      org_public_sponsor_comment = create(:issue_comment, user: @org_public_sponsor, issue: @user_issue, body: "test comment")
      user_private_sponsor_comment = create(:issue_comment, user: @user_private_sponsor, issue: @user_issue, body: "test comment")
      org_private_sponsor_comment = create(:issue_comment, user: @org_private_sponsor, issue: @user_issue, body: "test comment")
      random_comment = create(:issue_comment, user: @random_user, issue: @user_issue, body: "test comment")

      @context = Issue::Adapter::Context.new(@user_issue, @user_repo, @user_private_sponsor)

      assert_max_query_count(TestEnv.test_all_features? ? 10 : 9, ignore_feature_flags: true) do
        Issue::Loader::Sponsorships.load_for(
          @context,
          issue: @user_issue,
          issue_comments: [user_public_sponsor_comment, org_public_sponsor_comment, user_private_sponsor_comment, org_private_sponsor_comment, random_comment]
        )
      end

      sponsorship_hash = @context.author_to_repo_owner_sponsorships_by_author_id
      assert_equal @user_to_user_public_sponsorship, sponsorship_hash[@user_public_sponsor.id]
      assert_equal @org_to_user_public_sponsorship, sponsorship_hash[@org_public_sponsor.id]
      assert_equal @user_to_user_private_sponsorship, sponsorship_hash[@user_private_sponsor.id]

      assert_nil sponsorship_hash[@org_private_sponsor.id]
      assert_nil sponsorship_hash[@sponsorable_user.id]
      assert_nil sponsorship_hash[@random_user.id]
    end

    test "loads sponsorships for when the sponsorable is a user and viewer is a random user" do
      user_public_sponsor_comment = create(:issue_comment, user: @user_public_sponsor, issue: @user_issue, body: "test comment")
      org_public_sponsor_comment = create(:issue_comment, user: @org_public_sponsor, issue: @user_issue, body: "test comment")
      user_private_sponsor_comment = create(:issue_comment, user: @user_private_sponsor, issue: @user_issue, body: "test comment")
      org_private_sponsor_comment = create(:issue_comment, user: @org_private_sponsor, issue: @user_issue, body: "test comment")
      random_comment = create(:issue_comment, user: @random_user, issue: @user_issue, body: "test comment")

      @context = Issue::Adapter::Context.new(@user_issue, @user_repo, @random_user)

      assert_max_query_count(TestEnv.test_all_features? ? 10 : 9, ignore_feature_flags: true) do
        Issue::Loader::Sponsorships.load_for(
          @context,
          issue: @user_issue,
          issue_comments: [user_public_sponsor_comment, org_public_sponsor_comment, user_private_sponsor_comment, org_private_sponsor_comment, random_comment]
        )
      end

      sponsorship_hash = @context.author_to_repo_owner_sponsorships_by_author_id
      assert_equal @user_to_user_public_sponsorship, sponsorship_hash[@user_public_sponsor.id]
      assert_equal @org_to_user_public_sponsorship, sponsorship_hash[@org_public_sponsor.id]

      assert_nil sponsorship_hash[@user_private_sponsor.id]
      assert_nil sponsorship_hash[@org_private_sponsor.id]
      assert_nil sponsorship_hash[@sponsorable_user.id]
      assert_nil sponsorship_hash[@random_user.id]
    end

    test "loads sponsorships for when the sponsorable is an org and and viewer is the sponsorable" do
      user_public_sponsor_comment = create(:issue_comment, user: @user_public_sponsor, issue: @org_issue, body: "test comment")
      org_public_sponsor_comment = create(:issue_comment, user: @org_public_sponsor, issue: @org_issue, body: "test comment")
      user_private_sponsor_comment = create(:issue_comment, user: @user_private_sponsor, issue: @org_issue, body: "test comment")
      org_private_sponsor_comment = create(:issue_comment, user: @org_private_sponsor, issue: @org_issue, body: "test comment")
      random_comment = create(:issue_comment, user: @random_user, issue: @org_issue, body: "test comment")

      @context = Issue::Adapter::Context.new(@org_issue, @org_repo, @sponsorable_org)

      assert_max_query_count(TestEnv.test_all_features? ? 10 : 9, ignore_feature_flags: true) do
        Issue::Loader::Sponsorships.load_for(
          @context,
          issue: @org_issue,
          issue_comments: [user_public_sponsor_comment, org_public_sponsor_comment, user_private_sponsor_comment, org_private_sponsor_comment, random_comment]
        )
      end

      sponsorship_hash = @context.author_to_repo_owner_sponsorships_by_author_id
      assert_equal @user_to_org_public_sponsorship, sponsorship_hash[@user_public_sponsor.id]
      assert_equal @org_to_org_public_sponsorship, sponsorship_hash[@org_public_sponsor.id]
      assert_equal @user_to_org_private_sponsorship, sponsorship_hash[@user_private_sponsor.id]
      assert_equal @org_to_org_private_sponsorship, sponsorship_hash[@org_private_sponsor.id]

      assert_nil sponsorship_hash[@sponsorable_org.admin.id]
      assert_nil sponsorship_hash[@random_user.id]
    end

    test "loads sponsorships for when the sponsorable is an org and and viewer is an org private sponsor" do
      user_public_sponsor_comment = create(:issue_comment, user: @user_public_sponsor, issue: @org_issue, body: "test comment")
      org_public_sponsor_comment = create(:issue_comment, user: @org_public_sponsor, issue: @org_issue, body: "test comment")
      user_private_sponsor_comment = create(:issue_comment, user: @user_private_sponsor, issue: @org_issue, body: "test comment")
      org_private_sponsor_comment = create(:issue_comment, user: @org_private_sponsor, issue: @org_issue, body: "test comment")
      random_comment = create(:issue_comment, user: @random_user, issue: @org_issue, body: "test comment")

      @context = Issue::Adapter::Context.new(@org_issue, @org_repo, @org_private_sponsor.admin)

      assert_max_query_count(TestEnv.test_all_features? ? 11 : 10, ignore_feature_flags: true) do
        Issue::Loader::Sponsorships.load_for(
          @context,
          issue: @org_issue,
          issue_comments: [user_public_sponsor_comment, org_public_sponsor_comment, user_private_sponsor_comment, org_private_sponsor_comment, random_comment]
        )
      end

      sponsorship_hash = @context.author_to_repo_owner_sponsorships_by_author_id
      assert_equal @user_to_org_public_sponsorship, sponsorship_hash[@user_public_sponsor.id]
      assert_equal @org_to_org_public_sponsorship, sponsorship_hash[@org_public_sponsor.id]
      assert_equal @org_to_org_private_sponsorship, sponsorship_hash[@org_private_sponsor.id]

      assert_nil sponsorship_hash[@user_private_sponsor.id]
      assert_nil sponsorship_hash[@sponsorable_org.admin.id]
      assert_nil sponsorship_hash[@random_user.id]
    end

    test "loads sponsorships for when the sponsorable is an org and viewer is a random user" do
      user_public_sponsor_comment = create(:issue_comment, user: @user_public_sponsor, issue: @org_issue, body: "test comment")
      org_public_sponsor_comment = create(:issue_comment, user: @org_public_sponsor, issue: @org_issue, body: "test comment")
      user_private_sponsor_comment = create(:issue_comment, user: @user_private_sponsor, issue: @org_issue, body: "test comment")
      org_private_sponsor_comment = create(:issue_comment, user: @org_private_sponsor, issue: @org_issue, body: "test comment")
      random_comment = create(:issue_comment, user: @random_user, issue: @org_issue, body: "test comment")

      @context = Issue::Adapter::Context.new(@org_issue, @org_repo, @random_user)

      assert_max_query_count(TestEnv.test_all_features? ? 10 : 9, ignore_feature_flags: true) do
        Issue::Loader::Sponsorships.load_for(
          @context,
          issue: @org_issue,
          issue_comments: [user_public_sponsor_comment, org_public_sponsor_comment, user_private_sponsor_comment, org_private_sponsor_comment, random_comment]
        )
      end

      sponsorship_hash = @context.author_to_repo_owner_sponsorships_by_author_id
      assert_equal @user_to_org_public_sponsorship, sponsorship_hash[@user_public_sponsor.id]
      assert_equal @org_to_org_public_sponsorship, sponsorship_hash[@org_public_sponsor.id]

      assert_nil sponsorship_hash[@user_private_sponsor.id]
      assert_nil sponsorship_hash[@org_private_sponsor.id]
      assert_nil sponsorship_hash[@sponsorable_org.admin.id]
      assert_nil sponsorship_hash[@random_user.id]
    end
  end
end
