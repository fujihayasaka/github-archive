# typed: true
# frozen_string_literal: true

require "test_helper"

class User::SpamminessTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @free_user = create(:user, login: "free-user", email: "free-user@example.com")
    @spammer = create(:user, login: "spammer", spammy: true)
    @abuse_user = create :user, last_ip: "127.0.0.1"

    @paid_user = create(:user, login: "paid-user", email: "paid-user@example.com", plan: "medium")
    create(:billing_transaction, :zuora, user: @paid_user, asset_packs_total: 5)

    unless GitHub.enterprise?
      enterprise = create(:business, :enterprise_managed)
      create(:business_saml_provider, business: enterprise)
      @managed_user = create :emu, business: enterprise, login: "monalisa", email: "monalisa@github.com"
    end

    @staffer = create(:staff_admin_user, login: "staffer", plan: "medium", email: "staffer@example.com")
    @paid_org = create(:organization, admin: @staffer, plan: GitHub::Plan.non_free_org_plans.first.name)
    @paid_org_team = create(:team, organization: @paid_org)
  end

  setup do
    skip "spamminess checks are not enabled on Enterprise" unless GitHub.spamminess_check_enabled?
    @old_suspended_users_visible = GitHub.suspended_users_visible?
    GitHub.suspended_users_visible = false
    GitHub.preview_features_enabled = true
    Failbot.reports.clear
    GitHub.cache.allow = nil
    GitHub.cache.clear
  end

  teardown do
    GitHub.suspended_users_visible = @old_suspended_users_visible
  end

  def create_user(options = {})
    User.create({
      login: "quire",
      email: "quire@example.com",
      password: GitHub.default_password,
    }.merge(options))
  end

  context "#assignable_to_issues?" do
    test "returns false for spammy user" do
      user = create(:user)
      user.mark_as_spammy(reason: "some reason", actor: @staffer)
      assert_predicate user, :spammy?
      refute_predicate user, :assignable_to_issues?
    end
  end

  test "paid users can be spammy, too" do
    @paid_user.spammy = true
    refute @paid_user.never_spammy?
    assert @paid_user.spammy
    assert @paid_user.spammy?

    @paid_user.save!
    refute @paid_user.never_spammy?
    assert @paid_user.spammy
    assert @paid_user.spammy?
  end

  test "some phrases flag for spam" do
    user = create_user
    user.profile_location = "buy drugs online!"
    user.profile_blog = "http://github.com"
    perform_enqueued_jobs(only: CheckForSpamJob) do
      user.save
    end
    assert user.reload.spammy?
  end

  test "paying users are queued, not flagged, for spammy profiles" do
    @paid_user.profile_name = "I swear I have a prescription for these drugs"
    @paid_user.profile_blog = "http://github.com"
    reason = "totes spammy for sure"
    GitHub::SpamChecker.stubs(:test_profile).returns(reason)
    perform_enqueued_jobs(only: CheckForSpamJob) do
      @paid_user.save
    end
    refute @paid_user.reload.spammy?
    add_to_queue_message = {
      account_global_relay_id: @paid_user.global_relay_id,
      additional_context: reason,
      queue_global_relay_id: SpamQueue::SUSPICIOUS_OLDER_ACCOUNTS_GLOBAL_RELAY_ID,
      origin: :RESQUE_CHECK_FOR_SPAM_PROFILE,
    }
    assert_hydro_published(add_to_queue_message, schema: "hamzo.v1.AddToQueue")
    assert_hydro_messages(count: 1, schema: "hamzo.v1.AddToQueue")
  end

  context "hide_from_user?" do
    test "hides spammy user from other regular users" do
      viewer = create(:user)
      assert create(:user, spammy: true).hide_from_user?(viewer)
    end

    test "hides spammy user from other nil (anonymous) user" do
      assert create(:user, spammy: true).hide_from_user?(nil)
    end

    test "doesn't hide spammy user from staff user" do
      refute create(:user, spammy: true).hide_from_user?(@staffer)
    end

    test "doesn't hide spammy org from org owner" do
      owner = create(:user)
      org = create(:organization, admin: owner)
      org.mark_as_spammy(reason: "So spammy")
      refute org.hide_from_user?(owner)
    end

    test "doesn't hide spammy org from org member" do
      org = create(:organization)
      org.mark_as_spammy(reason: "So spammy")
      member = create(:user)
      org.add_member member
      refute org.hide_from_user?(member)
    end

    test "doesn't hide spammy org from org billing manager" do
      owner = create(:user)
      org = create(:organization, admin: owner)
      org.mark_as_spammy(reason: "So spammy")
      manager = create(:user)
      org.billing.add_manager manager, actor: owner
      refute org.hide_from_user?(manager)
    end

    test "doesn't hide spammy user from themselves" do
      spammer = create(:user, spammy: true)
      assert !spammer.hide_from_user?(spammer)
    end

    test "hides a user who is both spammy and suspended even if 'suspended users are visible' flag is enabled" do
      GitHub.suspended_users_visible = true
      spammer = create(:suspended_user, spammy: true)
      assert spammer.hide_from_user?(nil)
    end
  end

  context "Spammy followers/followings" do
    test "doesn't change a legit users followers count when a spammer follows them" do
      user = create(:user)
      @spammer.follow(user)
      assert_equal 0, User.find(user.id).followers_count(viewer: nil)
    end

    test "doesn't change a legit users following count when they follow a spammer" do
      user = create(:user)
      user.follow(@spammer)
      assert_equal 0, User.find(user.id).following_count(viewer: nil)
    end

    test "hides spammy user following count" do
      user = create(:user)
      @spammer.follow(user)
      assert_equal 0, User.find(user.id).followers_count(viewer: nil)
      assert_equal 0, User.find(@spammer.id).following_count(viewer: nil)
    end
  end

  context "allowlisting" do
    test "hammy? returns true for an extended spammy_reason" do
      @free_user.spammy_reason = "Not spammy: for extended reasons and whatnot"
      assert @free_user.hammy?
    end

    test "hammy? returns false for a normal user" do
      refute @free_user.hammy?
    end

    test "hammy? users are never_spammy" do
      refute @free_user.never_spammy?
      @free_user.stubs(:hammy?).returns(true)
      assert @free_user.never_spammy?
    end
  end

  context "renaming a user" do
    test "spammy users can't rename" do
      assert @free_user.rename!("foo")

      refute @spammer.rename!("bar")
      assert @spammer.rename!("bar", actor: @staffer)
    end
  end

  context "can_be_flagged?" do
    test "returns true for paid users" do
      assert @paid_user.can_be_flagged?
    end

    test "returns true for users in a paid Organization" do
      @paid_org_team.add_member @free_user
      assert @free_user.can_be_flagged?
    end

    test "returns false for an employee" do
      refute @staffer.can_be_flagged?
    end
  end

  context "enterprise managed users" do
    test "cannot be spammy" do
      @managed_user.spammy = true
      assert_predicate @managed_user, :never_spammy?
      assert_predicate @managed_user, :spammy
      assert_predicate @managed_user, :spammy?

      @managed_user.save!
      assert_predicate @managed_user, :never_spammy?
      refute_predicate @managed_user, :spammy
      refute_predicate @managed_user, :spammy?
    end

    test "cannot be marked as spammy" do
      @managed_user.mark_as_spammy(reason: "some reason", actor: @staffer)
      refute_predicate @managed_user, :spammy?
    end
  end
end
