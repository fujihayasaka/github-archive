# typed: true
# frozen_string_literal: true

require "test_helper"

class UserHovercardGlobalSubjectTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @anon = create(:user)
  end

  setup do
    @subject = UserHovercard::GlobalSubject.new
  end

  context "blocks context" do
    test "returns a context when the viewer has blocked the specified user" do
      @user.block(@anon)

      context = @subject.user_hovercard_context_for(@anon, viewer: @user,
        limit: :blocks)

      refute_nil context
      assert_equal "You have blocked this user", context.message
    end

    test "returns nil when the specified user has not been blocked" do
      context = @subject.user_hovercard_context_for(@anon, viewer: @user,
        limit: :blocks)
      assert_nil context
    end
  end

  context "your_sponsor context" do
    if GitHub.sponsors_enabled?
      test "returns a context for a user who is sponsoring the viewer" do
        sponsorship = create(:sponsorship)

        context = @subject.user_hovercard_context_for(sponsorship.sponsor,
          viewer: sponsorship.sponsorable, limit: :your_sponsor)

        refute_nil context
        refute_predicate context, :private_sponsor?
        assert_empty context.visible_related_org_sponsors
      end

      test "returns a context for a user who is privately sponsoring the viewer" do
        sponsorship = create(:sponsorship, :private)

        context = @subject.user_hovercard_context_for(sponsorship.sponsor,
          viewer: sponsorship.sponsorable, limit: :your_sponsor)

        refute_nil context
        assert_predicate context, :private_sponsor?
        assert_empty context.visible_related_org_sponsors
      end

      test "returns a context for a user whose org is sponsoring the viewer" do
        sponsorship = create(:sponsorship, :from_org)
        org_member = create(:user)
        org = sponsorship.sponsor
        org.add_member(org_member)
        org.publicize_member(org_member)

        context = @subject.user_hovercard_context_for(org_member, viewer: sponsorship.sponsorable,
          limit: :your_sponsor)

        refute_nil context
        refute_predicate context, :private_sponsor?
        assert_equal [org], context.visible_related_org_sponsors
      end

      test "prefers direct sponsorship when present over indirect sponsorships" do
        sponsorable = create(:user, :sponsorable)

        # Indirect sponsorship from org_member through org:
        sponsorship = create(:sponsorship, :from_org, sponsorable: sponsorable)
        org_member = create(:credit_card_user, plan_subscription: create(:billing_plan_subscription),
          plan: GitHub::Plan.free_with_addons)
        org = sponsorship.sponsor
        org.add_member(org_member)
        org.publicize_member(org_member)

        # Direct sponsorship from org_member:
        create(:sponsorship, sponsor: org_member, sponsorable: sponsorable)

        context = @subject.user_hovercard_context_for(org_member, viewer: sponsorable,
          limit: :your_sponsor)

        refute_nil context
        refute_predicate context, :private_sponsor?
        assert_empty context.visible_related_org_sponsors,
          "should not include indirect sponsor when a direct sponsorship exists"
      end

      test "returns nil when viewer is not sponsorable" do
        context = @subject.user_hovercard_context_for(@anon, viewer: @user, limit: :your_sponsor)
        assert_nil context
      end
    else
      test "returns nil when Sponsors is disabled" do
        sponsorship = create(:sponsorship)

        context = @subject.user_hovercard_context_for(sponsorship.sponsor,
          viewer: sponsorship.sponsorable, limit: :your_sponsor)

        assert_nil context
      end
    end
  end

  context "new_user context" do
    test "returns a status for a user that joined in the past month" do
      context = @subject.user_hovercard_context_for(@user, viewer: @user, limit: :new_user)

      assert_equal "Joined GitHub this month", context.message
    end

    test "returns no status for an existing user" do
      existing_user = create(:user, created_at: 1.year.ago)

      context = @subject.user_hovercard_context_for(existing_user, viewer: @user, limit: :new_user)

      assert_nil context
    end
  end

  context "organizations context" do
    test "returns nil if there are no visible organizations for the viewer" do
      org = create(:organization)
      org.add_member(@user)

      # Not visible to anon
      context = @subject.user_hovercard_context_for(@user, viewer: @anon, limit: :organizations)
      assert_nil context

      # Visible to self
      UserHovercard::Contexts::Organizations.expects(:new).once.with(user: @user, all: [org], related: [])
      @subject.user_hovercard_context_for(@user, viewer: @user, limit: :organizations)
    end

    test "returns nil if there is a subject but it has no organization" do
      repo = create(:repository)

      context = @subject.user_hovercard_context_for(@user, viewer: @user, limit: :organizations, descendant_subjects: [repo])

      assert_nil context
    end

    test "returns a context if there is a subject and it has an organization" do
      orgs = 2.times.map do
        create(:organization).tap do |org|
          org.add_member(@user)
          org.publicize_member(@user)
        end
      end

      relevant_org = orgs.first
      repo = create(:repository, owner: relevant_org)

      UserHovercard::Contexts::Organizations.expects(:new).once.with(user: @user, all: orgs, related: [relevant_org])
      @subject.user_hovercard_context_for(@user, viewer: @anon, limit: :organizations, descendant_subjects: [repo, relevant_org])
    end

    test "returns a context if there is NO subject (global context)" do
      org = create(:organization)
      org.add_member(@user)
      org.publicize_member(@user)

      UserHovercard::Contexts::Organizations.expects(:new).once.with(user: @user, all: [org], related: [])
      context = @subject.user_hovercard_context_for(@user, viewer: @anon, limit: :organizations)
    end
  end
end
