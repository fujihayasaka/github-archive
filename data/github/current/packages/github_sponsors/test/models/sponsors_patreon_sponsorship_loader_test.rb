# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsPatreonSponsorshipLoaderTest < GitHub::TestCase
  fixtures do
    @sponsorable = create(:user, :verified)
    @listing = create(:sponsors_listing, :approved, sponsorable: @sponsorable, tier_count: 0)
    @spu = create(:sponsors_patreon_user, :with_tier, user: @sponsorable)
  end

  if GitHub.sponsors_enabled?
    test "returns result for user with a Patreon membership" do
      sponsor_spu = create(:sponsors_patreon_user, :sponsor, patreon_user_id: "31189703") # patron ID in cassette

      data = VCR.use_cassette("patreon/get_campaigns_and_memberships") do
        SponsorsPatreonSponsorshipLoader.call(sponsors_patreon_user: @spu)
      end

      assert_equal({ sponsor_spu.user_id => 100 }, data.target_sponsorship_cents_by_sponsor_id)
      assert_empty data.membership_next_page_cursors_by_campaign_id
      assert_empty data.sponsorships_to_cancel
      assert_empty data.sponsorships_to_update
    end

    # https://github.com/github/sponsors/issues/5612
    test "does not include patron whose Patreon pledge does not meet the maintainer's GitHub Sponsors minimum amount" do
      sponsor_spu = create(:sponsors_patreon_user, :sponsor, patreon_user_id: "31189703") # patron has $1.00 pledge
      @listing.update!(min_custom_tier_amount_in_cents: 2_00)

      data = VCR.use_cassette("patreon/get_campaigns_and_memberships") do
        SponsorsPatreonSponsorshipLoader.call(sponsors_patreon_user: @spu)
      end

      assert_empty data.target_sponsorship_cents_by_sponsor_id, "should not include $1 patron"
      assert_empty data.membership_next_page_cursors_by_campaign_id
      assert_empty data.sponsorships_to_cancel
      assert_empty data.sponsorships_to_update
    end

    # https://github.com/github/sponsors/issues/5612
    test "does not include patron whose Patreon pledge is less than the global minimum amount" do
      below_limit, at_limit = create_pair(:sponsors_patreon_user, :sponsor)

      SponsorsPatreonSponsorshipLoader.any_instance
        .expects(:active_membership_cents_for_campaigns_by_sponsor_patreon_user_id).at_least_once
        .returns(
          {
            below_limit.patreon_user_id => SponsorsTier::MIN_PRICE_IN_CENTS - 1,
            at_limit.patreon_user_id => SponsorsTier::MIN_PRICE_IN_CENTS,
          },
        )
      data = SponsorsPatreonSponsorshipLoader.call(sponsors_patreon_user: @spu)

      expected_target_sponsorship_cents_by_sponsor_id = {
        at_limit.user_id => SponsorsTier::MIN_PRICE_IN_CENTS,
      }

      assert_equal expected_target_sponsorship_cents_by_sponsor_id, data.target_sponsorship_cents_by_sponsor_id
    end

    test "includes target cents from current results as well as given active-patron data" do
      some_other_sponsor = create(:sponsors_patreon_user, :sponsor).user
      sponsor_spu = create(:sponsors_patreon_user, :sponsor, patreon_user_id: "31189703") # patron ID in cassette

      data = VCR.use_cassette("patreon/get_campaigns_and_memberships") do
        SponsorsPatreonSponsorshipLoader.call(
          sponsors_patreon_user: @spu,
          target_sponsorship_cents_by_sponsor_id: { some_other_sponsor.id => 500 },
        )
      end

      assert_equal({ some_other_sponsor.id => 500, sponsor_spu.user_id => 100 },
        data.target_sponsorship_cents_by_sponsor_id)
      assert_empty data.membership_next_page_cursors_by_campaign_id
    end

    test "returns cursors for loading the next batch of membership data" do
      campaign_id = "459978"
      next_page_cursor = "02B9AS9r0rVy7smJCVpWQPdNob"

      data = VCR.use_cassette("patreon/get_campaigns_and_memberships") do
        SponsorsPatreonSponsorshipLoader.call(
          sponsors_patreon_user: @spu,
          max_membership_pages: 1,
        )
      end

      assert_empty data.sponsorships_to_cancel
      assert_empty data.sponsorships_to_update
      assert_empty data.target_sponsorship_cents_by_sponsor_id
      assert_equal({ campaign_id => next_page_cursor }, data.membership_next_page_cursors_by_campaign_id)
    end

    test "returns sponsorship to cancel when Patreon membership is no longer active" do
      sponsor = create(:user, :verified)
      former_patron_patreon_user_id = "7673474" # see VCR cassette, first page of results
      create(:sponsors_patreon_user, :sponsor, user: sponsor, patreon_user_id: former_patron_patreon_user_id)
      sponsorship = create(:sponsorship, :patreon, sponsorable: @sponsorable, sponsor: sponsor)

      data = VCR.use_cassette("patreon/get_campaigns_and_memberships") do
        SponsorsPatreonSponsorshipLoader.call(sponsors_patreon_user: @spu)
      end

      assert_equal [sponsorship], data.sponsorships_to_cancel.to_a
      assert_empty data.sponsorships_to_update
      assert_empty data.membership_next_page_cursors_by_campaign_id,
        "expected to have seen all batches of memberships"
      assert_empty data.target_sponsorship_cents_by_sponsor_id
    end

    # https://github.com/github/sponsors/issues/5612
    test "does not return sponsorship to cancel or update when sponsorship amount differs from Patreon but their Patreon pledge does not meet the maintainer's GitHub Sponsors minimum amount" do
      sponsor_spu = create(:sponsors_patreon_user, :sponsor, patreon_user_id: "31189703") # patron has $1.00 pledge
      create(:sponsorship, :patreon, sponsorable: @sponsorable, sponsor: sponsor_spu.user,
        monthly_price_in_cents: 2_00) # no longer matches Patreon pledge amount
      @listing.update!(min_custom_tier_amount_in_cents: 3_00)

      data = VCR.use_cassette("patreon/get_campaigns_and_memberships") do
        SponsorsPatreonSponsorshipLoader.call(sponsors_patreon_user: @spu)
      end

      assert_empty data.target_sponsorship_cents_by_sponsor_id
      assert_empty data.membership_next_page_cursors_by_campaign_id
      assert_empty data.sponsorships_to_cancel, "should not include existing sponsorship with out-of-date amount"
      assert_empty data.sponsorships_to_update, "should not include existing sponsorship with out-of-date amount"
    end

    test "does not return sponsorship to cancel when active Patreon membership hasn't been found, not all memberships have been loaded" do
      sponsor = create(:user, :verified)
      active_patron_patreon_user_id = "31189703" # see VCR cassette, later page of results
      create(:sponsors_patreon_user, :sponsor, user: sponsor, patreon_user_id: active_patron_patreon_user_id)
      create(:sponsorship, :patreon, sponsorable: @sponsorable, sponsor: sponsor)

      data = VCR.use_cassette("patreon/get_campaigns_and_memberships") do
        SponsorsPatreonSponsorshipLoader.call(sponsors_patreon_user: @spu, max_membership_pages: 1)
      end

      assert_empty data.sponsorships_to_cancel
      assert_empty data.sponsorships_to_update
      refute_empty data.membership_next_page_cursors_by_campaign_id,
        "expected not to have seen all batches of memberships"
      assert_empty data.target_sponsorship_cents_by_sponsor_id
    end



    test "does not return sponsorship to cancel when the patron isn't in the current batch and target_sponsorship_cents_by_sponsor_id includes that sponsor" do
      patreon_sponsor = create(:sponsors_patreon_user, :sponsor).user
      SponsorsPatreonClient.any_instance.expects(:get_monthly_campaigns).once.returns([{
        "attributes" => { "is_monthly" => true },
        "id" => @spu.patreon_campaign_ids.first,
        "relationships" => { "tiers" => { "data" => [{ "id" => "sometierid" , "type" => "tier" }] } },
        "included" => [{
          "attributes" => { "amount_cents" => 100, "published" => true }, "id" => "sometierid", "type" => "tier",
        }],
      }])
      SponsorsPatreonClient.any_instance.expects(:get_all_pages).once.returns({
        "data" => [],
        "included" => [],
        "meta" => { "pagination" => { "cursors" => { "next" => nil }, "total" => 1 } },
      })
      sponsorship = create(:sponsorship, :patreon, sponsor: patreon_sponsor, sponsorable: @sponsorable)
      current_cents = sponsorship.monthly_price_in_cents

      data = SponsorsPatreonSponsorshipLoader.call(
        sponsors_patreon_user: @spu,
        target_sponsorship_cents_by_sponsor_id: { patreon_sponsor.id => current_cents },
      )

      assert_empty data.sponsorships_to_cancel
    end

    test "returns sponsorship to cancel that exists for inactive Patreon memberships when sponsor has linked with Patreon" do
      sponsor_spu = create(:sponsors_patreon_user, :sponsor,
        patreon_user_id: "31189704") # nonexistent patron ID in cassette
      sponsorship_to_cancel = create(:sponsorship, :patreon, sponsorable: @sponsorable, sponsor: sponsor_spu.user)

      data = VCR.use_cassette("patreon/get_campaigns_and_memberships") do
        SponsorsPatreonSponsorshipLoader.call(sponsors_patreon_user: @spu)
      end

      assert_equal Set.new([sponsorship_to_cancel]), data.sponsorships_to_cancel
    end

    test "returns sponsorship to cancel when the sponsor is a trade-restricted user" do
      sponsor_spu = create(:sponsors_patreon_user, :sponsor, patreon_user_id: "31189703") # patron ID in cassette
      tier = create(:sponsors_tier, :published, sponsors_listing: @listing, monthly_price_in_cents: 18_00)
      sponsorship = create(:sponsorship, :patreon, sponsorable: @sponsorable, sponsor: sponsor_spu.user, tier: tier)
      sponsor_spu.user.trade_controls_restriction.full!

      data = VCR.use_cassette("patreon/get_campaigns_and_memberships") do
        SponsorsPatreonSponsorshipLoader.call(sponsors_patreon_user: @spu)
      end

      assert_equal Set.new([sponsorship]), data.sponsorships_to_cancel
    end

    test "returns sponsorship to cancel when maintainer's Patreon setting enabled_as_sponsorable is false" do
      sponsor_spu = create(:sponsors_patreon_user, :sponsor, patreon_user_id: "31189703") # patron ID in cassette
      tier = create(:sponsors_tier, :published, sponsors_listing: @listing, monthly_price_in_cents: 18_00)
      sponsorship = create(:sponsorship, :patreon, sponsorable: @sponsorable, sponsor: sponsor_spu.user, tier: tier)
      @spu.update(enabled_as_sponsorable: false)

      data = VCR.use_cassette("patreon/get_campaigns_and_memberships") do
        SponsorsPatreonSponsorshipLoader.call(sponsors_patreon_user: @spu)
      end

      assert_equal Set.new([sponsorship]), data.sponsorships_to_cancel
    end

    # https://github.com/github/sponsors/issues/5248
    test "does not return a non-Patreon sponsorship to be cancelled even if the sponsor has connected with Patreon" do
      sponsor_spu = create(:sponsors_patreon_user, :sponsor, patreon_user_id: "31189703")
      create(:sponsorship, sponsorable: @sponsorable, sponsor: sponsor_spu.user) # regular GitHub sponsorship

      data = VCR.use_cassette("patreon/get_campaigns_and_memberships") do
        SponsorsPatreonSponsorshipLoader.call(sponsors_patreon_user: @spu)
      end

      assert_empty data.sponsorships_to_cancel
    end

    test "raises when given SponsorsPatreonUser has no Patreon credentials" do
      @spu.update_attribute(:patreon_access_token, nil)
      @spu.update_attribute(:patreon_refresh_token, nil)

      SponsorsPatreonClient.any_instance.expects(:get_memberships).never

      assert_raises_with_message(
        SponsorsPatreonSponsorshipLoader::UnprocessableError,
        "Can't authenticate with Patreon API for given account",
      ) do
        SponsorsPatreonSponsorshipLoader.call(sponsors_patreon_user: @spu)
      end
    end

    test "raises when no user exists for given SponsorsPatreonUser" do
      @spu.update_attribute(:user_id, User.maximum(:id) + 1)

      assert_raises_with_message(
        SponsorsPatreonSponsorshipLoader::UnprocessableError,
        "Invalid Patreon account given for sponsorable",
      ) do
        SponsorsPatreonSponsorshipLoader.call(sponsors_patreon_user: @spu)
      end
    end
  else
    test "raises when Sponsors is disabled" do
      error = assert_raises(SponsorsPatreonSponsorshipLoader::UnprocessableError) do
        SponsorsPatreonSponsorshipLoader.call(sponsors_patreon_user: @spu)
      end
      assert_equal "GitHub Sponsors is not enabled", error.message
    end
  end
end
