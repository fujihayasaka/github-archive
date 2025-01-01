# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsListingTest < GitHub::TestCase
  include HydroTestHelpers
  include SponsorsListingTestHelper

  fixtures do
    @waitlisted_listing = create(:sponsors_listing, :waitlisted, :with_customized_sponsorable_profile)
    @waitlisted_org = create(:organization)
    @listing = create(:sponsors_listing)
    @exempt_listing = create(:sponsors_listing, :approved, :exempt_from_payout_probation)
    @org_listing = create(:sponsors_listing, :for_org, :approved)
    @pending_listing = create(:sponsors_listing, :with_w8_or_w9_verified_stripe_account, :pending_approval)
    @disabled_listing = create(:sponsors_listing, :disabled)
    @approved_listing = create(:sponsors_listing, :approved, :with_w8_or_w9_verified_stripe_account)
    @auto_approvable_sponsorable = create(:user, :sponsors_auto_approvable)
    @auto_approvable_listing = @auto_approvable_sponsorable.sponsors_listing
    @published_tier = @auto_approvable_listing.sponsors_tiers.first
    @staff = create(:staff_admin_user, login: GitHub.staff_user_login)
    @biztools_user = create(:biztools_user)
    @osc = create(:organization, :open_source_collective)
    @osc_stripe = create(:stripe_connect_account, :w8_or_w9_verified, sponsors_listing: @osc.sponsors_listing)
    @fiscal_host_listing = create(:sponsors_listing, :fiscal_host, :with_customized_sponsorable_profile, sponsorable_login: "numfocus")
    @fiscal_host_stripe = create(:stripe_connect_account, sponsors_listing: @fiscal_host_listing)
  end

  setup do
    skip unless GitHub.sponsors_enabled?
  end

  def stub_stripe_balance(stripe_account, amount:)
    if amount > 0
      create(:payouts_ledger_entry, :transfer, stripe_connect_account: stripe_account,
        sponsors_listing: stripe_account.sponsors_listing, amount_in_subunits: amount * 100)
    end

    fake_balance_result = stub(available: [stub(amount: amount)])
    fake_balance_object = stub(success?: true, result: fake_balance_result)
    Billing::StripeConnect::Account.any_instance.stubs(:current_balance).
      returns(fake_balance_object)
  end

  context ".sponsors_slug?" do
    test "returns true for Sponsors listing slug" do
      listing = create(:sponsors_listing)
      assert_predicate listing.slug, :present?
      assert SponsorsListing.sponsors_slug?(listing.slug)
    end

    test "returns false for Marketplace listing slug" do
      listing = create(:marketplace_listing)
      assert_predicate listing.slug, :present?
      refute SponsorsListing.sponsors_slug?(listing.slug)
    end
  end

  context "#has_published_recurring_tier_with_monthly_price?" do
    test "returns true when a published, recurring tier has the specified monthly amount" do
      assert_predicate @published_tier, :recurring?, "need a recurring tier"
      listing = @published_tier.sponsors_listing
      assert listing.has_published_recurring_tier_with_monthly_price?(@published_tier.monthly_price_in_cents)
    end

    test "returns false when only a one-time tier is published at that monthly amount" do
      one_time_tier = create(:sponsors_tier, :published, :one_time)
      listing = one_time_tier.sponsors_listing
      refute listing.has_published_recurring_tier_with_monthly_price?(one_time_tier.monthly_price_in_cents)
    end

    test "returns false when the recurring tier of the given amount is not published" do
      non_published_tier = create(:sponsors_tier, :retired)
      listing = non_published_tier.sponsors_listing
      refute listing.has_published_recurring_tier_with_monthly_price?(non_published_tier.monthly_price_in_cents)
    end

    test "returns false when the listing has no tiers" do
      listing = create(:sponsors_listing, tier_count: 0)
      refute listing.has_published_recurring_tier_with_monthly_price?(100)
    end
  end

  context ".support_url" do
    test "returns a URL for contacting support about Sponsors" do
      assert_equal "https://support.github.com/contact/account?type=github_sponsors", SponsorsListing.support_url
    end

    test "includes given URL parameters, escaped as necessary" do
      assert_equal "https://support.github.com/contact/account?subject=GitHub+Sponsors%3A+we+love+you" \
        "&type=github_sponsors", SponsorsListing.support_url(subject: "GitHub Sponsors: we love you")
    end
  end

  context "#amount_meets_required_minimum?" do
    test "returns true for $1 when listing has no minimum custom amount set" do
      assert_nil @listing.min_custom_tier_amount_in_cents, "need a listing with no min custom amount"
      assert @listing.amount_meets_required_minimum?(1_00)
    end

    test "returns true when given listing's minimum custom amount" do
      @listing.update!(min_custom_tier_amount_in_cents: 5_00)
      assert @listing.amount_meets_required_minimum?(5_00)
    end

    test "returns true when given an amount exceeding the listing's minimum custom amount" do
      @listing.update!(min_custom_tier_amount_in_cents: 5_00)
      assert @listing.amount_meets_required_minimum?(6_00)
    end

    test "returns false when given an amount below the listing's minimum custom amount" do
      @listing.update!(min_custom_tier_amount_in_cents: 5_00)
      refute @listing.amount_meets_required_minimum?(4_00)
    end

    test "returns false when given an amount less than $1" do
      refute @listing.amount_meets_required_minimum?(50) # $0.50
    end
  end

  context "#encourage_setting_country_of_residence?" do
    test "returns true when country of residence is blank, listing is for a user, and in draft state" do
      listing = SponsorsListing.new(country_of_residence: nil)
      assert_predicate listing, :encourage_setting_country_of_residence?
    end

    test "returns true when country of residence is blank, listing is for a user, and in pending_approval state" do
      listing = SponsorsListing.new(country_of_residence: nil, state: :pending_approval)
      assert_predicate listing, :encourage_setting_country_of_residence?
    end

    test "returns true when country of residence is blank, listing is for a user, and in requires_additional_review state" do
      listing = SponsorsListing.new(country_of_residence: nil, state: :requires_additional_review)
      assert_predicate listing, :encourage_setting_country_of_residence?
    end

    test "returns true when country of residence is blank, listing is for a user, and in queued_for_auto_approval state" do
      listing = SponsorsListing.new(country_of_residence: nil, state: :queued_for_auto_approval)
      assert_predicate listing, :encourage_setting_country_of_residence?
    end

    test "returns true when country of residence is blank, listing is for a user, and in approved state" do
      listing = SponsorsListing.new(country_of_residence: nil, state: :approved)
      assert_predicate listing, :encourage_setting_country_of_residence?
    end

    test "returns true when country of residence is blank, listing is for a user, and in waitlisted state" do
      listing = SponsorsListing.new(country_of_residence: nil, state: :waitlisted)
      assert_predicate listing, :encourage_setting_country_of_residence?
    end

    test "returns false when in disabled state" do
      listing = SponsorsListing.new(country_of_residence: nil, state: :disabled)
      refute_predicate listing, :encourage_setting_country_of_residence?
    end

    test "returns false when in sdn_disabled state" do
      listing = SponsorsListing.new(country_of_residence: nil, state: :sdn_disabled)
      refute_predicate listing, :encourage_setting_country_of_residence?
    end

    test "returns false when in spammy state" do
      listing = SponsorsListing.new(country_of_residence: nil, state: :spammy)
      refute_predicate listing, :encourage_setting_country_of_residence?
    end

    test "returns false when in banned state" do
      listing = SponsorsListing.new(country_of_residence: nil, state: :banned)
      refute_predicate listing, :encourage_setting_country_of_residence?
    end

    test "returns false when country of residence is set" do
      listing = SponsorsListing.new(country_of_residence: "US")
      refute_predicate listing, :encourage_setting_country_of_residence?
    end

    test "returns false when listing is for an organization" do
      listing = SponsorsListing.new(country_of_residence: nil, sponsorable: create(:organization))
      refute_predicate listing, :encourage_setting_country_of_residence?
    end
  end

  context "#sync_sponsors_patreon_user" do
    test "enqueues job to sync maintainer with Patreon when they have connected a Patreon account" do
      spu = create(:sponsors_patreon_user, :sponsor, user: @listing.sponsorable)
      @listing.actor = @staff

      # Wait long enough to allow enqueuing the same job for the sponsorable, since creating the SponsorsPatreonUser
      # enqueues one:
      travel_to (SyncSponsorsPatreonUserJob::LOCKOUT_IN_MINUTES + 1).minutes.from_now

      assert_no_enqueued_jobs(only: SyncPatreonSponsorshipsJob) do
        assert_enqueued_with(job: SyncSponsorsPatreonUserJob, args: [spu, { actor: @staff }]) do
          @listing.sync_sponsors_patreon_user
        end
      end
    end

    test "does not enqueue job to sync maintainer with Patreon when they are not connected with Patreon" do
      assert_nil @listing.sponsorable.sponsors_patreon_user

      assert_no_enqueued_jobs(only: [SyncSponsorsPatreonUserJob, SyncPatreonSponsorshipsJob]) do
        @listing.sync_sponsors_patreon_user
      end
    end
  end

  context "#colliding_published_tier" do
    test "returns a one-time tier with the same price" do
      one_time_tier = create(:sponsors_tier, :one_time, :published, sponsors_listing: @approved_listing)

      result = @approved_listing.colliding_published_tier(amount: one_time_tier.monthly_price_in_dollars,
        is_recurring: false)

      assert_equal one_time_tier, result
    end

    test "returns a recurring tier with the same price" do
      recurring_tier = @approved_listing.default_tier
      assert_predicate recurring_tier, :recurring?

      result = @approved_listing.colliding_published_tier(amount: recurring_tier.monthly_price_in_dollars,
        is_recurring: true)

      assert_equal recurring_tier, result
    end

    test "returns nil when no one-time tier with that price exists" do
      one_time_tier = create(:sponsors_tier, :one_time, :published, sponsors_listing: @approved_listing)

      result = @approved_listing.colliding_published_tier(
        amount: one_time_tier.monthly_price_in_dollars + 1,
        is_recurring: false,
      )

      assert_nil result
    end

    test "returns nil when no recurring tier with that price exists" do
      recurring_tier = @approved_listing.default_tier
      assert_predicate recurring_tier, :recurring?

      result = @approved_listing.colliding_published_tier(amount: recurring_tier.monthly_price_in_dollars + 1,
        is_recurring: true)

      assert_nil result
    end
  end

  context "#sponsor_exists_and_is_visible_to?" do
    test "returns false when viewer is not part of the private sponsorship" do
      sponsorship = create(:sponsorship, :private)
      sponsor = sponsorship.sponsor
      refute sponsorship.sponsors_listing.sponsor_exists_and_is_visible_to?(sponsor, viewer: nil)

      rando = create(:user)
      refute sponsorship.sponsors_listing.sponsor_exists_and_is_visible_to?(sponsor, viewer: rando)
    end

    test "returns true when viewer is part of the private sponsorship" do
      sponsorship = create(:sponsorship, :private)
      sponsor = sponsorship.sponsor
      assert sponsorship.sponsors_listing.sponsor_exists_and_is_visible_to?(sponsor, viewer: sponsor)

      rando = create(:user)
      assert sponsorship.sponsors_listing.sponsor_exists_and_is_visible_to?(sponsor, viewer: sponsorship.sponsorable)
    end

    test "returns true for admin of an org that receives a private sponsorship" do
      org = @org_listing.sponsorable
      sponsorship = create(:sponsorship, :private, sponsorable: org)
      org_admin = org.admins.first

      refute_nil org_admin
      assert @org_listing.sponsor_exists_and_is_visible_to?(sponsorship.sponsor, viewer: org_admin)
    end

    test "returns true for member of an org that receives a private sponsorship" do
      org = @org_listing.sponsorable
      sponsorship = create(:sponsorship, :private, sponsorable: org)
      org_member = create(:user)
      org.add_member(org_member)

      assert @org_listing.sponsor_exists_and_is_visible_to?(sponsorship.sponsor, viewer: org_member)
    end

    test "returns false for non-member of an org that receives a private sponsorship" do
      sponsorship = create(:sponsorship, :private, sponsorable: @org_listing.sponsorable)
      rando = create(:user)

      refute @org_listing.sponsor_exists_and_is_visible_to?(sponsorship.sponsor, viewer: rando)
    end

    test "returns true for admin of an org that gives a private sponsorship" do
      sponsorship = create(:sponsorship, :private, :from_org)
      org = sponsorship.sponsor
      org_admin = org.admins.first

      refute_nil org_admin
      assert sponsorship.sponsors_listing.sponsor_exists_and_is_visible_to?(org, viewer: org_admin)
    end

    test "returns true for member of an org that gives a private sponsorship" do
      sponsorship = create(:sponsorship, :private, :from_org)
      org = sponsorship.sponsor
      org_member = create(:user)
      org.add_member(org_member)

      assert sponsorship.sponsors_listing.sponsor_exists_and_is_visible_to?(org, viewer: org_member)
    end

    test "returns false for non-member of an org that gives a private sponsorship" do
      sponsorship = create(:sponsorship, :private, :from_org)
      org = sponsorship.sponsor
      rando = create(:user)

      refute sponsorship.sponsors_listing.sponsor_exists_and_is_visible_to?(org, viewer: rando)
    end

    test "returns true for one-time sponsor who sponsored recently" do
      sponsorship = create(:sponsorship, :one_time, sponsorable: @approved_listing.sponsorable)
      assert @approved_listing.sponsor_exists_and_is_visible_to?(sponsorship.sponsor, viewer: sponsorship.sponsor)
    end

    test "returns false for one-time sponsor who sponsored long ago" do
      sponsorship = create(:sponsorship, :one_time, :expired, sponsorable: @approved_listing.sponsorable)
      refute @approved_listing.sponsor_exists_and_is_visible_to?(sponsorship.sponsor, viewer: sponsorship.sponsor)
    end
  end

  context "uncustomized_github_profile scope" do
    test "filters based on whether the sponsorable has customized their user profile" do
      sponsorable1 = create(:user, :sponsorable)
      create(:profile, user: sponsorable1, name: "Nice Profile")
      sponsorable2 = create(:user, :sponsorable)
      customized_listing = sponsorable1.sponsors_listing
      uncustomized_listing = sponsorable2.sponsors_listing

      result = SponsorsListing.uncustomized_github_profile
        .where(id: [customized_listing, uncustomized_listing]).pluck(:id)

      assert_includes result, uncustomized_listing.id
      refute_includes result, customized_listing.id
    end
  end

  context "matches_sponsorable_login scope" do
    test "includes sponsorables whose login starts with the specified string, case insensitive" do
      listing1 = create(:sponsors_listing, :for_org, sponsorable_login: "catFacts")
      listing2 = create(:sponsors_listing, sponsorable_login: "CATEGORIES123")
      listing3 = create(:sponsors_listing, sponsorable_login: "DogTreats")
      listing4 = create(:sponsors_listing, sponsorable_login: "Facts-About-Cats")
      listing_ids = [listing1.id, listing2.id, listing3.id, listing4.id]

      result = SponsorsListing.matches_sponsorable_login("cat").where(id: listing_ids)

      assert_includes result, listing1
      assert_includes result, listing2
      refute_includes result, listing3, "should not match listing whose sponsorable login does not include query"
      refute_includes result, listing4, "should not match listing whose sponsorable login ends with query"
    end

    test "sanitizes given query string to avoid SQL injection" do
      sql = SponsorsListing.matches_sponsorable_login("Robert'); DROP TABLE Students;--").to_sql
      assert_includes sql, "LIKE '#{SponsorsListing::SLUG_PREFIX}Robert\\'); DROP TABLE Students;--%'"
    end
  end

  context "waitlist_queue scope" do
    test "returns users and orgs who have signed up for Sponsors but aren't yet accepted, ordered by Sponsors signup date" do
      medium_user_listing = create(:sponsors_listing, :waitlisted, joined_at: 1.month.ago)
      old_org_listing = create(:sponsors_listing, :waitlisted, joined_at: 1.year.ago)
      new_user_listing = create(:sponsors_listing, :waitlisted)

      result = SponsorsListing.waitlist_queue
        .where(id: [new_user_listing, medium_user_listing, old_org_listing])

      assert_equal [old_org_listing, medium_user_listing, new_user_listing], result
    end

    test "omits spammy users" do
      spammer = create(:spammy_user)
      listing = create(:sponsors_listing, :waitlisted, sponsorable: spammer)

      result = SponsorsListing.waitlist_queue.where(id: [listing])

      assert_empty result
    end if GitHub.spamminess_check_enabled?

    test "omits suspended users" do
      suspended_user = create(:suspended_user)
      listing = create(:sponsors_listing, :waitlisted, sponsorable: suspended_user)

      result = SponsorsListing.waitlist_queue.where(id: [listing])

      assert_empty result
    end

    test "omits ignored user" do
      ignored_user_listing = create(:sponsors_listing, :waitlisted, :ignored)
      result = SponsorsListing.waitlist_queue.where(id: [ignored_user_listing])
      assert_empty result
    end
  end

  context "after_listing scope" do
    test "includes listings that were made more recently than the specified one" do
      old_listing = travel_to(1.day.ago) { create(:sponsors_listing) }
      medium_listing = travel_to(1.hour.ago) { create(:sponsors_listing) }
      new_listing = create(:sponsors_listing)

      result = SponsorsListing.after_listing(medium_listing)
        .where(id: [new_listing, medium_listing, old_listing])
        .pluck(:id)

      assert_equal [new_listing.id], result
    end
  end

  context "with_sponsorable_logins scope" do
    test "includes listings who have a user or org with any of the given logins" do
      logins = [@fiscal_host_listing.sponsorable_login, @approved_listing.sponsorable_login]

      result = SponsorsListing.with_sponsorable_logins(logins)
        .where(id: [@fiscal_host_listing, @approved_listing, @listing])
        .pluck(:id)

      assert_includes result, @fiscal_host_listing.id
      assert_includes result, @approved_listing.id
      refute_includes result, @listing.id
    end

    test "includes listing who have a user or org with the given login" do
      result = SponsorsListing.with_sponsorable_logins(@fiscal_host_listing.sponsorable_login)
        .where(id: [@fiscal_host_listing, @approved_listing, @listing])
        .pluck(:id)

      assert_includes result, @fiscal_host_listing.id
      refute_includes result, @approved_listing.id
      refute_includes result, @listing.id
    end
  end

  context "without_current_pending_or_flagged_fraud_review scope" do
    test "only includes listings that have no pending or flagged fraud reviews" do
      no_fraud_reviews_listing, resolved_listing, pending_listing, flagged_listing = [
        @listing, @org_listing, @pending_listing, @approved_listing
      ]
      create(:sponsors_fraud_review, sponsors_listing: pending_listing)
      create(:sponsors_fraud_review, :resolved, sponsors_listing: resolved_listing)
      create(:sponsors_fraud_review, :flagged, sponsors_listing: flagged_listing)
      listing_ids = [no_fraud_reviews_listing, resolved_listing, pending_listing, flagged_listing].map(&:id)

      result = SponsorsListing.where(id: listing_ids).without_current_pending_or_flagged_fraud_review.to_a

      assert_same_elements result, [resolved_listing, no_fraud_reviews_listing]
    end

    test "returns a single listing when it has multiple resolved reviews" do
      create(:sponsors_fraud_review, :resolved, sponsors_listing: @listing)
      create(:sponsors_fraud_review, :resolved, sponsors_listing: @listing)

      result = SponsorsListing.where(id: @listing.id).without_current_pending_or_flagged_fraud_review.to_a

      assert_equal result, [@listing]
    end

    test "does not include listing with past resolved and current pending review" do
      create(:sponsors_fraud_review, :resolved, sponsors_listing: @listing)
      create(:sponsors_fraud_review, :pending, sponsors_listing: @listing)

      result = SponsorsListing.where(id: @listing.id).without_current_pending_or_flagged_fraud_review.to_a

      assert_empty result
    end
  end

  context "not_ignored scope" do
    test "omits listing whose metadata has ignored_at set" do
      @listing.stafftools_metadata.update!(ignored_at: Time.now)
      result = SponsorsListing.not_ignored.where(id: @listing)
      assert_empty result
    end

    test "includes listing whose metadata has nil ignored_at" do
      listing = create(:sponsors_listing)
      assert_nil listing.stafftools_metadata.ignored_at
      result = SponsorsListing.not_ignored.where(id: listing)
      assert_equal [listing], result
    end
  end

  context "#safe_to_update_slug?" do
    test "true if the listing has no tiers" do
      listing = create(:sponsors_listing, tier_count: 0)
      assert_predicate listing, :safe_to_update_slug?
    end

    test "true if the listing's tiers have no product UUIDs" do
      listing = create(:sponsors_listing, tier_count: 1)
      assert_predicate listing, :safe_to_update_slug?
    end

    test "false if any of the listing's tiers have a product UUID" do
      listing = create(:sponsors_listing, tier_count: 1)
      create(:billing_product_uuid, :sponsors_tier, tier: listing.default_tier)
      refute_predicate listing, :safe_to_update_slug?
    end
  end

  context "#update_slug" do
    test "changes listing slug, renames Zuora product, and updates Zuora product's maintainer name" do
      old_slug = @approved_listing.slug
      new_login = "someNewUsername"
      new_slug = SponsorsListing.slug_for(new_login)

      @approved_listing.expects(:update_zuora_product_and_maintainer_name).once.with(
        old_slug: old_slug,
        new_slug: new_slug,
        new_login: new_login,
      ).returns(true)

      update_success = @approved_listing.update_slug(new_login: new_login)

      assert update_success, "should have returned true to indicate the slug change was a success"
      assert_equal new_slug, @approved_listing.reload.slug, "should have updated the listing's slug"
    end

    test "reverts slug change if Zuora update fails" do
      old_slug = @approved_listing.slug
      new_login = "someNewUsername"
      new_slug = SponsorsListing.slug_for(new_login)

      @approved_listing.expects(:update_zuora_product_and_maintainer_name).once.with(
        old_slug: old_slug,
        new_slug: new_slug,
        new_login: new_login,
      ).returns(false)

      update_success = @approved_listing.update_slug(new_login: new_login)

      refute update_success, "should have returned false to indicate the slug change failed"
      assert_equal old_slug, @approved_listing.reload.slug, "should have restored the listing's original slug"
    end
  end

  context "without_time_zone scope" do
    test "excludes listings whose sponsorable's time zone is known" do
      sponsorable_with_tz = create(:user, :sponsorable, time_zone_name: "America/Los_Angeles")
      sponsorable_wo_tz = create(:user, :sponsorable, time_zone_name: nil)
      listing_with_tz = sponsorable_with_tz.sponsors_listing
      listing_wo_tz = sponsorable_wo_tz.sponsors_listing

      result = SponsorsListing.without_time_zone

      assert_includes result, listing_wo_tz
      refute_includes result, listing_with_tz
    end
  end

  context "without_sponsorable_time_zone_or_country_of_residence scope" do
    test "includes listings that lack a country of residence and whose sponsorable's time zone is unknown" do
      user1 = create(:user, :verified, time_zone_name: "Europe/Madrid")
      listing_with_values = create(:sponsors_listing, sponsorable: user1, country_of_residence: "ES")

      user2 = create(:user, :verified, time_zone_name: nil)
      listing_wo_tz = create(:sponsors_listing, sponsorable: user2, country_of_residence: "ES")

      user3 = create(:user, :verified, time_zone_name: "America/Los_Angeles")
      listing_wo_country = create(:sponsors_listing, sponsorable: user3)
      listing_wo_country.update_column(:country_of_residence, nil)

      user4 = create(:user, :verified, time_zone_name: nil)
      listing_wo_country_or_tz = create(:sponsors_listing, sponsorable: user4)
      listing_wo_country_or_tz.update_column(:country_of_residence, nil)

      result = SponsorsListing.without_sponsorable_time_zone_or_country_of_residence

      refute_includes result, listing_with_values
      refute_includes result, listing_wo_tz
      refute_includes result, listing_wo_country
      assert_includes result, listing_wo_country_or_tz
    end
  end

  context "with_sponsorable_time_zone_and_country_of_residence scope" do
    test "includes listings with the specified country of residence and a time zone within it" do
      user1 = create(:user, :verified, time_zone_name: "Europe/Madrid")
      listing_w_match = create(:sponsors_listing, sponsorable: user1, country_of_residence: "ES")

      user2 = create(:user, :verified, time_zone_name: "America/Los_Angeles")
      listing_wo_match = create(:sponsors_listing, sponsorable: user2, country_of_residence: "ES")

      user3 = create(:user, :verified, time_zone_name: "America/Los_Angeles")
      listing_for_other_country = create(:sponsors_listing, sponsorable: user3, country_of_residence: "US")

      user4 = create(:user, :verified, time_zone_name: nil)
      listing_wo_tz = create(:sponsors_listing, sponsorable: user4, country_of_residence: "ES")

      result = SponsorsListing.with_sponsorable_time_zone_and_country_of_residence("ES")

      assert_includes result, listing_w_match
      refute_includes result, listing_wo_match
      refute_includes result, listing_for_other_country
      refute_includes result, listing_wo_tz
    end
  end

  context "without_public_non_fork_repository scope" do
    test "includes listings whose sponsorable has only private or forked repositories" do
      sponsorable_with_fork = create(:user, :sponsorable)
      source_repo = create(:repository, from_example: :simple)
      fork_repo = create(:fork_repository, forker: sponsorable_with_fork, fork_repo: source_repo)

      sponsorable_with_private_repo = create(:user, :sponsorable)
      create(:private_repository, owner: sponsorable_with_private_repo)

      sponsorable_with_public_non_fork = create(:user, :sponsorable)
      create(:repository, :full_creation, owner: sponsorable_with_public_non_fork)

      all_listings = [sponsorable_with_fork, sponsorable_with_private_repo, sponsorable_with_public_non_fork]
        .map(&:sponsors_listing)

      result = SponsorsListing.without_public_non_fork_repository
        .where(id: all_listings.map(&:id)).pluck(:id)

      assert_includes result, sponsorable_with_fork.sponsors_listing.id
      assert_includes result, sponsorable_with_private_repo.sponsors_listing.id
      refute_includes result, sponsorable_with_public_non_fork.sponsors_listing.id
    end
  end

  context "sponsorable_time_zone_matches_country_of_residence scope" do
    test "includes listings whose sponsorable's time zone exists in the listing's country of residence" do
      user1 = create(:user, :verified, time_zone_name: "Europe/Budapest")
      listing_w_mismatch = create(:sponsors_listing, sponsorable: user1, country_of_residence: "US")

      user2 = create(:user, :verified, time_zone_name: "Europe/Madrid")
      listing_w_match = create(:sponsors_listing, sponsorable: user2, country_of_residence: "ES")

      user3 = create(:user, :verified, time_zone_name: nil)
      listing_wo_tz = create(:sponsors_listing, sponsorable: user3, country_of_residence: "CA")

      user4 = create(:user, :verified, time_zone_name: "America/Los_Angeles")
      listing_wo_country = create(:sponsors_listing, sponsorable: user4)
      listing_wo_country.update_column(:country_of_residence, nil)

      user5 = create(:user, :verified, time_zone_name: nil)
      listing_wo_country_or_tz = create(:sponsors_listing, sponsorable: user5)
      listing_wo_country_or_tz.update_column(:country_of_residence, nil)

      all_listings = [listing_w_mismatch, listing_w_match, listing_wo_tz, listing_wo_country,
        listing_wo_country_or_tz]

      result = SponsorsListing.sponsorable_time_zone_matches_country_of_residence
        .where(id: all_listings.map(&:id)).pluck(:id)

      refute_includes result, listing_w_mismatch.id,
        "should not include listing whose sponsorable's time zone does not match the country of residence"
      assert_includes result, listing_w_match.id,
        "should include listing whose sponsorable's time zone matches the country of residence"
      refute_includes result, listing_wo_tz.id,
        "should not include listing that has a country of residence but whose sponsorable lacks a time zone"
      refute_includes result, listing_wo_country.id,
        "should not include listing that has no country of residence but whose sponsorable has a time zone"
      assert_includes result, listing_wo_country_or_tz.id,
        "should include listing that has no country of residence and whose sponsorable lacks a time zone"
    end
  end

  context "mismatched_time_zone scope" do
    test "includes listings whose sponsorable's time zone does not exist in the listing's country of residence" do
      user1 = create(:user, :verified, time_zone_name: "Europe/Budapest")
      listing_w_mismatch = create(:sponsors_listing, sponsorable: user1, country_of_residence: "US")

      user2 = create(:user, :verified, time_zone_name: "Europe/Madrid")
      listing_w_match = create(:sponsors_listing, sponsorable: user2, country_of_residence: "ES")

      user3 = create(:user, :verified, time_zone_name: nil)
      listing_wo_tz = create(:sponsors_listing, sponsorable: user3, country_of_residence: "CA")

      user4 = create(:user, :verified, time_zone_name: "America/Los_Angeles")
      listing_wo_country = create(:sponsors_listing, sponsorable: user4)
      listing_wo_country.update_column(:country_of_residence, nil)

      user6 = create(:user, :verified, time_zone_name: nil)
      listing_wo_country_or_tz = create(:sponsors_listing, sponsorable: user6)
      listing_wo_country_or_tz.update_column(:country_of_residence, nil)

      all_listings = [listing_w_mismatch, listing_w_match, listing_wo_tz, listing_wo_country,
        listing_wo_country_or_tz]

      result = SponsorsListing.mismatched_time_zone.where(id: all_listings.map(&:id)).pluck(:id)

      assert_includes result, listing_w_mismatch.id,
        "should include listing whose country of residence does not match the sponsorable's time zone"
      refute_includes result, listing_w_match.id,
        "should not include listing whose country of residence matches the sponsorable's time zone"
      refute_includes result, listing_wo_tz.id,
        "should not include listing with a country of residence and no time zone"
      assert_includes result, listing_wo_country.id,
        "should include listing with no country of residence and a time zone"
      refute_includes result, listing_wo_country_or_tz.id,
        "should not include listing that has neither a country of residence nor a time zone"
    end
  end

  context "with_unsupported_time_zone scope" do
    test "includes listings whose sponsorable has a time zone for a country we don't support" do
      supported_tz_user = create(:user, :sponsorable, time_zone_name: "America/Los_Angeles")
      unsupported_tz_user = create(:user, :sponsorable, time_zone_name: "Kabul")
      assert_includes Billing::StripeConnect::Account.unsupported_countries, "AF", "need a country we don't support"
      assert_includes ActiveSupport::TimeZone.country_zones("AF").map(&:name), "Kabul",
        "need a time zone for a country we don't support"
      supported_tz_listing = supported_tz_user.sponsors_listing
      unsupported_tz_listing = unsupported_tz_user.sponsors_listing

      result = SponsorsListing.with_unsupported_time_zone
        .where(id: [supported_tz_listing.id, unsupported_tz_listing.id]).pluck(:id)

      assert_includes result, unsupported_tz_listing.id
      refute_includes result, supported_tz_listing.id
    end
  end

  context "filter_by_flags scope" do
    test "filters by account-age flag" do
      old_timestamp = (SponsorsListingStafftoolsMetadata::NEW_ACCOUNT_AGE_CUTOFF_IN_DAYS + 1).days.ago
      old_listing = create(:user, :sponsorable, created_at: old_timestamp).sponsors_listing
      new_listing = create(:user, :sponsorable, created_at: DateTime.now).sponsors_listing

      result = SponsorsListing.filter_by_flags(["recently_created_github_account"])
        .where(id: [old_listing, new_listing]).pluck(:id)

      assert_includes result, new_listing.id
      refute_includes result, old_listing.id
    end

    test "filters by customized-profile flag" do
      sponsorable1 = create(:user, :sponsorable)
      create(:profile, user: sponsorable1, name: "Nice Profile")
      sponsorable2 = create(:user, :sponsorable)
      customized_listing = sponsorable1.sponsors_listing
      uncustomized_listing = sponsorable2.sponsors_listing

      result = SponsorsListing.filter_by_flags(["uncustomized_github_profile"])
        .where(id: [customized_listing, uncustomized_listing]).pluck(:id)

      assert_includes result, uncustomized_listing.id
      refute_includes result, customized_listing.id
    end

    test "filters by lack of a time zone" do
      sponsorable_with_tz = create(:user, :sponsorable, time_zone_name: "America/Chicago")
      sponsorable_wo_tz = create(:user, :sponsorable, time_zone_name: nil)
      listing_with_tz = sponsorable_with_tz.sponsors_listing
      listing_wo_tz = sponsorable_wo_tz.sponsors_listing

      result = SponsorsListing.filter_by_flags(["no_time_zone"])
        .where(id: [listing_with_tz, listing_wo_tz]).pluck(:id)

      assert_includes result, listing_wo_tz.id
      refute_includes result, listing_with_tz.id
    end

    test "filters by unsupported time zone" do
      supported_tz_user = create(:user, :sponsorable, time_zone_name: "America/Los_Angeles")
      unsupported_tz_user = create(:user, :sponsorable, time_zone_name: "Kabul")
      assert_includes Billing::StripeConnect::Account.unsupported_countries, "AF", "need a country we don't support"
      assert_includes ActiveSupport::TimeZone.country_zones("AF").map(&:name), "Kabul",
        "need a time zone for a country we don't support"
      supported_tz_listing = supported_tz_user.sponsors_listing
      unsupported_tz_listing = unsupported_tz_user.sponsors_listing

      result = SponsorsListing.filter_by_flags(["unsupported_time_zone"])
        .where(id: [supported_tz_listing, unsupported_tz_listing]).pluck(:id)

      assert_includes result, unsupported_tz_listing.id
      refute_includes result, supported_tz_listing.id
    end

    test "filters by lack of a public non-fork repository" do
      sponsorable_with_fork = create(:user, :sponsorable)
      source_repo = create(:repository, from_example: :simple)
      fork_repo = create(:fork_repository, forker: sponsorable_with_fork, fork_repo: source_repo)

      sponsorable_with_private_repo = create(:user, :sponsorable)
      create(:private_repository, owner: sponsorable_with_private_repo)

      sponsorable_with_public_non_fork = create(:user, :sponsorable)
      create(:repository, :full_creation, owner: sponsorable_with_public_non_fork)

      all_listings = [sponsorable_with_fork, sponsorable_with_private_repo, sponsorable_with_public_non_fork]
        .map(&:sponsors_listing)

      result = SponsorsListing.filter_by_flags(["no_public_non_fork_repos"])
        .where(id: all_listings.map(&:id)).pluck(:id)

      assert_includes result, sponsorable_with_fork.sponsors_listing.id
      assert_includes result, sponsorable_with_private_repo.sponsors_listing.id
      refute_includes result, sponsorable_with_public_non_fork.sponsors_listing.id
    end

    test "filters by whether the time zone does not match the country of residence" do
      user1 = create(:user, :verified, time_zone_name: "Europe/Budapest")
      listing_w_mismatch = create(:sponsors_listing, sponsorable: user1, country_of_residence: "US")

      user2 = create(:user, :verified, time_zone_name: "Europe/Madrid")
      listing_w_match = create(:sponsors_listing, sponsorable: user2, country_of_residence: "ES")

      user3 = create(:user, :verified, time_zone_name: nil)
      listing_wo_tz = create(:sponsors_listing, sponsorable: user3, country_of_residence: "CA")

      user4 = create(:user, :verified, time_zone_name: "America/Los_Angeles")
      listing_wo_country = create(:sponsors_listing, sponsorable: user4)
      listing_wo_country.update_column(:country_of_residence, nil)

      user6 = create(:user, :verified, time_zone_name: nil)
      listing_wo_country_or_tz = create(:sponsors_listing, sponsorable: user6)
      listing_wo_country_or_tz.update_column(:country_of_residence, nil)

      all_listings = [listing_w_mismatch, listing_w_match, listing_wo_tz, listing_wo_country,
        listing_wo_country_or_tz]

      result = SponsorsListing.filter_by_flags(["mismatched_time_zone"])
        .where(id: all_listings).pluck(:id)

      assert_includes result, listing_w_mismatch.id
      refute_includes result, listing_w_match.id
      refute_includes result, listing_wo_tz.id
      assert_includes result, listing_wo_country.id
      refute_includes result, listing_wo_country_or_tz.id
    end

    test "filters by many flags at once" do
      old_timestamp = (SponsorsListingStafftoolsMetadata::NEW_ACCOUNT_AGE_CUTOFF_IN_DAYS + 1).days.ago
      old_sponsorable1, old_sponsorable2 = create_list(:user, 2, :sponsorable, created_at: old_timestamp)
      new_sponsorable1, new_sponsorable2 = create_list(:user, 2, :sponsorable, created_at: DateTime.now)
      create(:profile, user: old_sponsorable1, name: "Nice Profile")
      create(:profile, user: new_sponsorable1, name: "Nice Profile")
      customized_old_listing = old_sponsorable1.sponsors_listing
      customized_new_listing = new_sponsorable1.sponsors_listing
      uncustomized_old_listing = old_sponsorable2.sponsors_listing
      uncustomized_new_listing = new_sponsorable2.sponsors_listing
      all_listings = [customized_old_listing, customized_new_listing, uncustomized_old_listing,
        uncustomized_new_listing]

      result = SponsorsListing.filter_by_flags(%w[uncustomized_github_profile recently_created_github_account])
        .where(id: all_listings).pluck(:id)

      assert_includes result, uncustomized_new_listing.id
      refute_includes result, uncustomized_old_listing.id
      refute_includes result, customized_new_listing.id
      refute_includes result, customized_old_listing.id
    end

    test "excludes listings that don't match all the specified filters" do
      matching_all_filters = create(:sponsors_listing, metadata_traits: [:with_unsupported_time_zone])
      matching_some_filters = create(:sponsors_listing)
      assert_predicate matching_some_filters.reload_stafftools_metadata.sponsorable_time_zone_name, :blank?

      result = SponsorsListing.filter_by_flags(%w[uncustomized_github_profile
        no_public_non_fork_repos unsupported_time_zone]).pluck(:id)

      assert_includes result, matching_all_filters.id
      refute_includes result, matching_some_filters.id, "should not include listing without a time zone"
    end
  end

  context "#min_custom_tier_amount_money" do
    test "returns a Money worth $0 when the maintainer has no minimum custom tier amount set" do
      assert_nil @listing.min_custom_tier_amount_in_cents
      assert_equal Billing::Money.new(0), @listing.min_custom_tier_amount_money
    end

    test "returns a Money worth the minimum custom tier amount when the maintainer has one set" do
      cents = 5_00
      @listing.update!(min_custom_tier_amount_in_cents: cents)
      assert_equal Billing::Money.new(cents), @listing.min_custom_tier_amount_money
    end
  end

  context "#sponsorable_primary_avatar_url" do
    test "returns the URL for the sponsorable's primary avatar when sponsorable is already loaded" do
      sponsorable = @listing.sponsorable
      assert_predicate @listing.association(:sponsorable), :loaded?
      size = 30
      expected_value = sponsorable.primary_avatar_url(size)

      result = assert_query_count(0) do
        @listing.sponsorable_primary_avatar_url(size)
      end

      assert_equal expected_value, result
    end

    # We skip this test in multitenant mode because in the said mode, it will call the `sponsorable` association
    test "returns the URL for the sponsorable's primary avatar when sponsorable is not already loaded", skip_in_multitenant_mode: true do
      size = 30
      refute_predicate @listing.association(:sponsorable), :loaded?

      result = assert_query_count(2) do
        @listing.sponsorable_primary_avatar_url(size)
      end

      assert_equal @listing.sponsorable.primary_avatar_url(size), result
    end
  end

  context "#sponsorable_login" do
    test "returns the login from the sponsorable record when it's already loaded" do
      sponsorable = @listing.sponsorable
      assert_predicate @listing.association(:sponsorable), :loaded?

      result = assert_query_count(0) do
        @listing.sponsorable_login
      end

      assert_equal sponsorable.login, result
    end

    test "returns the login from the slug when the sponsorable hasn't already been loaded" do
      expected_value = @listing.slug.sub(/^sponsors-/, "")
      refute_predicate @listing.association(:sponsorable), :loaded?

      result = assert_query_count(0) do
        @listing.sponsorable_login
      end

      assert_equal expected_value, result
      assert_equal @listing.sponsorable.login, result
    end

    test "handles if sponsorable login starts with slug prefix" do
      sponsorable = create(:user, :verified, login: "sponsors-bananas")
      listing = create(:sponsors_listing, sponsorable: sponsorable)
      assert_equal "sponsors-sponsors-bananas", listing.slug
      listing = SponsorsListing.find(listing.id) # make sure `sponsorable` relation isn't loaded
      assert_equal "sponsors-bananas", listing.sponsorable_login
    end
  end

  context "filter_by_matchableness scope" do
    test "returns listings that are matchable" do
      SponsorsListing.stub_const(:MATCHING_LIMIT_AMOUNT_IN_CENTS, 10) do
        transfer = create(:payouts_ledger_entry, :transfer, amount_in_subunits: 5)
        matchable_listing = transfer.stripe_connect_account.sponsors_listing
        matchable_listing.update!(
          match_disabled: false,
          published_at: (1.year.ago.to_date + 1.day),
          accepted_at: 1.year.ago,
          joined_at: SponsorsListing::JOINED_WAITLIST_MATCH_DEADLINE - 1.day,
        )
        listing = create(:sponsors_listing)

        result = SponsorsListing.filter_by_matchableness(true).where(id: [listing, matchable_listing])

        assert_equal [matchable_listing], result
      end
    end

    test "returns listings that are not_matchable" do
      SponsorsListing.stub_const(:MATCHING_LIMIT_AMOUNT_IN_CENTS, 10) do
        not_matchable_transfer = create(:payouts_ledger_entry, :transfer, amount_in_subunits: 11)
        not_matchable_listing = not_matchable_transfer.stripe_connect_account.sponsors_listing
        not_matchable_listing.update!(match_disabled: true)

        matchable_transfer = create(:payouts_ledger_entry, :transfer, amount_in_subunits: 5)
        matchable_listing = matchable_transfer.stripe_connect_account.sponsors_listing
        matchable_listing.update!(
          match_disabled: false,
          published_at: (1.year.ago.to_date + 1.day),
          joined_at: SponsorsListing::JOINED_WAITLIST_MATCH_DEADLINE - 1.day,
          accepted_at: 1.year.ago,
        )

        result = SponsorsListing.filter_by_matchableness(false).where(id: [not_matchable_listing, matchable_listing])

        refute_includes result, matchable_listing
        assert_includes result, not_matchable_listing
      end
    end
  end

  context "matchable scope" do
    test "returns listings that are matchable" do
      SponsorsListing.stub_const(:MATCHING_LIMIT_AMOUNT_IN_CENTS, 10) do
        transfer = create(:payouts_ledger_entry, :transfer, amount_in_subunits: 5)
        matchable_listing = transfer.stripe_connect_account.sponsors_listing
        matchable_listing.update!(
          match_disabled: false,
          published_at: (1.year.ago.to_date + 1.day),
          accepted_at: 1.year.ago,
          joined_at: SponsorsListing::JOINED_WAITLIST_MATCH_DEADLINE - 1.day,
        )
        listing = create(:sponsors_listing)

        result = SponsorsListing.matchable.where(id: [listing, matchable_listing])

        assert_equal [matchable_listing], result
      end
    end
  end

  context "not_matchable scope" do
    test "returns listings that are not_matchable" do
      SponsorsListing.stub_const(:MATCHING_LIMIT_AMOUNT_IN_CENTS, 10) do
        not_matchable_transfer = create(:payouts_ledger_entry, :transfer, amount_in_subunits: 11)
        not_matchable_listing = not_matchable_transfer.stripe_connect_account.sponsors_listing
        not_matchable_listing.update!(match_disabled: true)

        matchable_transfer = create(:payouts_ledger_entry, :transfer, amount_in_subunits: 5)
        matchable_listing = matchable_transfer.stripe_connect_account.sponsors_listing
        matchable_listing.update!(
          match_disabled: false,
          published_at: (1.year.ago.to_date + 1.day),
          accepted_at: 1.year.ago,
          joined_at: (SponsorsListing::JOINED_WAITLIST_MATCH_DEADLINE - 1.day)
        )

        result = SponsorsListing.not_matchable.where(id: [not_matchable_listing, matchable_listing])

        refute_includes result, matchable_listing
        assert_includes result, not_matchable_listing
      end
    end
  end

  context "match_limit_met scope" do
    test "returns listings who's transfers add up to more than the match limit" do
      SponsorsListing.stub_const(:MATCHING_LIMIT_AMOUNT_IN_CENTS, 10) do
        transfer = create(:payouts_ledger_entry, :transfer, amount_in_subunits: 15)
        listing = transfer.stripe_connect_account.sponsors_listing

        result = SponsorsListing.match_limit_met.where(id: [listing])

        assert_equal [listing], result
      end
    end
  end

  context "match_limit_not_met scope" do
    test "returns listings who's transfers add up to less than the match limit" do
      SponsorsListing.stub_const(:MATCHING_LIMIT_AMOUNT_IN_CENTS, 10) do
        transfer = create(:payouts_ledger_entry, :transfer, amount_in_subunits: 5)
        listing = transfer.stripe_connect_account.sponsors_listing

        result = SponsorsListing.match_limit_not_met.where(id: [listing])

        assert_equal [listing], result
      end
    end
  end

  context "joined waitlist match deadline" do
    test "joined_before_match_deadline scope" do
      @listing.update!(joined_at: SponsorsListing::JOINED_WAITLIST_MATCH_DEADLINE - 1.day)

      result = SponsorsListing.joined_before_match_deadline

      assert_includes result, @listing
    end

    test "joined_after_match_deadline scope" do
      listing = create(:sponsors_listing)

      result = SponsorsListing.joined_after_match_deadline

      assert_includes result, listing
    end
  end

  context "published before or during last year" do
    test "published_in_last_year scope" do
      @listing.update!(published_at: (1.year.ago + 1.day))

      result = SponsorsListing.published_in_last_year

      assert_includes result, @listing
    end

    test "published_prior_to_this_last_year scope" do
      @listing.update!(published_at: (1.year.ago - 1.day))

      result = SponsorsListing.published_prior_to_this_last_year

      assert_includes result, @listing
    end
  end

  # https://github.com/github/sponsors/issues/2082
  context "accepted match period before or during the last fourteen months" do
    test "accepted_in_match_period scope" do
      travel_to(Date.new(2022, 10, 1)) do
        not_eligible = create(:sponsors_listing, :draft, accepted_at: 15.months.ago)
        @listing.update!(accepted_at: 1.month.ago)

        result = SponsorsListing.accepted_in_match_period

        assert_includes result, @listing
        refute_includes result, not_eligible
      end
    end

    test "accepted_after_match_period scope" do
      travel_to(Date.new(2022, 10, 1)) do
        eligible = create(:sponsors_listing, :draft, accepted_at: 1.month.ago)
        @listing.update!(accepted_at: 15.months.ago)

        result = SponsorsListing.accepted_after_match_period

        assert_includes result, @listing
        refute_includes result, eligible
      end
    end
  end

  context "#ignore!" do
    test "sets ignored_at value on listing and metadata" do
      assert_nil @listing.stafftools_metadata.ignored_at

      @listing.ignore!(actor: @staff)

      refute_nil @listing.reload_stafftools_metadata.ignored_at
    end

    test "instruments audit log event for user" do
      events = subscribe "sponsors_membership.ignore"

      @listing.ignore!(actor: @staff)

      expected_payload = GitHub.guarded_audit_log_staff_actor_entry(@staff).merge(
        sponsors_listing_id: @listing.id,
        sponsors_listing: @listing.slug,
        short_description: @listing.short_description,
        user: @listing.sponsorable_login,
        user_id: @listing.sponsorable.id,
        state: :draft,
        created_by: @listing.sponsorable_login,
        created_by_id: @listing.sponsorable_id,
      )

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments audit log event for organization" do
      events = subscribe "sponsors_membership.ignore"

      @org_listing.ignore!(actor: @staff)

      expected_payload = GitHub.guarded_audit_log_staff_actor_entry(@staff).merge({
        sponsors_listing_id: @org_listing.id,
        sponsors_listing: @org_listing.slug,
        short_description: @org_listing.short_description,
        state: :approved,
        org: @org_listing.sponsorable_login,
        org_id: @org_listing.sponsorable.id,
        created_by: @org_listing.created_by.login,
        created_by_id: @org_listing.created_by_id,
      })

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end
  end

  context "#unignore!" do
    test "unsets ignored_at value on listing and metadata" do
      ignored_listing = create(:sponsors_listing, :ignored)
      metadata = ignored_listing.stafftools_metadata

      ignored_listing.unignore!(actor: @staff)

      assert_nil metadata.reload.ignored_at
    end

    test "instruments audit log event for user" do
      listing = create(:sponsors_listing, :ignored)
      events = subscribe "sponsors_membership.unignore"

      listing.unignore!(actor: @staff)

      expected_payload = GitHub.guarded_audit_log_staff_actor_entry(@staff).merge({
        sponsors_listing_id: listing.id,
        sponsors_listing: listing.slug,
        state: :draft,
        short_description: listing.short_description,
        user: listing.sponsorable_login,
        user_id: listing.sponsorable.id,
        created_by: listing.sponsorable_login,
        created_by_id: listing.sponsorable_id,
      })

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments audit log event for org" do
      listing = create(:sponsors_listing, :ignored, :for_org)
      events = subscribe "sponsors_membership.unignore"

      listing.unignore!(actor: @staff)

      expected_payload = GitHub.guarded_audit_log_staff_actor_entry(@staff).merge({
        sponsors_listing_id: listing.id,
        sponsors_listing: listing.slug,
        state: :draft,
        short_description: listing.short_description,
        org: listing.sponsorable_login,
        org_id: listing.sponsorable.id,
        created_by: listing.created_by.login,
        created_by_id: listing.created_by_id,
      })

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end
  end

  context "not_featured scope" do
    test "does not include listing with featured_state=active and state=approved" do
      @approved_listing.update_attribute(:featured_state, :active)
      assert_empty SponsorsListing.not_featured.where(id: [@approved_listing])
    end

    test "includes listing with featured_state=active when state is not approved" do
      @pending_listing.update_attribute(:featured_state, :active)
      assert_equal [@pending_listing], SponsorsListing.not_featured.where(id: [@pending_listing])
    end

    test "includes listing with featured_state=active when not approved" do
      @pending_listing.update_attribute(:featured_state, :active)
      assert_equal [@pending_listing], SponsorsListing.not_featured.where(id: [@pending_listing])
    end

    test "includes listing in state=approved where listing has featured_state=allowed but is ignored" do
      listing = create(:sponsors_listing, :approved, :ignored, featured_state: :allowed)
      assert_equal [listing], SponsorsListing.not_featured.where(id: [listing])
    end

    test "does not include listing in state=approved where listing has featured_state=allowed and is not ignored" do
      listing = create(:sponsors_listing, :approved, featured_state: :allowed)
      assert_empty SponsorsListing.not_featured.where(id: [listing])
    end
  end

  context "featured scope" do
    test "includes listing with featured_state=active and state=approved" do
      @approved_listing.update_attribute(:featured_state, :active)

      result = SponsorsListing.featured
        .where(id: [@approved_listing])

      assert_equal [@approved_listing], result
    end

    test "doesn't include listing with featured_state=active when state is not approved" do
      @pending_listing.update_attribute(:featured_state, :active)

      result = SponsorsListing.featured
        .where(id: [@pending_listing])

      assert_empty result
    end

    test "doesn't include listing with featured_state=active when not approved" do
      @pending_listing.update_attribute(:featured_state, :active)

      result = SponsorsListing.featured
        .where(id: [@pending_listing])

      assert_empty result
    end

    test "doesn't include listing in state=approved where listing has featured_state=allowed but is ignored" do
      listing = create(:sponsors_listing, :approved, :ignored, featured_state: :allowed)
      assert_empty SponsorsListing.featured.where(id: [listing])
    end

    test "includes listing in state=approved where listing has featured_state=allowed and is not ignored" do
      listing = create(:sponsors_listing, :approved, featured_state: :allowed)
      assert_equal [listing], SponsorsListing.featured.where(id: [listing])
    end
  end

  context "#sponsored_by_viewer?" do
    test "returns true if listing's sponsorable is sponsored by a user" do
      sponsorship = create(:sponsorship, sponsorable: @approved_listing.sponsorable)
      assert @approved_listing.sponsored_by_viewer?(sponsorship.sponsor)
    end

    test "returns false if listing's sponsorable is not sponsored by a user" do
      refute @approved_listing.sponsored_by_viewer?(create(:user))
    end

    test "returns false for nil user" do
      refute @approved_listing.sponsored_by_viewer?(nil)
    end

    test "can be preloaded to avoid N+1s" do
      sponsorship = create(:sponsorship, sponsorable: @approved_listing.sponsorable)
      user = sponsorship.sponsor
      unsponsored_listing = create(:sponsors_listing, :approved)
      GitHub::PrefillAssociations.prefill_batch_method([@approved_listing, unsponsored_listing],
        :sponsored_by_viewer?, user)

      assert_query_count 0 do
        assert @approved_listing.sponsored_by_viewer?(user)
        refute unsponsored_listing.sponsored_by_viewer?(user)
      end
    end
  end

  context "manual criteria" do
    test "creates criteria records on creation of listing" do
      criterion = create(:sponsors_criterion)
      listing = create(:sponsors_listing)
      assert_equal 1, SponsorsCriterion.for(listing.sponsorable).count
      assert_equal 1, listing.sponsors_memberships_criteria.count
    end

    test "creates manual criteria applicable to users" do
      all_criterion = create(:sponsors_criterion, applicable_to: :all)
      user_criterion = create(:sponsors_criterion, applicable_to: :user)
      org_criterion = create(:sponsors_criterion, applicable_to: :organization)

      listing = assert_difference(-> { SponsorsMembershipsCriterion.count }, 2) do
        create(:sponsors_listing)
      end

      assert listing.sponsors_memberships_criteria
        .all? { |criterion| criterion.sponsors_listing == listing }
      criteria_ids = listing.sponsors_memberships_criteria.map(&:sponsors_criterion_id)
      assert_equal [all_criterion, user_criterion], SponsorsCriterion.manual.where(id: criteria_ids)
    end

    test "creates manual criteria applicable to organizations" do
      all_criterion = create(:sponsors_criterion, applicable_to: :all)
      user_criterion = create(:sponsors_criterion, applicable_to: :user)
      org_criterion = create(:sponsors_criterion, applicable_to: :organization)

      listing = assert_difference(-> { SponsorsMembershipsCriterion.count }, 2) do
        create(:sponsors_listing, :for_org)
      end

      assert listing.sponsors_memberships_criteria
        .all? { |criterion| criterion.sponsors_listing == listing }
      criteria_ids = listing.sponsors_memberships_criteria.map(&:sponsors_criterion_id)
      assert_equal [all_criterion, org_criterion], SponsorsCriterion.manual.where(id: criteria_ids)
    end
  end

  test "scopes survey answers to sponsorable" do
    listing = create(:sponsors_listing)
    survey_answer = create :survey_answer,
      survey: listing.survey,
      user:   listing.sponsorable

    other_listing = create(:sponsors_listing, survey: listing.survey)
    create :survey_answer,
      survey: listing.survey,
      user:   other_listing.sponsorable

    assert_equal 2, SurveyAnswer.count
    assert_equal 1, listing.survey_answers.count
    assert_equal survey_answer.id, listing.survey_answers.first.id
  end

  context "destroy" do
    test "destroys the sponsors listing record when the sponsorable is destroyed" do
      sponsorable = create(:user)
      sponsors_listing = create(:sponsors_listing, sponsorable: sponsorable)

      assert_equal sponsors_listing, sponsorable.sponsors_listing

      assert_difference -> { SponsorsListing.count }, -1 do
        sponsorable.destroy
      end

      assert_raises ActiveRecord::RecordNotFound do
        sponsors_listing.reload
      end
    end

    test "destroys associated sponsors membership criteria when listing is destroyed" do
      criterion = create(:sponsors_memberships_criterion, sponsors_listing: @listing)
      @listing.destroy
      assert_nil SponsorsMembershipsCriterion.find_by(id: criterion.id)
    end

    test "destroys sponsors goals when the listing is destroyed" do
      create(:sponsors_goal, listing: @listing)

      assert_equal 1, SponsorsGoal.count
      assert_equal 1, @listing.goals.count

      assert_difference -> { SponsorsGoal.count }, -1 do
        @listing.destroy
      end
    end

    test "does not destroy the listing if there have been previous sponsorships when confirmation is blank" do
      sponsorship = create(:sponsorship, :inactive)
      listing = sponsorship.sponsors_listing

      refute_predicate listing, :destroy
      assert_includes listing.errors[:base], "@#{listing.sponsorable_login} has received sponsorships. " \
        "Please confirm their financial data from Stripe has been downloaded and github/revenue has saved the data " \
        "before deleting the Sponsors profile."
    end

    test "will destroy the listing if there are any previous sponsorships and confirmation is provided" do
      sponsorship = create(:sponsorship, :inactive)
      listing = sponsorship.sponsors_listing
      listing.deletion_confirmation = listing.sponsorable_login

      assert_predicate listing, :destroy
    end

    test "does not destroy the listing if it's a fiscal host" do
      refute_predicate @fiscal_host_listing, :destroy
      assert_includes @fiscal_host_listing.errors[:base], "Fiscal host listings can't be deleted (should be disabled)"
    end

    test "deletes the listing's tiers that have not been referenced in subscription items, sponsorships, sponsorship newsletters, or Sponsors activity records" do
      listing = create(:sponsors_listing, :approved, tier_count: 0)
      sponsorable = listing.sponsorable
      unused_tier = create(:sponsors_tier, sponsors_listing: listing)
      tier_used_in_activity1 = create(:sponsors_activity, sponsorable: sponsorable).sponsors_tier
      tier_used_in_activity2 = create(:sponsors_activity, :upgrade, sponsorable: sponsorable).old_sponsors_tier
      tier_used_in_sponsorship = create(:sponsorship, :inactive, sponsorable: sponsorable).tier
      tier_used_in_subscription_item = create(:sponsors_tier, :published, sponsors_listing: listing)
      create(:sponsors_subscription_item, :inactive, subscribable: tier_used_in_subscription_item)
      tier_used_in_newsletter = create(:sponsors_tier, :published, sponsors_listing: listing)
      create(:sponsorship_newsletter, :with_tier, sponsorable: sponsorable, tier: tier_used_in_newsletter)

      assert_difference("SponsorsTier.count", -1) do
        listing.deletion_confirmation = listing.sponsorable.display_login
        listing.destroy!
      end

      refute SponsorsTier.exists?(unused_tier.id)
      assert SponsorsTier.exists?(tier_used_in_activity1.id)
      assert SponsorsTier.exists?(tier_used_in_activity2.id)
      assert SponsorsTier.exists?(tier_used_in_sponsorship.id)
      assert SponsorsTier.exists?(tier_used_in_subscription_item.id)
      assert SponsorsTier.exists?(tier_used_in_newsletter.id)
    end
  end

  context "#reached_maximum_tier_count?" do
    test "returns false when recurring=true and not at recurring tier limit" do
      refute @auto_approvable_listing.reached_maximum_tier_count?(recurring: true)
    end

    test "returns false when recurring=false and not at one-time tier limit" do
      refute @auto_approvable_listing.reached_maximum_tier_count?(recurring: false)
    end

    test "returns true when recurring=true and at recurring tier limit" do
      SponsorsTier.stub_const(:PUBLISHED_TIER_LIMIT_PER_FREQUENCY, 1) do
        assert @auto_approvable_listing.reached_maximum_tier_count?(recurring: true)
      end
    end

    test "returns true when recurring=false and at one-time tier limit" do
      create(:sponsors_tier, :one_time, :published, sponsors_listing: @auto_approvable_listing)
      SponsorsTier.stub_const(:PUBLISHED_TIER_LIMIT_PER_FREQUENCY, 1) do
        assert @auto_approvable_listing.reached_maximum_tier_count?(recurring: false)
      end
    end
  end

  context "validations" do
    test "contact_email must be verified for pending_approval state" do
      user = create(:verified_user)
      unverified_email = create(:user_email, user: user)
      refute_predicate unverified_email, :verified?

      listing = build(:sponsors_listing, :pending_approval, sponsorable: user,
        contact_email: unverified_email)

      refute_predicate listing, :valid?
      assert_includes listing.errors[:contact_email], "must be verified"
    end

    test "contact_email must be verified for approved state" do
      user = create(:verified_user)
      unverified_email = create(:user_email, user: user)
      refute_predicate unverified_email, :verified?

      listing = build(:sponsors_listing, :approved, sponsorable: user,
        contact_email: unverified_email)

      refute_predicate listing, :valid?
      assert_includes listing.errors[:contact_email], "must be verified"
    end

    test "contact_email need not be verified for draft state" do
      user = create(:verified_user)
      unverified_email = create(:user_email, user: user)
      refute_predicate unverified_email, :verified?

      listing = build(:sponsors_listing, sponsorable: user,
        contact_email: unverified_email)

      assert_predicate listing, :valid?
    end

    test "contact_email need not be verified for disabled state" do
      user = create(:verified_user)
      unverified_email = create(:user_email, user: user)
      refute_predicate unverified_email, :verified?

      listing = build(:sponsors_listing, :disabled, sponsorable: user,
        contact_email: unverified_email)

      assert_predicate listing, :valid?
    end

    test "contact_email need not be verified for waitlisted state" do
      user = create(:verified_user)
      unverified_email = create(:user_email, user: user)
      refute_predicate unverified_email, :verified?

      listing = build(:sponsors_listing, state: :waitlisted, sponsorable: user,
        contact_email: unverified_email)

      assert_predicate listing, :valid?
    end

    test "contact_email need not be verified for banned state" do
      user = create(:verified_user)
      unverified_email = create(:user_email, user: user)
      refute_predicate unverified_email, :verified?

      listing = build(:sponsors_listing, :banned, sponsorable: user,
        contact_email: unverified_email)

      assert_predicate listing, :valid?
    end

    test "contact_email must belong to sponsorable" do
      user = create(:verified_user)
      rando_email = create(:verified_user_email)
      assert_predicate rando_email, :verified?
      refute_equal rando_email.user, user

      listing = build(:sponsors_listing, sponsorable: user, contact_email: rando_email)

      refute_predicate listing, :valid?
      assert_includes listing.errors[:contact_email], "is invalid for sponsorable"
    end

    test "existing record valid if contact email is not being modified and email is unverified" do
      assert_predicate @listing, :valid?
      assert_predicate @listing.contact_email, :verified?

      @listing.contact_email.unverify!

      assert_predicate @listing, :valid?
      refute_predicate @listing.contact_email, :verified?
    end

    test "sponsors listing should be unique to the sponsorable" do
      existing_listing = create(:sponsors_listing)
      listing = build(:sponsors_listing, sponsorable: existing_listing.sponsorable)

      refute_predicate listing, :valid?
      assert_includes listing.errors[:sponsorable_id], "has already been taken"
    end

    test "requires a sponsorable" do
      listing = SponsorsListing.new
      refute_predicate listing, :valid?
      assert_includes listing.errors[:sponsorable], "must exist"
    end

    test "slug must be unique (case insensitive)" do
      existing_listing = create(:sponsors_listing)
      new_listing = build(:sponsors_listing, sponsorable: existing_listing.sponsorable)
      refute_predicate new_listing, :valid?
      assert_includes new_listing.errors[:slug], "has already been taken"

      new_listing.slug = existing_listing.slug.upcase
      refute_predicate new_listing, :valid?
      assert_includes new_listing.errors[:slug], "has already been taken"
    end

    test "requires descriptions on a non-draft listing" do
      listing = build(
        :sponsors_listing,
        :pending_approval,
        short_description: nil,
        full_description: nil,
      )

      refute_predicate listing, :valid?
      assert_includes listing.errors[:full_description], "can't be blank"
    end

    test "validates length of full_description" do
      max_length = SponsorsListing::MAX_FULL_DESCRIPTION_LENGTH
      text = "a" * (max_length + 1)
      listing = build(:sponsors_listing, full_description: text)
      refute_predicate listing, :valid?
      assert_includes listing.errors[:full_description], "is too long (maximum is #{max_length} characters)"
    end

    test "validates length of featured_description" do
      max_length = SponsorsListing::MAX_FEATURED_DESCRIPTION_LENGTH

      description = "a" * (max_length + 1)
      listing = build(:sponsors_listing, featured_description: description)

      refute_predicate listing, :valid?
      assert_includes listing.errors[:featured_description],
        "is too long (maximum is #{max_length} characters)"

      description = "a" * max_length
      listing.featured_description = description

      assert_predicate listing, :valid?
    end

    test "validates length of featured_description with emojis 💖" do
      max_length = SponsorsListing::MAX_FEATURED_DESCRIPTION_LENGTH

      description = "🐛" * (max_length + 1)
      listing = build(:sponsors_listing, featured_description: description)

      refute_predicate listing, :valid?
      assert_includes listing.errors[:featured_description],
        "is too long (maximum is #{max_length} characters)"

      description = "🐛" * max_length
      listing.featured_description = description

      refute_predicate listing, :valid?
      assert_includes listing.errors[:featured_description],
        "is too long (maximum is #{max_length} characters)"

      description = "✨" * (max_length / 4) # emojis use 4-bytes for encoding
      listing.featured_description = description

      assert_predicate listing, :valid?
    end

    test "validates length of short_description" do
      max_length = SponsorsListing::MAX_SHORT_DESCRIPTION_LENGTH

      description = "a" * (max_length + 1)
      listing = build(:sponsors_listing, short_description: description)

      refute_predicate listing, :valid?
      refute listing.save
      assert_includes listing.errors[:short_description], "is too long (maximum is #{max_length} characters)"

      description = "a" * max_length
      listing.short_description = description

      assert_predicate listing, :valid?
      assert listing.save
    end

    test "validates length of short_description with emojis 💖" do
      max_length = SponsorsListing::MAX_SHORT_DESCRIPTION_LENGTH

      description = "🐛" * (max_length + 1)
      listing = build(:sponsors_listing, short_description: description)

      refute_predicate listing, :valid?
      refute listing.save
      assert_includes listing.errors[:short_description],
        "is too long (maximum is #{max_length} characters)"

      description = "🐛" * max_length
      listing.short_description = description

      refute_predicate listing, :valid?
      refute listing.save
      assert_includes listing.errors[:short_description],
        "is too long (maximum is #{max_length} characters)"

      description = "✨" * (max_length / 4) # emojis use 4-bytes for encoding
      listing.short_description = description

      assert_predicate listing, :valid?
      assert listing.save
    end

    test "requires billing_country to be valid country code" do
      valid_listing = build(:sponsors_listing, billing_country: "US")
      assert_predicate valid_listing, :valid?

      invalid_listing = build(:sponsors_listing, billing_country: "XX")
      refute_predicate invalid_listing, :valid?
    end

    test "requires country_of_residence to be valid country code" do
      valid_listing = build(:sponsors_listing, country_of_residence: "US")
      assert_predicate valid_listing, :valid?

      invalid_listing = build(:sponsors_listing, country_of_residence: "XX")
      refute_predicate invalid_listing, :valid?
    end

    test "requires country_of_residence to match active Stripe account's country when updating listing" do
      listing = create(:sponsors_listing)
      stripe_account = create(:stripe_connect_account, sponsors_listing: listing, country: "DE")

      listing.country_of_residence = "GB"

      refute_predicate listing, :valid?
      assert_includes listing.errors[:country_of_residence], "(GB) must match the active Stripe Connect account's " \
        "country or region (DE)"
    end

    test "requires billing_country to match active Stripe account's billing_country when updating listing" do
      listing = create(:sponsors_listing)
      stripe_account = create(:stripe_connect_account, sponsors_listing: listing, billing_country: "ca")

      listing.billing_country = "US"

      refute_predicate listing, :valid?
      assert_includes listing.errors[:billing_country], "(US) must match the active Stripe Connect account's " \
        "billing country or region (CA)"
    end

    test "allows differing capitalization between listing and Stripe account's country of residence" do
      listing = create(:sponsors_listing)
      stripe_account = create(:stripe_connect_account, sponsors_listing: listing, country: "fr")

      listing.country_of_residence = "FR"

      assert_predicate listing, :valid?
    end

    test "allows Stripe account's country of residence to be blank while listing's is not" do
      listing = create(:sponsors_listing)
      stripe_account = create(:stripe_connect_account, sponsors_listing: listing, country: "")

      listing.country_of_residence = "FR"

      assert_predicate listing, :valid?
    end

    test "allows differing capitalization between listing and Stripe account's billing country" do
      listing = create(:sponsors_listing)
      stripe_account = create(:stripe_connect_account, sponsors_listing: listing, billing_country: "fr")

      listing.billing_country = "FR"

      assert_predicate listing, :valid?
    end

    test "allows Stripe account's billing country to be blank while listing's is not" do
      listing = create(:sponsors_listing)
      stripe_account = create(:stripe_connect_account, sponsors_listing: listing, billing_country: nil)

      listing.billing_country = "FR"

      assert_predicate listing, :valid?
    end
  end

  test "sets slug leveraging sponsorable's login" do
    sponsorable = create(:user, login: "hamburger")
    listing = create(:sponsors_listing, sponsorable: sponsorable)
    assert_equal "sponsors-hamburger", listing.reload.slug
  end

  context "create" do
    test "sets joined_at on creation" do
      listing = build(:sponsors_listing, joined_at: nil)
      assert_predicate listing, :valid?
      refute_nil listing.joined_at
    end

    test "instruments audit log event on creation" do
      events = subscribe "sponsors.waitlist_join"
      user = create(:verified_user)
      listing = create(:sponsors_listing, :waitlisted, sponsorable: user)

      expected_payload = {
        user: user.login,
        user_id: user.id,
        sponsors_listing_id: listing.id,
        sponsors_listing: listing.slug,
        created_by: user.login,
        created_by_id: user.id,
        state: :waitlisted,
        short_description: listing.short_description,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments hydro event on creation" do
      listing = create(:sponsors_listing, :waitlisted)

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        user: Hydro::EntitySerializer.user(listing.sponsorable),
      }

      assert_hydro_published(message, schema: "github.sponsors.v0.JoinedWaitlist")
    end
  end

  context "#total_monthly_pledged_in_dollars" do
    test "returns 0 if there are no sponsorships" do
      assert_equal Billing::Money.zero, @waitlisted_listing.total_monthly_pledged_in_dollars
    end

    test "returns total monthly pledged on active sponsorships for a sponsorable" do
      sponsorship1, sponsorship2 = create_list(:sponsorship, 2, sponsorable: @approved_listing.sponsorable)
      subscribed_tiers = [sponsorship1, sponsorship2].map(&:tier)
      expected_dollars = subscribed_tiers.sum(&:monthly_price_in_cents) / 100

      assert_equal expected_dollars, @approved_listing.total_monthly_pledged_in_dollars.to_i
    end

    test "omits one-time sponsorships" do
      one_time_tier = create(:sponsors_tier, :one_time, :published, sponsorable: @approved_listing.sponsorable)
      create(:sponsorship, sponsorable: @approved_listing.sponsorable, tier: one_time_tier)

      assert_equal Billing::Money.zero, @approved_listing.total_monthly_pledged_in_dollars
    end
  end

  context "without_fraud_review_since_last_payout scope" do
    test "omits listing that has a fraud review created since the listing's last payout" do
      listing = create(:sponsors_listing, last_payout_at: 1.day.ago)
      create(:sponsors_fraud_review, sponsors_listing: listing)

      result = SponsorsListing.without_fraud_review_since_last_payout.where(id: listing)

      assert_empty result
    end

    # https://github.com/github/sponsors/issues/2492
    test "omits listing with fraud reviews created before the last payout and with any fraud review after last payout" do
      listing = create(:sponsors_listing, last_payout_at: 1.day.ago)

      travel_to(1.day.ago) do
        create(:sponsors_fraud_review, :resolved, sponsors_listing: listing)
      end

      create(:sponsors_fraud_review, sponsors_listing: listing)

      result = SponsorsListing.without_fraud_review_since_last_payout.where(id: listing)

      assert_empty result
    end

    test "includes listing that has no fraud reviews and has never been paid out" do
      listing = create(:sponsors_listing, last_payout_at: nil)
      result = SponsorsListing.without_fraud_review_since_last_payout.where(id: listing)
      assert_equal [listing], result
    end

    test "includes listing that has a fraud review from before the listing was paid out" do
      listing = create(:sponsors_listing, last_payout_at: Time.now)
      travel_to(1.day.ago) do
        create(:sponsors_fraud_review, sponsors_listing: listing)
      end

      result = SponsorsListing.without_fraud_review_since_last_payout.where(id: listing)

      assert_equal [listing], result
    end

    # See https://github.com/github/sponsors/issues/3650
    test "includes listing only a single time that has had multiple fraud reviews before last payout" do
      listing = create(:sponsors_listing, last_payout_at: Time.now)
      travel_to(1.day.ago) do
        create(:sponsors_fraud_review, :resolved, sponsors_listing: listing)
        create(:sponsors_fraud_review, :resolved, sponsors_listing: listing)
      end

      result = SponsorsListing.without_fraud_review_since_last_payout.where(id: listing)

      assert_equal [listing], result
    end

    test "includes listing that has no fraud reviews and has been paid out" do
      listing = create(:sponsors_listing, last_payout_at: Time.now)
      result = SponsorsListing.without_fraud_review_since_last_payout.where(id: listing)
      assert_equal [listing], result
    end

    test "omits listing that has a fraud review and has never been paid out" do
      listing = create(:sponsors_listing, last_payout_at: nil)
      create(:sponsors_fraud_review, sponsors_listing: listing)

      result = SponsorsListing.without_fraud_review_since_last_payout.where(id: listing)

      assert_empty result
    end
  end

  context "for_tier scope" do
    test "includes sponsors listing when passed a sponsors tier" do
      tier = @org_listing.default_tier

      assert_predicate SponsorsListing.for_tier(tier), :one?
      assert_equal @org_listing, SponsorsListing.for_tier(tier).first
    end

    test "includes sponsors listing when passed a sponsors tier id" do
      tier_id = @org_listing.default_tier.id

      assert_predicate SponsorsListing.for_tier(tier_id), :one?
      assert_equal @org_listing, SponsorsListing.for_tier(tier_id).first
    end
  end

  context ".auto_ban_reason" do
    # https://github.com/github/sponsors/issues/3760
    test "account age cutoff for auto ban is in months" do
      expected_auto_ban_reason = "Account is less than 6 months old, does not have a Sponsors profile description, " +
        "does not use a supported timezone, has not customized their GitHub profile, and has no public contributions."

      assert_equal expected_auto_ban_reason, SponsorsListing.auto_ban_reason
    end
  end

  context "with_min_sponsorship_amount_since_last_payout scope" do
    test "includes listings where new sponsorships total at least the given dollar amount since the last time the maintainer was paid out" do
      last_payout_date = 1.week.ago
      min_cents = 300_00 # $300

      # Listing with $400 in new sponsorship money:
      listing1 = create(:sponsors_listing, :approved, :with_tier, last_payout_at: last_payout_date,
        sponsorable_login: "maintainer-400")
      tier1 = create(:sponsors_tier, :published, sponsors_listing: listing1,
        monthly_price_in_cents: 200_00)

      # New sponsorship worth $200:
      create(:sponsorship, sponsorable: listing1.sponsorable, tier: tier1)

      # Old sponsorship that will get a tier upgrade worth $200:
      old_sponsorship = travel_to(last_payout_date - 1.day) do
        create(:sponsorship, sponsorable: listing1.sponsorable, tier: listing1.default_tier)
      end
      old_sponsorship.tier = tier1
      old_sponsorship.subscribable_selected_at = Time.now
      old_sponsorship.save!

      # Listing with $300 in sponsorship money that has never been paid out:
      listing2 = create(:sponsors_listing, :approved, tier_count: 0, last_payout_at: nil,
        sponsorable_login: "maintainer-300")
      tier2 = create(:sponsors_tier, :published, sponsors_listing: listing2,
        monthly_price_in_cents: 300_00)
      create(:sponsorship, sponsorable: listing2.sponsorable, tier: tier2)

      # Listing with only $200 in new sponsorship money since last payout:
      listing3 = create(:sponsors_listing, :approved, tier_count: 0,
        last_payout_at: last_payout_date, sponsorable_login: "maintainer-200")
      tier3 = create(:sponsors_tier, :published, sponsors_listing: listing3,
        monthly_price_in_cents: 200_00)
      create(:sponsorship, sponsorable: listing3.sponsorable, tier: tier3)
      travel_to(last_payout_date - 1.day) do
        create(:sponsorship, sponsorable: listing3.sponsorable, tier: tier3)
      end

      # Listing with no sponsorships:
      listing4 = create(:sponsors_listing, :approved, tier_count: 0, last_payout_at: nil,
        sponsorable_login: "maintainer-zero")
      create(:sponsors_tier, :published, sponsors_listing: listing4,
        monthly_price_in_cents: 400)

      # Listing with $400 invoiced payment sponsorship
      listing5 = create(:sponsors_listing, :approved, tier_count: 0, last_payout_at: nil,
        sponsorable_login: "maintainer-invoiced")
      tier5 = create(:sponsors_tier, :invoiced, sponsors_listing: listing5,
        monthly_price_in_cents: 400_00)
      create(:sponsorship, :invoiced, sponsorable: listing5.sponsorable, tier: tier5)

      result = SponsorsListing.with_min_sponsorship_amount_since_last_payout(min_cents)
        .where(id: [listing1, listing2, listing3, listing4, listing5])
        .pluck(:slug)

      assert_includes result, listing1.slug,
        "should have included listing with new and upgrade sponsorship amount exceeding the " \
        "specified amount"
      assert_includes result, listing2.slug,
        "should have included listing with new sponsorship amount that matches the specified amount"
      refute_includes result, listing3.slug,
        "should not have included listing that doesn't meet or exceed sponsorship amount"
      refute_includes result, listing4.slug,
        "should not have included listing that has no sponsorships"
      refute_includes result, listing5.slug,
        "should not have included listing with an invoiced sponsorship"
    end
  end

  test "can reassign country of residence if listing is draft" do
    listing = create(:sponsors_listing, country_of_residence: "US")
    assert listing.update(country_of_residence: "SV")
  end

  context "#contact_email_address" do
    test "returns contact email" do
      user = @listing.sponsorable
      email = create(:verified_user_email, user: user)
      @listing.update!(contact_email: email)

      assert_equal email.email, @listing.contact_email_address
    end

    test "returns billing email for organizations" do
      org = create(:organization)
      listing = create(:sponsors_listing, sponsorable: org, state: :accepted)

      assert_equal org.billing_email, listing.contact_email_address
    end
  end

  context "#subscription_value" do
    test "returns sum of active sponsorships in cents for the listing" do
      listing = @org_listing
      tier1 = create(:sponsors_tier, :published, sponsors_listing: listing,
        monthly_price_in_cents: 5000)
      tier2 = create(:sponsors_tier, :published, sponsors_listing: listing,
        monthly_price_in_cents: 1200)

      # $50.00 + $12.00 + $12.00 = $74.00 total
      create(:sponsorship, sponsorable: listing.sponsorable, tier: tier1)
      create(:sponsorship, sponsorable: listing.sponsorable, tier: tier2)
      create(:sponsorship, sponsorable: listing.sponsorable, tier: tier2)

      assert_equal 7400, listing.subscription_value
    end
  end

  context ".subscription_value_for" do
    test "returns sum of active recurring sponsorships in cents for the specified listing" do
      listing = @approved_listing
      tier1 = create(:sponsors_tier, :published, sponsors_listing: listing,
        monthly_price_in_cents: 18_00)
      tier2 = create(:sponsors_tier, :published, sponsors_listing: listing,
        monthly_price_in_cents: 22_00)
      one_time_tier = create(:sponsors_tier, :published, :one_time,
        sponsors_listing: listing, monthly_price_in_cents: 35_00)

      # $18.00 + $22.00 = $40.00 total
      create(:sponsorship, sponsorable: listing.sponsorable, tier: tier1)
      create(:sponsorship, sponsorable: listing.sponsorable, tier: tier2)

      # Should not be counted since it's a one-time payment:
      create(:sponsorship, sponsorable: listing.sponsorable, tier: one_time_tier)

      result = SponsorsListing.subscription_value_for(listing.id)

      assert_equal 40_00, result
    end
  end

  context ".past_thirty_day_monthly_sponsorship_value_for" do
    test "returns sum of active recurring sponsorships in cents excluding prorated payments in the past 30 days for the specified listing" do
      listing = @approved_listing
      tier1 = create(:sponsors_tier, :published, sponsors_listing: listing,
        monthly_price_in_cents: 18_00)
      tier2 = create(:sponsors_tier, :published, sponsors_listing: listing,
        monthly_price_in_cents: 22_00)
      one_time_tier = create(:sponsors_tier, :published, :one_time,
        sponsors_listing: listing, monthly_price_in_cents: 35_00)
      yearly_sponsor = create(:credit_card_user, plan_duration: "year",
        plan_subscription: create(:billing_plan_subscription))
      custom_tier = create(:sponsors_tier, :custom, sponsors_listing: listing, monthly_price_in_cents: 5_00)

      # $18.00 + $22.00 + $22.00 + $22.00 + $5.00 = $89.00 total
      create(:sponsorship, :with_billing_transaction_and_line_item, sponsorable: listing.sponsorable, tier: tier1)
      create(:sponsorship, :with_billing_transaction_and_line_item, sponsorable: listing.sponsorable, tier: tier2)
      create(:sponsorship, :with_billing_transaction_and_line_item, sponsorable: listing.sponsorable, tier: tier2)
      create(:sponsorship, :patreon, sponsorable: listing.sponsorable, tier: custom_tier,
        sponsor: custom_tier.creator)

      # Should count since it's a yearly sponsor who paid between 30 and 365 days ago:
      travel_to 60.days.ago do
        create(:sponsorship, :with_billing_transaction_and_line_item, sponsor: yearly_sponsor,
          sponsorable: listing.sponsorable, tier: tier2)
      end

      # Should not be counted since it's a one-time payment:
      create(:sponsorship, :with_billing_transaction_and_line_item, sponsorable: listing.sponsorable, tier: one_time_tier)

      # Should not be counted since it's prorated:
      create(:sponsorship, :with_prorated_billing_transaction_and_line_item, sponsorable: listing.sponsorable, tier: tier1)

      # Should not be counted since the transaction was not successful:
      create(:sponsorship, :with_failed_billing_transaction_and_line_item, sponsorable: listing.sponsorable, tier: tier1)

      expected_table_counts = {
        billing_transaction_line_items: 3, # 1 extra for sponsorships_excluding_prorated scope
        sponsorships: 1,
        sponsors_tiers: 2, # 1 for sponsorships_excluding_prorated scope, 1 for preloading subscribable on line_items
      }

      assert_query_count_per_table(expected_table_counts) do
        assert_query_count(expected_table_counts.values.sum) do
          result = SponsorsListing.past_thirty_day_monthly_sponsorship_value_for(listing.id)

          assert_equal 89_00, result
        end
      end
    end

    test "only counts most recent line item for each sponsor" do
      listing = @approved_listing
      tier = create(:sponsors_tier, :published, sponsors_listing: listing, monthly_price_in_cents: 18_00)
      sponsor = create(:credit_card_user, plan_subscription: create(:billing_plan_subscription))

      travel_to 1.day.ago do
        sponsorship = create(:sponsorship, :with_billing_transaction_and_line_item, sponsor: sponsor,
          sponsorable: listing.sponsorable, tier: tier)
      end

      # Most recent line item, should be the only one counted:
      create(:billing_transaction_line_item, :sponsors, user: sponsor, subscribable: tier)

      result = SponsorsListing.past_thirty_day_monthly_sponsorship_value_for(listing.id)

      assert_equal 18_00, result
    end
  end

  context "#auto_acceptable?" do
    SponsorsListing.auto_acceptable_countries.each do |country|
      test "true for listing with billing country #{country} if meets requirements" do
        @waitlisted_listing.update!(billing_country: country)

        assert_predicate @waitlisted_listing, :eligible_for_stripe_connect?
        assert_predicate @waitlisted_listing, :auto_acceptable?
      end
    end

    test "false if not in eligible country" do
      @waitlisted_listing.update!(billing_country: "AF")

      refute_predicate @waitlisted_listing, :eligible_for_stripe_connect?
      refute_predicate @waitlisted_listing, :auto_acceptable?
    end

    test "false for suspended user" do
      user = create(:suspended_user)
      listing = create(:sponsors_listing, :waitlisted, sponsorable: user)
      refute_predicate listing, :auto_acceptable?
    end

    test "false if meets requirements but is ignored" do
      @waitlisted_listing.update!(billing_country: SponsorsListing.auto_acceptable_countries.sample)
      @waitlisted_listing.stafftools_metadata.update!(ignored_at: Time.now)

      assert_predicate @waitlisted_listing.reload_stafftools_metadata, :ignored?
      assert_predicate @waitlisted_listing, :eligible_for_stripe_connect?
      refute_predicate @waitlisted_listing, :auto_acceptable?
    end

    test "true for an organization in a supported country and not spammy or ofac flagged" do
      listing = create(:sponsors_listing, :for_org, :waitlisted,
        billing_country: SponsorsListing.auto_acceptable_countries.sample)

      refute_predicate listing, :ignored?
      assert_predicate listing, :eligible_for_stripe_connect?
      assert_predicate listing, :auto_acceptable?
    end

    test "false for organization that is spammy" do
      org = create(:organization)
      org.mark_as_spammy
      listing = create(:sponsors_listing, :waitlisted, sponsorable: org,
        billing_country: SponsorsListing.auto_acceptable_countries.sample)

      assert_predicate org, :spammy?
      assert_predicate listing, :eligible_for_stripe_connect?
      refute_predicate listing, :auto_acceptable?
    end

    test "false for organization that has trade restrictions" do
      org = create(:organization, :fully_trade_restricted)
      listing = create(:sponsors_listing, sponsorable: org,
        billing_country: SponsorsListing.auto_acceptable_countries.sample)

      assert_predicate org, :has_any_trade_restrictions?
      assert_predicate listing, :eligible_for_stripe_connect?
      refute_predicate listing, :auto_acceptable?
    end
  end

  context "#reviewed?" do
    test "returns true when stafftools metadata has reviewed_at set" do
      stafftools_metadata = create(:sponsors_listing_stafftools_metadata, reviewed_at: Time.now)
      assert_predicate stafftools_metadata.sponsors_listing, :reviewed?
    end

    test "returns false when stafftools metadata has no reviewed_at" do
      stafftools_metadata = create(:sponsors_listing_stafftools_metadata, reviewed_at: nil)
      refute_predicate stafftools_metadata.sponsors_listing, :reviewed?
    end
  end

  context "#ignored?" do
    test "returns true when stafftools metadata has ignored_at set" do
      stafftools_metadata = create(:sponsors_listing_stafftools_metadata, ignored_at: Time.now)
      assert_predicate stafftools_metadata.sponsors_listing, :ignored?
    end

    test "returns false when stafftools metadata has no ignored_at" do
      stafftools_metadata = create(:sponsors_listing_stafftools_metadata, ignored_at: nil)
      refute_predicate stafftools_metadata.sponsors_listing, :ignored?
    end
  end

  context "#public_contribution_count" do
    test "returns count of public contributions the sponsorable has made in the last year" do
      sponsorable = create(:user, :sponsorable)
      assert_equal 0, sponsorable.sponsors_listing.public_contribution_count

      # Should count, public issue and commit:
      public_repo = create(:repository, owner: sponsorable)
      create(:commit_contribution, :with_summaries, user: sponsorable, repository: public_repo,
        commit_count: 1, committed_date: 6.months.ago)
      create(:issue, user: sponsorable)

      # Shouldn't count, private:
      private_repo = create(:private_repository, owner: sponsorable)
      create(:issue, repository: private_repo, user: sponsorable)

      # Shouldn't count, old:
      travel_to(13.months.ago) { create(:issue, user: sponsorable) }

      listing = SponsorsListing.find(sponsorable.sponsors_listing.id) # clear memoization
      assert_equal 2, listing.public_contribution_count
    end

    test "returns count of public contributions that the creator of the sponsorable org's listing has made in the last year" do
      org_listing = create(:sponsors_listing, :for_org)
      sponsorable_org = org_listing.sponsorable
      listing_creator = org_listing.created_by
      org_admin = create(:user, :verified)
      sponsorable_org.add_admin(org_admin)
      org_member = create(:user, :verified)
      sponsorable_org.add_member(org_member)
      org_contributor = create(:user, :verified)

      assert_equal 0, org_listing.public_contribution_count

      public_repo = create(:repository, owner: sponsorable_org)

      # Should count, contribution made by creator
      create(:commit_contribution, :with_summaries, user: listing_creator,
        repository: public_repo, commit_count: 1, committed_date: 6.months.ago)

      # Should not count, contribution made by admin
      create(:commit_contribution, :with_summaries, user: org_admin, repository: public_repo,
        commit_count: 1, committed_date: 6.months.ago)

      # Should not count, contribution made by contributor
      create(:commit_contribution, :with_summaries, user: org_member, repository: public_repo,
        commit_count: 1, committed_date: 6.months.ago)

      # Should not count, contribution made by org member
      create(:commit_contribution, :with_summaries, user: org_contributor, repository: public_repo,
        commit_count: 1, committed_date: 6.months.ago)

      listing = SponsorsListing.find(sponsorable_org.sponsors_listing.id) # clear memoization
      assert_equal 1, listing.public_contribution_count
    end

    test "returns zero if listing creator for sponsorable org is nil" do
      org_listing = create(:sponsors_listing, :for_org)
      create(:issue, user: org_listing.created_by)
      org_listing.update!(created_by_id: nil)

      assert_equal 0, org_listing.public_contribution_count
    end
  end

  test "enqueues job to delete repo-sponsorables on deletion of approved listing" do
    assert_enqueued_with(
      job: UpdateOwnerRepositorySponsorablesJob,
      args: [{ sponsorable_id: @approved_listing.sponsorable_id }],
    ) do
      @approved_listing.destroy!
    end
  end

  test "does not enqueue job to delete repo-sponsorables on deletion of non-approved listing" do
    assert_no_enqueued_jobs(only: UpdateOwnerRepositorySponsorablesJob) do
      @waitlisted_listing.destroy!
    end
  end

  context "#published_one_time_tier_count" do
    test "returns count of published tiers with frequency=one_time" do
      tier = create(:sponsors_tier, :published, :one_time)
      listing = tier.sponsors_listing

      # Shouldn't count, recurring:
      create(:sponsors_tier, :published, frequency: :recurring, sponsors_listing: listing)

      # Shouldn't count, not published:
      create(:sponsors_tier, :retired, :one_time, sponsors_listing: listing)

      # Shouldn't count, different listing:
      create(:sponsors_tier, :published, :one_time)

      assert_equal 1, listing.published_one_time_tier_count

      # Create another to make the count change:
      create(:sponsors_tier, :published, :one_time, sponsors_listing: listing)

      assert_equal 2, listing.published_one_time_tier_count
    end
  end

  context "#published_recurring_tier_count" do
    test "returns count of published tiers with frequency=recurring" do
      tier = create(:sponsors_tier, :published, frequency: :recurring)
      listing = tier.sponsors_listing

      # Shouldn't count, one-time:
      create(:sponsors_tier, :published, :one_time, sponsors_listing: listing)

      # Shouldn't count, not published:
      create(:sponsors_tier, :retired, frequency: :recurring, sponsors_listing: listing)

      # Shouldn't count, different listing:
      create(:sponsors_tier, :published, frequency: :recurring)

      assert_equal 1, listing.published_recurring_tier_count

      # Create another to make the count change:
      create(:sponsors_tier, :published, frequency: :recurring, sponsors_listing: listing)

      assert_equal 2, listing.published_recurring_tier_count
    end
  end

  context "filter_spam_for scope" do
    test "filters out listings with spammy sponsorables" do
      listing1 = @listing
      listing2 = create(:sponsors_listing, :for_org)

      result = SponsorsListing.where(id: [listing1, listing2])
        .filter_spam_for(nil)
      assert_same_elements [listing1, listing2], result

      listing1.sponsorable.mark_as_spammy(reason: "So spammy", actor: @staff)
      listing2.sponsorable.mark_as_spammy(reason: "Also spammy", actor: @staff)

      result = SponsorsListing.where(id: [listing1, listing2])
        .filter_spam_for(nil)
      assert_empty result
    end

    test "does not filter out a spammer's own listing" do
      spammer = @listing.sponsorable
      spammer.mark_as_spammy(reason: "So spammy", actor: @staff)

      result = SponsorsListing.where(id: [@listing]).filter_spam_for(spammer)

      assert_equal [@listing], result
    end

    test "does not filter out spammy sponsorables for staff viewer" do
      listing1 = @listing
      listing2 = create(:sponsors_listing, :for_org)

      result = SponsorsListing.where(id: [listing1, listing2])
        .filter_spam_for(@staff)
      assert_same_elements [listing1, listing2], result

      listing1.sponsorable.mark_as_spammy(reason: "So spammy", actor: @staff)
      listing2.sponsorable.mark_as_spammy(reason: "Also spammy", actor: @staff)

      result = SponsorsListing.where(id: [listing1, listing2])
        .filter_spam_for(@staff)
      assert_same_elements [listing1, listing2], result
    end
  end if GitHub.spamminess_check_enabled?

  context "reviewed_at" do
    test "sets reviewed_at after updating state" do
      assert_nil @waitlisted_listing.stafftools_metadata.reviewed_at
      @waitlisted_listing.accept!
      refute_nil @waitlisted_listing.reload_stafftools_metadata.reviewed_at
    end

    test "updates existing reviewed_at if state changes" do
      travel_to "2023-11-13"
      old_time = 1.day.ago
      metadata = @waitlisted_listing.stafftools_metadata
      assert_nil metadata.reviewed_at
      travel_to(old_time) { @waitlisted_listing.accept! }
      assert_equal old_time.to_time.utc.iso8601, metadata.reload.reviewed_at.to_time.utc.iso8601

      assert_changes -> { metadata.reload.reviewed_at } do
        @waitlisted_listing.actor = @staff
        @waitlisted_listing.ban!(banned_reason: "o noes")
      end
    end
  end

  context "approval_requested_at" do
    test "records the approval_requested_at timestamp when approval is requested" do
      travel_to "2023-11-13"
      listing = create(:sponsors_listing, :ready_for_submission, :with_customized_sponsorable_profile)
      metadata = listing.stafftools_metadata

      now = Time.now
      assert_nil metadata.approval_requested_at

      travel_to(now) { listing.request_approval! }

      refute_nil metadata.reload.approval_requested_at, "should have set approval_requested_at"
      assert_equal now.utc.to_s, metadata.approval_requested_at.utc.to_s
    end

    test "updates the approval_requested_at timestamp when approval is requested" do
      travel_to "2023-11-14"
      listing = create(:sponsors_listing, :ready_for_submission, :with_customized_sponsorable_profile)
      metadata = listing.stafftools_metadata
      now = Time.now

      travel_to(now) { listing.request_approval! }

      assert_equal now.utc.to_s, metadata.reload.approval_requested_at.utc.to_s
    end
  end

  context "#country_of_residence_flag_emoji_alias" do
    test "returns emoji alias for the listing's country of residence's flag" do
      EXPECTED_EMOJI_ALIASES_BY_COUNTRY_CODE.each do |country_code, expected_alias|
        listing = SponsorsListing.new(country_of_residence: country_code)
        result = listing.country_of_residence_flag_emoji_alias
        assert_equal expected_alias, result
        refute_nil Emoji.find_by_alias(result), "returned string should be an emoji alias"
      end
    end

    test "returns nil when listing has no country of residence" do
      listing = SponsorsListing.new(country_of_residence: nil)
      assert_nil listing.country_of_residence_flag_emoji_alias
    end
  end

  context "#billing_country_flag_emoji_alias" do
    test "returns emoji alias for the listing's billing country's flag" do
      EXPECTED_EMOJI_ALIASES_BY_COUNTRY_CODE.each do |country_code, expected_alias|
        listing = SponsorsListing.new(billing_country: country_code)

        result = listing.billing_country_flag_emoji_alias

        assert_equal expected_alias, result
        refute_nil Emoji.find_by_alias(result), "returned string should be an emoji alias"
      end
    end

    test "returns nil when listing has no billing country" do
      listing = SponsorsListing.new(billing_country: nil)
      assert_nil listing.billing_country_flag_emoji_alias
    end
  end

  context "#sponsorable_time_zone_name" do
    test "returns name of the sponsorable's time zone" do
      sponsorable = create(:user, :sponsorable, time_zone_name: "Canberra")
      assert_equal "Canberra", sponsorable.sponsors_listing.sponsorable_time_zone_name
    end
  end

  context "pending_approval_since" do
    test "returns nil when the listing is not in pending_approval_state" do
      listing = create(:sponsors_listing, :draft)
      listing.stafftools_metadata.update!(approval_requested_at: Time.now)

      assert_nil listing.pending_approval_since
    end

    test "returns nil when approval_requested_at is not set" do
      listing = create(:sponsors_listing, :pending_approval)
      listing.stafftools_metadata.update!(approval_requested_at: nil)

      assert_nil listing.pending_approval_since
    end

    test "returns approval_requested_at when it is set" do
      timestamp = Time.now.utc
      listing = create(:sponsors_listing, :pending_approval)
      listing.stafftools_metadata.update!(approval_requested_at: timestamp)

      assert_equal timestamp.to_s, listing.pending_approval_since.to_s
    end
  end

  context "#in_current_state_since" do
    test "returns the listing waitlist join time when the listing is in waitlisted state" do
      listing = create(:sponsors_listing, :waitlisted)

      assert_equal listing.joined_at, listing.in_current_state_since
    end

    test "returns when the listing was last reviewed when the listing is in disabled state" do
      listing = create(:sponsors_listing, :disabled)

      assert_equal listing.stafftools_metadata.reviewed_at, listing.in_current_state_since
    end

    test "returns nil when approval_requested_at is not set for a pending_approval listing" do
      listing = create(:sponsors_listing, :pending_approval)
      listing.stafftools_metadata.update!(approval_requested_at: nil)

      assert_nil listing.in_current_state_since
    end

    test "returns approval_requested_at when it is set for a pending_approval listing" do
      timestamp = Time.now.utc
      listing = create(:sponsors_listing, :pending_approval)
      listing.stafftools_metadata.update!(approval_requested_at: timestamp)

      assert_equal timestamp.to_s, listing.in_current_state_since.to_s
    end

    test "returns accepted_at for draft listing when it is set" do
      timestamp = Time.now.utc
      listing = create(:sponsors_listing, accepted_at: timestamp)

      assert_equal timestamp.to_s, listing.in_current_state_since.to_s
    end

    test "returns published_at for approved listing when it is set" do
      timestamp = Time.now.utc
      listing = create(:sponsors_listing, :approved, published_at: timestamp)

      assert_equal timestamp.to_s, listing.in_current_state_since.to_s
    end

    test "returns ignored_at when it is more recent than the latest state change" do
      ignored_at = Time.now.utc
      listing = create(:sponsors_listing, :approved, published_at: 1.week.ago)
      listing.stafftools_metadata.update!(ignored_at: ignored_at)

      assert_equal ignored_at.to_s, listing.in_current_state_since.to_s
    end

    test "returns state change time when it is more recent than when the listing was ignored" do
      published_at = Time.now.utc
      listing = create(:sponsors_listing, :approved, published_at: published_at)
      listing.stafftools_metadata.update!(ignored_at: 1.week.ago)

      assert_equal published_at.to_s, listing.in_current_state_since.to_s
    end

    test "returns banned_at when it is set for a banned listing" do
      timestamp = Time.now.utc
      listing = create(:sponsors_listing, :banned)
      listing.stafftools_metadata.update!(banned_at: timestamp)

      assert_equal timestamp.to_s, listing.in_current_state_since.to_s
    end

    test "returns reviewed_at when listing is spammy" do
      timestamp = Time.now.utc
      listing = create(:sponsors_listing, :spammy)
      listing.stafftools_metadata.update!(reviewed_at: timestamp)
      assert_equal timestamp.to_s, listing.in_current_state_since.to_s
    end
  end

  context "#sponsorable_has_any_trade_restrictions?" do
    test "returns true when sponsorable has trade restrictions" do
      sponsorable = create(:user, :verified, :fully_trade_restricted)
      listing = build(:sponsors_listing, sponsorable: sponsorable)
      assert_predicate listing, :sponsorable_has_any_trade_restrictions?
    end

    test "returns false when sponsorable does not have trade restrictions" do
      sponsorable = create(:user, :verified)
      listing = build(:sponsors_listing, sponsorable: sponsorable)
      refute_predicate listing, :sponsorable_has_any_trade_restrictions?
    end
  end

  context "ordered_by_sponsorable_login scope" do
    test "sorts listings alphabetically by sponsorable login" do
      b_listing = create(:sponsors_listing, sponsorable_login: "bearListing")
      a_listing = create(:sponsors_listing, sponsorable_login: "aardvarkListing")
      c_listing = create(:sponsors_listing, sponsorable_login: "coelacanthListing")

      result = SponsorsListing.where(id: [c_listing, a_listing, b_listing])
        .ordered_by_sponsorable_login

      assert_equal [a_listing, b_listing, c_listing], result
    end
  end

  def assert_adminable_by(sponsors_listing, actor)
    assert sponsors_listing.adminable_by?(actor)
    assert sponsors_listing.async_adminable_by?(actor).sync,
      "expected #async_adminable_by? to agree with #adminable_by?"
  end

  def refute_adminable_by(sponsors_listing, actor)
    refute sponsors_listing.adminable_by?(actor)
    refute sponsors_listing.async_adminable_by?(actor).sync,
      "expected #async_adminable_by? to agree with #adminable_by?"
  end

  context "#adminable_by? and #async_adminable_by?" do
    test "returns true for sponsorable user's listing only if actor is the sponsorable" do
      sponsorable = create(:user)
      rando = create(:user)
      listing = create(:sponsors_listing, sponsorable: sponsorable)

      assert_adminable_by listing, sponsorable
      refute_adminable_by listing, rando
    end

    test "returns true for sponsorable org's listing only if actor is the org's admin" do
      org = create(:organization)
      rando = create(:user)
      billing_manager = create(:user)
      org_member = create(:user)

      org.add_member(org_member)
      org.billing.add_manager(billing_manager, actor: org.admin)

      listing = create(:sponsors_listing, sponsorable: org)

      assert_adminable_by listing, org.admin
      refute_adminable_by listing, rando
      refute_adminable_by listing, billing_manager
      refute_adminable_by listing, org_member
    end

    test "returns false for nil viewer" do
      listing = create(:sponsors_listing)
      refute_adminable_by listing, nil
    end
  end

  context "#has_published_tier?" do
    test "true when listing has a published tier" do
      assert_predicate @published_tier.sponsors_listing, :has_published_tier?
    end

    test "false when listing has no tiers" do
      assert_empty @listing.sponsors_tiers, "need a listing without tiers for this test"
      refute_predicate @listing, :has_published_tier?
    end

    test "false when listing has only a draft tier" do
      draft_tier = create(:sponsors_tier, :draft)
      refute_predicate draft_tier.sponsors_listing, :has_published_tier?
    end

    test "false when listing has a published tier with the same amount but different frequency" do
      refute @published_tier.sponsors_listing.has_published_tier?(
        monthly_price_in_cents: @published_tier.monthly_price_in_cents,
        frequency: :one_time
      )
    end

    test "true when listing has a published tier with the same amount and frequency" do
      assert @published_tier.sponsors_listing.has_published_tier?(
        monthly_price_in_cents: @published_tier.monthly_price_in_cents,
        frequency: @published_tier.frequency
      )
    end

    test "true when listing has a published tier with the same frequency" do
      assert @published_tier.sponsors_listing.has_published_tier?(
        frequency: @published_tier.frequency
      )
    end

    test "false when listing has a published tier with a different monthly price in cents" do
      refute @published_tier.sponsors_listing.has_published_tier?(
        monthly_price_in_cents: build(:sponsors_tier).monthly_price_in_cents
      )
    end
  end

  def assert_listing_readable_by(listing, actor)
    assert listing.readable_by?(actor), "expected #{listing} to be readable by #{actor&.display_login || "anon"}"
    assert listing.async_readable_by?(actor).sync,
      "expected #async_readable_by? to be in agreement with #readable_by?"
  end

  def refute_listing_readable_by(listing, actor)
    refute listing.readable_by?(actor), "expected #{listing} not to be readable by #{actor&.display_login || "anon"}"
    refute listing.async_readable_by?(actor).sync,
      "expected #async_readable_by? to be in agreement with #readable_by?"
  end

  context "#readable_by? and #async_readable_by?" do
    test "returns true when viewing your own unapproved listing" do
      listing = create(:sponsors_listing)
      refute_predicate listing, :approved?

      assert_listing_readable_by(listing, listing.sponsorable)
    end

    test "returns true when viewing your own approved listing" do
      listing = create(:sponsors_listing, :approved)
      assert_predicate listing, :approved?

      assert_listing_readable_by(listing, listing.sponsorable)
    end

    test "returns true for random viewer when viewing approved listing" do
      listing = create(:sponsors_listing, :approved)
      assert_predicate listing, :approved?

      assert_listing_readable_by(listing, create(:user))
    end

    test "returns true for approved listing even when maintainer has blocked viewer" do
      listing = create(:sponsors_listing, :approved)
      viewer = create(:user)
      assert listing.sponsorable.block(viewer)

      assert_listing_readable_by(listing, viewer)
    end

    test "returns true for random viewer of approved org listing" do
      org = create(:organization, :sponsorable)
      assert org.sponsors_listing.update(state: :approved)
      user = create(:user)

      assert_listing_readable_by(org.sponsors_listing, user)
    end

    test "returns true for site admin when viewing unapproved listing" do
      listing = create(:sponsors_listing)
      refute_predicate listing, :approved?

      assert_listing_readable_by(listing, @staff)
    end

    test "returns true for biztools user when viewing unapproved listing" do
      listing = create(:sponsors_listing)
      refute_predicate listing, :approved?

      assert_listing_readable_by(listing, @biztools_user)
    end

    test "returns true for org admin user viewing unapproved listing" do
      org_admin = create(:user)
      org = create(:organization, admin: org_admin)
      listing = create(:sponsors_listing, sponsorable: org)
      refute_predicate listing, :approved?

      assert_listing_readable_by(listing, org_admin)
    end

    test "returns false for random viewer viewing unapproved listing" do
      listing = create(:sponsors_listing)
      refute_predicate listing, :approved?

      refute_listing_readable_by(listing, create(:user))
    end

    test "returns false for anonymous viewer viewing disabled listing" do
      refute_listing_readable_by(@disabled_listing, nil)
    end

    test "returns false for random viewer viewing disabled listing" do
      refute_listing_readable_by(@disabled_listing, create(:user))
    end

    test "returns false for viewing your own disabled listing" do
      refute_listing_readable_by(@disabled_listing, @disabled_listing.sponsorable)
    end

    test "returns false for viewing your org's disabled listing" do
      disabled_org_listing = create(:sponsors_listing, :for_org, :disabled)
      org = disabled_org_listing.sponsorable
      refute_listing_readable_by(disabled_org_listing, org.admins.first)
    end

    test "returns true for site admin viewer viewing disabled listing" do
      assert_listing_readable_by(@disabled_listing, @staff)
    end

    test "returns true for biztools viewer viewing disabled listing" do
      assert_listing_readable_by(@disabled_listing, @biztools_user)
    end
  end

  context "country of residence on create" do
    test "syncs country of residence with billing country for org with their own bank account" do
      listing = create(
        :sponsors_listing,
        sponsorable: @waitlisted_org,
        billing_country: "SV",
        country_of_residence: "US",
      )

      assert_equal "SV", listing.reload.billing_country
      assert_equal "SV", listing.country_of_residence
    end

    test "syncs country of residence with billing country for org when none is given" do
      listing = create(
        :sponsors_listing,
        sponsorable: @waitlisted_org,
        billing_country: "SV",
        country_of_residence: nil,
      )

      assert_equal "SV", listing.reload.billing_country
      assert_equal "SV", listing.country_of_residence
    end

    test "does not sync residence country for users" do
      listing = create(:sponsors_listing,
        billing_country: "SV",
        country_of_residence: "US",
      )

      assert_equal "SV", listing.reload.billing_country
      assert_equal "US", listing.country_of_residence
    end

    test "can update country of residence for orgs after create" do
      listing = create(:sponsors_listing, sponsorable: @waitlisted_org, billing_country: "SV")
      assert_equal "SV", listing.reload.billing_country
      assert_equal "SV", listing.country_of_residence

      assert listing.update(billing_country: "US")
      assert_equal "US", listing.reload.billing_country
      assert_equal "SV", listing.country_of_residence
    end
  end

  context "#country_of_residence_name" do
    test "returns the full name of the country of residence when set" do
      listing = build(:sponsors_listing, country_of_residence: "IT")
      assert_equal "Italy", listing.country_of_residence_name
    end

    test "returns nil when country of residence is not set" do
      listing = build(:sponsors_listing, country_of_residence: nil)
      assert_nil listing.country_of_residence_name
    end
  end

  context "#has_country_of_residence?" do
    test "true when listing has a country of residence" do
      listing = build(:sponsors_listing, country_of_residence: "US")
      assert_predicate listing, :has_country_of_residence?
    end

    test "false when listing does not have a country of residence" do
      listing = build(:sponsors_listing)
      listing.country_of_residence = nil
      refute_predicate listing, :has_country_of_residence?
    end
  end

  context "#editable_by?" do
    test "returns false if actor is a biztools user" do
      refute @listing.editable_by?(@biztools_user)
    end

    test "returns false if actor is a site admin" do
      user = create(:staff_admin_user)
      refute @listing.editable_by?(user)
    end

    test "returns true if actor is the listing's sponsorable" do
      assert @listing.editable_by?(@listing.sponsorable)
    end

    test "returns false if actor is a rando" do
      user = create(:user)
      refute @listing.editable_by?(user)
    end
  end

  context "#for_user?" do
    test "returns true when the type of sponsorable is User" do
      assert_predicate @listing, :for_user?
    end

    test "returns false when the type of sponsorable is Organization" do
      refute_predicate @org_listing, :for_user?
    end
  end

  context "#for_organization?" do
    test "returns true when the type of sponsorable is Organization" do
      assert_predicate @org_listing, :for_organization?
    end

    test "returns false when the type of sponsorable is User" do
      refute_predicate @listing, :for_organization?
    end
  end

  context "#allow_self_service_disable?" do
    test "true when user has tax form, no active sponsorships, and $0 in Stripe" do
      stub_stripe_balance(@approved_listing.active_stripe_connect_account, amount: 0)
      assert_predicate @approved_listing, :allow_self_service_disable?
    end

    test "true when user has tax form was not requested and verified" do
      assert_predicate @approved_listing, :allow_self_service_disable?
    end

    test "true when listing is in draft state" do
      assert_predicate @listing, :allow_self_service_disable?
    end

    test "false when listing is already disabled" do
      @approved_listing.update!(state: :disabled)
      refute_predicate @approved_listing, :allow_self_service_disable?
    end

    test "false when user has w8 or w9 tax form requested but not verified" do
      @approved_listing.active_stripe_connect_account.update(w8_or_w9_requested_at: Time.current, w8_or_w9_verified: false)
      refute_predicate @approved_listing.reload, :allow_self_service_disable?
    end

    test "false when user has active sponsorships" do
      create(:sponsorship, sponsorable: @approved_listing.sponsorable)
      refute_predicate @approved_listing, :allow_self_service_disable?
    end

    test "false when user has money in Stripe" do
      stub_stripe_balance(@approved_listing.active_stripe_connect_account, amount: 1)
      refute_predicate @approved_listing, :allow_self_service_disable?
    end
  end

  context "default_tier relation" do
    test "returns a published tier" do
      listing = create(:sponsors_listing)
      tier = create(:sponsors_tier, :published, sponsors_listing: listing)
      other_tier = create(:sponsors_tier, :retired, sponsors_listing: listing,
        monthly_price_in_cents: 2_00, yearly_price_in_cents: 24_00)

      assert_equal tier, listing.default_tier
    end
  end

  context "#subscription_items" do
    test "returns subscription items associated with this listing" do
      listing = create :sponsors_listing, :approved
      tiers = create_list :sponsors_tier, 2, :published, sponsors_listing: listing
      item = create :sponsors_subscription_item, subscribable: tiers.first
      other_item = create :sponsors_subscription_item, subscribable: tiers.second

      # add other tiers that shouldn't be returned
      other_listing = create :sponsors_listing, :approved
      other_tiers = create_list :sponsors_tier, 2, :published, sponsors_listing: other_listing
      create :sponsors_subscription_item, subscribable: other_tiers.first
      create :sponsors_subscription_item, subscribable: other_tiers.second

      assert_equal 2, listing.subscription_items.count
      assert_includes listing.subscription_items, item
      assert_includes listing.subscription_items, other_item
    end
  end

  context ".on_payout_probation" do
    test "returns listings that are currently on payout probation" do
      on_probation_listing = create :sponsors_listing, \
        payout_probation_started_at: 4.days.ago
      off_probation_listing = create :sponsors_listing, \
        payout_probation_started_at: 4.days.ago, \
        payout_probation_ended_at: 1.day.ago

      listings = SponsorsListing.on_payout_probation
      assert_includes listings, on_probation_listing
      refute_includes listings, off_probation_listing
    end
  end

  context ".matches_slug_or_description" do
    test "returns listings with slugs that match the query" do
      exact_matching_listing = create :sponsors_listing, slug: "coconut"
      lazy_matching_listing = create :sponsors_listing, slug: "a-coconut-yay"
      non_matching_listing = create :sponsors_listing, slug: "hazelnut"

      matching_listings = SponsorsListing.matches_slug_or_description("coconut")

      assert_equal 2, matching_listings.count
      assert_includes matching_listings, exact_matching_listing
      assert_includes matching_listings, lazy_matching_listing
      refute_includes matching_listings, non_matching_listing
    end

    test "returns listings with short descriptions that match the query" do
      exact_matching_listing = create :sponsors_listing,
        short_description: "coconut"
      lazy_matching_listing = create :sponsors_listing,
        short_description: "I want some coconuts"
      non_matching_listing = create :sponsors_listing,
        short_description: "It's all about hazelnuts"

      matching_listings = SponsorsListing.matches_slug_or_description("coconut")

      assert_equal 2, matching_listings.count
      assert_includes matching_listings, exact_matching_listing
      assert_includes matching_listings, lazy_matching_listing
      refute_includes matching_listings, non_matching_listing
    end

    test "returns listings with full descriptions that match the query" do
      exact_matching_listing = create :sponsors_listing,
        full_description: "coconut"
      lazy_matching_listing = create :sponsors_listing,
        full_description: "I want some coconuts"
      non_matching_listing = create :sponsors_listing,
        full_description: "It's all about hazelnuts"

      matching_listings = SponsorsListing.matches_slug_or_description("coconut")

      assert_equal 2, matching_listings.count
      assert_includes matching_listings, exact_matching_listing
      assert_includes matching_listings, lazy_matching_listing
      refute_includes matching_listings, non_matching_listing
    end
  end

  context "#stripe_connect_account" do
    test "returns stripe account associated with SponsorsListing" do
      stripe_account = create(:stripe_connect_account, sponsors_listing: @listing)
      assert_equal stripe_account, @listing.active_stripe_connect_account
    end

    test "returns nil if listing does not have associated stripe account" do
      assert_nil @listing.active_stripe_connect_account
    end
  end

  context "#on_payout_probation?" do
    test "returns true if probation has not ended" do
      listing = create(:sponsors_listing, payout_probation_started_at: 4.days.ago)
      assert_predicate listing, :on_payout_probation?
    end

    test "returns false if probation has ended" do
      listing = create(:sponsors_listing,
        payout_probation_started_at: 4.days.ago,
        payout_probation_ended_at: 1.day.ago,
      )

      refute_predicate listing, :on_payout_probation?
    end

    test "returns false if probation has not started" do
      listing = create(:sponsors_listing)
      refute_predicate listing, :on_payout_probation?
    end
  end

  context "#completed_payout_probation?" do
    test "returns true if payout_probation_ended_at is set" do
      listing = create(:sponsors_listing,
        payout_probation_started_at: 4.days.ago,
        payout_probation_ended_at: 1.day.ago,
      )

      assert_predicate listing, :completed_payout_probation?
    end

    test "returns false if payout_probation_ended_at is not set" do
      assert_nil @listing.payout_probation_ended_at
      refute_predicate @listing, :completed_payout_probation?
    end
  end

  context "#matchable?" do
    test "false if match_disabled?" do
      listing = create(:sponsors_listing, match_disabled: true)
      listing.update!(
        joined_at: SponsorsListing::JOINED_WAITLIST_MATCH_DEADLINE - 1.day,
        accepted_at: 1.year.ago,
      )
      refute_predicate listing, :matchable?
    end

    test "false if published outside match deadline" do
      refute_predicate @listing, :matchable?
    end

    test "false if an organization" do
      listing = create(:organization, :sponsorable).sponsors_listing
      listing.update!(
        joined_at: SponsorsListing::JOINED_WAITLIST_MATCH_DEADLINE - 1.day,
        accepted_at: 1.year.ago,
      )
      refute_predicate listing, :matchable?
      refute_predicate listing.reload, :matchable?
    end

    test "false if at or over match limit" do
      SponsorsListing.stub_const(:MATCHING_LIMIT_AMOUNT_IN_CENTS, 10) do
        @listing.stubs(:total_match_in_cents).returns(11)
        @listing.update!(
          joined_at: SponsorsListing::JOINED_WAITLIST_MATCH_DEADLINE - 1.day,
          accepted_at: 1.year.ago,
        )
        refute_predicate @listing, :matchable?
      end
    end

    test "true when listing is matchable" do
      @listing.update!(
        joined_at: SponsorsListing::JOINED_WAITLIST_MATCH_DEADLINE - 1.day,
        accepted_at: 1.year.ago,
      )
      assert_predicate @listing, :matchable?
    end

    # https://github.com/github/sponsors/issues/2082
    context "start matching fund clock" do
      test "full match period" do
        travel_to(Date.new(2021, 8, 1)) do
          @listing.update!(joined_at: SponsorsListing::JOINED_WAITLIST_MATCH_DEADLINE - 1.day, accepted_at: Date.today)
        end

        travel_to(Date.new(2021, 8, 7)) do
          @listing.update!(published_at: Date.today)
        end

        travel_to(Date.new(2022, 8, 6)) do
          assert_predicate @listing, :matchable?
        end

        travel_to(Date.new(2022, 8, 8)) do
          refute_predicate @listing, :matchable?
        end
      end

      test "partial match period" do
        travel_to(Date.new(2021, 8, 1)) do
          @listing.update!(joined_at: SponsorsListing::JOINED_WAITLIST_MATCH_DEADLINE - 1.day,
            accepted_at: Date.today)
        end

        travel_to(Date.new(2021, 11, 15)) do
          @listing.update!(published_at: Date.today)
        end

        travel_to(Date.new(2022, 9, 30)) do
          assert_predicate @listing, :matchable?
        end

        travel_to(Date.new(2022, 10, 1)) do
          refute_predicate @listing, :matchable?
        end
      end

      test "no match period" do
        travel_to(Date.new(2021, 8, 1)) do
          @listing.update!(joined_at: SponsorsListing::JOINED_WAITLIST_MATCH_DEADLINE - 1.day,
            accepted_at: Date.today)
        end

        travel_to(Date.new(2022, 9, 30)) do
          assert_predicate @listing, :matchable?
        end

        travel_to(Date.new(2022, 10, 1)) do
          refute_predicate @listing, :matchable?
        end

        travel_to(Date.new(2022, 10, 15)) do
          @listing.update!(published_at: Date.today)
          refute_predicate @listing, :matchable?
        end
      end

      test "for existing waitlisted users" do
        travel_to(Date.new(2019, 1, 1)) do
          @listing.update!(joined_at: SponsorsListing::JOINED_WAITLIST_MATCH_DEADLINE - 1.day,
            accepted_at: Date.today)
        end

        travel_to(Date.new(2022, 9, 30)) do
          assert_predicate @listing, :matchable?
        end

        travel_to(Date.new(2022, 10, 1)) do
          refute_predicate @listing, :matchable?
        end
      end
    end
  end

  context "oldest_join_date_first scope" do
    test "sorts listings by join date ascending" do
      old_listing = @listing
      new_listing = create(:sponsors_listing, joined_at: 1.minute.from_now)

      result = SponsorsListing.where(id: [old_listing, new_listing]).oldest_join_date_first

      assert_equal [old_listing, new_listing], result
    end
  end

  context "most_recent_join_date_first scope" do
    test "sorts listings by join date descending" do
      old_listing = @listing
      new_listing = create(:sponsors_listing, joined_at: 1.minute.from_now)

      result = SponsorsListing.where(id: [old_listing, new_listing]).most_recent_join_date_first

      assert_equal [new_listing, old_listing], result
    end
  end

  context "#next_payout_date" do
    test "returns nil if listing has never started probation period" do
      assert_nil @listing.payout_probation_started_at
      assert_nil @listing.next_payout_date
    end

    test "returns payout date for next month if payout already this month" do
      # Match the date in the (hard to modify) webhook payload
      travel_to(Date.new(2019, 7, 16)) do
        @auto_approvable_listing.update!(
          payout_probation_started_at: Date.new(2019, 3, 20),
          payout_probation_ended_at: Date.new(2019, 6, 20),
        )
        stripe_account = @auto_approvable_listing.active_stripe_connect_account
        create(:stripe_webhook, :payout_created, account: stripe_account.stripe_account_id)
        assert_equal Date.new(2019, 8, 22), @auto_approvable_listing.next_payout_date
      end
    end

    test "returns payout date for next month if probation ends after the 22nd" do
      travel_to(Date.new(2019, 12, 20)) do
        @listing.update!(payout_probation_started_at: Date.new(2019, 8, 25))
        assert_equal Date.new(2019, 12, 22), @listing.next_payout_date
      end
    end

    test "returns next payout date for listing that has completed probation" do
      travel_to(Date.new(2019, 9, 12)) do
        @listing.update!(
          payout_probation_started_at: Date.new(2019, 5, 20),
          payout_probation_ended_at: Date.new(2019, 8, 20),
        )
        assert_equal Date.new(2019, 9, 22), @listing.next_payout_date
      end
    end

    test "payout probation is over but payouts aren't enabled" do
      travel_to(Date.new(2020, 5, 5)) do
        @listing.update!(
          payout_probation_started_at: Date.new(2020, 1, 9),
        )
        assert_equal Date.new(2020, 5, 22), @listing.next_payout_date
      end
    end
  end

  context "#approvable_by?" do
    test "returns true if viewer is site admin" do
      assert @pending_listing.approvable_by?(@staff)
    end

    test "returns false if viewer is the listing's maintainer" do
      refute @pending_listing.approvable_by?(@pending_listing.sponsorable)
    end

    test "returns false if listing is not pending_approval" do
      refute_predicate @listing, :pending_approval?
      refute @listing.approvable_by?(@staff)
    end
  end

  context "#unpublishable_by?" do
    test "returns true if viewer is site admin" do
      assert @approved_listing.unpublishable_by?(@staff)
    end

    test "returns false if the sponsorable has active sponsorships" do
      create(:sponsorship, sponsorable: @approved_listing.sponsorable)
      refute @approved_listing.unpublishable_by?(@staff)
    end

    test "returns false if viewer is the listing's maintainer" do
      refute @approved_listing.unpublishable_by?(@approved_listing.sponsorable)
    end

    test "returns false if listing is not approved" do
      refute_predicate @listing, :approved?
      refute @listing.unpublishable_by?(@staff)
    end
  end

  context "#auto_approvable?" do
    test "returns true for listing with published tier, description, and verified stripe account" do
      assert_predicate @auto_approvable_listing.active_stripe_connect_account, :verified_verification_status?
      assert_equal 1, @auto_approvable_listing.published_sponsors_tiers.count
      assert @auto_approvable_listing.full_description.present?

      assert_predicate @auto_approvable_listing, :auto_approvable?
    end

    test "returns false for listing that uses a fiscal host" do
      @auto_approvable_listing.update!(parent_listing: @fiscal_host_listing)

      refute_predicate @auto_approvable_listing, :auto_approvable?
    end

    test "returns false for listing without stripe account" do
      @auto_approvable_listing.active_stripe_connect_account.destroy!
      assert_nil @auto_approvable_listing.reload.active_stripe_connect_account
      assert_equal 1, @auto_approvable_listing.published_sponsors_tiers.count
      assert @auto_approvable_listing.full_description.present?

      refute_predicate @auto_approvable_listing, :auto_approvable?
    end

    test "returns true for listing without published tier" do
      @auto_approvable_listing.published_sponsors_tiers.destroy_all
      assert_predicate @auto_approvable_listing.reload.active_stripe_connect_account, :verified_verification_status?
      assert_empty @auto_approvable_listing.published_sponsors_tiers
      assert @auto_approvable_listing.full_description.present?

      assert_predicate @auto_approvable_listing, :auto_approvable?
    end

    test "returns false for listing without description" do
      @auto_approvable_listing.full_description = ""

      refute @auto_approvable_listing.full_description.present?
      assert_predicate @auto_approvable_listing.active_stripe_connect_account, :verified_verification_status?
      assert_equal 1, @auto_approvable_listing.published_sponsors_tiers.count

      refute_predicate @auto_approvable_listing, :auto_approvable?
    end

    test "returns false for listing without verified stripe account" do
      account = @auto_approvable_listing.active_stripe_connect_account
      account.update!(verification_status: :unverified)
      assert_equal 1, @auto_approvable_listing.published_sponsors_tiers.count
      assert @auto_approvable_listing.full_description.present?

      refute_predicate @auto_approvable_listing, :auto_approvable?
    end

    test "returns false if sponsorable is banned from program" do
      @auto_approvable_listing.actor = @staff
      assert @auto_approvable_listing.ban!(banned_reason: "reasons")
      assert_predicate @auto_approvable_listing.reload, :banned?
      assert_predicate @auto_approvable_listing.active_stripe_connect_account, :verified_verification_status?
      assert_equal 1, @auto_approvable_listing.published_sponsors_tiers.count
      assert @auto_approvable_listing.full_description.present?

      refute_predicate @auto_approvable_listing, :auto_approvable?
    end

    test "returns true for organization meeting criteria" do
      auto_approvable_org_as_sponsorable = create(:organization, :sponsors_auto_approvable, created_at: 1.year.ago)
      auto_approvable_org_listing = auto_approvable_org_as_sponsorable.sponsors_listing

      assert auto_approvable_org_listing.full_description.present?
      assert_equal 1, auto_approvable_org_listing.published_sponsors_tiers.count
      assert_predicate auto_approvable_org_listing.active_stripe_connect_account, :verified_verification_status?
      assert_predicate auto_approvable_org_listing, :auto_approvable?
    end

    test "returns false if sponsorable account is younger than six months" do
      @auto_approvable_listing.sponsorable.update!(created_at: 5.months.ago)
      refute_predicate @auto_approvable_listing, :auto_approvable?
    end

    test "returns false if sponsorable billing country is not supported" do
      unsupported_country = Billing::StripeConnect::Account.unsupported_countries.first
      @auto_approvable_listing.active_stripe_connect_account.update!(billing_country: unsupported_country)
      @auto_approvable_listing.update!(billing_country: unsupported_country)

      refute_predicate @auto_approvable_listing, :auto_approvable?
    end

    test "returns false if sponsorable's time zone does not match listing's country of residence" do
      @auto_approvable_listing.active_stripe_connect_account.update!(country: "CA")
      @auto_approvable_listing.update!(country_of_residence: "CA")
      refute_predicate @auto_approvable_listing, :auto_approvable?
    end

    test "returns false if sponsorable has not customized their GitHub profile" do
      profile = @auto_approvable_listing.sponsorable.profile
      profile.update!(bio: nil, name: nil, twitter_username: nil, blog: nil, company: nil)
      refute SponsorsListingStafftoolsMetadata.profile_customized_for_sponsors?(profile)
      refute_predicate @auto_approvable_listing.reload_stafftools_metadata, :has_customized_user_profile?

      refute_predicate @auto_approvable_listing, :auto_approvable?
    end

    test "returns false if tax forms are required but unverified on Stripe" do
      @auto_approvable_listing.active_stripe_connect_account.update(w8_or_w9_requested_at: Time.current, w8_or_w9_verified: false)

      refute_predicate @auto_approvable_listing.reload, :auto_approvable?
    end

    test "returns true if tax forms are required and verified on Stripe" do
      @auto_approvable_listing.active_stripe_connect_account.update(w8_or_w9_requested_at: Time.current, w8_or_w9_verified: true)

      assert_predicate @auto_approvable_listing.reload, :auto_approvable?
    end

    TradeControls::SdnScreeningTestHelper::NOT_ALLOWED_SDN_AUTO_SPONSORSHIP_STATUSES.each do |status|
      test "false for sponsorable user with trade screening status #{status}" do
        trade_screening_record = @auto_approvable_listing.trade_screening_record
        trade_screening_record.update!(msft_trade_screening_status: status)

        enable_feature_flag(:live_sdn_screening)

        refute_predicate @auto_approvable_listing, :auto_approvable?
      end
    end

    TradeControls::SdnScreeningTestHelper::ALLOWED_SDN_AUTO_SPONSORSHIP_STATUSES.each do |status|
      test "true for sponsorable user with trade screening status #{status}" do
        @auto_approvable_listing.update!(state: :draft)

        trade_screening_record = @auto_approvable_listing.trade_screening_record
        trade_screening_record.update!(msft_trade_screening_status: status)

        enable_feature_flag(:live_sdn_screening)
        # We don't want to screen the sponsorable user (this could cause a different screening status)
        @auto_approvable_listing.sponsorable.expects(:should_perform_live_sdn_screening?).returns(false)

        assert_predicate @auto_approvable_listing, :auto_approvable?

        assert_enqueued_with(job: AutoApproveSponsorsListingJob) do
          @auto_approvable_listing.request_approval!
        end
      end
    end
  end

  context "#eligible_for_sponsors?" do
    test "returns true if sponsorable has public contributions" do
      refute_includes Billing::StripeConnect::Account.supported_countries, "IR",
      "expecting Iran not to be a supported country for this test"
      sponsorable = create(:user, time_zone_name: "Tehran",
        created_at: (SponsorsListing::ACCOUNT_AGE_CUTOFF_FOR_AUTO_BAN - 1.day).ago
      )
      public_repo = create(:repository, owner: sponsorable)
      create(:commit_contribution, :with_summaries, user: sponsorable, repository: public_repo,
        commit_count: 1, committed_date: 3.months.ago)
      listing = create(:sponsors_listing, sponsorable: sponsorable, full_description: "", short_description: "")

      assert_predicate listing, :eligible_for_sponsors?
    end

    test "returns true if sponsorable has customized user profile" do
      refute_includes Billing::StripeConnect::Account.supported_countries, "IR",
      "expecting Iran not to be a supported country for this test"
      sponsorable = create(:user, time_zone_name: "Tehran",
        created_at: (SponsorsListing::ACCOUNT_AGE_CUTOFF_FOR_AUTO_BAN - 1.day).ago
      )
      listing = create(:sponsors_listing, :with_customized_sponsorable_profile, sponsorable: sponsorable, full_description: "", short_description: "")

      assert_predicate listing, :eligible_for_sponsors?
    end

    test "returns true if sponsorable is in a supported timezone" do
      assert_includes Billing::StripeConnect::Account.supported_countries, "AU",
      "expecting Australia to be a supported country for this test"
      sponsorable = create(:user, time_zone_name: "Canberra",
        created_at: (SponsorsListing::ACCOUNT_AGE_CUTOFF_FOR_AUTO_BAN - 1.day).ago
      )
      listing = create(:sponsors_listing, sponsorable: sponsorable, full_description: "", short_description: "")

      assert_predicate listing, :eligible_for_sponsors?
    end

    test "returns false if all conditions are met and sponsorable is younger than auto-ban age cutoff" do
      refute_includes Billing::StripeConnect::Account.supported_countries, "IR",
      "expecting Iran not to be a supported country for this test"
      sponsorable = create(:user, time_zone_name: "Tehran",
        created_at: (SponsorsListing::ACCOUNT_AGE_CUTOFF_FOR_AUTO_BAN - 1.day).ago
      )
      listing = create(:sponsors_listing, sponsorable: sponsorable, full_description: "", short_description: "")

      refute_predicate listing, :eligible_for_sponsors?
    end

    test "returns true if sponsorable is older than auto-ban age cutoff" do
      assert_includes Billing::StripeConnect::Account.supported_countries, "AU",
      "expecting Australia to be a supported country for this test"
      sponsorable = create(:user, :sponsors_old_enough_to_not_get_auto_banned, time_zone_name: "Canberra")
      public_repo = create(:repository, owner: sponsorable)
      create(:commit_contribution, :with_summaries, user: sponsorable, repository: public_repo,
        commit_count: 1, committed_date: 7.months.ago)
      listing = create(:sponsors_listing, :with_customized_sponsorable_profile, sponsorable: sponsorable, full_description: "Hello", short_description: "Hi")

      assert_predicate listing, :eligible_for_sponsors?
    end
  end

  context "#reached_match_limit?" do
    test "returns true when listing has met the match limit" do
      listing = create(:sponsors_listing, :approved, :with_stripe_account)
      create(:payouts_ledger_entry, :github_match,
        stripe_connect_account: listing.active_stripe_connect_account,
        amount_in_subunits: -SponsorsListing::MATCHING_LIMIT_AMOUNT_IN_CENTS) # NOTE: these are recorded as a negative value

      assert_predicate listing.reload, :reached_match_limit?
    end

    test "considers ledger entries from across Stripe accounts" do
      half_limit = SponsorsListing::MATCHING_LIMIT_AMOUNT_IN_CENTS / 2
      child_listing = create(:sponsors_listing, :with_fiscal_host,
        parent_listing: @fiscal_host_listing)

      # Have an old inactive Stripe account personally owned by the child listing, where some
      # matching money went:
      inactive_stripe = create(:stripe_connect_account, :inactive, sponsors_listing: child_listing)
      create(:payouts_ledger_entry, :github_match,
        sponsors_listing: child_listing,
        stripe_connect_account: inactive_stripe,
        amount_in_subunits: -half_limit) # NOTE: these are recorded as a negative value

      # Have more matching money paid into the fiscal host's Stripe, tied to the child listing:
      create(:payouts_ledger_entry, :github_match,
        sponsors_listing: child_listing,
        stripe_connect_account: @fiscal_host_stripe,
        amount_in_subunits: -half_limit)

      assert_predicate child_listing.reload, :reached_match_limit?
    end

    test "returns false when listing has not met the match limit" do
      listing = create(:sponsors_listing, :approved, :with_stripe_account)

      refute_predicate listing.reload, :reached_match_limit?
    end
  end

  context "match_limit_reached_at" do
    test "instruments hydro event when date is set" do
      @listing.touch(:match_limit_reached_at)

      expected_message = {
        listing: Hydro::EntitySerializer.sponsors_listing(@listing),
      }

      assert_hydro_published(expected_message,
        schema: "github.sponsors.v0.SponsorsListingMatchLimitReached")
      assert_hydro_messages(count: 1,
        schema: "github.sponsors.v0.SponsorsListingMatchLimitReached")
    end

    test "does not instrument event if match_limit_reached_at is nil" do
      @listing.touch(:published_at)
      assert_nil @listing.match_limit_reached_at
      refute_hydro_messages(schema: "github.sponsors.v0.SponsorsListingMatchLimitReached")
    end

    test "sends an email to sponsorable" do
      SponsorsPrimerMailer.expects(:reached_match_cap)
                    .once
                    .with(sponsorable: @listing.sponsorable)
                    .returns(stub(deliver_later: nil))

      @listing.touch(:match_limit_reached_at)
    end

    test "does not send email when opted out" do
      email_opt_outs = SponsorsEmailOptOuts.new(bitmask: nil)
      email_opt_outs.opt_out_of(:reached_match_cap)
      @listing.update_email_opt_outs(email_opt_outs)

      SponsorsPrimerMailer.expects(:reached_match_cap).never

      @listing.touch(:match_limit_reached_at)
    end

    test "does not send email when opted out of all" do
      email_opt_outs = SponsorsEmailOptOuts.new(bitmask: nil)
      email_opt_outs.opt_out_of(:all)
      @listing.update_email_opt_outs(email_opt_outs)

      SponsorsPrimerMailer.expects(:reached_match_cap).never

      @listing.touch(:match_limit_reached_at)
    end

    test "does not send email if match_limit_reached_at is nil" do
      SponsorsPrimerMailer.expects(:reached_match_cap).never
      @listing.touch(:published_at)
      assert_nil @listing.match_limit_reached_at
    end
  end

  context "#disable_sponsors_match!" do
    test "sets match to disabled and sets staff note" do
      refute_predicate @listing, :match_disabled?

      reason = "You want matching? Too bad!"

      @listing.actor = @staff
      @listing.disable_sponsors_match!(reason: reason)

      expected_note = "Matching was disabled by staff. Reason: #{reason}"

      assert_predicate @listing.reload, :match_disabled?
      assert_equal expected_note, @listing.staff_notes.last.note
    end

    test "instruments audit log event" do
      events = subscribe "sponsors_listing.disable_match"
      reason = "You want matching? Too bad!"
      expected_payload = GitHub.guarded_audit_log_staff_actor_entry(@staff).merge(
        user: @listing.sponsorable_login,
        user_id: @listing.sponsorable.id,
        reason: reason,
        sponsors_listing_id: @listing.id,
        short_description: @listing.short_description,
        sponsors_listing: @listing.slug,
        state: :draft,
        created_by: @listing.sponsorable_login,
        created_by_id: @listing.sponsorable_id,
      )

      @listing.actor = @staff
      @listing.disable_sponsors_match!(reason: reason)

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end
  end

  context "#enable_sponsors_match!" do
    test "sets match to enabled" do
      @listing.actor = @staff
      @listing.disable_sponsors_match!(reason: "testing")
      assert_predicate @listing, :match_disabled?
      @listing.enable_sponsors_match!
      refute_predicate @listing.reload, :match_disabled?
    end

    test "instruments audit log event" do
      events = subscribe "sponsors_listing.enable_match"
      expected_payload = GitHub.guarded_audit_log_staff_actor_entry(@staff).merge(
        user: @listing.sponsorable_login,
        user_id: @listing.sponsorable.id,
        sponsors_listing_id: @listing.id,
        short_description: @listing.short_description,
        sponsors_listing: @listing.slug,
        state: :draft,
        created_by: @listing.sponsorable_login,
        created_by_id: @listing.sponsorable_id,
      )

      @listing.actor = @staff
      @listing.enable_sponsors_match!

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end
  end

  context "#joined_waitlist_before_match_deadline?" do
    test "true if joined_at is before deadline" do
      @listing.update!(joined_at: SponsorsListing::JOINED_WAITLIST_MATCH_DEADLINE - 1.day)
      assert_predicate @listing, :joined_waitlist_before_match_deadline?
    end

    test "false if created after deadline" do
      @listing.update!(joined_at: SponsorsListing::JOINED_WAITLIST_MATCH_DEADLINE + 1.day)
      refute_predicate @listing, :joined_waitlist_before_match_deadline?
    end
  end

  context "ordered_by_user_creation_time scope" do
    test "sorts with newest GitHub users first" do
      old_user = travel_to(4.years.ago) { create(:user, :sponsorable) }
      middle_user = travel_to(2.years.ago) { create(:user, :sponsorable) }
      new_user = create(:user, :sponsorable)
      all_listings = [middle_user, new_user, old_user].map(&:sponsors_listing)

      result = SponsorsListing.where(id: all_listings).ordered_by_user_creation_time(:desc)

      assert_equal [new_user, middle_user, old_user].map(&:sponsors_listing), result
    end

    test "sorts with oldest GitHub users first" do
      old_user = travel_to(4.years.ago) { create(:user, :sponsorable) }
      middle_user = travel_to(2.years.ago) { create(:user, :sponsorable) }
      new_user = create(:user, :sponsorable)
      all_listings = [middle_user, new_user, old_user].map(&:sponsors_listing)

      result = SponsorsListing.where(id: all_listings).ordered_by_user_creation_time(:asc)

      assert_equal [old_user, middle_user, new_user].map(&:sponsors_listing), result
    end

    test "defaults to descending order when invalid direction is given" do
      old_user = travel_to(4.years.ago) { create(:user, :sponsorable) }
      middle_user = travel_to(2.years.ago) { create(:user, :sponsorable) }
      new_user = create(:user, :sponsorable)
      all_listings = [middle_user, new_user, old_user].map(&:sponsors_listing)

      result = SponsorsListing.where(id: all_listings).ordered_by_user_creation_time(:bad_direction)

      assert_equal [new_user, middle_user, old_user].map(&:sponsors_listing), result
    end
  end

  context "without_sponsorable_users scope" do
    test "excludes listings for the specified sponsorable users and orgs" do
      included_listing = @listing
      excluded_listing = @pending_listing
      included_org_listing = @org_listing
      excluded_org_listing = create(:sponsors_listing, :for_org)
      all_listings = [included_listing, excluded_listing, included_org_listing,
        excluded_org_listing]

      result = SponsorsListing.without_sponsorable_users([
        excluded_listing.sponsorable_id, excluded_org_listing.sponsorable_id
      ]).where(id: all_listings)

      assert_same_elements [included_listing, included_org_listing],
        result
    end
  end

  context "with_supported_billing_country scope" do
    test "includes listings with a supported billing country" do
      included_listing = create(:sponsors_listing, billing_country: "IT")
      excluded_listing = create(:sponsors_listing, billing_country: "AZ")

      result = SponsorsListing.with_supported_billing_country.
        where(id: [included_listing, excluded_listing])

      assert_includes result, included_listing
      refute_includes result, excluded_listing
    end
  end

  context "with_unsupported_billing_country scope" do
    test "includes listings without a billing country or in an unsupported billing country" do
      excluded_listing = create(:sponsors_listing, billing_country: "IT")
      included_listing1 = create(:sponsors_listing, billing_country: "AZ")
      included_listing2 = create(:sponsors_listing, billing_country: nil)

      result = SponsorsListing.with_unsupported_billing_country.
        where(id: [included_listing1, included_listing2, excluded_listing])

      assert_includes result, included_listing1
      assert_includes result, included_listing2
      refute_includes result, excluded_listing
    end
  end

  context "#country_of_residence_emoji" do
    test "returns nil when listing is missing country of residence" do
      no_country_listing = create(:sponsors_listing)
      no_country_listing.country_of_residence = nil
      no_country_listing.save!(validate: false)
      no_details_account = build(:stripe_connect_account, country: nil)
      assert_nil no_country_listing.country_of_residence_emoji
    end

    test "returns emoji that represents the account's country" do
      us_listing = create(:sponsors_listing, country_of_residence: "US")

      result = us_listing.country_of_residence_emoji

      refute_nil result
      assert_equal Emoji.find_by_alias("us"), result
      assert_instance_of Emoji::Character, result
    end

    test "returns flag for Canada" do
      canadian_listing = create(:sponsors_listing, country_of_residence: "CA")

      result = canadian_listing.country_of_residence_emoji

      refute_nil result
      assert_equal Emoji.find_by_alias("canada"), result
      assert_instance_of Emoji::Character, result
    end
  end

  context "with_billing_country scope" do
    test "includes listings with the specified billing country" do
      included_listing = create(:sponsors_listing, billing_country: "IT")
      excluded_listing = create(:sponsors_listing, billing_country: "AZ")

      result = SponsorsListing.with_billing_country("IT").
        where(id: [included_listing, excluded_listing])

      assert_includes result, included_listing
      refute_includes result, excluded_listing
    end
  end

  context "with_country_of_residence scope" do
    test "includes listings with the given country of residence" do
      it_listing = create(:sponsors_listing, country_of_residence: "IT")
      ca_listing = create(:sponsors_listing, country_of_residence: "CA")

      result = SponsorsListing.with_country_of_residence("IT")
        .where(id: [it_listing, ca_listing])

      assert_includes result, it_listing
      refute_includes result, ca_listing
    end
  end

  context "without_country_of_residence scope" do
    test "includes listings whose country of residence is not the given country" do
      us_listing = create(:sponsors_listing, country_of_residence: "US")
      es_listing = create(:sponsors_listing, country_of_residence: "ES")
      countryless_listing = create(:sponsors_listing)
      countryless_listing.update_attribute(:country_of_residence, "")
      ca_listing = create(:sponsors_listing, country_of_residence: "CA")

      result = SponsorsListing.without_country_of_residence("US").
        where(id: [us_listing, es_listing, countryless_listing, ca_listing])

      assert_includes result, es_listing
      refute_includes result, us_listing
      refute_includes result, countryless_listing
      assert_includes result, ca_listing
    end
  end

  context "#sponsorable_name" do
    test "returns display name of the sponsorable if set" do
      create(:profile, user: @listing.sponsorable, name: "My Great Name")
      assert_equal "My Great Name", @listing.sponsorable_name
    end

    test "returns login of sponsorable if no display name is set" do
      assert_equal @listing.sponsorable_login, @listing.sponsorable_name
    end
  end

  context "#supports_payout_receipts?" do
    test "false when listing has a parent listing" do
      listing = build(:sponsors_listing, parent_listing: @fiscal_host_listing)
      refute_predicate listing, :supports_payout_receipts?
    end

    test "true when listing does not have a parent listing" do
      listing = build(:sponsors_listing, parent_listing: nil)
      assert_predicate listing, :supports_payout_receipts?
    end
  end

  context ".get_spammy_sponsorable_ids" do
    test "returns IDs of spammy sponsorables" do
      spammer = create(:spammy_user)
      spammy_listing = create(:sponsors_listing, sponsorable: spammer)
      non_spammy_listing = @listing
      listings = SponsorsListing.where(id: [spammy_listing, non_spammy_listing])

      result = SponsorsListing.get_spammy_sponsorable_ids(listings)

      assert_equal [spammer.id], result
    end
  end if GitHub.spamminess_check_enabled?

  context ".get_suspended_sponsorable_ids" do
    test "returns IDs of suspended sponsorables" do
      suspended_user = create(:suspended_user)
      suspended_listing = create(:sponsors_listing, sponsorable: suspended_user)
      non_suspended_listing = @listing
      listings = SponsorsListing.where(id: [suspended_listing, non_suspended_listing])

      result = SponsorsListing.get_suspended_sponsorable_ids(listings)

      assert_equal [suspended_user.id], result
    end

    test "batches lookup of suspended sponsorable IDs" do
      suspended_users = create_list(:suspended_sponsorable, 3)
      listings = suspended_users.map(&:sponsors_listing)

      result = SponsorsListing.stub_const(:SUSPENDED_SPONSORABLE_IDS_BATCH_SIZE, 1) do
        assert_query_count_per_table({ users: 3 }) do
          SponsorsListing.get_suspended_sponsorable_ids(listings)
        end
      end

      assert_equal suspended_users.map(&:id), result
    end
  end

  context ".get_sponsorable_ids_of_type" do
    test "returns IDs of sponsorables that are users when specified" do
      listings = SponsorsListing.where(id: [@listing, @org_listing])

      result = SponsorsListing.get_sponsorable_ids_of_type(listings,
        user_type: "user")

      assert_equal [@listing.sponsorable_id], result
    end

    test "returns IDs of sponsorables that are organizations when specified" do
      listings = SponsorsListing.where(id: [@listing, @org_listing])

      result = SponsorsListing.get_sponsorable_ids_of_type(listings,
        user_type: "organization")

      assert_equal [@org_listing.sponsorable_id], result
    end
  end

  context "filter_by_featured scope" do
    test "filters to listings that are featured" do
      featured_listing1 = create(:sponsors_listing, :approved, featured_state: :allowed)
      featured_listing2 = create(:sponsors_listing, :approved, featured_state: :allowed)
      featured_listing2.update!(featured_state: :active)
      non_featured_listing = create(:sponsors_listing, :approved)

      result = SponsorsListing.filter_by_featured(true)

      assert_includes result, featured_listing1
      assert_includes result, featured_listing2
      refute_includes result, non_featured_listing
    end

    test "filters to listings that are not featured" do
      featured_listing = create(:sponsors_listing, :approved, featured_state: :allowed)
      non_featured_listing1 = create(:sponsors_listing, :approved)
      non_featured_listing2 = create(:sponsors_listing, :approved, :ignored, featured_state: :allowed)
      non_featured_listing3 = create(:sponsors_listing, featured_state: :allowed)

      result = SponsorsListing.filter_by_featured(false)

      refute_includes result, featured_listing
      assert_includes result, non_featured_listing1
      assert_includes result, non_featured_listing2
      assert_includes result, non_featured_listing3
    end

    test "includes featured and non-featured listings when given nil" do
      featured_listing1 = create(:sponsors_listing, :approved, featured_state: :allowed)
      featured_listing2 = create(:sponsors_listing, :approved, featured_state: :allowed)
      featured_listing2.update!(featured_state: :active)
      non_featured_listing1 = create(:sponsors_listing, :approved)
      non_featured_listing2 = create(:sponsors_listing, :approved, :ignored, featured_state: :allowed)
      non_featured_listing3 = create(:sponsors_listing, featured_state: :allowed)

      result = SponsorsListing.filter_by_featured(nil)

      assert_includes result, featured_listing1
      assert_includes result, featured_listing2
      assert_includes result, non_featured_listing1
      assert_includes result, non_featured_listing2
      assert_includes result, non_featured_listing3
    end
  end

  context "#ready_for_approval?" do
    test "true when pending approval, has verified Stripe account, and tax forms are required and verified on Stripe" do
      listing = create(:sponsors_listing, :with_w8_or_w9_verified_stripe_account, :pending_approval,
        parent_listing: nil)

      assert_predicate listing, :ready_for_approval?
    end

    test "true when pending approval and using a supported fiscal host with a verified stripe account" do
      listing = create(:sponsors_listing, :pending_approval, parent_listing: @osc.sponsors_listing)
      create(:stripe_connect_account, :w8_or_w9_verified, sponsors_listing: @osc.sponsors_listing, active: false)

      # Make sure we're correctly getting the active stripe account
      assert_equal @osc_stripe, listing.stripe_transfer_account
      assert_predicate listing, :ready_for_approval?
    end

    test "true when pending approval, has a verified Stripe account" do
      listing = create(:sponsors_listing, :with_w8_or_w9_verified_stripe_account, :pending_approval,
        parent_listing: nil)

      assert_predicate listing, :ready_for_approval?
    end

    test "true when requires_additional_review, has a verified Stripe account, and satisfies w8/w9 requirements" do
      listing = create(:sponsors_listing, :with_w8_or_w9_verified_stripe_account, :requires_additional_review,
        parent_listing: nil)

      assert_predicate listing, :ready_for_approval?
    end

    test "true when queued_for_auto_approval, has a verified Stripe account, and satisfies w8/w9 requirements" do
      listing = create(:sponsors_listing, :with_w8_or_w9_verified_stripe_account, :queued_for_auto_approval,
        parent_listing: nil)

      assert_predicate listing, :ready_for_approval?
    end

    test "false when pending approval, has verified Stripe account, but tax forms are required and unverified on Stripe" do
      listing = create(:sponsors_listing, :with_w8_or_w9_requested_but_unverified_stripe_account, :pending_approval,
        parent_listing: nil)

      refute_predicate listing, :ready_for_approval?
    end

    test "false when not pending approval, requires_additional_review, or queued_for_auto_approval" do
      listing = create(:sponsors_listing, :draft, :with_w8_or_w9_verified_stripe_account, parent_listing: nil)

      refute_predicate listing, :ready_for_approval?
    end

    test "false when no Stripe account" do
      listing = create(:sponsors_listing, :pending_approval)

      refute_predicate listing, :ready_for_approval?
    end

    test "false when Stripe account is unverified" do
      listing = create(:sponsors_listing, :pending_approval, parent_listing: nil)
      create(:stripe_connect_account, :unverified, sponsors_listing: listing)

      refute_predicate listing, :ready_for_approval?
    end
  end

  context "#ready_for_submission?" do
    test "true for listing ready for submission with a published tier" do
      listing = create(:sponsors_listing, :ready_for_submission)

      assert listing.full_description.present?
      assert_predicate listing, :draft?
      assert_predicate listing.active_stripe_connect_account, :verified_verification_status?
      assert_predicate listing.contact_email, :verified?
      assert_predicate listing, :ready_for_submission?
    end

    test "false for listing that requires and is missing w8 or w9 tax verification on Stripe" do
      listing = create(:sponsors_listing, :ready_for_submission, legal_name: nil)
      listing.active_stripe_connect_account.update(w8_or_w9_requested_at: Time.current, w8_or_w9_verified: false)

      assert listing.full_description.present?
      refute listing.legal_name, "legal name is not required when using Stripe tax verification"
      refute_predicate listing.active_stripe_connect_account, :w8_or_w9_verified
      assert_predicate listing, :draft?
      assert_predicate listing.active_stripe_connect_account, :verified_verification_status?
      assert_predicate listing.contact_email, :verified?
      refute_predicate listing, :ready_for_submission?
    end

    test "true for listing that has required stripe w8 or w9 verification and no legal name" do
      listing = create(:sponsors_listing, :ready_for_submission, legal_name: nil)
      listing.active_stripe_connect_account.update!(w8_or_w9_requested_at: Time.now, w8_or_w9_verified: true)

      assert listing.full_description.present?
      refute listing.legal_name, "legal name is not required when using Stripe tax verification"
      assert_predicate listing.active_stripe_connect_account, :w8_or_w9_verified
      assert_predicate listing, :draft?
      assert_predicate listing.active_stripe_connect_account, :verified_verification_status?
      assert_predicate listing.contact_email, :verified?
      assert_predicate listing, :ready_for_submission?
    end

    # Legal name is not required in this case, but also should not stop submission if it is present
    test "true for listing that has required stripe w8 or w9 verification and has legal name" do
      listing = create(:sponsors_listing, :ready_for_submission)
      listing.active_stripe_connect_account.update!(w8_or_w9_verified: true)

      assert listing.full_description.present?
      assert listing.legal_name, "legal name is not required when using Stripe tax verification"
      assert_predicate listing.active_stripe_connect_account, :w8_or_w9_verified
      assert_predicate listing, :draft?
      assert_predicate listing.active_stripe_connect_account, :verified_verification_status?
      assert_predicate listing.contact_email, :verified?
      assert_predicate listing, :ready_for_submission?
    end

    test "true for listing ready for submission with a published tier with live_sdn_screening enabled" do
      listing = create(:sponsors_listing, :ready_for_submission)

      assert listing.full_description.present?
      assert_predicate listing, :draft?
      assert_predicate listing.active_stripe_connect_account, :verified_verification_status?
      assert_predicate listing.contact_email, :verified?
      assert_predicate listing, :ready_for_submission?
    end

    test "false for listing ready for submission with a published tier with live_sdn_screening enabled but no account_screening_profile" do
      listing = create(:sponsors_listing, :ready_for_submission)
      listing.sponsorable.trade_screening_record.destroy!

      assert listing.full_description.present?
      assert_predicate listing, :draft?
      assert_predicate listing.active_stripe_connect_account, :verified_verification_status?
      assert_predicate listing.contact_email, :verified?
      refute_predicate listing, :ready_for_submission?
    end

    test "true for listing ready for submission with custom amounts enabled" do
      listing = create(:sponsors_listing, :ready_for_submission_with_custom_amounts)

      assert listing.full_description.present?
      assert_predicate listing, :draft?
      assert_predicate listing.active_stripe_connect_account, :verified_verification_status?
      assert_predicate listing.contact_email, :verified?
      assert_predicate listing, :ready_for_submission?
    end

    test "false for user listing with unverified contact email" do
      user = create(:verified_user)
      unverified_email = create(:user_email, user: user)
      listing = create(:sponsors_listing, :ready_for_submission, sponsorable: user,
        contact_email: unverified_email)

      assert listing.full_description.present?
      assert_predicate listing, :draft?
      assert_predicate listing.active_stripe_connect_account, :verified_verification_status?
      refute_predicate listing.contact_email, :verified?
      refute_predicate listing, :ready_for_submission?
    end

    test "false for listing without verified stripe account" do
      listing = create(:sponsors_listing, :draft, :with_tier)
      create(:stripe_connect_account, :unverified, sponsors_listing: listing)

      assert listing.full_description.present?
      assert_predicate listing, :draft?
      refute_predicate listing.active_stripe_connect_account, :verified_verification_status?
      refute_predicate listing, :ready_for_submission?
    end

    test "true for org listing using a supported fiscal host that has a Stripe" do
      child_listing = create(:sponsors_listing, :with_fiscal_host, :for_org, :with_tier)
      create(:stripe_connect_account, sponsors_listing: child_listing.parent_listing)

      assert child_listing.full_description.present?
      assert_predicate child_listing, :draft?
      assert_nil child_listing.active_stripe_connect_account
      refute_nil child_listing.active_stripe_account_for_self_or_fiscal_host

      assert_predicate child_listing, :ready_for_submission?
    end

    test "true for user listing using a supported fiscal host that has a Stripe" do
      user = create(:user, :verified)
      child_listing = create(:sponsors_listing, :with_fiscal_host, :with_trade_screening_record, :with_tier,
        sponsorable: user, contact_email: user.emails.verified.first)
      create(:stripe_connect_account, sponsors_listing: child_listing.parent_listing)

      assert child_listing.full_description.present?
      assert_predicate child_listing, :has_published_tier?
      assert_predicate child_listing, :draft?
      assert_nil child_listing.active_stripe_connect_account
      refute_nil child_listing.active_stripe_account_for_self_or_fiscal_host

      assert_predicate child_listing, :ready_for_submission?
    end

    test "false for listing without full description" do
      listing = create(:sponsors_listing, :ready_for_submission,
        full_description: "")

      refute listing.full_description.present?
      assert_predicate listing, :draft?
      assert_predicate listing.active_stripe_connect_account, :verified_verification_status?
      refute_predicate listing, :ready_for_submission?
    end

    test "false for listing without billing country" do
      listing = create(:sponsors_listing, :ready_for_submission, billing_country: nil)

      refute listing.billing_country.present?
      assert_predicate listing, :draft?
      assert_predicate listing.active_stripe_connect_account, :verified_verification_status?
      refute_predicate listing, :ready_for_submission?
    end

    test "true for org listing without legal name" do
      listing = create(:sponsors_listing, :for_org, :ready_for_submission, legal_name: nil)

      refute listing.legal_name.present?
      assert_predicate listing, :draft?
      assert_predicate listing.active_stripe_connect_account, :verified_verification_status?
      assert_predicate listing, :ready_for_submission?
    end

    test "false for user listing without contact email" do
      listing = create(:sponsors_listing, :ready_for_submission, contact_email_id: nil)
      listing.update!(contact_email_id: nil)

      refute listing.contact_email_address.present?
      assert_predicate listing, :draft?
      assert_predicate listing.active_stripe_connect_account, :verified_verification_status?
      refute_predicate listing, :ready_for_submission?
    end

    test "false for a spammy user's listing" do
      listing = create(:sponsors_listing, :ready_for_submission)
      listing.sponsorable.mark_as_spammy

      assert_predicate listing.sponsorable, :spammy?
      assert_predicate listing, :draft?
      assert_predicate listing.active_stripe_connect_account, :verified_verification_status?
      refute_predicate listing, :ready_for_submission?
    end

    test "false for org listing without billing email" do
      listing = create(:sponsors_listing, :ready_for_submission, :for_org)
      listing.sponsorable.update_attribute(:organization_billing_email, nil)

      refute listing.contact_email_address.present?
      assert_predicate listing, :draft?
      assert_predicate listing.active_stripe_connect_account, :verified_verification_status?
      refute_predicate listing, :ready_for_submission?
    end

    test "true for listing without a published tier" do
      listing = create(:sponsors_listing, :draft, :with_w8_or_w9_verified_stripe_account, :with_trade_screening_record)
      create(:sponsors_tier, :draft, sponsors_listing: listing)

      assert listing.full_description.present?
      assert_predicate listing, :draft?
      assert_predicate listing.active_stripe_connect_account, :verified_verification_status?
      assert_predicate listing, :ready_for_submission?
    end

    test "false for listing that is already pending approval" do
      listing = create(:sponsors_listing, :pending_approval, :with_w8_or_w9_verified_stripe_account,
        :with_tier)
      create(:sponsors_tier, :draft, sponsors_listing: listing)

      assert listing.full_description.present?
      assert_predicate listing, :pending_approval?
      assert_predicate listing.active_stripe_connect_account, :verified_verification_status?
      refute_predicate listing, :ready_for_submission?
    end

    test "false for listing that requires additional review" do
      listing = create(:sponsors_listing, :requires_additional_review, :with_stripe_account,
        :with_tier)
      create(:sponsors_tier, :draft, sponsors_listing: listing)

      assert listing.full_description.present?
      assert_predicate listing, :requires_additional_review?
      assert_predicate listing.active_stripe_connect_account, :verified_verification_status?
      refute_predicate listing, :ready_for_submission?
    end

    test "false for listing in queued_for_auto_approval state" do
      listing = create(:sponsors_listing, :queued_for_auto_approval, :with_stripe_account, :with_tier)
      create(:sponsors_tier, :draft, sponsors_listing: listing)

      assert listing.full_description.present?
      assert_predicate listing, :queued_for_auto_approval?
      assert_predicate listing.active_stripe_connect_account, :verified_verification_status?
      refute_predicate listing, :ready_for_submission?
    end
  end

  context "target_for_conditional_access" do
    test "tfca defers to sponsorable" do
      assert_equal @listing.sponsorable.target_for_conditional_access, @listing.target_for_conditional_access
      assert_equal @org_listing.sponsorable.target_for_conditional_access, @org_listing.target_for_conditional_access
    end

    test "async_tfca defers to sponsorable" do
      assert_equal @listing.sponsorable.target_for_conditional_access, @listing.async_target_for_conditional_access.sync
      assert_equal @org_listing.sponsorable.target_for_conditional_access, @org_listing.async_target_for_conditional_access.sync
    end
  end

  context "#short_description=" do
    test "syncs with featured description" do
      listing = build(:sponsors_listing)

      listing.short_description = "my funky short description"

      assert_equal "my funky short description", listing.short_description
      assert_equal "my funky short description", listing.featured_description
    end

    test "strips leading and trailing whitespace" do
      listing = build(:sponsors_listing)

      listing.short_description = "  my funky short description   "

      assert_equal "my funky short description", listing.short_description
      assert_equal "my funky short description", listing.featured_description
    end
  end

  context "#short_description_html" do
    test "returns an html version of short description" do
      listing = build(:sponsors_listing)

      listing.short_description = "my **funky** short description"

      assert_equal "<p>my <strong>funky</strong> short description</p>", listing.short_description_html
    end
  end

  context "#deletable?" do
    # https://github.com/github/sponsors/issues/4023
    test "true even when ledger entries exist, if the right confirmation is given" do
      ledger_entry = create(:payouts_ledger_entry, :transfer)
      listing_with_funding = ledger_entry.sponsors_listing
      listing_with_funding.deletion_confirmation = listing_with_funding.sponsorable_login

      assert_predicate listing_with_funding, :deletable?, "should be deletable once confirmation given"
    end

    # https://github.com/github/github/pull/258857#discussion_r1115815176
    test "true even when ledger entry, tier, and inactive sponsorship exists, if the right confirmation is given" do
      ledger_entry = create(:payouts_ledger_entry, :transfer)
      listing_with_funding = ledger_entry.sponsors_listing
      tier = create(:sponsors_tier, :published, sponsors_listing: listing_with_funding)
      sponsorship = create(:sponsorship, :inactive, tier: tier, sponsorable: listing_with_funding.sponsorable)
      assert_includes tier.subscription_items, sponsorship.reload.subscription_item
      listing_with_funding.deletion_confirmation = listing_with_funding.sponsorable_login

      result = listing_with_funding.deletable?

      assert result, "should be deletable once confirmation given; #{listing_with_funding.errors.full_messages}"
    end

    test "false when active subscription item exists for the listing's maintainer" do
      sub_item = create(:sponsors_subscription_item)
      listing = sub_item.sponsorable.sponsors_listing

      refute_predicate listing, :deletable?
      assert_includes listing.errors.full_messages,
        "Cannot delete Sponsors profile while it has active subscription items."
    end

    test "true when inactive subscription item exists for the listing's maintainer" do
      sub_item = create(:sponsors_subscription_item, :inactive)
      listing = sub_item.sponsorable.sponsors_listing

      assert_predicate listing, :deletable?
    end

    test "false for fiscal host's listing" do
      refute_predicate @fiscal_host_listing, :deletable?
      assert_includes @fiscal_host_listing.errors.full_messages,
        "Fiscal host listings can't be deleted (should be disabled)"
    end

    test "true for newly approved listing" do
      assert_predicate @approved_listing, :deletable?
    end

    test "repeated calls to #deletable? don't duplicate the errors" do
      sub_item = create(:sponsors_subscription_item)
      listing = sub_item.sponsorable.sponsors_listing

      listing.deletable?
      assert_same_elements ["Cannot delete Sponsors profile while it has active subscription items."],
        listing.errors.full_messages

      listing.deletable? # second call shouldn't duplicate existing error message
      assert_same_elements ["Cannot delete Sponsors profile while it has active subscription items."],
        listing.errors.full_messages
    end
  end

  context "hiding past sponsorships" do
    test "defaults to showing past sponsorships" do
      refute_predicate @approved_listing, :hide_past_sponsorships?
    end

    test "supports hiding past sponsorships" do
      @approved_listing.update_past_sponsorships_visibility!(hidden: true)

      assert_predicate @approved_listing, :hide_past_sponsorships?

      @approved_listing.update_past_sponsorships_visibility!(hidden: false)

      refute_predicate @approved_listing, :hide_past_sponsorships?
    end
  end

  context "email opt out settings" do
    test "returns SponsorsEmailOptOuts with default bitmask" do
      opt_outs = @approved_listing.email_opt_outs

      assert_equal opt_outs.bitmask, 0
      refute opt_outs.opted_out_of_all?
      refute opt_outs.opted_out_of_new_sponsorships?
      refute opt_outs.opted_out_of_cancelled_sponsorships?
      refute opt_outs.opted_out_of_upgrade_notices?
      refute opt_outs.opted_out_of_goal_completed?
      refute opt_outs.opted_out_of_milestone_reached?
      refute opt_outs.opted_out_of_reached_match_cap?
    end

    test "updates and persists email opt out settings" do
      refute @approved_listing.email_opt_outs.opted_out_of_cancelled_sponsorships?

      updated_opt_out_settings = SponsorsEmailOptOuts.new(bitmask: 0)
      updated_opt_out_settings.opt_out_of(:cancelled_sponsorships)
      @approved_listing.update_email_opt_outs(updated_opt_out_settings)

      assert @approved_listing.email_opt_outs.opted_out_of_cancelled_sponsorships?
    end
  end

  context "#flagged_sponsorable?" do
    test "false when user is neither spammy nor suspended" do
      sponsorable = @approved_listing.sponsorable
      refute_predicate sponsorable, :spammy?
      refute_predicate sponsorable, :suspended?

      refute_predicate @approved_listing, :flagged_sponsorable?
    end

    test "true when sponsorable is suspended" do
      sponsorable = @approved_listing.sponsorable
      sponsorable.suspend("Suspended!")
      assert_predicate sponsorable, :suspended?

      assert_predicate @approved_listing, :flagged_sponsorable?
    end

    test "true when sponsorable is spammy" do
      sponsorable = @approved_listing.sponsorable
      sponsorable.mark_as_spammy
      assert_predicate sponsorable, :spammy?

      assert_predicate @approved_listing, :flagged_sponsorable?
    end

    test "nil when missing sponsorable" do
      @approved_listing.sponsorable = nil

      assert_nil @approved_listing.flagged_sponsorable?
    end
  end

  context "#serialize_for_signgup" do
    test "serializes a waitlisted listing" do
      expected_serialization = {
        isWaitlisted: true,
        contactEmail: @waitlisted_listing.contact_email_address,
        countryOfResidence: @waitlisted_listing.country_of_residence,
        billingCountry: @waitlisted_listing.billing_country,
        usesFiscalHost: false,
        signupStatusPartialPath: "/sponsors/#{@waitlisted_listing.sponsorable_login}/signup_status",
      }
      assert_equal expected_serialization, @waitlisted_listing.serialize_for_signup
    end

    test "serializes an approved fiscally hosted listing" do
      @approved_listing.update!(parent_listing: @fiscal_host_listing)
      expected_serialization = {
        isWaitlisted: false,
        contactEmail: @approved_listing.contact_email_address,
        countryOfResidence: @approved_listing.country_of_residence,
        billingCountry: @approved_listing.billing_country,
        usesFiscalHost: true,
        signupStatusPartialPath: "/sponsors/#{@approved_listing.sponsorable_login}/signup_status",
      }
      assert_equal expected_serialization, @approved_listing.serialize_for_signup
    end
  end
end if GitHub.sponsors_enabled?
