# typed: true
# frozen_string_literal: true

require "test_helper"

class SyncSponsorsPatreonUserTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @non_sponsorable_patreon_user = create(:sponsors_patreon_user, :sponsor)
    @spu = create(:sponsors_patreon_user)
  end

  setup do
    @datadog_prefix = SyncSponsorsPatreonUser::DATADOG_PREFIX
  end

  context ".call" do
    if GitHub.sponsors_enabled?
      test "creates Sponsors Patreon tiers for published Patreon tiers" do
        SponsorsPatreonClient.any_instance.expects(:get_campaigns).once.returns({
          "data" => [
            { "attributes" => { "is_monthly" => false, "published_at" => "2023-08-15T14:50:13.000+00:00" },
              "type" => "campaign", "id" => "8675309",
              "relationships" => { "tiers" => { "data" => [{ "id" => "345", "type" => "tier" }] } } },
            { "attributes" => { "is_monthly" => true, "published_at" => "2023-08-15T14:50:13.000+00:00" },
              "type" => "campaign", "id" => "368121",
              "relationships" => { "tiers" => { "data" => [
                { "id" => "123", "type" => "tier" },
                { "id" => "456", "type" => "tier" },
                { "id" => "789", "type" => "tier" },
              ] } } },
          ],
          "included" => [
            { "attributes" => { "amount_cents" => 200, "published" => true }, "id" => "123", "type" => "tier" },
            { "attributes" => { "amount_cents" => 100, "published" => false }, "id" => "345", "type" => "tier" },
            { "attributes" => { "amount_cents" => 150, "published" => true }, "id" => "456", "type" => "tier" },
            { "attributes" => { "amount_cents" => 300, "published" => true }, "id" => "789", "type" => "tier" },
          ],
          "meta" => { "pagination" => { "cursors" => { "next" => nil }, "total" => 1 } },
        })

        assert_difference(-> { @spu.reload.sponsors_patreon_tiers.count }, 3) do
          SyncSponsorsPatreonUser.call(sponsors_patreon_user: @spu)
        end

        assert_predicate @spu.sponsors_patreon_tiers.where(campaign_id: "368121", amount_in_cents: 200), :exists?
        assert_predicate @spu.sponsors_patreon_tiers.where(campaign_id: "368121", amount_in_cents: 150), :exists?
        assert_predicate @spu.sponsors_patreon_tiers.where(campaign_id: "368121", amount_in_cents: 300), :exists?
      end

      test "deletes existing SponsorsPatreonTier records when there are no monthly Patreon campaigns" do
        unrelated_patreon_tier = create(:sponsors_patreon_tier) # should not be deleted, another user's tier
        patreon_tier1, patreon_tier2 = create_pair(:sponsors_patreon_tier, sponsors_patreon_user: @spu)
        SponsorsPatreonClient.any_instance.expects(:get_campaigns).once.returns({
          "data" => [],
          "included" => [],
          "meta" => { "pagination" => { "cursors" => { "next" => nil }, "total" => 1 } },
        })

        assert_difference(-> { SponsorsPatreonTier.count }, -2) do
          SyncSponsorsPatreonUser.call(sponsors_patreon_user: @spu)
        end

        assert_empty @spu.sponsors_patreon_tiers.reload
        refute SponsorsPatreonTier.exists?(patreon_tier1.id)
        refute SponsorsPatreonTier.exists?(patreon_tier2.id)
        assert SponsorsPatreonTier.exists?(unrelated_patreon_tier.id)
      end

      test "deletes existing SponsorsPatreonTier records when user has no SponsorsListing" do
        assert_nil @non_sponsorable_patreon_user.user.sponsors_listing
        patreon_tier = create(:sponsors_patreon_tier, sponsors_patreon_user: @non_sponsorable_patreon_user)
        SponsorsPatreonClient.any_instance.expects(:get_campaigns).once.returns({
          "data" => [
            { "attributes" => { "is_monthly" => true, "published_at" => "2023-08-15T14:50:13.000+00:00" },
              "type" => "campaign", "id" => patreon_tier.campaign_id,
              "relationships" => { "tiers" => { "data" => [{ "id" => "123", "type" => "tier" }] } } },
          ],
          "included" => [
            { "attributes" => { "amount_cents" => patreon_tier.amount_in_cents, "published" => true },
              "id" => "123", "type" => "tier" },
          ],
          "meta" => { "pagination" => { "cursors" => { "next" => nil }, "total" => 1 } },
        })

        assert_difference(-> { SponsorsPatreonTier.count }, -1) do
          SyncSponsorsPatreonUser.call(sponsors_patreon_user: @non_sponsorable_patreon_user)
        end

        refute SponsorsPatreonTier.exists?(patreon_tier.id)
      end

      # See https://github.com/github/sponsors/issues/5475
      test "does not create SponsorsPatreonTier records when tier's campaign is not published" do
        SponsorsPatreonClient.any_instance.expects(:get_campaigns).once.returns({
          "data" => [
            { "attributes" => { "is_monthly" => true, "published_at" => nil },
              "type" => "campaign", "id" => "8675309",
              "relationships" => { "tiers" => { "data" => [{ "id" => "123", "type" => "tier" }] } } },
          ],
          "included" => [
            { "attributes" => { "amount_cents" => 200, "published" => true },
              "id" => "123", "type" => "tier" },
          ],
          "meta" => { "pagination" => { "cursors" => { "next" => nil }, "total" => 1 } },
        })

        assert_no_difference(-> { SponsorsPatreonTier.count }) do
          SyncSponsorsPatreonUser.call(sponsors_patreon_user: @spu)
        end

        assert_empty @spu.sponsors_patreon_tiers.reload
      end

      test "does not create SponsorsPatreonTier records when user has no SponsorsListing" do
        assert_nil @non_sponsorable_patreon_user.user.sponsors_listing
        SponsorsPatreonClient.any_instance.expects(:get_campaigns).once.returns({
          "data" => [
            { "attributes" => { "is_monthly" => true, "published_at" => "2023-08-15T14:50:13.000+00:00" },
              "type" => "campaign", "id" => "8675309",
              "relationships" => { "tiers" => { "data" => [{ "id" => "123", "type" => "tier" }] } } },
          ],
          "included" => [
            { "attributes" => { "amount_cents" => 200, "published" => true },
              "id" => "123", "type" => "tier" },
          ],
          "meta" => { "pagination" => { "cursors" => { "next" => nil }, "total" => 1 } },
        })

        assert_no_difference(-> { SponsorsPatreonTier.count }) do
          SyncSponsorsPatreonUser.call(sponsors_patreon_user: @non_sponsorable_patreon_user)
        end

        assert_empty @non_sponsorable_patreon_user.sponsors_patreon_tiers.reload
      end

      test "does not create SponsorsPatreonTier records when user has been banned from Sponsors" do
        create(:sponsors_listing, :banned, sponsorable: @non_sponsorable_patreon_user.user)
        SponsorsPatreonClient.any_instance.expects(:get_campaigns).once.returns({
          "data" => [
            { "attributes" => { "is_monthly" => true, "published_at" => "2023-08-15T14:50:13.000+00:00" },
              "type" => "campaign", "id" => "8675309",
              "relationships" => { "tiers" => { "data" => [{ "id" => "123", "type" => "tier" }] } } },
          ],
          "included" => [
            { "attributes" => { "amount_cents" => 200, "published" => true },
              "id" => "123", "type" => "tier" },
          ],
          "meta" => { "pagination" => { "cursors" => { "next" => nil }, "total" => 1 } },
        })

        assert_no_difference(-> { SponsorsPatreonTier.count }) do
          SyncSponsorsPatreonUser.call(sponsors_patreon_user: @non_sponsorable_patreon_user)
        end

        assert_empty @non_sponsorable_patreon_user.sponsors_patreon_tiers.reload
      end

      test "deletes existing SponsorsPatreonTier records when the tier's campaign is no longer published on Patreon" do
        patreon_tier = create(:sponsors_patreon_tier, sponsors_patreon_user: @spu)
        SponsorsPatreonClient.any_instance.expects(:get_campaigns).once.returns({
          "data" => [
            { "attributes" => { "is_monthly" => true, "published_at" => nil },
              "type" => "campaign",
              "id" => patreon_tier.campaign_id, "relationships" => { "tiers" => { "data" => [
                { "id" => "123", "type" => "tier" },
              ] } } },
          ],
          "included" => [
            { "attributes" => { "amount_cents" => patreon_tier.amount_in_cents, "published" => true },
              "id" => "123", "type" => "tier" },
          ],
          "meta" => { "pagination" => { "cursors" => { "next" => nil }, "total" => 1 } },
        })

        assert_difference(-> { SponsorsPatreonTier.count }, -1) do
          SyncSponsorsPatreonUser.call(sponsors_patreon_user: @spu)
        end

        refute SponsorsPatreonTier.exists?(patreon_tier.id)
      end

      test "deletes existing SponsorsPatreonTier record when the tier is no longer published on Patreon" do
        patreon_tier_to_keep, patreon_tier_to_delete = create_pair(:sponsors_patreon_tier,
          sponsors_patreon_user: @spu)
        SponsorsPatreonClient.any_instance.expects(:get_campaigns).once.returns({
          "data" => [
            { "attributes" => { "is_monthly" => true, "published_at" => "2023-08-15T14:50:13.000+00:00" },
              "type" => "campaign",
              "id" => patreon_tier_to_keep.campaign_id, "relationships" => { "tiers" => { "data" => [
                { "id" => "123", "type" => "tier" },
              ] } } },
            { "attributes" => { "is_monthly" => true, "published_at" => "2023-08-15T14:50:13.000+00:00" },
              "type" => "campaign",
              "id" => patreon_tier_to_delete.campaign_id, "relationships" => { "tiers" => { "data" => [
                { "id" => "456", "type" => "tier" },
              ] } } },
          ],
          "included" => [
            { "attributes" => { "amount_cents" => patreon_tier_to_keep.amount_in_cents, "published" => true },
              "id" => "123", "type" => "tier" },
            { "attributes" => { "amount_cents" => patreon_tier_to_delete.amount_in_cents, "published" => false },
              "id" => "456", "type" => "tier" },
          ],
          "meta" => { "pagination" => { "cursors" => { "next" => nil }, "total" => 1 } },
        })

        assert_difference(-> { SponsorsPatreonTier.count }, -1) do
          SyncSponsorsPatreonUser.call(sponsors_patreon_user: @spu)
        end

        assert SponsorsPatreonTier.exists?(patreon_tier_to_keep.id)
        refute SponsorsPatreonTier.exists?(patreon_tier_to_delete.id)
      end

      test "does not create duplicates when all published Patreon tiers already exist in our database" do
        SponsorsPatreonClient.any_instance.expects(:get_campaigns).once.returns({
          "data" => [
            { "attributes" => { "is_monthly" => true, "published_at" => "2023-08-15T14:50:13.000+00:00" },
              "type" => "campaign", "id" => "368121",
              "relationships" => { "tiers" => { "data" => [
                { "id" => "123", "type" => "tier" },
                { "id" => "456", "type" => "tier" },
              ] } } },
          ],
          "included" => [
            { "attributes" => { "amount_cents" => 200, "published" => true }, "id" => "123", "type" => "tier" },
            { "attributes" => { "amount_cents" => 150, "published" => true }, "id" => "456", "type" => "tier" },
          ],
          "meta" => { "pagination" => { "cursors" => { "next" => nil }, "total" => 1 } },
        })
        patreon_tier1 = create(:sponsors_patreon_tier, sponsors_patreon_user: @spu,
          campaign_id: "368121", amount_in_cents: 200)
        patreon_tier2 = create(:sponsors_patreon_tier, sponsors_patreon_user: @spu,
          campaign_id: "368121", amount_in_cents: 150)

        assert_no_difference(-> { SponsorsPatreonTier.count }) do
          SyncSponsorsPatreonUser.call(sponsors_patreon_user: @spu)
        end

        assert_equal "368121", patreon_tier1.reload.campaign_id, "should not have changed campaign ID on Patreon tier"
        assert_equal "368121", patreon_tier2.reload.campaign_id, "should not have changed campaign ID on Patreon tier"
        assert_equal 200, patreon_tier1.amount_in_cents, "should not have changed amount on Patreon tier"
        assert_equal 150, patreon_tier2.amount_in_cents, "should not have changed amount on Patreon tier"
      end

      test "does not create duplicates when some published Patreon tiers already exist in our database" do
        SponsorsPatreonClient.any_instance.expects(:get_campaigns).once.returns({
          "data" => [
            { "attributes" => { "is_monthly" => true, "published_at" => "2023-08-15T14:50:13.000+00:00" },
              "type" => "campaign", "id" => "368121",
              "relationships" => { "tiers" => { "data" => [
                { "id" => "123", "type" => "tier" },
                { "id" => "456", "type" => "tier" },
              ] } } },
          ],
          "included" => [
            { "attributes" => { "amount_cents" => 200, "published" => true }, "id" => "123", "type" => "tier" },
            { "attributes" => { "amount_cents" => 150, "published" => true }, "id" => "456", "type" => "tier" },
          ],
          "meta" => { "pagination" => { "cursors" => { "next" => nil }, "total" => 1 } },
        })
        existing_patreon_tier = create(:sponsors_patreon_tier, sponsors_patreon_user: @spu,
          campaign_id: "368121", amount_in_cents: 200)

        assert_difference(-> { SponsorsPatreonTier.count }, 1) do
          SyncSponsorsPatreonUser.call(sponsors_patreon_user: @spu)
        end

        assert_equal "368121", existing_patreon_tier.reload.campaign_id, "should not have changed campaign ID on " \
          "Patreon tier"
        assert_equal 200, existing_patreon_tier.amount_in_cents, "should not have changed amount on Patreon tier"
        assert @spu.sponsors_patreon_tiers.reload.where(campaign_id: "368121", amount_in_cents: 150).exists?
      end

      test "handles when there is an outdated Patreon tier in our system and one missing" do
        SponsorsPatreonClient.any_instance.expects(:get_campaigns).once.returns({
          "data" => [
            { "attributes" => { "is_monthly" => true, "published_at" => "2023-08-15T14:50:13.000+00:00" },
              "type" => "campaign", "id" => "368121",
              "relationships" => { "tiers" => { "data" => [
                { "id" => "123", "type" => "tier" },
                { "id" => "456", "type" => "tier" },
              ] } } },
          ],
          "included" => [
            { "attributes" => { "amount_cents" => 200, "published" => true }, "id" => "123", "type" => "tier" },
            { "attributes" => { "amount_cents" => 150, "published" => true }, "id" => "456", "type" => "tier" },
          ],
          "meta" => { "pagination" => { "cursors" => { "next" => nil }, "total" => 1 } },
        })
        valid_patreon_tier = create(:sponsors_patreon_tier, sponsors_patreon_user: @spu,
          campaign_id: "368121", amount_in_cents: 200)
        outdated_patreon_tier = create(:sponsors_patreon_tier, sponsors_patreon_user: @spu,
          campaign_id: "368121", amount_in_cents: 100)

        assert_no_difference(-> { SponsorsPatreonTier.count }) do # one created, one deleted
          SyncSponsorsPatreonUser.call(sponsors_patreon_user: @spu)
        end

        assert_equal "368121", valid_patreon_tier.reload.campaign_id, "should not have changed campaign ID on " \
          "Patreon tier"
        assert_equal 200, valid_patreon_tier.amount_in_cents, "should not have changed amount on Patreon tier"
        assert @spu.sponsors_patreon_tiers.reload.where(campaign_id: "368121", amount_in_cents: 150).exists?
        refute SponsorsPatreonTier.exists?(outdated_patreon_tier.id)
      end

      test "raises when given sponsorable's SponsorsPatreonUser has no Patreon credentials" do
        spu = create(:sponsors_patreon_user, :sponsor, patreon_access_token: nil, patreon_refresh_token: nil)

        SponsorsPatreonClient.any_instance.expects(:get_campaigns).never

        error = assert_raises(SyncSponsorsPatreonUser::UnprocessableError) do
          SyncSponsorsPatreonUser.call(sponsors_patreon_user: spu)
        end

        assert_equal "Can't authenticate with Patreon API for given account", error.message
      end

      test "increments a count when Patreon credentials are invalid and attempts to refresh tokens" do
        assert_difference(-> { GitHub.dogstats.increments("#{@datadog_prefix}.unauthorized").size }) do
          assert_difference("SponsorsPatreonUser.count", -1) do
            assert_no_difference("SponsorsPatreonTier.count") do
              VCR.use_cassette("patreon/get_campaigns_invalid") do
                SyncSponsorsPatreonUser.call(sponsors_patreon_user: @spu)
              end
            end
          end
        end

        refute SponsorsPatreonUser.exists?(@spu.id), "should have deleted SponsorsPatreonUser with invalid tokens"
      end

      # https://github.com/github/sponsors/issues/5349
      test "does not create Sponsors Patreon tier when Patreon campaign ID is not present" do
        tier_data = { "id" => "123", "type" => "tier" }
        campaign_attrs = { "attributes" => { "is_monthly" => true,
          "published_at" => "2023-08-15T14:50:13.000+00:00" }, "type" => "campaign", "id" => "" }
        tier_attrs = { "attributes" => { "amount_cents" => 200, "published" => true } }
        SponsorsPatreonClient.any_instance.expects(:get_campaigns).once.returns({
          "data" => [campaign_attrs.merge("relationships" => { "tiers" => { "data" => [tier_data] } })],
          "included" => [tier_attrs.merge("id" => "123", "type" => "tier")],
          "meta" => { "pagination" => { "cursors" => { "next" => nil }, "total" => 1 } },
        })

        assert_no_difference("SponsorsPatreonTier.count") do
          SyncSponsorsPatreonUser.call(sponsors_patreon_user: @spu)
        end
      end

      # https://github.com/github/sponsors/issues/5349
      test "does not create Sponsors Patreon tier when amount in cents is 0" do
        tier_data = { "id" => "123", "type" => "tier" }
        campaign_attrs = { "attributes" => { "is_monthly" => true,
          "published_at" => "2023-08-15T14:50:13.000+00:00" }, "type" => "campaign", "id" => "abc123" }
        tier_attrs = { "attributes" => { "amount_cents" => 0, "published" => true } }
        SponsorsPatreonClient.any_instance.expects(:get_campaigns).once.returns({
          "data" => [campaign_attrs.merge("relationships" => { "tiers" => { "data" => [tier_data] } })],
          "included" => [tier_attrs.merge("id" => "123", "type" => "tier")],
          "meta" => { "pagination" => { "cursors" => { "next" => nil }, "total" => 1 } },
        })

        assert_no_difference("SponsorsPatreonTier.count") do
          SyncSponsorsPatreonUser.call(sponsors_patreon_user: @spu)
        end
      end

      # https://github.com/github/sponsors/issues/5349
      test "does not create Sponsors Patreon tier when Patreon tier exceeds Sponsors tier limit" do
        tier_data = { "id" => "123", "type" => "tier" }
        campaign_attrs = { "attributes" => { "is_monthly" => true,
          "published_at" => "2023-08-15T14:50:13.000+00:00" }, "type" => "campaign", "id" => "abc123" }
        tier_attrs = { "attributes" => { "amount_cents" => SponsorsTier::MAX_SPONSORSHIP_AMOUNT_IN_CENTS + 1,
          "published" => true } }
        SponsorsPatreonClient.any_instance.expects(:get_campaigns).once.returns({
          "data" => [campaign_attrs.merge("relationships" => { "tiers" => { "data" => [tier_data] } })],
          "included" => [tier_attrs.merge("id" => "123", "type" => "tier")],
          "meta" => { "pagination" => { "cursors" => { "next" => nil }, "total" => 1 } },
        })

        assert_no_difference("SponsorsPatreonTier.count") do
          SyncSponsorsPatreonUser.call(sponsors_patreon_user: @spu)
        end
      end
    else
      test "raises when Sponsors is disabled" do
        error = assert_raises(SyncSponsorsPatreonUser::UnprocessableError) do
          SyncSponsorsPatreonUser.call(sponsors_patreon_user: @spu)
        end
        assert_equal "GitHub Sponsors is not enabled", error.message
      end
    end
  end
end
