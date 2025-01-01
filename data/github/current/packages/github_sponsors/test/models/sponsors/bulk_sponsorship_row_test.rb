# typed: true
# frozen_string_literal: true

require "test_helper"

class Sponsors::BulkSponsorshipRowTest < GitHub::TestCase
  fixtures do
    @approved_listing1 = create(:sponsors_listing, :approved_with_only_custom_amounts)
    @user_sponsorable = @approved_listing1.sponsorable
    @approved_listing2 = create(:sponsors_listing, :approved_with_only_custom_amounts, :for_org)
    @org_sponsorable = @approved_listing2.sponsorable
    @draft_listing = create(:sponsors_listing, :draft, tier_count: 0)
    @non_sponsorable_user = create(:credit_card_user, :verified,
      plan_subscription: create(:billing_plan_subscription))
  end

  context ".prefill_necessary_data" do
    test "correctly prefills data to prevent N+1 queries for various types of logins" do
      user_sponsorable2 = create(:user, :sponsorable)
      approved_listing3 = user_sponsorable2.sponsors_listing
      sponsorship = create(:sponsorship, :one_time, sponsorable: user_sponsorable2, sponsor: @non_sponsorable_user)
      assert_predicate sponsorship, :locked?, "need a locked sponsorship"

      login_with_exactly_matching_case = @approved_listing1.sponsorable_login
      # https://github.com/github/sponsors/issues/4332 and https://github.com/github/sponsors/issues/4253
      login_with_tier_and_funky_characters_and_casing = " @#{@approved_listing2.sponsorable_login.upcase} "
      lower_cost_tier = create(:sponsors_tier, :one_time, :published, sponsors_listing: @approved_listing2)
      login_for_non_sponsorable_user = " @#{@non_sponsorable_user.login.upcase} "
      login_that_doesnt_exist = "nobody"

      blocked_sponsorable = create(:user, :sponsorable)
      @non_sponsorable_user.block(blocked_sponsorable)
      blocked_by_sponsorable = create(:user, :sponsorable)
      blocked_by_sponsorable.block(@non_sponsorable_user)

      existing_recurring_sponsorship = create(:sponsorship, sponsorable: @user_sponsorable,
        sponsor: @non_sponsorable_user)

      rows = [
        new_row(
          sponsorable_login: login_with_exactly_matching_case,
          amount: 1,
          is_duplicate: false,
          sponsor: @non_sponsorable_user
        ),
        new_row(
          sponsorable_login: login_with_tier_and_funky_characters_and_casing,
          amount: lower_cost_tier.monthly_price_in_cents,
          is_duplicate: false,
          sponsor: @non_sponsorable_user
        ),
        new_row(
          sponsorable_login: login_for_non_sponsorable_user,
          amount: 1,
          is_duplicate: false,
          sponsor: @non_sponsorable_user
        ),
        new_row(
          sponsorable_login: login_that_doesnt_exist,
          amount: 1,
          is_duplicate: false,
          sponsor: @non_sponsorable_user
        ),
        new_row(
          sponsorable_login: approved_listing3.sponsorable_login,
          amount: 1,
          is_duplicate: false,
          sponsor: @non_sponsorable_user,
        ),
        new_row(
          sponsorable_login: blocked_sponsorable.login,
          amount: 1,
          is_duplicate: false,
          sponsor: @non_sponsorable_user,
        ),
        new_row(
          sponsorable_login: blocked_by_sponsorable.login,
          amount: 1,
          is_duplicate: false,
          sponsor: @non_sponsorable_user,
        ),
        new_row(
          sponsorable_login: existing_recurring_sponsorship.sponsorable_login,
          amount: 1,
          is_duplicate: false,
          sponsor: @non_sponsorable_user,
          recurring: true,
        )
      ]

      # 1 `sponsors_listings` query to get the SponsorsListing.
      # 2 `users` queries to get the SponsorsListing's Sponsorable, and to get non-sponsorable Users
      # 1 `sponsors_tiers` query to get the list of published SponsorsTiers at the exact or lower amount
      # 2 `sponsorships` queries: 1 to get locked sponsorships, 1 to get existing recurring sponsorships
      # 1 `ignored_users` query to get blocked relationships between sponsor and sponsorable
      assert_query_count_per_table({
        sponsors_listings: 1,
        users: 2,
        sponsors_tiers: 1,
        sponsorships: 2,
        ignored_users: 1,
      }) do
        Sponsors::BulkSponsorshipRow.prefill_necessary_data(rows)
      end

      assert_query_count(0) do
        # approved_sponsors_listing
        assert_equal @approved_listing1, rows[0].approved_sponsors_listing
        assert_equal @approved_listing2, rows[1].approved_sponsors_listing
        assert_nil rows[2].approved_sponsors_listing
        assert_nil rows[3].approved_sponsors_listing
        assert_equal approved_listing3, rows[4].approved_sponsors_listing
        assert_equal blocked_sponsorable.sponsors_listing, rows[5].approved_sponsors_listing
        assert_equal blocked_by_sponsorable.sponsors_listing, rows[6].approved_sponsors_listing
        assert_equal existing_recurring_sponsorship.sponsors_listing, rows[7].approved_sponsors_listing

        # sponsorable
        assert_equal @user_sponsorable, rows[0].sponsorable
        assert_equal @org_sponsorable, rows[1].sponsorable
        assert_nil rows[2].sponsorable
        assert_nil rows[3].sponsorable
        assert_equal user_sponsorable2, rows[4].sponsorable
        assert_equal blocked_sponsorable, rows[5].sponsorable
        assert_equal blocked_by_sponsorable, rows[6].sponsorable
        assert_equal existing_recurring_sponsorship.sponsorable, rows[7].sponsorable

        # exact_and_lower_price_tier
        assert_empty rows[0].exact_and_lower_price_tiers
        assert_equal [lower_cost_tier], rows[1].exact_and_lower_price_tiers
        assert_empty rows[2].exact_and_lower_price_tiers
        assert_empty rows[3].exact_and_lower_price_tiers
        assert_empty rows[4].exact_and_lower_price_tiers
        assert_empty rows[5].exact_and_lower_price_tiers
        assert_empty rows[6].exact_and_lower_price_tiers
        assert_empty rows[7].exact_and_lower_price_tiers

        # non_sponsorable_user_or_organization
        assert_nil rows[0].non_sponsorable_user_or_organization
        assert_nil rows[1].non_sponsorable_user_or_organization
        assert_equal @non_sponsorable_user, rows[2].non_sponsorable_user_or_organization
        assert_nil rows[3].non_sponsorable_user_or_organization
        assert_nil rows[4].non_sponsorable_user_or_organization
        assert_nil rows[5].non_sponsorable_user_or_organization
        assert_nil rows[6].non_sponsorable_user_or_organization
        assert_nil rows[7].non_sponsorable_user_or_organization

        # locked?
        refute_predicate rows[0], :locked_sponsorship?
        refute_predicate rows[1], :locked_sponsorship?
        refute_predicate rows[2], :locked_sponsorship?
        refute_predicate rows[3], :locked_sponsorship?
        assert_predicate rows[4], :locked_sponsorship?
        refute_predicate rows[5], :locked_sponsorship?
        refute_predicate rows[6], :locked_sponsorship?
        refute_predicate rows[7], :locked_sponsorship?

        # blocked?
        refute_predicate rows[0], :blocked?
        refute_predicate rows[1], :blocked?
        refute_predicate rows[2], :blocked?
        refute_predicate rows[3], :blocked?
        refute_predicate rows[4], :blocked?
        assert_predicate rows[5], :blocked?
        assert_predicate rows[6], :blocked?
        refute_predicate rows[7], :blocked?

        # conflicting recurring sponsorship
        refute_predicate rows[0], :conflicting_recurring_sponsorship?
        refute_predicate rows[1], :conflicting_recurring_sponsorship?
        refute_predicate rows[2], :conflicting_recurring_sponsorship?
        refute_predicate rows[3], :conflicting_recurring_sponsorship?
        refute_predicate rows[4], :conflicting_recurring_sponsorship?
        refute_predicate rows[5], :conflicting_recurring_sponsorship?
        refute_predicate rows[6], :conflicting_recurring_sponsorship?
        assert_predicate rows[7], :conflicting_recurring_sponsorship?
      end
    end
  end

  test "can be used as a key in a hash" do
    row1 = Sponsors::BulkSponsorshipRow.new(sponsorable_login: "foo", amount: "2", is_duplicate: false,
      sponsor: @non_sponsorable_user, recurring: false)
    row2 = Sponsors::BulkSponsorshipRow.new(sponsorable_login: "foo", amount: "2", is_duplicate: true,
      sponsor: @non_sponsorable_user, recurring: false)
    row3 = Sponsors::BulkSponsorshipRow.new(sponsorable_login: "bar", amount: "5", is_duplicate: false,
      sponsor: @non_sponsorable_user, recurring: false)
    row4 = Sponsors::BulkSponsorshipRow.new(sponsorable_login: "bar", amount: "10", is_duplicate: false,
      sponsor: @non_sponsorable_user, recurring: false)

    hash = { row1 => "a", row2 => "b", row3 => "c", row4 => "d" }

    assert_equal "a", hash[row1]
    assert_equal "b", hash[row2]
    assert_equal "c", hash[row3]
    assert_equal "d", hash[row4]
  end

  context ".build_rows_from_params" do
    test "returns an Array of BulkSponsorshipRow objects from Hash of logins and amounts" do
      amounts_by_sponsorable_login = [
        { sponsorable_login: @approved_listing1.sponsorable_login, amount: "5" },
        { sponsorable_login: "nobody", amount: "" },
      ]

      rows = Sponsors::BulkSponsorshipRow.build_rows_from_params(
        amounts_by_sponsorable_login_array: amounts_by_sponsorable_login,
        sponsor: @non_sponsorable_user,
        recurring: false,
      )

      assert_equal 2, rows.size
      first_row = T.must(rows.first)
      assert_equal @approved_listing1.sponsorable_login, first_row.sponsorable_login
      assert_equal Billing::Money.new(5_00), first_row.amount
      refute_predicate rows.first, :duplicate?
      refute_predicate rows.first, :recurring?

      assert_equal "nobody", rows.second.sponsorable_login
      assert_equal Billing::Money.zero, rows.second.amount
      refute_predicate rows.second, :duplicate?
      refute_predicate rows.second, :recurring?
    end

    test "limits number of rows to specified max" do
      Sponsors::BulkSponsorshipValidator.stub_const(:MAX_SPONSORABLES, 1) do
        amounts_by_sponsorable_login = [
          { sponsorable_login: @approved_listing1.sponsorable_login, amount: "5" },
          { sponsorable_login: "nobody", amount: "" },
        ]

        rows = Sponsors::BulkSponsorshipRow.build_rows_from_params(
          amounts_by_sponsorable_login_array: amounts_by_sponsorable_login,
          sponsor: @non_sponsorable_user,
          recurring: false,
        )

        assert_equal 1, rows.size
      end
    end

    test "returns true for #duplicate? when logins only differ by case" do
      maintainer1 = "maintainer1"
      maintainer2 = "MaiNtAiner1"

      amounts_by_sponsorable_login = [
        { sponsorable_login: maintainer1, amount: "5" },
        { sponsorable_login: maintainer2, amount: "" },
      ]

      rows = Sponsors::BulkSponsorshipRow.build_rows_from_params(
        amounts_by_sponsorable_login_array: amounts_by_sponsorable_login,
        sponsor: @non_sponsorable_user,
        recurring: false,
      )

      assert_equal 2, rows.size
      first_row = T.must(rows.first)
      assert_equal Sponsors::BulkSponsorshipRow.normalize_login(maintainer1), first_row.sponsorable_login
      assert_predicate rows.first, :duplicate?

      assert_equal Sponsors::BulkSponsorshipRow.normalize_login(maintainer2), rows.second.sponsorable_login
      assert_predicate rows.second, :duplicate?
    end

    test "returns true for is_duplicate when logins have different casing and whitespace" do
      maintainer1 = " maintainer1 "
      maintainer2 = "MaiNtAiner1"

      amounts_by_sponsorable_login = [
        { sponsorable_login: maintainer1, amount: "5" },
        { sponsorable_login: maintainer2, amount: "" },
      ]

      rows = Sponsors::BulkSponsorshipRow.build_rows_from_params(
        amounts_by_sponsorable_login_array: amounts_by_sponsorable_login,
        sponsor: @non_sponsorable_user,
        recurring: false,
      )

      assert_equal 2, rows.size
      first_row = T.must(rows.first)
      assert_equal Sponsors::BulkSponsorshipRow.normalize_login(maintainer1), first_row.sponsorable_login
      assert_predicate rows.first, :duplicate?

      assert_equal Sponsors::BulkSponsorshipRow.normalize_login(maintainer2), rows.second.sponsorable_login
      assert_predicate rows.second, :duplicate?
    end

    test "returns true for is_duplicate when logins have leading @ and whitespace" do
      maintainer1 = "@maintainer1 "
      maintainer2 = " MaiNtAiner1"

      amounts_by_sponsorable_login = [
        { sponsorable_login: maintainer1, amount: "5" },
        { sponsorable_login: maintainer2, amount: "" },
      ]

      rows = Sponsors::BulkSponsorshipRow.build_rows_from_params(
        amounts_by_sponsorable_login_array: amounts_by_sponsorable_login,
        sponsor: @non_sponsorable_user,
        recurring: false,
      )

      assert_equal 2, rows.size
      first_row = T.must(rows.first)
      assert_equal Sponsors::BulkSponsorshipRow.normalize_login(maintainer1), first_row.sponsorable_login
      assert_predicate rows.first, :duplicate?

      assert_equal Sponsors::BulkSponsorshipRow.normalize_login(maintainer2), rows.second.sponsorable_login
      assert_predicate rows.second, :duplicate?
    end

    test "returns true for is_duplicate when logins are exact duplicates" do
      maintainer1 = "@maintainer1"
      maintainer2 = "@maintainer1"

      amounts_by_sponsorable_login = [
        { sponsorable_login: maintainer1, amount: "5" },
        { sponsorable_login: maintainer2, amount: "10" }
      ]

      rows = Sponsors::BulkSponsorshipRow.build_rows_from_params(
        amounts_by_sponsorable_login_array: amounts_by_sponsorable_login,
        sponsor: @non_sponsorable_user,
        recurring: false,
      )

      assert_equal 2, rows.size
      first_row = T.must(rows.first)
      assert_equal Sponsors::BulkSponsorshipRow.normalize_login(maintainer1), first_row.sponsorable_login
      assert_predicate rows.first, :duplicate?

      assert_equal Sponsors::BulkSponsorshipRow.normalize_login(maintainer2), rows.second.sponsorable_login
      assert_predicate rows.second, :duplicate?
    end

    test "returns false for is_duplicate when logins are not duplicates" do
      maintainer1 = "maintainer1"
      maintainer2 = "maintainer2"

      amounts_by_sponsorable_login = [
        { sponsorable_login: maintainer1, amount: "5" },
        { sponsorable_login: maintainer2, amount: "" },
      ]

      rows = Sponsors::BulkSponsorshipRow.build_rows_from_params(
        amounts_by_sponsorable_login_array: amounts_by_sponsorable_login,
        sponsor: @non_sponsorable_user,
        recurring: false,
      )

      assert_equal 2, rows.size
      first_row = T.must(rows.first)
      assert_equal Sponsors::BulkSponsorshipRow.normalize_login(maintainer1), first_row.sponsorable_login
      refute_predicate rows.first, :duplicate?

      assert_equal Sponsors::BulkSponsorshipRow.normalize_login(maintainer2), rows.second.sponsorable_login
      refute_predicate rows.second, :duplicate?
    end
  end

  context ".form_data_for" do
    test "returns hash of data for valid bulk sponsorships" do
      rows = [
        new_row(
          sponsorable_login: @approved_listing1.sponsorable_login,
          amount: "5",
          is_duplicate: false,
          sponsor: @non_sponsorable_user
        ),
        new_row(
          sponsorable_login: @approved_listing2.sponsorable_login,
          amount: "200",
          is_duplicate: false,
          sponsor: @non_sponsorable_user
        ),
        new_row(
          sponsorable_login: @draft_listing.sponsorable_login,
          amount: "5",
          is_duplicate: false,
          sponsor: @non_sponsorable_user
        ),
        new_row(
          sponsorable_login: "nobody",
          amount: "5",
          is_duplicate: false,
          sponsor: @non_sponsorable_user
        ),
      ]

      result = Sponsors::BulkSponsorshipRow.form_data_for(rows)

      assert_equal({
        @approved_listing1.sponsorable_login => { amount: 5, amount_with_fee: 5 },
        @approved_listing2.sponsorable_login => { amount: 200, amount_with_fee: 200 },
      }, result[:bulk_sponsorship])
      assert_same_elements [@approved_listing1.sponsorable_login, @approved_listing2.sponsorable_login],
        result[:sponsorables]
    end

    test "includes fees for cc org sponsor" do
      cc_org = create(:credit_card_org)

      rows = [
        new_row(
          sponsorable_login: @approved_listing1.sponsorable_login,
          amount: "5",
          is_duplicate: false,
          sponsor: cc_org
        ),
        new_row(
          sponsorable_login: @approved_listing2.sponsorable_login,
          amount: "200",
          is_duplicate: false,
          sponsor: cc_org
        ),
        new_row(
          sponsorable_login: @draft_listing.sponsorable_login,
          amount: "5",
          is_duplicate: false,
          sponsor: cc_org
        ),
        new_row(
          sponsorable_login: "nobody",
          amount: "5",
          is_duplicate: false,
          sponsor: cc_org
        ),
      ]

      result = Sponsors::BulkSponsorshipRow.form_data_for(rows)
      assert_equal({
        @approved_listing1.sponsorable_login => { amount: 5, amount_with_fee: 5.3 },
        @approved_listing2.sponsorable_login => { amount: 200, amount_with_fee: 212 },
      }, result[:bulk_sponsorship])
      assert_same_elements [@approved_listing1.sponsorable_login, @approved_listing2.sponsorable_login],
        result[:sponsorables]
    end
  end

  context "#approved_sponsors_listing" do
    test "returns nil if the SponsorsListing associated with the login is not approved" do
      row = new_row(
        sponsorable_login: @draft_listing.sponsorable_login,
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert_nil row.approved_sponsors_listing
    end

    test "returns the SponsorsListing if it is approved" do
      row = new_row(
        sponsorable_login: @approved_listing1.sponsorable_login,
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert_equal @approved_listing1, row.approved_sponsors_listing
    end

    test "returns the SponsorsListing even when login has extra spaces, leading '@', and different case" do
      row = new_row(
        sponsorable_login: " @#{@approved_listing1.sponsorable_login} ",
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert_equal @approved_listing1, row.approved_sponsors_listing
    end

    test "returns the SponsorsListing when provided login has different case" do
      original_login = @approved_listing1.sponsorable_login
      upcased_login = original_login.upcase
      refute_equal original_login, upcased_login

      row = new_row(
        sponsorable_login: upcased_login,
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )

      assert_equal @approved_listing1, row.approved_sponsors_listing
    end

    test "returns nil if the SponsorsListing has a deleted Sponsorable" do
      sponsorable_login_that_was_deleted = @approved_listing1.sponsorable_login
      @approved_listing1.sponsorable.delete
      listing_without_sponsorable = @approved_listing1

      row = new_row(
        sponsorable_login: sponsorable_login_that_was_deleted,
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )

      assert_nil row.approved_sponsors_listing
    end
  end

  context "#lower_published_tier_amounts" do
    test "returns empty list when maintainer has no published one-time tiers" do
      non_published_tier = create(:sponsors_tier, :one_time, sponsors_listing: @approved_listing1)
      recurring_tier = create(:sponsors_tier, :published, sponsors_listing: @approved_listing1)

      row = new_row(
        sponsorable_login: @approved_listing1.sponsorable_login,
        amount: "50",
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )

      assert_equal [], row.lower_published_tier_amounts
    end

    test "returns empty list when maintainer's published one-time tiers exceed given amount" do
      tier = create(:sponsors_tier, :one_time, sponsors_listing: @approved_listing1)
      amount = tier.monthly_price_in_cents.to_i

      row = new_row(
        sponsorable_login: tier.sponsorable_login,
        amount: (amount - 1).to_s,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )

      assert_equal [], row.lower_published_tier_amounts
    end

    test "returns ordered list of maintainer's published one-time tier amounts as dollars when they are less than given amount" do
      listing = @approved_listing1
      create(:sponsors_tier, :one_time, :published, sponsors_listing: listing, monthly_price_in_cents: 10_00)
      create(:sponsors_tier, :one_time, :published, sponsors_listing: listing, monthly_price_in_cents: 15_00)
      create(:sponsors_tier, :one_time, :published, sponsors_listing: listing, monthly_price_in_cents: 12_00)
      create(:sponsors_tier, :one_time, :published, sponsors_listing: listing, monthly_price_in_cents: 50_00)

      row = new_row(
        sponsorable_login: listing.sponsorable_login,
        amount: "50",
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )

      assert_equal [15, 12, 10], row.lower_published_tier_amounts
    end

    # https://github.com/github/sponsors/issues/4383
    test "returns empty list when amount is nil" do
      tier = create(:sponsors_tier, :one_time, sponsors_listing: @approved_listing1)
      amount = tier.monthly_price_in_cents.to_i

      row = new_row(
        sponsorable_login: tier.sponsorable_login,
        amount: nil,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )

      assert_equal [], row.lower_published_tier_amounts
    end
  end

  context "#published_tier" do
    test "returns the published one-time tier of the matching amount for that maintainer" do
      tier = create(:sponsors_tier, :one_time, :approved_sponsors_listing)
      amount = tier.monthly_price_in_dollars.to_i

      row = new_row(
        sponsorable_login: tier.sponsorable_login,
        amount: amount.to_s,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )

      assert_equal tier, row.published_tier
    end

    test "prefers the tier with the exact amount when it and a lesser-value tier exists" do
      lesser_value_tier = create(:sponsors_tier, :one_time, :approved_sponsors_listing)
      exact_match_tier = create(:sponsors_tier, :one_time, :published,
        sponsors_listing: lesser_value_tier.sponsors_listing,
        monthly_price_in_cents: lesser_value_tier.monthly_price_in_cents + 1_00)
      amount = exact_match_tier.monthly_price_in_dollars.to_i

      row = new_row(
        sponsorable_login: lesser_value_tier.sponsorable_login,
        amount: amount.to_s,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )

      assert_equal exact_match_tier, row.published_tier
    end

    test "returns the published one-time tier of lesser value for that maintainer when the custom amount minimum precludes creating a new custom tier" do
      listing = create(:sponsors_listing, :approved_with_only_custom_amounts, min_custom_tier_amount_in_cents: 50_00)
      tier = create(:sponsors_tier, :one_time, :published, monthly_price_in_cents: 3_00, sponsors_listing: listing)

      row = new_row(
        sponsorable_login: tier.sponsorable_login,
        amount: "4",
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )

      assert_equal tier, row.published_tier
    end

    test "returns nil when a lesser-value tier exists but the maintainer also allows custom one-time amounts" do
      listing = create(:sponsors_listing, :approved_with_only_custom_amounts)
      lesser_value_tier = create(:sponsors_tier, :one_time, :published, sponsors_listing: listing)
      amount = lesser_value_tier.monthly_price_in_dollars.to_i + 1

      row = new_row(
        sponsorable_login: listing.sponsorable_login,
        amount: amount.to_s,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )

      assert_nil row.published_tier
    end

    test "returns nil the only equal-or-lesser-value tiers are recurring for specified maintainer" do
      tier1 = create(:sponsors_tier, :approved_sponsors_listing, monthly_price_in_cents: 5_00)
      tier2 = create(:sponsors_tier, :published, monthly_price_in_cents: 4_00,
        sponsors_listing: tier1.sponsors_listing)

      row = new_row(
        sponsorable_login: tier1.sponsorable_login,
        amount: "6",
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )

      assert_nil row.published_tier
    end

    test "returns nil when no exact or lesser-value tier exists" do
      tier = create(:sponsors_tier, :one_time, :approved_sponsors_listing, monthly_price_in_cents: 5_00)
      row = new_row(
        sponsorable_login: tier.sponsorable_login,
        amount: "4",
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert_nil row.published_tier
    end

    test "returns nil when the maintainer only has custom amounts and no valid published one-time tier" do
      listing = create(:sponsors_listing, :approved_with_only_custom_amounts)
      row = new_row(
        sponsorable_login: listing.sponsorable_login,
        amount: "5",
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert_nil row.published_tier
    end

    test "returns nil when published one-time tiers all exceed specified amount" do
      tier1 = create(:sponsors_tier, :one_time, :approved_sponsors_listing, monthly_price_in_cents: 5_00)
      tier2 = create(:sponsors_tier, :one_time, :published, monthly_price_in_cents: 6_00,
        sponsors_listing: tier1.sponsors_listing)

      row = new_row(
        sponsorable_login: tier1.sponsorable_login,
        amount: "4",
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )

      assert_nil row.published_tier
    end
  end

  context "#parent_tier_for_custom_tier" do
    test "returns the closest lesser-or-equal-value tier for a maintainer" do
      listing = create(:sponsors_listing, :approved_with_only_custom_amounts)
      parent_tier = create(:sponsors_tier, :published, :one_time, sponsors_listing: listing,
        monthly_price_in_cents: 4_00)
      row = new_row(
        sponsorable_login: listing.sponsorable_login,
        amount: "5",
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert_equal parent_tier, row.parent_tier_for_custom_tier
    end

    test "returns nil when a custom tier would be necessary but the maintainer requires an amount greater than the specified amount" do
      listing = create(:sponsors_listing, :approved_with_only_custom_amounts, min_custom_tier_amount_in_cents: 50_00)
      published_tier = create(:sponsors_tier, :published, :one_time, sponsors_listing: listing,
        monthly_price_in_cents: 6_00) # exceeds requested price so shouldn't be returned
      row = new_row(
        sponsorable_login: listing.sponsorable_login,
        amount: "5",
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert_nil row.parent_tier_for_custom_tier
    end

    test "returns nil when the maintainer has no published one-time tiers" do
      listing = create(:sponsors_listing, :approved, tier_count: 1, one_time_tier_count: 0)
      row = new_row(
        sponsorable_login: listing.sponsorable_login,
        amount: "5",
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert_nil row.parent_tier_for_custom_tier
    end

    test "returns nil when the maintainer has a published one-time tier that is the exact amount" do
      listing = create(:sponsors_listing, :approved_with_only_custom_amounts)
      tier = create(:sponsors_tier, :one_time, :published, sponsors_listing: listing)
      amount = tier.monthly_price_in_dollars.to_i
      row = new_row(
        sponsorable_login: listing.sponsorable_login,
        amount: amount.to_s,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert_nil row.parent_tier_for_custom_tier,
        "should have returned nil because no custom tier will need to be created, so no parent tier is necessary"
    end
  end

  context "#has_correctable_error?" do
    test "returns true when there's no error for the maintainer" do
      row = new_row(
        sponsorable_login: @approved_listing1.sponsorable_login,
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert row.has_correctable_error?
    end

    test "returns true when that maintainer can't be sponsored at the requested amount" do
      listing = create(:sponsors_listing, :approved_with_only_custom_amounts, min_custom_tier_amount_in_cents: 50_00)
      row = new_row(
        sponsorable_login: @approved_listing1.sponsorable_login,
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert row.has_correctable_error?
    end

    test "returns true when amount is negative" do
      row = new_row(
        sponsorable_login: @approved_listing1.sponsorable_login,
        amount: -1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert row.has_correctable_error?
    end

    test "returns true when amount is zero" do
      row = new_row(
        sponsorable_login: @approved_listing1.sponsorable_login,
        amount: 0,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert row.has_correctable_error?
    end

    test "returns true when amount is higher than the limit" do
      amount = SponsorsTier::MAX_SPONSORSHIP_AMOUNT_IN_DOLLARS + 1
      row = new_row(
        sponsorable_login: @approved_listing1.sponsorable_login,
        amount: 0,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert row.has_correctable_error?
    end

    test "returns true when amount is not a number" do
      row = new_row(
        sponsorable_login: @approved_listing1.sponsorable_login,
        amount: "not a number",
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert row.has_correctable_error?
    end

    test "returns false when nonexistent username is given" do
      row = new_row(
        sponsorable_login: "nobody",
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      refute row.has_correctable_error?
    end

    test "returns false when empty string username is given" do
      row = new_row(
        sponsorable_login: "",
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      refute row.has_correctable_error?
    end

    test "returns false when nil username is given" do
      row = new_row(
        sponsorable_login: nil,
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      refute row.has_correctable_error?
    end

    test "returns false when maintainer does not have a Sponsors listing" do
      row = new_row(
        sponsorable_login: @non_sponsorable_user.login,
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      refute row.has_correctable_error?
    end

    test "returns false when maintainer does not have an approved Sponsors listing" do
      row = new_row(
        sponsorable_login: @draft_listing.sponsorable_login,
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      refute_predicate row, :has_correctable_error?
    end

    test "returns false when maintainer is duplicated" do
      listing = create(:sponsors_listing, :approved_with_only_custom_amounts, min_custom_tier_amount_in_cents: 50_00)
      row = new_row(
        sponsorable_login: @approved_listing1.sponsorable_login,
        amount: 1,
        is_duplicate: true,
        sponsor: @non_sponsorable_user
      )
      refute_predicate row, :has_correctable_error?
    end

    test "returns false when maintainer and sponsor login are the same" do
      listing = create(:sponsors_listing, :approved_with_only_custom_amounts, min_custom_tier_amount_in_cents: 50_00)
      row = new_row(
        sponsorable_login: @approved_listing1.sponsorable_login,
        amount: 1,
        is_duplicate: true,
        sponsor: @approved_listing1.sponsorable
      )
      refute_predicate row, :has_correctable_error?
    end

    test "returns false when sponsor has a locked sponsorship to maintainer" do
      sponsor = create(:credit_card_user, :verified, plan_subscription: create(:billing_plan_subscription),
        plan: GitHub::Plan.free_with_addons)
      sponsorship = create(:sponsorship, :one_time, sponsorable: @approved_listing1.sponsorable, sponsor: sponsor)
      assert_predicate sponsorship, :locked?, "need a locked sponsorship"

      row = new_row(
        sponsorable_login: @approved_listing1.sponsorable_login,
        amount: 1,
        is_duplicate: false,
        sponsor: sponsor
      )

      refute_predicate row, :has_correctable_error?
    end

    test "returns false when sponsor has an active recurring sponsorship for the maintainer and the row is for a recurring sponsorship" do
      sponsorship = create(:sponsorship, sponsorable: @user_sponsorable)

      row = new_row(
        sponsorable_login: @user_sponsorable.login,
        amount: 1,
        is_duplicate: false,
        sponsor: sponsorship.sponsor,
        recurring: true,
      )

      refute_predicate row, :has_correctable_error?
    end
  end

  context "#user_or_organization" do
    test "returns the user with the specified login, case-insensitive, when Sponsors listing does not exist" do
      user = create(:user, login: "IHaveCapsInMyName")
      row = new_row(
        sponsorable_login: "ihavecapsinmyname",
        amount: 5,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert_equal user, row.user_or_organization
    end

    test "returns the user with the specified login, case-insensitive, when Sponsors listing does exist" do
      user = create(:user, :sponsorable, login: "IHaveCapsInMyName")
      row = new_row(
        sponsorable_login: "ihavecapsinmyname",
        amount: 5,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert_equal user, row.user_or_organization
    end

    test "returns nil if no user or organization exists with the login" do
      row = new_row(
        sponsorable_login: "nobody",
        amount: 5,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert_nil row.user_or_organization
    end
  end

  context "#exact_and_lower_price_tiers" do
    test "returns the published, one-time tiers that are the same price or less - order with highest price first" do
      lowest_price_tier = create(:sponsors_tier, :published, :one_time, monthly_price_in_cents: 2_00,
        sponsors_listing: @approved_listing1)
      middle_price_tier = create(:sponsors_tier, :published, :one_time, monthly_price_in_cents: 3_00,
        sponsors_listing: @approved_listing1)
      exact_match_tier = create(:sponsors_tier, :published, :one_time, monthly_price_in_cents: 4_00,
        sponsors_listing: @approved_listing1)
      # Should not be returned because it is too expensive
      create(:sponsors_tier, :published, :one_time, monthly_price_in_cents: 5_00,
        sponsors_listing: @approved_listing1)
      # Should not be returned because it's the wrong frequency:
      create(:sponsors_tier, :published, monthly_price_in_cents: 4_00,
        sponsors_listing: @approved_listing1)

      row = new_row(
        sponsorable_login: @approved_listing1.sponsorable_login,
        amount: exact_match_tier.monthly_price_in_dollars.to_i,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )

      assert_equal [exact_match_tier, middle_price_tier, lowest_price_tier], row.exact_and_lower_price_tiers
    end

    test "returns the published, recurring tiers that are the same price or less - order with highest price first" do
      lowest_price_tier = create(:sponsors_tier, :published, monthly_price_in_cents: 2_00,
        sponsors_listing: @approved_listing1)
      middle_price_tier = create(:sponsors_tier, :published, monthly_price_in_cents: 3_00,
        sponsors_listing: @approved_listing1)
      exact_match_tier = create(:sponsors_tier, :published, monthly_price_in_cents: 4_00,
        sponsors_listing: @approved_listing1)
      # Should not be returned because it is too expensive
      create(:sponsors_tier, :published, monthly_price_in_cents: 5_00,
        sponsors_listing: @approved_listing1)
      # Should not be returned because it's the wrong frequency:
      create(:sponsors_tier, :published, :one_time, monthly_price_in_cents: 4_00,
        sponsors_listing: @approved_listing1)

      row = new_row(
        sponsorable_login: @approved_listing1.sponsorable_login,
        amount: exact_match_tier.monthly_price_in_dollars.to_i,
        is_duplicate: false,
        sponsor: @non_sponsorable_user,
        recurring: true,
      )

      assert_equal [exact_match_tier, middle_price_tier, lowest_price_tier], row.exact_and_lower_price_tiers
    end

    test "is empty if there are no published one-time tiers at or below the desired amount" do
      # Should not be returned because it is recurring
      create(:sponsors_tier,
        :published,
        frequency: :recurring,
        monthly_price_in_cents: 2_00,
        sponsors_listing: @approved_listing1
      )
      # Should not be returned because it is not published
      create(:sponsors_tier,
        :draft,
        :one_time,
        monthly_price_in_cents: 2_00,
        sponsors_listing: @approved_listing1
      )
      # Should not be returned because the price is too high
      create(:sponsors_tier,
        :published,
        :one_time,
        monthly_price_in_cents: 4_00,
        sponsors_listing: @approved_listing1
      )
      # # Should not be returned because it is for a different listing
      create(:sponsors_tier,
        :published,
        :one_time,
        monthly_price_in_cents: 2_00,
        sponsors_listing: @approved_listing2
      )

      row = new_row(
        sponsorable_login: @approved_listing1.sponsorable_login,
        amount: 3,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )

      assert_empty row.exact_and_lower_price_tiers
    end

    test "is empty if there are no tiers for the given sponsorable login" do
      row = new_row(
        sponsorable_login: @approved_listing1.sponsorable_login,
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert_empty row.exact_and_lower_price_tiers
    end

    test "is empty when there is no sponsors listing for the given login" do
      row = new_row(
        sponsorable_login: @non_sponsorable_user.login,
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert_empty row.exact_and_lower_price_tiers
    end
  end

  context "error handling" do
    test "invalid when listing belongs to the sponsor" do
      row = new_row(
        sponsorable_login: @approved_listing1.sponsorable_login,
        amount: 1,
        is_duplicate: false,
        sponsor: @approved_listing1.sponsorable,
      )
      assert_equal "You cannot sponsor yourself", row.error_message
      refute_predicate row, :valid?
    end

    test "invalid when listing belongs to the sponsor and login is written differently" do
      sponsorable_login = @approved_listing1.sponsorable_login.upcase

      row = new_row(
        sponsorable_login: sponsorable_login,
        amount: 1,
        is_duplicate: false,
        sponsor: @approved_listing1.sponsorable,
      )
      assert_equal "You cannot sponsor yourself", row.error_message
      refute_predicate row, :valid?
    end

    test "invalid when listing is not approved" do
      row = new_row(
        sponsorable_login: @draft_listing.sponsorable_login,
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert_equal "Cannot be sponsored", row.error_message
      refute_predicate row, :valid?
    end

    test "invalid when login has no associated listing" do
      row = new_row(
        sponsorable_login: "nobody",
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert_equal "Cannot be sponsored", row.error_message
      refute_predicate row, :valid?
    end

    test "invalid when amount is non-positive" do
      row = new_row(
        sponsorable_login: @approved_listing1.sponsorable_login,
        amount: 0,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert_equal "Custom amount must be at least $1", row.error_message
      refute_predicate row, :valid?
    end

    test "invalid when amount is positive, but below specified limit" do
      @approved_listing1.update!(min_custom_tier_amount_in_cents: 2_00)
      row = new_row(
        sponsorable_login: @approved_listing1.sponsorable_login,
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert_equal "Custom amount must be at least $2", row.error_message
      refute_predicate row, :valid?
    end

    test "invalid when amount is below lowest published tier and below minimum amount" do
      @approved_listing1.update!(min_custom_tier_amount_in_cents: 2_00)
      higher_tier = create(
        :sponsors_tier,
        :published,
        :one_time,
        monthly_price_in_cents: 3_00,
        sponsors_listing: @approved_listing1
      )

      row = new_row(
        sponsorable_login: @approved_listing1.sponsorable_login,
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )

      assert_equal "Custom amount must be at least $2", row.error_message
      refute_predicate row, :valid?
    end

    test "invalid when amount is higher than sponsorship limit" do
      amount = SponsorsTier::MAX_SPONSORSHIP_AMOUNT_IN_DOLLARS + 1
      limit = SponsorsTier::MAX_SPONSORSHIP_AMOUNT_HUMAN
      row = new_row(
        sponsorable_login: @approved_listing1.sponsorable_login,
        amount: amount,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert_equal "Custom amount must be at most #{limit}", row.error_message
      refute_predicate row, :valid?
    end

    test "valid when amount is valid and sponsors listing is approved" do
      row = new_row(
        sponsorable_login: @approved_listing1.sponsorable_login,
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert_nil row.error_message
      assert_predicate row, :valid?
    end

    test "valid when no tiers match and the maintainer's min custom amount exceeds sponsor-specified amount" do
      row = new_row(
        sponsorable_login: @approved_listing1.sponsorable_login,
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert_nil row.error_message
      assert_predicate row, :valid?
    end

    test "invalid when sponsorship is locked" do
      sponsorship = create(:sponsorship, :one_time, sponsorable: @user_sponsorable, sponsor: @non_sponsorable_user)
      assert_predicate sponsorship, :locked?, "need a locked sponsorship"

      row = new_row(
        sponsorable_login: @approved_listing1.sponsorable_login,
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user,
      )
      assert_equal "A sponsorship is being processed from you to this maintainer", row.error_message
      refute_predicate row, :valid?
    end

    test "invalid when the sponsorable has blocked the sponsor" do
      @user_sponsorable.block(@non_sponsorable_user)

      row = new_row(
        sponsorable_login: @user_sponsorable.login,
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user,
      )
      assert_equal "Cannot be sponsored", row.error_message
      refute_predicate row, :valid?
    end

    test "invalid when the sponsor has blocked the sponsorable" do
      @non_sponsorable_user.block(@user_sponsorable)

      row = new_row(
        sponsorable_login: @user_sponsorable.login,
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user,
      )
      assert_equal "Cannot be sponsored", row.error_message
      refute_predicate row, :valid?
    end

    test "invalid when no sponsorable login is given" do
      row = new_row(
        sponsorable_login: "",
        amount: 1,
        is_duplicate: false,
        sponsor: @approved_listing1.sponsorable,
      )
      assert_equal "No maintainer username given", row.error_message
      refute_predicate row, :valid?
      assert_predicate row, :login_missing?
    end

    test "valid when one-time and there is an active recurring sponsorship from sponsor to maintainer" do
      create(:sponsorship, sponsor: @non_sponsorable_user, sponsorable: @user_sponsorable)
      row = new_row(
        sponsorable_login: @user_sponsorable.login,
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user,
        recurring: false,
      )
      assert_nil row.error_message
      assert_predicate row, :valid?
      refute_predicate row, :conflicting_recurring_sponsorship?
    end

    test "valid when recurring and there is an active, unlocked, one-time sponsorship from sponsor to maintainer" do
      create(:sponsorship, :one_time, :unlocked, sponsor: @non_sponsorable_user, sponsorable: @user_sponsorable)
      row = new_row(
        sponsorable_login: @user_sponsorable.login,
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user,
        recurring: true,
      )
      assert_predicate row, :valid?
      refute_predicate row, :conflicting_recurring_sponsorship?
    end

    test "valid when recurring and there is an inactive recurring sponsorship from sponsor to maintainer" do
      create(:sponsorship, :inactive, sponsor: @non_sponsorable_user, sponsorable: @user_sponsorable)
      row = new_row(
        sponsorable_login: @user_sponsorable.login,
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user,
        recurring: true,
      )
      assert_nil row.error_message
      assert_predicate row, :valid?
      refute_predicate row, :conflicting_recurring_sponsorship?
    end

    test "invalid when recurring and there is already an active recurring sponsorship from user sponsor to maintainer" do
      create(:sponsorship, sponsor: @non_sponsorable_user, sponsorable: @user_sponsorable)
      row = new_row(
        sponsorable_login: @user_sponsorable.login,
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user,
        recurring: true,
      )
      refute_predicate row, :valid?
      assert_predicate row, :conflicting_recurring_sponsorship?
      assert_equal "You are already sponsoring this maintainer", row.error_message
    end

    test "invalid when recurring and there is already an active recurring sponsorship from org sponsor to maintainer" do
      org = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription))
      create(:sponsorship, sponsor: org, sponsorable: @user_sponsorable)
      row = new_row(
        sponsorable_login: @user_sponsorable.login,
        amount: 1,
        is_duplicate: false,
        sponsor: org,
        recurring: true,
      )
      refute_predicate row, :valid?
      assert_predicate row, :conflicting_recurring_sponsorship?
      assert_equal "@#{org} is already sponsoring this maintainer", row.error_message
    end
  end

  context "#sponsorable_login" do
    test "returns normalized with spaces and @ removed" do
      row = new_row(
        sponsorable_login: " @Foo ",
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert_equal "Foo", row.sponsorable_login
    end

    test "returns empty string when login is missing" do
      row = new_row(
        sponsorable_login: nil,
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert_equal "", row.sponsorable_login
    end
  end

  context "#amount" do
    test "returns given amount as Billing::Money" do
      row = new_row(
        sponsorable_login: "unused",
        amount: "$1",
        is_duplicate: false,
        sponsor: @non_sponsorable_user,
      )
      assert_equal Billing::Money.new(1_00), row.amount
    end

    test "returns amount as-is if already Billing::Money" do
      row = new_row(
        sponsorable_login: "unused",
        amount: Billing::Money.new(1_00),
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert_equal Billing::Money.new(1_00), row.amount
    end
  end

  context "#dollars" do
    test "returns amount in dollars as an Integer" do
      row = new_row(
        sponsorable_login: "unused",
        amount: "$1",
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert_equal 1, row.dollars
    end
  end

  context "#for_organization?" do
    test "returns false for user sponsorable" do
      row = new_row(
        sponsorable_login: @user_sponsorable.login,
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      refute_predicate row, :for_organization?
    end

    test "returns true for org sponsorable" do
      row = new_row(
        sponsorable_login: @org_sponsorable.login,
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert_predicate row, :for_organization?
    end
  end

  context "#for_user?" do
    test "returns true for user" do
      row = new_row(
        sponsorable_login: @user_sponsorable.login,
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert_predicate row, :for_user?
    end

    test "returns false for org sponsorable" do
      row = new_row(
        sponsorable_login: @org_sponsorable.login,
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      refute_predicate row, :for_user?
    end
  end

  context "#non_sponsorable?" do
    test "returns true when sponsorable is nil" do
      row = new_row(
        sponsorable_login: "@no_user_exists",
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert_predicate row, :non_sponsorable?
    end

    test "returns true when sponsors_listing is nil" do
      user_without_listing = create(:user)
      row = new_row(
        sponsorable_login: user_without_listing.login,
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert_predicate row, :non_sponsorable?
    end

    test "returns true when sponsor is blocked" do
      blocked_by_sponsorable = create(:user, :sponsorable)
      blocked_by_sponsorable.block(@non_sponsorable_user)
      row = new_row(
        sponsorable_login: blocked_by_sponsorable.login,
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      assert_predicate row, :non_sponsorable?
    end

    test "returns false when sponsorable_login is missing" do
      row = new_row(
        sponsorable_login: nil,
        amount: 1,
        is_duplicate: false,
        sponsor: @non_sponsorable_user
      )
      refute_predicate row, :non_sponsorable?
    end
  end

  def new_row(sponsorable_login:, amount:, is_duplicate:, sponsor:, recurring: false)
    Sponsors::BulkSponsorshipRow.new(sponsorable_login:, amount:, is_duplicate:, sponsor:, recurring: recurring)
  end
end
