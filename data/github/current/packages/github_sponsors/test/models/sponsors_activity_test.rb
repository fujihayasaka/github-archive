# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsActivityTest < GitHub::TestCase
  fixtures do
    @sponsorable = create(:user, :sponsorable)
    @sponsor = create(:credit_card_user, plan_subscription: create(:billing_plan_subscription),
      plan: GitHub::Plan.free_with_addons)
    @activity = create(:sponsors_activity, sponsorable: @sponsorable, sponsor: @sponsor)
    @staff = create(:staff_admin_user)
    @spammy_user = if GitHub.spamminess_check_enabled?
      create(:credit_card_user, :sponsorable, spammy: true,
        plan_subscription: create(:billing_plan_subscription),
        plan: GitHub::Plan.free_with_addons)
    end
    @spammy_org = if GitHub.spamminess_check_enabled?
      create(:credit_card_org, :sponsorable, spammy: true,
        plan_subscription: create(:billing_plan_subscription),
        plan: GitHub::Plan.free_with_addons)
    end
    @repo1, @repo2 = create_list(:repository, 2, :private, :org_owned)
  end

  context ".for_sponsorables_and_sponsors" do
    test "returns results for requested maintainers and funders" do
      non_sponsor = create(:user) # will be requested but should not appear in results b/c no activity
      other_sponsor = create(:credit_card_user)
      other_sponsor_activity1, other_sponsor_activity2 = create_pair(:sponsors_activity, sponsorable: @sponsorable,
        sponsor: other_sponsor)
      other_sponsorable = create(:user, :sponsorable)
      other_sponsorable_activity = create(:sponsors_activity, sponsorable: other_sponsorable, sponsor: @sponsor)
      sponsorable_and_sponsor_pairs = [
        [@sponsorable, @sponsor],
        [@sponsorable, non_sponsor],
        [@sponsorable.id, other_sponsor.id],
        [other_sponsorable, @sponsor]
      ]

      result = SponsorsActivity.for_sponsorables_and_sponsors(sponsorable_and_sponsor_pairs)

      assert_instance_of Hash, result
      assert_same_elements [@sponsorable.id, other_sponsorable.id], result.keys

      sponsorable_result = T.must(result[@sponsorable.id])
      assert_instance_of Hash, sponsorable_result
      assert_same_elements [@sponsor.id, other_sponsor.id], sponsorable_result.keys
      assert_equal [@activity], sponsorable_result[@sponsor.id]
      assert_same_elements [other_sponsor_activity1, other_sponsor_activity2], sponsorable_result[other_sponsor.id]

      other_sponsorable_result = T.must(result[other_sponsorable.id])
      assert_instance_of Hash, other_sponsorable_result
      assert_equal [@sponsor.id], other_sponsorable_result.keys
      assert_equal [other_sponsorable_activity], other_sponsorable_result[@sponsor.id]
    end
  end

  context "#most_recent_prior_similar_activity", skip_enterprise: true do
    test "returns the most recent prior new_sponsorship activity for the same sponsorable and sponsor" do
      assert_predicate @activity, :is_new_sponsorship?
      prior_activity = create(:sponsors_activity, action: @activity.action, sponsorable: @sponsorable,
        sponsor: @sponsor, timestamp: @activity.timestamp - 1.minute, sponsors_tier: @activity.sponsors_tier)

      assert_equal prior_activity, @activity.most_recent_prior_similar_activity
    end

    test "returns the most recent prior cancelled_sponsorship activity for the same sponsorable and sponsor" do
      prior_activity = create(:sponsors_activity, :cancelled_sponsorship, sponsorable: @sponsorable,
        sponsor: @sponsor)
      activity = create(:sponsors_activity, :cancelled_sponsorship, sponsorable: @sponsorable,
        sponsor: @sponsor, timestamp: prior_activity.timestamp + 1.minute,
        old_sponsors_tier: prior_activity.old_sponsors_tier)

      assert_equal prior_activity, activity.most_recent_prior_similar_activity
    end

    test "returns the most recent prior tier_change activity for the same sponsorable, sponsor, old tier, and new tier" do
      prior_activity = create(:sponsors_activity, :upgrade, sponsorable: @sponsorable, sponsor: @sponsor)
      activity = create(:sponsors_activity, :upgrade, sponsorable: @sponsorable, sponsor: @sponsor,
        timestamp: prior_activity.timestamp + 1.minute, sponsors_tier: prior_activity.sponsors_tier,
        old_sponsors_tier: prior_activity.old_sponsors_tier)

      assert_equal prior_activity, activity.most_recent_prior_similar_activity
    end

    test "returns the most recent prior pending_change activity for the same sponsorable, sponsor, old tier, and new tier" do
      prior_activity = create(:sponsors_activity, :pending_downgrade, sponsorable: @sponsorable, sponsor: @sponsor)
      activity = create(:sponsors_activity, :pending_downgrade, sponsorable: @sponsorable, sponsor: @sponsor,
        timestamp: prior_activity.timestamp + 1.minute, sponsors_tier: prior_activity.sponsors_tier,
        old_sponsors_tier: prior_activity.old_sponsors_tier)

      assert_equal prior_activity, activity.most_recent_prior_similar_activity
    end

    test "returns nil when there is no prior activity" do
      first_activity = SponsorsActivity.order(timestamp: :asc).first
      refute_nil first_activity, "need a SponsorsActivity to exist"

      assert_nil T.must(first_activity).most_recent_prior_similar_activity
    end

    test "returns nil when there is no prior activity of the same action" do
      other_action_activity = create(:sponsors_activity, :upgrade, sponsorable: @sponsorable, sponsor: @sponsor,
        timestamp: @activity.timestamp - 1.minute)
      refute_equal @activity.action, other_action_activity.action, "need activities of two different actions"

      assert_nil @activity.most_recent_prior_similar_activity
    end

    test "returns nil when prior activity is not for the same sponsorable" do
      other_sponsorable = create(:user, :sponsorable)
      create(:sponsors_activity, action: @activity.action, sponsorable: other_sponsorable, sponsor: @sponsor,
        timestamp: @activity.timestamp - 1.minute)

      assert_nil @activity.most_recent_prior_similar_activity
    end

    test "returns nil when prior activity is not for the same sponsor" do
      other_sponsor = create(:user)
      create(:sponsors_activity, action: @activity.action, sponsorable: @sponsorable, sponsor: other_sponsor,
        timestamp: @activity.timestamp - 1.minute)

      assert_nil @activity.most_recent_prior_similar_activity
    end

    test "returns nil when prior activity is not for the same current tier" do
      other_tier_activity = create(:sponsors_activity, :upgrade, sponsorable: @sponsorable, sponsor: @sponsor)
      tier = create(:sponsors_tier, :published, sponsors_listing: @sponsorable.sponsors_listing)
      activity = create(:sponsors_activity, :upgrade, sponsorable: @sponsorable, sponsor: @sponsor,
        sponsors_tier: tier, timestamp: other_tier_activity.timestamp + 1.minute,
        old_sponsors_tier: other_tier_activity.old_sponsors_tier)

      assert_nil @activity.most_recent_prior_similar_activity
    end

    test "returns nil when prior activity is not for the same old tier" do
      other_tier_activity = create(:sponsors_activity, :pending_cancellation, sponsorable: @sponsorable,
        sponsor: @sponsor)
      tier = create(:sponsors_tier, :published, sponsors_listing: @sponsorable.sponsors_listing)
      activity = create(:sponsors_activity, :pending_cancellation, sponsorable: @sponsorable, sponsor: @sponsor,
        sponsors_tier: other_tier_activity.sponsors_tier, timestamp: other_tier_activity.timestamp + 1.minute,
        old_sponsors_tier: tier)

      assert_nil @activity.most_recent_prior_similar_activity
    end

    test "returns nil when other activity comes after the activity being checked" do
      create(:sponsors_activity, action: @activity.action, sponsorable: @sponsorable, sponsor: @sponsor,
        timestamp: @activity.timestamp + 1.minute)

      assert_nil @activity.most_recent_prior_similar_activity
    end
  end

  context "on create" do
    test "sends the sponsorship_upgrade_notice email with expected arguments" do
      sponsorship = create(:sponsorship, sponsorable: @sponsorable)
      tier = create(:sponsors_tier, sponsors_listing: sponsorship.sponsors_listing)

      mock_mailer = mock
      mock_mailer.expects(:deliver_later)

      SponsorsPrimerMailer.expects(:sponsorship_upgrade_notice)
        .once
        .with(sponsorable: @sponsorable, sponsorship: sponsorship, tier: tier)
        .returns(mock_mailer)

      create(:sponsors_activity, :upgrade, sponsorable: @sponsorable, sponsor: sponsorship.sponsor, sponsors_tier: tier)
    end

    test "does not send sponsorship_upgrade_notice email when opted out" do
      sponsorship = create(:sponsorship, sponsorable: @sponsorable)
      tier = create(:sponsors_tier, sponsors_listing: sponsorship.sponsors_listing)

      email_opt_outs = SponsorsEmailOptOuts.new(bitmask: nil)
      email_opt_outs.opt_out_of(:upgrade_notices)
      @sponsorable.sponsors_listing.update_email_opt_outs(email_opt_outs)

      SponsorsPrimerMailer.expects(:sponsorship_upgrade_notice).never

      create(:sponsors_activity, :upgrade, sponsorable: @sponsorable, sponsor: sponsorship.sponsor, sponsors_tier: tier)
    end

    test "does not send sponsorship_upgrade_notice email when opted out of all" do
      sponsorship = create(:sponsorship, sponsorable: @sponsorable)
      tier = create(:sponsors_tier, sponsors_listing: sponsorship.sponsors_listing)

      email_opt_outs = SponsorsEmailOptOuts.new(bitmask: nil)
      email_opt_outs.opt_out_of(:all)
      @sponsorable.sponsors_listing.update_email_opt_outs(email_opt_outs)

      SponsorsPrimerMailer.expects(:sponsorship_upgrade_notice).never

      create(:sponsors_activity, :upgrade, sponsorable: @sponsorable, sponsor: sponsorship.sponsor, sponsors_tier: tier)
    end

    test "defaults to github as payment source" do
      activity = create(:sponsors_activity, sponsorable: @sponsorable, sponsor: @sponsor)

      assert_predicate activity, :github?
    end

    test "can have patreon as the payment source" do
      assert_predicate SponsorsActivity.new(payment_source: :patreon), :patreon?
    end

    test "enqueues a job to email sponsors on action=new_sponsorship" do
      activity = build(:sponsors_activity, :new_sponsorship)

      assert_enqueued_with(job: SendSponsorshipEmailsJob, args: [{ sponsors_activity: activity }]) do
        activity.save!
      end
    end

    test "does not enqueue a job to email sponsors when action is not new_sponsorship" do
      activity = build(:sponsors_activity, :upgrade)

      assert_no_enqueued_jobs(only: SendSponsorshipEmailsJob) do
        activity.save!
      end
    end

    test "enqueues job to send new sponsorship emails when activity is new Patreon sponsorship" do
      activity = build(:sponsors_activity, :new_sponsorship, :patreon, sponsor: @sponsor)

      assert_enqueued_with(job: SendSponsorshipEmailsJob, args: [{ sponsors_activity: activity }]) do
        activity.save!
      end
    end

    test "enqueues a job to grant the sponsor access to the repository on action=new_sponsorship" do
      tier = create(:sponsors_tier, :approved_sponsors_listing, :with_repository)
      activity = build(:sponsors_activity, :new_sponsorship, sponsors_tier: tier)

      assert_enqueued_with(
        job: GrantSponsorsOnlyRepositoryAccessJob,
        args: [activity.sponsor_id, tier.repository_id, tier.id],
      ) do
        activity.save!
      end
    end

    test "does not enqueue a job to grant the sponsor access to a repository on action=new_sponsorship when activity has no repo" do
      activity = build(:sponsors_activity, :new_sponsorship)
      refute_predicate activity.sponsors_tier, :has_repository?
      assert_nil activity.repository_id

      assert_no_enqueued_jobs(only: GrantSponsorsOnlyRepositoryAccessJob) do
        activity.save!
      end
    end

    test "does not enqueue a job to grant the sponsor access to the repository when action is not new_sponsorship" do
      old_tier_with_repo = create(:sponsors_tier, :approved_sponsors_listing, :with_repository)
      new_tier_with_repo = create(:sponsors_tier, :published, :with_repository,
        sponsors_listing: old_tier_with_repo.sponsors_listing)
      activity = build(:sponsors_activity, :upgrade, sponsors_tier: new_tier_with_repo,
        old_sponsors_tier: old_tier_with_repo)

      assert_no_enqueued_jobs(only: GrantSponsorsOnlyRepositoryAccessJob) do
        activity.save!
      end
    end

    test "enqueues a job to revoke a sponsor's repository access on action=tier_change" do
      tier = create(:sponsors_tier, :approved_sponsors_listing, :with_repository)
      activity = build(:sponsors_activity, :upgrade, old_sponsors_tier: tier, sponsorable: @sponsorable)

      assert_enqueued_with(
        job: RevokeSponsorsOnlyRepositoryAccessJob,
        args: [activity.sponsor_id, tier.repository_id, tier.id],
      ) do
        activity.save!
      end
    end

    test "does not enqueue a job to revoke a sponsor's repository access on action=tier_change when activity has no old repo" do
      tier = build(:sponsors_tier, :approved_sponsors_listing)
      activity = build(:sponsors_activity, :downgrade, old_sponsors_tier: tier, sponsorable: @sponsorable)

      assert_no_enqueued_jobs(only: RevokeSponsorsOnlyRepositoryAccessJob) do
        activity.save!
      end
    end

    test "does not enqueue a job to revoke a sponsor's repository access on action=tier_change when the repositories
    for the new and previous tier are the same" do
      org_admin = build(:user)
      org = build(:organization, :sponsorable, admin: org_admin)
      repository = build(:repository, :private, owner: org)
      old_tier = build(:sponsors_tier, :approved_sponsors_listing, sponsorable: org, repository: repository)
      new_tier = build(:sponsors_tier, :approved_sponsors_listing, sponsorable: org, repository: repository)
      activity = build(:sponsors_activity, :upgrade, old_sponsors_tier: old_tier, sponsors_tier: new_tier, sponsorable: org)

      assert_no_enqueued_jobs(only: RevokeSponsorsOnlyRepositoryAccessJob) do
        activity.save!
      end
    end

    test "does not enqueue a job to revoke a sponsor's repository access when action is not tier_change" do
      activity = build(:sponsors_activity, :new_sponsorship, sponsorable: @sponsorable)

      assert_no_enqueued_jobs(only: RevokeSponsorsOnlyRepositoryAccessJob) do
        activity.save!
      end
    end
  end

  context "#repository_sponsor_gained_access_to" do
    test "returns repository relation for new sponsorship" do
      activity = SponsorsActivity.new(action: :new_sponsorship, repository: @repo1, old_repository: @repo2)
      assert_equal @repo1, activity.repository_sponsor_gained_access_to
    end

    test "returns nil for cancellation" do
      activity = SponsorsActivity.new(action: :cancelled_sponsorship, repository: @repo1, old_repository: @repo2)
      assert_nil activity.repository_sponsor_gained_access_to
    end

    test "returns nil for refund" do
      activity = SponsorsActivity.new(action: :refund, repository: @repo1, old_repository: @repo2)
      assert_nil activity.repository_sponsor_gained_access_to
    end

    test "returns nil for match disabled" do
      activity = SponsorsActivity.new(action: :sponsor_match_disabled, repository: @repo1, old_repository: @repo2)
      assert_nil activity.repository_sponsor_gained_access_to
    end

    test "returns repository relation for pending change when it differs from old_repository" do
      activity = SponsorsActivity.new(action: :pending_change, repository: @repo1, old_repository: @repo2)
      assert_equal @repo1, activity.repository_sponsor_gained_access_to
    end

    test "returns nil for pending change when repo and old repo are the same" do
      activity = SponsorsActivity.new(action: :pending_change, repository: @repo1, old_repository: @repo1)
      assert_nil activity.repository_sponsor_gained_access_to
    end

    test "returns repository relation for tier change when it differs from old_repository" do
      activity = SponsorsActivity.new(action: :tier_change, repository: @repo1, old_repository: @repo2)
      assert_equal @repo1, activity.repository_sponsor_gained_access_to
    end

    test "returns nil for tier change when repo and old repo are the same" do
      activity = SponsorsActivity.new(action: :tier_change, repository: @repo1, old_repository: @repo1)
      assert_nil activity.repository_sponsor_gained_access_to
    end
  end

  context "#repository_sponsor_lost_access_to" do
    test "returns nil for new sponsorship" do
      activity = SponsorsActivity.new(action: :new_sponsorship, repository: @repo1, old_repository: @repo2)
      assert_nil activity.repository_sponsor_lost_access_to
    end

    test "returns repository relation for cancellation" do
      activity = SponsorsActivity.new(action: :cancelled_sponsorship, repository: @repo1, old_repository: @repo2)
      assert_equal @repo1, activity.repository_sponsor_lost_access_to
    end

    test "returns nil for refund" do
      activity = SponsorsActivity.new(action: :refund, repository: @repo1, old_repository: @repo2)
      assert_nil activity.repository_sponsor_lost_access_to
    end

    test "returns nil for match disabled" do
      activity = SponsorsActivity.new(action: :sponsor_match_disabled, repository: @repo1, old_repository: @repo2)
      assert_nil activity.repository_sponsor_lost_access_to
    end

    test "returns old_repository for pending change when it differs from repository" do
      activity = SponsorsActivity.new(action: :pending_change, repository: @repo1, old_repository: @repo2)
      assert_equal @repo2, activity.repository_sponsor_lost_access_to
    end

    test "returns nil for pending change when repo and old repo are the same" do
      activity = SponsorsActivity.new(action: :pending_change, repository: @repo1, old_repository: @repo1)
      assert_nil activity.repository_sponsor_lost_access_to
    end

    test "returns old_repository for tier change when it differs from repository" do
      activity = SponsorsActivity.new(action: :tier_change, repository: @repo1, old_repository: @repo2)
      assert_equal @repo2, activity.repository_sponsor_lost_access_to
    end

    test "returns nil for tier change when repo and old repo are the same" do
      activity = SponsorsActivity.new(action: :tier_change, repository: @repo1, old_repository: @repo1)
      assert_nil activity.repository_sponsor_lost_access_to
    end
  end

  context "#readable_by?" do
    test "returns true if actor is the sponsorable" do
      assert @activity.readable_by?(@sponsorable)
    end

    test "returns true if actor is the sponsor" do
      assert @activity.readable_by?(@sponsor)
    end

    test "returns false if actor is the sponsor but action is not visible to sponsors" do
      sponsorable_activity = create(:sponsors_activity, :sponsor_match_disabled, sponsor: @sponsor,
        sponsorable: @sponsorable)
      refute sponsorable_activity.readable_by?(@sponsor)
    end

    test "returns false if actor is neither the sponsorable nor the sponsor" do
      rando = create(:user)
      refute @activity.readable_by?(rando)
    end

    test "returns true if actor is the sponsorable org's admin" do
      org_admin = create(:user)
      org = create(:organization, :sponsorable, admin: org_admin)
      activity = create(:sponsors_activity, sponsorable: org)

      assert activity.readable_by?(org_admin)
    end

    test "returns true if actor is the sponsoring org's admin" do
      org_admin = create(:user)
      org = create(:organization, admin: org_admin)
      activity = create(:sponsors_activity, sponsor: org)

      assert activity.readable_by?(org_admin)
    end

    test "returns false if actor is the sponsoring org's admin but action is not visible to sponsors" do
      org_admin = create(:user)
      org = create(:organization, admin: org_admin)
      sponsorable_activity = create(:sponsors_activity, :sponsor_match_disabled, sponsor: org)

      refute sponsorable_activity.readable_by?(org_admin)
    end

    test "returns false if actor is the sponsorable org's member" do
      org = create(:organization, :sponsorable)
      org_member = create(:user)
      org.add_member(org_member)
      activity = create(:sponsors_activity, sponsorable: org)

      refute activity.readable_by?(org_member)
    end

    test "returns false if actor is the sponsoring org's member" do
      org = create(:organization)
      org_member = create(:user)
      org.add_member(org_member)
      activity = create(:sponsors_activity, sponsor: org)

      refute activity.readable_by?(org_member)
    end

    test "returns false if actor is the sponsorable org's billing manager" do
      org = create(:organization, :sponsorable)
      billing_manager = create(:user)
      org.billing.add_manager(billing_manager, actor: org.admin)
      activity = create(:sponsors_activity, sponsorable: org)

      refute activity.readable_by?(billing_manager), "billing managers cannot manage their org's Sponsors listing, " \
        "so they should not see activity about it"
    end

    test "returns true if actor is the sponsoring org's billing manager" do
      org = create(:organization)
      billing_manager = create(:user)
      org.billing.add_manager(billing_manager, actor: org.admin)
      activity = create(:sponsors_activity, sponsor: org)

      assert activity.readable_by?(billing_manager), "billing managers can create/cancel/modify sponsorships " \
        "from their org, so they should be able to see activity about those sponsorships"
    end

    test "returns false if actor is not related to the sponsorable org" do
      org = create(:organization, :sponsorable)
      rando = create(:user)
      activity = create(:sponsors_activity, sponsorable: org)

      refute activity.readable_by?(rando)
    end

    test "returns false if actor is not related to the sponsoring org" do
      org = create(:organization, :sponsorable)
      rando = create(:user)
      activity = create(:sponsors_activity, sponsor: org)

      refute activity.readable_by?(rando)
    end

    test "returns false for anonymous viewer" do
      refute @activity.readable_by?(nil)
    end

    test "returns false for site admin viewer" do
      refute @activity.readable_by?(@staff)
    end

    test "returns true even with a spammy sponsor for sponsorable viewer" do
      activity = create(:sponsors_activity, sponsor: @spammy_user, sponsorable: @sponsorable)
      assert activity.readable_by?(@sponsorable)
    end if GitHub.spamminess_check_enabled?

    test "returns true even with a spammy sponsor for org admin of sponsorable" do
      org_admin = create(:user)
      org = create(:organization, :sponsorable, admin: org_admin)
      activity = create(:sponsors_activity, sponsor: @spammy_user, sponsorable: org)
      assert activity.readable_by?(org_admin)
    end if GitHub.spamminess_check_enabled?

    test "returns true for spammy sponsor viewer" do
      activity = create(:sponsors_activity, sponsor: @spammy_user)
      assert activity.readable_by?(@spammy_user)
    end if GitHub.spamminess_check_enabled?
  end

  context "for_sponsorable_or_sponsor scope" do
    test "includes activity for the given user's listing" do
      result = SponsorsActivity.for_sponsorable_or_sponsor(@sponsorable)
      assert_includes result, @activity
    end

    test "includes activity for the given user as sponsor" do
      result = SponsorsActivity.for_sponsorable_or_sponsor(@sponsor)
      assert_includes result, @activity
    end

    test "omits activity unrelated to given user" do
      rando = create(:user)
      assert_empty SponsorsActivity.for_sponsorable_or_sponsor(rando)
    end

    test "omits all activity when given nil" do
      assert_empty SponsorsActivity.for_sponsorable_or_sponsor(nil)
    end
  end

  context "for_sponsor scope" do
    test "omits activity for the given user's listing" do
      result = SponsorsActivity.for_sponsor(@sponsorable)
      refute_includes result, @activity
    end

    test "includes activity for the given user as sponsor" do
      result = SponsorsActivity.for_sponsor(@sponsor)
      assert_includes result, @activity
    end

    test "omits activity for org sponsor when viewed by org admin" do
      org_admin = create(:user)
      org = create(:organization, admin: org_admin)
      activity = create(:sponsors_activity, sponsor: org)

      result = SponsorsActivity.for_sponsor(org_admin)

      refute_includes result, activity
    end

    test "omits activity for org sponsor when viewed by org billing manager" do
      org = create(:organization)
      billing_manager = create(:user)
      org.billing.add_manager(billing_manager, actor: org.admin)
      activity = create(:sponsors_activity, sponsor: org)

      result = SponsorsActivity.for_sponsor(billing_manager)

      refute_includes result, activity
    end

    test "omits activity for org sponsor when viewed by org member" do
      org = create(:organization)
      org_member = create(:user)
      org.add_member(org_member)
      activity = create(:sponsors_activity, sponsor: org)

      result = SponsorsActivity.for_sponsor(org_member)

      refute_includes result, activity
    end

    test "omits activity for a different sponsor" do
      other_activity = create(:sponsors_activity, sponsorable: @sponsorable)
      refute_equal @sponsor, other_activity.sponsor

      result = SponsorsActivity.for_sponsor(@sponsor)

      refute_includes result, other_activity
    end

    test "omits activity unrelated to given user" do
      rando = create(:user)
      assert_empty SponsorsActivity.for_sponsor(rando)
    end

    test "omits activity unrelated to viewer even if viewer is staff" do
      result = SponsorsActivity.for_sponsor(@staff)
      refute_includes result, @activity
    end

    test "omits all activity when given nil" do
      assert_empty SponsorsActivity.for_sponsor(nil)
    end
  end

  context "visible_to scope" do
    test "includes activity for the given user's listing" do
      result = SponsorsActivity.visible_to(@sponsorable)
      assert_includes result, @activity
    end

    test "includes activity for the given user as sponsor" do
      result = SponsorsActivity.visible_to(@sponsor)
      assert_includes result, @activity
    end

    test "omits activity for the given user as sponsor when action is not for the sponsor" do
      sponsorable_activity = create(:sponsors_activity, :sponsor_match_disabled, sponsor: @sponsor)
      result = SponsorsActivity.visible_to(@sponsor)
      refute_includes result, sponsorable_activity
    end

    # https://github.com/github/sponsors/issues/2807
    test "omits activity with nil sponsor_id for sponsor viewer when sponsor owns an org with a profile" do
      activity = create(:sponsors_activity, sponsorable: @sponsorable)
      activity.update_attribute(:sponsor_id, nil)
      assert_nil activity.reload.sponsor_id

      owned_org = create(:organization, admin: @sponsor)
      create(:organization_profile, organization: owned_org)

      result = @sponsorable.sponsors_activities.visible_to(@sponsor)

      refute_includes result, activity
    end

    test "includes activity for org sponsor when viewed by org admin" do
      org_admin = create(:user)
      org = create(:organization, admin: org_admin)
      activity = create(:sponsors_activity, sponsor: org)

      result = SponsorsActivity.visible_to(org_admin)

      assert_includes result, activity
    end

    test "includes activity for org sponsor when viewed by linked org admin" do
      org_that_gets_credit_admin = create(:user)
      org_that_gets_credit = create(:organization, admin: org_that_gets_credit_admin)
      org_that_pays = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription))
      create(:organization_profile, organization: org_that_gets_credit, sponsoring_linked_organization: org_that_pays)
      activity = create(:sponsors_activity, sponsor: org_that_pays)

      result = SponsorsActivity.visible_to(org_that_gets_credit_admin)

      assert_includes result, activity
    end

    test "includes activity for org sponsor when viewed by linked org billing manager" do
      org_that_gets_credit = create(:organization)

      org_that_gets_credit_billing_manager = create(:user)
      org_that_gets_credit.billing.add_manager(org_that_gets_credit_billing_manager,
        actor: org_that_gets_credit.admin)

      org_that_pays = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription))
      create(:organization_profile, organization: org_that_gets_credit, sponsoring_linked_organization: org_that_pays)

      activity = create(:sponsors_activity, sponsor: org_that_pays)

      result = SponsorsActivity.visible_to(org_that_gets_credit_billing_manager)

      assert_includes result, activity
    end

    test "omits activity for org sponsor when viewed by linked org member" do
      org_that_gets_credit = create(:organization)

      org_that_gets_credit_member = create(:user)
      org_that_gets_credit.add_member(org_that_gets_credit_member)

      org_that_pays = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription))
      create(:organization_profile, organization: org_that_gets_credit, sponsoring_linked_organization: org_that_pays)

      activity = create(:sponsors_activity, sponsor: org_that_pays)

      result = SponsorsActivity.visible_to(org_that_gets_credit_member)

      refute_includes result, activity
    end

    test "includes activity for org sponsor when viewed by org billing manager" do
      org = create(:organization)
      billing_manager = create(:user)
      org.billing.add_manager(billing_manager, actor: org.admin)
      activity = create(:sponsors_activity, sponsor: org)

      result = SponsorsActivity.visible_to(billing_manager)

      assert_includes result, activity
    end

    test "omits activity for org sponsor when viewed by org member" do
      org = create(:organization)
      org_member = create(:user)
      org.add_member(org_member)
      activity = create(:sponsors_activity, sponsor: org)

      result = SponsorsActivity.visible_to(org_member)

      refute_includes result, activity
    end

    test "includes activities for a sponsorable who is also a sponsor" do
      sponsorship = create(:sponsorship)
      user = sponsorship.sponsor
      create(:sponsors_listing, :approved, sponsorable: user)
      sponsorable_activity = create(:sponsors_activity, sponsorable: user)
      sponsor_activity = create(:sponsors_activity, sponsor: user)

      result = SponsorsActivity.visible_to(user)

      assert_same_elements [sponsorable_activity, sponsor_activity], result
    end

    test "omits activity for a different sponsor" do
      other_activity = create(:sponsors_activity, sponsorable: @sponsorable)
      refute_equal @sponsor, other_activity.sponsor

      result = SponsorsActivity.visible_to(@sponsor)

      refute_includes result, other_activity
    end

    test "includes activity for org listing when viewer is an org admin" do
      org_admin = create(:user)
      org = create(:organization, :sponsorable, admin: org_admin)
      org_activity = create(:sponsors_activity, sponsorable: org)

      result = SponsorsActivity.visible_to(org_admin)

      assert_includes result, org_activity
    end

    test "omits activity for org listing when viewer is an org member" do
      org = create(:organization, :sponsorable)
      org_member = create(:user)
      org.add_member(org_member)
      org_activity = create(:sponsors_activity, sponsorable: org)

      result = SponsorsActivity.visible_to(org_member)

      refute_includes result, org_activity
    end

    test "omits activity for org listing when viewer is an org billing manager" do
      org = create(:organization, :sponsorable)
      billing_manager = create(:user)
      org.billing.add_manager(billing_manager, actor: org.admin)
      org_activity = create(:sponsors_activity, sponsorable: org)

      result = SponsorsActivity.visible_to(billing_manager)

      refute_includes result, org_activity
    end

    test "omits activity for someone else's listing even when viewer is staff" do
      result = SponsorsActivity.visible_to(@staff)
      refute_includes result, @activity
    end

    test "omits activity unrelated to regular viewer" do
      rando = create(:user)
      result = SponsorsActivity.visible_to(rando)
      refute_includes result, @activity
    end

    test "omits all activity for anonymous viewer" do
      assert_empty SponsorsActivity.visible_to(nil)
    end
  end

  context "#target_for_conditional_access" do
    test "returns the sponsorable user" do
      assert_equal @sponsorable, @activity.target_for_conditional_access
    end

    test "returns the sponsorable org" do
      org = create(:organization, :sponsorable)
      activity = create(:sponsors_activity, sponsorable: org)
      assert_equal org, activity.target_for_conditional_access
    end

    test "returns :no_target_for_conditional_access when there is no sponsorable" do
      @sponsorable.delete
      assert_equal :no_target_for_conditional_access, @activity.target_for_conditional_access
    end
  end

  context "for_period scope" do
    test "includes activity made within last day for period=day" do
      activity = travel_to("2021-07-05 00:00:00") do
        create(:sponsors_activity, sponsorable: @sponsorable, sponsor: @sponsor)
      end

      result = travel_to("2021-07-05 23:59:59") do
        SponsorsActivity.for_period(:day)
      end

      assert_includes result, activity
    end

    test "omits activity made before the current day for period=day" do
      activity = travel_to("2021-07-04 23:59:59") do
        create(:sponsors_activity, sponsorable: @sponsorable, sponsor: @sponsor)
      end

      result = travel_to("2021-07-05 23:59:59") do
        SponsorsActivity.for_period(:day)
      end

      refute_includes result, activity
    end

    test "includes activity made within the last 7 days for period=week" do
      activity = travel_to("2021-07-01 00:00:00") do
        create(:sponsors_activity, sponsorable: @sponsorable, sponsor: @sponsor)
      end

      result = travel_to("2021-07-07 23:59:59") do
        SponsorsActivity.for_period(:week)
      end

      assert_includes result, activity
    end

    test "omits activity made more than 7 days ago for period=week" do
      activity = travel_to("2021-07-01 00:00:00") do
        create(:sponsors_activity, sponsorable: @sponsorable, sponsor: @sponsor)
      end

      result = travel_to("2021-07-08 00:00:00") do
        SponsorsActivity.for_period(:week)
      end

      refute_includes result, activity
    end

    test "includes activity made within the last 30 days for period=month" do
      activity = travel_to("2021-07-01 00:00:00") do
        create(:sponsors_activity, sponsorable: @sponsorable, sponsor: @sponsor)
      end

      result = travel_to("2021-07-30 23:59:59") do
        SponsorsActivity.for_period(:month)
      end

      assert_includes result, activity
    end

    test "omits activity made more than 30 days ago for period=month" do
      activity = travel_to("2021-07-01 00:00:00") do
        create(:sponsors_activity, sponsorable: @sponsorable, sponsor: @sponsor)
      end

      result = travel_to("2021-07-31 00:00:00") do
        SponsorsActivity.for_period(:month)
      end

      refute_includes result, activity
    end

    test "includes activity made within the last 365 days for period=year" do
      activity = travel_to("2021-01-01 00:00:00") do
        create(:sponsors_activity, sponsorable: @sponsorable, sponsor: @sponsor)
      end

      result = travel_to("2021-12-31 23:59:59") do
        SponsorsActivity.for_period(:year)
      end

      assert_includes result, activity
    end

    test "omits activity made more than 365 days ago for period=year" do
      activity = travel_to("2021-01-01 00:00:00") do
        create(:sponsors_activity, sponsorable: @sponsorable, sponsor: @sponsor)
      end

      result = travel_to("2022-01-02 00:00:00") do
        SponsorsActivity.for_period(:year)
      end

      refute_includes result, activity
    end

    test "includes all activity regardless of time for period=alltime" do
      activity = travel_to("2019-07-01 00:00:00") do
        create(:sponsors_activity, sponsorable: @sponsorable, sponsor: @sponsor)
      end

      result = SponsorsActivity.for_period(:alltime)

      assert_includes result, activity
    end
  end

  context "#linked_or_direct_sponsor" do
    test "returns user sponsor" do
      assert_equal @sponsor, @activity.linked_or_direct_sponsor
    end

    test "returns direct org sponsor when there is no sponsoring linked org" do
      sponsor = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription))
      activity = create(:sponsors_activity, sponsor: sponsor, sponsorable: @sponsorable)
      assert_equal sponsor, activity.linked_or_direct_sponsor
    end

    test "returns sponsoring linked org when it exists for org sponsor" do
      linked_org = create(:organization)
      sponsor = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription))
      activity = create(:sponsors_activity, sponsor: sponsor, sponsorable: @sponsorable)
      create(:organization_profile, organization: linked_org,
        sponsoring_linked_organization: sponsor)

      assert_equal linked_org, activity.linked_or_direct_sponsor
    end
  end

  if GitHub.sponsors_enabled?
    [:sponsorable, :action, :sponsors_tier, :timestamp].each do |attr|
      test "requires a #{attr}" do
        assert_predicate @activity, :valid?

        @activity.send("#{attr}=", nil)

        refute_predicate @activity, :valid?
        assert_predicate @activity.errors[attr], :any?
      end
    end

    test "pending_change does not require a sponsors tier" do
      activity = build(:sponsors_activity, :pending_cancellation, sponsorable: @sponsorable)

      assert_nil activity.sponsors_tier
      assert_predicate activity, :valid?
    end

    test "pending_change with no sponsors tier is a cancellation" do
      activity = build(:sponsors_activity, :pending_cancellation, sponsorable: @sponsorable)

      assert_nil activity.sponsors_tier
      assert_predicate activity, :is_pending_cancellation?
      refute_predicate activity, :is_pending_tier_change?
    end

    test "pending change with a sponsors tier is a tier change" do
      activity = build(:sponsors_activity, :pending_upgrade, sponsorable: @sponsorable)

      refute_predicate activity, :is_pending_cancellation?
      assert_predicate activity, :is_pending_tier_change?
    end

    test "pending_change requires an old sponsors tier" do
      activity = build(:sponsors_activity, :pending_cancellation, sponsorable: @sponsorable)

      assert_equal "pending_change", activity.action
      activity.old_sponsors_tier = nil
      refute_predicate activity, :valid?
      assert_predicate activity.errors[:old_sponsors_tier], :any?
    end

    test "tier_change requires an old sponsors tier" do
      activity = build(:sponsors_activity, :upgrade, sponsorable: @sponsorable)

      assert_equal "tier_change", activity.action
      activity.old_sponsors_tier = nil
      refute_predicate activity, :valid?
      assert_predicate activity.errors[:old_sponsors_tier], :any?
    end

    test "sponsor falls back to Ghost user" do
      @activity.update(sponsor: nil)

      assert_predicate @activity, :valid?
      assert_equal User.ghost, @activity.sponsor
    end

    test "new sponsorships are increases" do
      activity = build(:sponsors_activity, :new_sponsorship, sponsorable: @sponsorable)
      assert_predicate activity, :is_increase?
    end

    test "upgrades are increases" do
      activity = build(:sponsors_activity, :upgrade, sponsorable: @sponsorable)
      assert_equal "tier_change", activity.action
      assert_predicate activity, :is_increase?
    end

    test "pending upgrades are increases" do
      activity = build(:sponsors_activity, :pending_upgrade, sponsorable: @sponsorable)
      assert_equal "pending_change", activity.action
      assert_predicate activity, :is_increase?
    end

    test "downgrades are not increases" do
      activity = build(:sponsors_activity, :downgrade, sponsorable: @sponsorable)
      assert_equal "tier_change", activity.action
      refute_predicate activity, :is_increase?
    end

    test "pending downgrades are not increases" do
      activity = build(:sponsors_activity, :pending_downgrade, sponsorable: @sponsorable)
      assert_equal "pending_change", activity.action
      refute_predicate activity, :is_increase?
    end

    test "cancellations are not increases" do
      activity = build(:sponsors_activity, :cancelled_sponsorship, sponsorable: @sponsorable)
      refute_predicate activity, :is_increase?
    end

    test "pending cancellations are not increases" do
      activity = build(:sponsors_activity, :pending_cancellation, sponsorable: @sponsorable)
      assert_equal "pending_change", activity.action
      refute_predicate activity, :is_increase?
    end

    test "refunds are not increases" do
      activity = build(:sponsors_activity, :refund, sponsorable: @sponsorable)
      refute_predicate activity, :is_increase?
    end

    test "sponsor_match_disabled does not require old_sponsors_tier" do
      activity = build(:sponsors_activity, :sponsor_match_disabled, old_sponsors_tier: nil)
      assert_predicate activity, :valid?
    end

    test "sponsor_match_disabled requires sponsors_tier" do
      activity = build(:sponsors_activity, :sponsor_match_disabled, sponsors_tier: nil)
      refute_predicate activity, :valid?
    end

    context "#one_time_tier?" do
      test "returns true when the new tier frequency is one-time" do
        activity = build(:sponsors_activity, sponsors_tier: build(:sponsors_tier, :one_time))

        assert_predicate activity.sponsors_tier, :one_time?
        assert_predicate activity, :one_time_tier?
      end

      test "returns false when the new tier frequency is recurring" do
        assert_predicate @activity.sponsors_tier, :recurring?
        refute_predicate @activity, :one_time_tier?
      end

      test "returns false when there is not a new tier" do
        activity = build(:sponsors_activity, :pending_cancellation, sponsorable: @sponsorable)

        assert_nil activity.sponsors_tier
        refute_predicate activity, :one_time_tier?
      end
    end

    context "#one_time_old_tier?" do
      test "returns true when the old tier frequency is one-time" do
        activity = build(:sponsors_activity, old_sponsors_tier: build(:sponsors_tier, :one_time))
        assert_predicate activity.old_sponsors_tier, :one_time?
        assert_predicate activity, :one_time_old_tier?
      end

      test "returns false when the old tier frequency is recurring" do
        activity = build(:sponsors_activity, :downgrade)
        assert_predicate activity.old_sponsors_tier, :recurring?
        refute_predicate activity, :one_time_old_tier?
      end

      test "returns false when there is not an old tier" do
        activity = build(:sponsors_activity, :new_sponsorship, sponsorable: @sponsorable)
        assert_nil activity.old_sponsors_tier
        refute_predicate activity, :one_time_old_tier?
      end
    end

    context "since scope" do
      test "returns only activities created on or after the given time" do
        three_day_activity = create(:sponsors_activity, sponsorable: @sponsorable, sponsor: @sponsor,
          timestamp: 3.days.ago)
        week_activity = create(:sponsors_activity, sponsorable: @sponsorable, sponsor: @sponsor,
          timestamp: 1.week.ago)
        day_activity = create(:sponsors_activity, sponsorable: @sponsorable, sponsor: @sponsor, timestamp: 1.day.ago)

        result = @sponsorable.sponsors_activities.since(three_day_activity.timestamp)

        assert_includes result, day_activity
        assert_includes result, three_day_activity
        refute_includes result, week_activity
      end
    end

    context "until scope" do
      test "returns only activities created before the given time" do
        three_day_activity = create(:sponsors_activity, sponsorable: @sponsorable, sponsor: @sponsor,
          timestamp: 3.days.ago)
        week_activity = create(:sponsors_activity, sponsorable: @sponsorable, sponsor: @sponsor,
          timestamp: 1.week.ago)
        day_activity = create(:sponsors_activity, sponsorable: @sponsorable, sponsor: @sponsor, timestamp: 1.day.ago)

        result = @sponsorable.sponsors_activities.until(three_day_activity.timestamp)

        refute_includes result, day_activity
        refute_includes result, three_day_activity
        assert_includes result, week_activity
      end
    end

    context "by_timestamp scope" do
      test "returns activities with most recent timestamp first" do
        older_activity = create(:sponsors_activity, sponsorable: @sponsorable, sponsor: @sponsor,
          timestamp: 3.days.ago)
        middle_activity = create(:sponsors_activity, sponsorable: @sponsorable, sponsor: @sponsor,
          timestamp: 2.days.ago)
        newer_activity = create(:sponsors_activity, sponsorable: @sponsorable, sponsor: @sponsor,
          timestamp: 1.day.ago)

        result = SponsorsActivity.where(id: [older_activity, middle_activity, newer_activity]).by_timestamp.to_a

        assert_equal [newer_activity, middle_activity, older_activity], result
      end

      test "sorts activities by id descending when they have the same timestamp" do
        timestamp = 3.days.ago
        lower_id_activity = create(:sponsors_activity, sponsorable: @sponsorable, sponsor: @sponsor,
          timestamp: timestamp)
        higher_id_activity = create(:sponsors_activity, sponsorable: @sponsorable, sponsor: @sponsor,
          timestamp: timestamp)
        assert_operator lower_id_activity.id, :<, higher_id_activity.id,
          "need an activity with its id preceding another"

        result = SponsorsActivity.where(id: [lower_id_activity, higher_id_activity]).by_timestamp.to_a

        assert_equal [higher_id_activity, lower_id_activity], result
      end
    end

    context "oldest_first scope" do
      test "returns activities with most recent timestamp last" do
        older_activity = create(:sponsors_activity, sponsorable: @sponsorable, sponsor: @sponsor,
          timestamp: 3.days.ago)
        middle_activity = create(:sponsors_activity, sponsorable: @sponsorable, sponsor: @sponsor,
          timestamp: 2.days.ago)
        newer_activity = create(:sponsors_activity, sponsorable: @sponsorable, sponsor: @sponsor,
          timestamp: 1.day.ago)

        result = SponsorsActivity.where(id: [older_activity, middle_activity, newer_activity]).oldest_first.to_a

        assert_equal [older_activity, middle_activity, newer_activity], result
      end

      test "sorts activities by id ascending when they have the same timestamp" do
        timestamp = 3.days.ago
        lower_id_activity = create(:sponsors_activity, sponsorable: @sponsorable, sponsor: @sponsor,
          timestamp: timestamp)
        higher_id_activity = create(:sponsors_activity, sponsorable: @sponsorable, sponsor: @sponsor,
          timestamp: timestamp)
        assert_operator lower_id_activity.id, :<, higher_id_activity.id,
          "need an activity with its id preceding another"

        result = SponsorsActivity.where(id: [lower_id_activity, higher_id_activity]).oldest_first.to_a

        assert_equal [lower_id_activity, higher_id_activity], result
      end
    end

    context "filter_by_date" do
      test "allows filter by timestamp" do
        activity = create(:sponsors_activity, sponsorable: @sponsorable, sponsor: @sponsor, timestamp: 3.days.ago)
        create(:sponsors_activity, sponsorable: @sponsorable, sponsor: @sponsor, timestamp: 1.week.ago)
        create(:sponsors_activity, sponsorable: @sponsorable, sponsor: @sponsor, timestamp: 1.day.ago)

        filtered_activities = @sponsorable.sponsors_activities.filter_by_date(activity.timestamp)

        assert_equal [activity], filtered_activities
      end

      test "allows filter by date" do
        activity = create(:sponsors_activity, sponsorable: @sponsorable, sponsor: @sponsor, timestamp: 3.days.ago)
        other_activity = create(:sponsors_activity, sponsorable: @sponsorable, sponsor: @sponsor, timestamp: 1.week.ago)

        filtered_activities = @sponsorable.sponsors_activities.filter_by_date(other_activity.timestamp.to_date)

        assert_equal [other_activity], filtered_activities
      end

      test "allows filter by formatted date string" do
        activity = create(:sponsors_activity, sponsorable: @sponsorable, sponsor: @sponsor, timestamp: 3.days.ago)
        other_activity = create(:sponsors_activity, sponsorable: @sponsorable, sponsor: @sponsor, timestamp: 1.week.ago)
        formatted_date = other_activity.timestamp.strftime("%Y-%m-%d")

        filtered_activities = @sponsorable.sponsors_activities.filter_by_date(formatted_date)

        assert_equal [other_activity], filtered_activities
      end

      test "do not filter when the date is not present" do
        assert_equal 1, @sponsorable.sponsors_activities.filter_by_date(nil).count
      end
    end

    context "enqueue_sponsorship_cancellation_email_job" do
      test "enqueues a job to send a sponsorship cancellation email" do
        activity = build(:sponsors_activity, :cancelled_sponsorship, sponsorable: @sponsorable)

        assert_enqueued_with(job: SendSponsorshipCancellationEmailJob, args: [{ sponsors_activity: activity }]) do
          activity.save!
        end
      end

      test "does not enqueue a job to send a sponsorship cancellation email when the activity is due to a sponsorable user unlinking Patreon" do
        activity = build(:sponsors_activity, :cancelled_sponsorship, :patreon, sponsor: @sponsor, sponsorable: @sponsorable)

        assert_no_enqueued_jobs(only: SendSponsorshipCancellationEmailJob) do
          activity.save!
        end
      end

      test "does not enqueue a job to send a sponsorship cancellation email when the activity is due to a sponsorable user disabling the `enabled_as_sponsorable` flag for Patreon" do
        create(:sponsors_patreon_user, enabled_as_sponsorable: false, user: @sponsorable)
        activity = build(:sponsors_activity, :cancelled_sponsorship, :patreon, sponsor: @sponsor, sponsorable: @sponsorable)

        assert_no_enqueued_jobs(only: SendSponsorshipCancellationEmailJob) do
          activity.save!
        end
      end

      test "enqueues a job to send a sponsorship cancellation email when the activity is due to a cancellation of a Patreon sponsorship and the sponsorable still has Patreon linked and enabled" do
        create(:sponsors_patreon_user, :with_tier, enabled_as_sponsorable: true, user: @sponsorable)
        activity = build(:sponsors_activity, :cancelled_sponsorship, :patreon, sponsor: @sponsor, sponsorable: @sponsorable)

        assert_enqueued_with(job: SendSponsorshipCancellationEmailJob, args: [{ sponsors_activity: activity }]) do
          activity.save!
        end
      end

      test "does not enqueue a job to send a sponsorship cancellation email when the activity is not a sponsorship cancellation" do
        activity = build(:sponsors_activity, :pending_cancellation, sponsorable: @sponsorable)

        assert_no_enqueued_jobs(only: SendSponsorshipCancellationEmailJob) do
          activity.save!
        end
      end
    end

    context "async_current_privacy_level" do
      test "returns privacy level of associated sponsorship" do
        sponsorship = create(:sponsorship, :public, sponsor: @activity.sponsor, sponsorable: @activity.sponsorable)
        refute_nil @activity.sponsorship, "expected sponsorship to exist"
        assert_equal sponsorship, @activity.sponsorship, "expected reference to created sponsorship"

        assert_equal "public", @activity.async_current_privacy_level.sync

        # user updates the privacy of their sponsorship
        sponsorship.update!(privacy_level: :private)
        @activity.reload

        assert_equal "private", @activity.async_current_privacy_level.sync
      end

      test "returns nil when no associated sponsorship exists" do
        assert_nil @activity.sponsorship, "expected sponsorship to be missing"

        assert_nil @activity.async_current_privacy_level.sync
      end
    end

    context "with_currently_public_sponsorship scope" do
      test "returns only the activities with public sponsorships" do
        with_public_sponsorship1 = create(:sponsors_activity, :new_sponsorship, :with_public_sponsorship)
        sponsorable = with_public_sponsorship1.sponsorable
        with_public_sponsorship2 = create(:sponsors_activity, :new_sponsorship, :with_public_sponsorship,
          sponsorable: sponsorable
        )
        with_private_sponsorship = create(:sponsors_activity, :new_sponsorship, :with_private_sponsorship,
          sponsorable: sponsorable
        )
        missing_sponsorship = create(:sponsors_activity, :new_sponsorship,
          sponsorable: sponsorable
        )

        activities = SponsorsActivity.with_currently_public_sponsorship.for_sponsorable(sponsorable)

        assert_same_elements [with_public_sponsorship1, with_public_sponsorship2], activities.to_a
      end
    end
  end
end
