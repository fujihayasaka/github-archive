# typed: true
# frozen_string_literal: true

require "test_helper"

class Sponsors::LifetimeSponsorshipValuesLoaderTest < GitHub::TestCase
  fixtures do
    @sponsorable_user = create(:user, :verified, login: "SponsorableUser")
    @sponsorable_org = create(:organization, login: "SponsorableOrg", admin: @sponsorable_user)

    @user_listing = create(:sponsors_listing, :approved, tier_count: 0, sponsorable: @sponsorable_user)
    @org_listing = create(:sponsors_listing, :approved, :for_org, tier_count: 0, sponsorable: @sponsorable_org)

    # Sponsoring users:
    @user_sponsor = create(:user)
    @org_sponsor = create(:organization)
    @non_sponsor = create(:user)

    # Linked org to be a sponsor:
    @org_that_gets_credit = create(:organization, admin: @sponsorable_user, login: "OrgThatGetsCredit")
    @org_that_pays = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription),
      login: "OrgThatPays")
    create(:organization_profile, organization: @org_that_gets_credit, sponsoring_linked_organization: @org_that_pays)
  end

  setup do
    skip unless GitHub.sponsors_enabled?
  end

  context ".call" do
    test "returns a hash of the total amount each sponsor has ever paid the specified sponsorables" do
      travel_to(3.months.ago) do
        # Sponsorships of user:
        create(:payouts_ledger_entry, :transfer, amount_in_subunits: 10_00, sponsors_listing: @user_listing,
          sponsor: @user_sponsor) # $5 from sponsor, $5 from GitHub match
        create(:payouts_ledger_entry, :github_match, amount_in_subunits: -5_00, sponsors_listing: @user_listing,
          sponsor: @user_sponsor)
        create(:payouts_ledger_entry, :transfer, amount_in_subunits: 5_00, sponsors_listing: @user_listing,
          sponsor: @org_that_pays)

        # Sponsorships of org:
        create(:payouts_ledger_entry, :transfer, amount_in_subunits: 2_00, sponsors_listing: @org_listing,
          sponsor: @user_sponsor)
        create(:payouts_ledger_entry, :transfer, amount_in_subunits: 40_00, sponsors_listing: @org_listing,
          sponsor: @org_sponsor)
      end

      travel_to(2.months.ago) do
        # Sponsorships of user:
        create(:payouts_ledger_entry, :transfer, amount_in_subunits: 5_00, sponsors_listing: @user_listing,
          sponsor: @user_sponsor)
        create(:payouts_ledger_entry, :transfer, amount_in_subunits: 25_00, sponsors_listing: @user_listing,
          sponsor: @org_sponsor) # only $3 should count because $22 will be reversed
        create(:payouts_ledger_entry, :transfer_reversal, amount_in_subunits: -22_00, sponsors_listing: @user_listing,
          sponsor: @org_sponsor)

        # Sponsorships of org:
        create(:payouts_ledger_entry, :transfer, amount_in_subunits: 2_00, sponsors_listing: @org_listing,
          sponsor: @user_sponsor)
        create(:payouts_ledger_entry, :transfer, amount_in_subunits: 2_00, sponsors_listing: @org_listing,
          sponsor: @org_sponsor) # tier downgrade from previous $40/mo
      end

      travel_to(1.month.ago) do
        # Sponsorships of user:
        create(:payouts_ledger_entry, :transfer, amount_in_subunits: 5_00, sponsors_listing: @user_listing,
          sponsor: @user_sponsor)
        create(:payouts_ledger_entry, :transfer, amount_in_subunits: 3_00, sponsors_listing: @user_listing,
          sponsor: @org_sponsor)

        # Concurrent one-time sponsorship of user:
        create(:payouts_ledger_entry, :transfer, amount_in_subunits: 4_00, sponsors_listing: @user_listing,
          sponsor: @user_sponsor)

        # Sponsorships of org:
        create(:payouts_ledger_entry, :transfer, amount_in_subunits: 2_00, sponsors_listing: @org_listing,
          sponsor: @org_sponsor)
        create(:payouts_ledger_entry, :transfer, amount_in_subunits: 40_00, sponsors_listing: @org_listing,
          sponsor: @user_sponsor) # tier upgrade from previous $2/mo
      end

      # Sponsorships of org:
      create(:payouts_ledger_entry, :transfer, amount_in_subunits: 40_00, sponsors_listing: @org_listing,
        sponsor: @user_sponsor)

      # Sponsorship activity for other maintainers that shouldn't be counted:
      create(:payouts_ledger_entry, :transfer, sponsor: @user_sponsor)
      create(:payouts_ledger_entry, :transfer, sponsor: @org_sponsor)
      create(:payouts_ledger_entry, :github_match, sponsor: @org_sponsor)

      expected_queries = {
        abilities: 1,
        billing_payouts_ledger_entries: 1,
        billing_transactions: 1,
        organization_profiles: 1,
        sponsors_listings: 1,
        users: 1,
      }

      result = assert_query_count(expected_queries.values.sum) do
        assert_query_count_per_table(expected_queries) do
          Sponsors::LifetimeSponsorshipValuesLoader.call(
            sponsorable_ids: [@sponsorable_user.id, @sponsorable_org.id],
            viewer: @sponsorable_user,
          )
        end
      end

      assert_instance_of Hash, result
      assert_same_elements [@sponsorable_user.id, @sponsorable_org.id], result.keys

      sponsorable_user_result = T.must(result[@sponsorable_user.id])
      assert_equal [@user_sponsor.id, @org_sponsor.id, @org_that_gets_credit.id].sort,
        sponsorable_user_result.keys.sort, "expected only sponsors of the sponsorable to be included"
      assert_equal Billing::Money.new(19_00), # $5/mo for 3 months + $4 one-time
        sponsorable_user_result[@user_sponsor.id]
      assert_equal Billing::Money.new(6_00), # $3/mo for 2 months
        sponsorable_user_result[@org_sponsor.id]
      assert_equal Billing::Money.new(5_00), # $5/mo for 1 month via linked org
        sponsorable_user_result[@org_that_gets_credit.id]
      assert_equal Billing::Money.zero, sponsorable_user_result[@non_sponsor.id]

      sponsorable_org_result = T.must(result[@sponsorable_org.id])
      assert_equal [@user_sponsor.id, @org_sponsor.id].sort,
        sponsorable_org_result.keys.sort, "expected only sponsors of the sponsorable to be included"
      assert_equal Billing::Money.new(84_00), # $2/mo for 2 months + $40/mo for 2 months
        sponsorable_org_result[@user_sponsor.id]
      assert_equal Billing::Money.new(44_00), # $40/mo for 1 month + $2/mo for 2 months
        sponsorable_org_result[@org_sponsor.id]
      assert_equal Billing::Money.zero, sponsorable_org_result[@org_that_gets_credit.id]
      assert_equal Billing::Money.zero, sponsorable_org_result[@non_sponsor.id]
    end

    test "will not return results for a user other than the viewer" do
      other_sponsorable = create(:user, :sponsorable)

      result = Sponsors::LifetimeSponsorshipValuesLoader.call(
        sponsorable_ids: [@sponsorable_user.id, other_sponsorable.id],
        viewer: @sponsorable_user,
      )

      assert_instance_of Hash, result
      assert_same_elements [@sponsorable_user.id], result.keys
    end

    test "will not return results for an organization the viewer does not admin" do
      rando_org = create(:organization, :sponsorable)
      member_org = create(:organization)
      member_org.add_member(@sponsorable_user)
      billing_mgr_org = create(:organization)
      billing_mgr_org.billing.add_manager(@sponsorable_user, actor: billing_mgr_org.admin)

      result = Sponsors::LifetimeSponsorshipValuesLoader.call(
        sponsorable_ids: [@sponsorable_user.id, rando_org.id, member_org.id, billing_mgr_org.id],
        viewer: @sponsorable_user,
      )

      assert_instance_of Hash, result
      assert_same_elements [@sponsorable_user.id], result.keys
    end

    test "omits spammy sponsors" do
      spammer = create(:spammy_user)
      create(:payouts_ledger_entry, :transfer, amount_in_subunits: 10_00, sponsors_listing: @user_listing,
        sponsor: spammer)

      result = Sponsors::LifetimeSponsorshipValuesLoader.call(
        sponsorable_ids: [@sponsorable_user.id],
        viewer: @sponsorable_user,
      )

      assert_equal({ @sponsorable_user.id => {} }, result)
    end
  end
end
