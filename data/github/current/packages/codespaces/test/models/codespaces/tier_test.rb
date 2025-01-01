# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesTierTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @user = create(:user)
    @new_user = create(:user, created_at: TrustTiers::TierDetails::NEUTRAL_FREE_AGE_LIMIT.ago + 1.day)
    @known_user = create(:user, created_at: TrustTiers::TierDetails::NEUTRAL_FREE_AGE_LIMIT.ago - 1.day)

    @educational_coupon = create(:coupon, group: Coupon::EDUCATION_GROUP_NAMES.first)
    @non_educational_coupon = create(:coupon, group: "internal")

    @emu = create(:emu)
    @business = @emu.enterprise_managed_business
  end

  if !GitHub.enterprise?
    context "#for_billable_owner" do
      context "TIER 1" do
        # **************** Tier 1 ****************
        # * Sales serve accounts (invoiced Organization or Enterprise)
        #    *************   OR    *************
        # * Accounts with established billing history
        #     * Most recent payment was successful
        #     * One successful payment at least two months ago
        #    *************   OR    *************
        # * Oldest account owner > 14 days old AND has eligible coupon
        test "returns tier 1 if the billing plan owner is an Enterprise Account" do
          org = create(:enterprise_linked_organization)
          assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::BUSINESS_OR_INVOICED), Codespaces::Tier.for_billable_owner(org.reload)
        end

        test "returns tier 1 if the billing plan owner is invoiced" do
          org = create(:invoiced_organization, plan: "business_plus")
          assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::BUSINESS_OR_INVOICED), Codespaces::Tier.for_billable_owner(org.reload)
        end

        test "returns tier 1 if account is older than limit and has non-educational coupon" do
          org = create(:business_plus_organization, admin: @known_user)
          org.redeem_coupon(@non_educational_coupon)
          assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::TRUSTED_COUPON), Codespaces::Tier.for_billable_owner(org.reload)
        end

        test "returns tier 1 if settings are set to tier 1" do
          org = create(:free_org, admins: [@known_user])
          org.settings.set!(:trust_tier, TrustTiers::Tier::TRUSTED)
          assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::SETTINGS_FORCED), Codespaces::Tier.for_billable_owner(org.reload)
        end

        test "returns tier 1 if everything is fulfilled" do
          org = create(:team_org, admins: [@known_user])
          create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, created_at: 10.days.ago)
          create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, created_at: 66.days.ago)

          refute org.dunning?
          assert_equal TrustTiers::Tier::TRUSTED, Codespaces::Tier.for_billable_owner(org.reload).tier
        end

        test "does not return tier 1 if only billing has been zero cents" do
          org = create(:team_org, admins: [@known_user])
          create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, amount_in_cents: 0, created_at: 10.days.ago)
          create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, amount_in_cents: 0, created_at: 66.days.ago)

          refute org.dunning?
          refute_equal TrustTiers::Tier::TRUSTED, Codespaces::Tier.for_billable_owner(org.reload).tier
        end

        test "does not return tier 1 if only billings have been refunded" do
          org = create(:team_org, admins: [@known_user])
          create(:billing_transaction, :zuora, :refunded_sale, user: org, asset_packs_total: 5, created_at: 10.days.ago)
          create(:billing_transaction, :zuora, :refunded_sale, user: org, asset_packs_total: 5, created_at: 66.days.ago)

          refute org.dunning?
          refute_equal TrustTiers::Tier::TRUSTED, Codespaces::Tier.for_billable_owner(org.reload).tier
        end

        test "NOT tier 1 if settings are set to lower tier" do
          org = create(:team_org, admins: [@known_user])
          create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, created_at: 10.days.ago)
          create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, created_at: 36.days.ago)

          org.settings.set!(:trust_tier, TrustTiers::Tier::NEUTRAL)
          refute_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::SETTINGS_FORCED), Codespaces::Tier.for_billable_owner(org.reload)
        end

        test "NOT tier 1 if only owner was created less than limit" do
          org = create(:team_org, admins: [@known_user])

          refute_equal TrustTiers::Tier::TRUSTED, Codespaces::Tier.for_billable_owner(org.reload).tier
        end

        test "NOT tier 1 if enterprise trial" do
          org = create(:business_plus_organization, admins: [@known_user])
          Billing::EnterpriseCloudTrial.new(org).create
          refute_equal TrustTiers::Tier::TRUSTED, Codespaces::Tier.for_billable_owner(org.reload).tier
        end

        test "NOT tier 1 if enterprise business trial and not invoiced" do
          org = create(:organization, admins: [@known_user])
          business = create(:business, :with_self_serve_payment, trial_expires_at: 3.days.from_now)
          business.add_organization(org)
          org.reload
          refute_equal TrustTiers::Tier::TRUSTED, Codespaces::Tier.for_billable_owner(org.business).tier
        end

        test "Tier 1 if enterprise business trial and invoiced" do
          org = create(:organization, admins: [@known_user])
          business = create(:business, trial_expires_at: 3.days.from_now)
          business.add_organization(org)
          org.reload
          assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::BUSINESS_OR_INVOICED), TrustTiers::Tier.for_billable_owner(org.business)
        end

        test "NOT tier 1 if free org" do
          org = create(:free_org, admins: [@known_user], plan: GitHub::Plan.free)

          refute_equal TrustTiers::Tier::TRUSTED, Codespaces::Tier.for_billable_owner(org.reload).tier
        end

        test "returns tier 1 if account has a non-education coupon that is newer than limit" do
          org = create(:organization, admins: [@new_user], plan: GitHub::Plan.business)
          org.redeem_coupon(@non_educational_coupon)
          assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::TRUSTED_COUPON), Codespaces::Tier.for_billable_owner(org.reload)
        end

        test "returns tier 1 if account has an education coupon that is newer than limit (non-Pro account)" do
          org = create(:organization, admins: [@new_user], plan: GitHub::Plan.business)
          org.redeem_coupon(@educational_coupon)
          assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::TRUSTED_COUPON), Codespaces::Tier.for_billable_owner(org.reload)
        end
      end

      context "TIER 2" do
        # **************** Tier 2 ****************
        # * The repo owner must fulfill ONLY ONE of the following requirements:
        #   * Oldest account owner created more than limit
        #   * Has a paid plan with hasActuallyPaidMoney
        #   * Has a non-education coupon
        test "returns tier 2 if the oldest account owner is greater than limit" do
          org = create(:organization, admins: [@known_user], plan: GitHub::Plan.business)
          assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::NEUTRAL, TrustTiers::TierResult::OLDEST_OWNER_AGE), Codespaces::Tier.for_billable_owner(org.reload)
        end

        test "returns tier 2 if account has a paid plan that actually paid money" do
          org = create(:organization, admins: [@new_user], plan: GitHub::Plan.business)
          create(:billing_transaction, :zuora, user: org, asset_packs_total: 5)
          assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::NEUTRAL, TrustTiers::TierResult::PAID), Codespaces::Tier.for_billable_owner(org.reload)
        end
      end

      context "TIER 3" do
        # **************** Tier 3 ****************
        # * Everyone else
        test "returns calculated tier for user" do
          user = create(:user)
          assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, TrustTiers::TierResult::NO_MATCH), Codespaces::Tier.for_billable_owner(user)
        end

        test "returns tier 3 if the oldest account owner is less than limit" do
          org = create(:organization, admins: [@new_user], plan: GitHub::Plan.business)
          assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, TrustTiers::TierResult::NO_MATCH), Codespaces::Tier.for_billable_owner(org.reload)
        end

        test "returns tier 3 if the oldest account owner is less than limit and refunded money" do
          org = create(:organization, admins: [@new_user], plan: GitHub::Plan.business)
          create(:billing_transaction, :zuora, :refunded_sale, user: org, asset_packs_total: 5)
          assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, TrustTiers::TierResult::NO_MATCH), Codespaces::Tier.for_billable_owner(org.reload)
        end

        test "returns tier 3 if the oldest account owner is less than limit and free org" do
          org = create(:organization, admins: [@new_user], plan: GitHub::Plan.free)
          assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, TrustTiers::TierResult::NO_MATCH), Codespaces::Tier.for_billable_owner(org.reload)
        end

        test "returns tier 3 if the oldest account owner is less than limit and enterprise trial" do
          org = create(:organization, admins: [@new_user], plan: GitHub::Plan.business_plus)
          Billing::EnterpriseCloudTrial.new(org).create
          assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, TrustTiers::TierResult::NO_MATCH), Codespaces::Tier.for_billable_owner(org.reload)
        end
      end

      context "multi-tenant enterprise" do
        test "returns tier 2 for proxima users over 30 days old" do
          on_multi_tenant_enterprise(tenant: @business) do
            emu = create(:emu)

            Timecop.travel(TrustTiers::TierDetails::NEUTRAL_FREE_AGE_LIMIT) do
              assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::NEUTRAL, TrustTiers::TierResult::OLDEST_OWNER_AGE), Codespaces::Tier.for_billable_owner(emu)
            end
          end
        end

        test "returns tier 3 for proxima users under 30 days old" do
          on_multi_tenant_enterprise(tenant: @business) do
            emu = create(:emu)

            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, TrustTiers::TierResult::NO_MATCH), Codespaces::Tier.for_billable_owner(emu)
          end
        end

        test "returns tier 1 for org" do
          on_multi_tenant_enterprise(tenant: @business) do
            org = create(:organization, :with_org_namespacing, business: @business)
            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::BUSINESS_OR_INVOICED), Codespaces::Tier.for_billable_owner(org.reload)
          end
        end
      end

      context "Enterprise managed users" do
        test "returns tier 2 for emu over 30 days old" do

          Timecop.travel(TrustTiers::TierDetails::NEUTRAL_FREE_AGE_LIMIT) do
            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::NEUTRAL, TrustTiers::TierResult::OLDEST_OWNER_AGE), Codespaces::Tier.for_billable_owner(@emu)
          end
        end

        test "returns tier 3 for emu under 30 days old" do
          assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, TrustTiers::TierResult::NO_MATCH), Codespaces::Tier.for_billable_owner(@emu)
        end
      end
    end

    context "#for_user" do
      test "returns user tier if no owner" do
        stub_trust_tier = TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, TrustTiers::TierResult::USER)
        Codespaces::Tier.expects(:for_billable_owner).with(@user).at_least_once.returns(stub_trust_tier)

        assert_equal stub_trust_tier, Codespaces::Tier.for_user(@user)
      end

      test "emits a metric for number of owners to check" do
        GitHub.stubs(:dogstats).at_least_once.returns(GitHub::MemoryDogstatsD.new)

        tier_1_org = create(:codespaces_credit_card_organization, admin: @user)
        another_tier_1_org = create(:codespaces_credit_card_organization, admin: @user)
        tier_2_org = create(:codespaces_credit_card_organization, admin: @user)
        tier_3_org = create(:codespaces_credit_card_organization, admin: @user)
        [tier_1_org, another_tier_1_org, tier_2_org, tier_3_org].each do |org|
          Codespaces::OrgPolicy.grant_billing_permission!(@user, org)
        end
        Codespaces::Tier.expects(:for_billable_owner).with(tier_1_org).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, "reason"))
        Codespaces::Tier.expects(:for_billable_owner).with(another_tier_1_org).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, "reason"))
        Codespaces::Tier.expects(:for_billable_owner).with(tier_2_org).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::NEUTRAL, "reason"))
        Codespaces::Tier.expects(:for_billable_owner).with(tier_3_org).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, "reason"))
        Codespaces::Tier.expects(:for_billable_owner).with(@user).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, "reason"))

        Codespaces::Tier.for_user(@user)

        increments = GitHub.dogstats.increments("codespaces.tier.for_user.cache")
        assert_equal 1, increments.size
        assert_equal true, increments.first.tags.include?("result:miss")

        assert_equal 1, GitHub.dogstats.distributions("codespaces.tier.for_user.billable_owners.size").size
        assert_equal 5, GitHub.dogstats.distributions("codespaces.tier.for_user.billable_owners.size").first.value
      end

      test "returns tier 1 if given all tiers" do
        tier_1_org = create(:codespaces_credit_card_organization, admin: @user)
        another_tier_1_org = create(:codespaces_credit_card_organization, admin: @user)
        tier_2_org = create(:codespaces_credit_card_organization, admin: @user)
        tier_3_org = create(:codespaces_credit_card_organization, admin: @user)
        [tier_1_org, another_tier_1_org, tier_2_org, tier_3_org].each do |org|
          Codespaces::OrgPolicy.grant_billing_permission!(@user, org)
        end
        Codespaces::Tier.expects(:for_billable_owner).with(tier_1_org).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, "reason"))
        Codespaces::Tier.expects(:for_billable_owner).with(another_tier_1_org).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, "reason"))
        Codespaces::Tier.expects(:for_billable_owner).with(tier_2_org).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::NEUTRAL, "reason"))
        Codespaces::Tier.expects(:for_billable_owner).with(tier_3_org).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, "reason"))
        Codespaces::Tier.expects(:for_billable_owner).with(@user).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, "reason"))
        assert_equal(Codespaces::Tier.for_user(@user), TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, "reason"))
      end

      test "returns tier 2 if given 2 and 3" do
        tier_2_org = create(:codespaces_credit_card_organization, admin: @user)
        tier_3_org = create(:codespaces_credit_card_organization, admin: @user)
        another_tier_3_org = create(:codespaces_credit_card_organization, admin: @user)
        [tier_2_org, tier_3_org, another_tier_3_org].each do |org|
          Codespaces::OrgPolicy.grant_billing_permission!(@user, org)
        end
        Codespaces::Tier.expects(:for_billable_owner).with(tier_2_org).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::NEUTRAL, "reason"))
        Codespaces::Tier.expects(:for_billable_owner).with(tier_3_org).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, "reason"))
        Codespaces::Tier.expects(:for_billable_owner).with(another_tier_3_org).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, "reason"))
        Codespaces::Tier.expects(:for_billable_owner).with(@user).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, "reason"))
        assert_equal(Codespaces::Tier.for_user(@user), TrustTiers::TierResult.new(TrustTiers::Tier::NEUTRAL, "reason"))
      end

      test "returns tier 3 if given tier 3" do
        tier_3_org = create(:codespaces_credit_card_organization, admin: @user)
        another_tier_3_org = create(:codespaces_credit_card_organization, admin: @user)
        [tier_3_org, another_tier_3_org].each do |org|
          Codespaces::OrgPolicy.grant_billing_permission!(@user, org)
        end
        Codespaces::Tier.expects(:for_billable_owner).with(tier_3_org).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, "reason"))
        Codespaces::Tier.expects(:for_billable_owner).with(another_tier_3_org).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, "reason"))
        Codespaces::Tier.expects(:for_billable_owner).with(@user).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, "reason"))
        assert_equal(Codespaces::Tier.for_user(@user), TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, "reason"))
      end

      test "returns cached value if present" do
        GitHub.stubs(:dogstats).at_least_once.returns(GitHub::MemoryDogstatsD.new)

        mock_tier_result = TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, "reason")
        Codespaces::UserTierCache.set(user_id: @user.id, tier_result: mock_tier_result)
        Codespaces::Tier.expects(:for_billable_owner).never

        result = Codespaces::Tier.for_user(@user)

        increments = GitHub.dogstats.increments("codespaces.tier.for_user.cache")
        assert_equal 1, increments.size
        assert_equal true, increments.first.tags.include?("result:hit")

        assert_equal mock_tier_result.tier, result.tier
        assert_equal mock_tier_result.reason, result.reason
      end

      test "caches the user tier after calculation" do
        org = create(:codespaces_credit_card_organization)
        org.add_member(@user)
        Codespaces::OrgPolicy.grant_billing_permission!(@user, org)

        mock_tier_result = TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, "reason")

        Codespaces::Tier.expects(:for_billable_owner).with(org).at_least_once.returns(mock_tier_result)
        Codespaces::Tier.expects(:for_billable_owner).with(@user).at_least_once.returns(mock_tier_result)

        Codespaces::UserTierCache.expects(:set).with(user_id: @user.id, tier_result: mock_tier_result)

        Codespaces::Tier.for_user(@user)
      end

      test "locked cache write handles gracefully" do
        stub_trust_tier = TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, TrustTiers::TierResult::USER)
        Codespaces::Tier.expects(:for_billable_owner).with(@user).at_least_once.returns(stub_trust_tier)

        Codespaces::UserTierCache.expects(:set).never

        # Fake someone else locking the cache write
        key = Codespaces::UserTierCache.key(user_id: @user.id)
        mutex = GitHub::Redis::ConcurrencySafeMutex.new(key)
        result = mutex.lock do
          Codespaces::Tier.for_user(@user)
        end

        assert_equal stub_trust_tier, result
      end

      test "only uses orgs the user is able to bill codespaces to; org member but not allowed to bill codespaces" do
        org = create(:team_org)
        org.add_member(@user)
        Codespaces::Tier.expects(:for_billable_owner).with(@user).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, "reason"))
        Codespaces::Tier.expects(:for_billable_owner).with(org).at_most_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, "reason"))
        assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, "reason"), Codespaces::Tier.for_user(@user)
      end

      test "only uses orgs the user is able to bill codespaces to; org outside-collaborator but not allowed to bill codespaces" do
        org = create(:team_org)
        repo = create(:repository, owner: org)
        repo.add_member(@user)
        Codespaces::Tier.expects(:for_billable_owner).with(@user).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, "reason"))
        Codespaces::Tier.expects(:for_billable_owner).with(org).at_most_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, "reason"))
        assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, "reason"), Codespaces::Tier.for_user(@user)
      end

      test "only uses orgs the user is able to bill codespaces to; business member but not allowed to bill codespaces" do
        business = create(:business)
        org = create(:team_org)
        business.add_organization(org)
        org.add_member(@user)
        Codespaces::Tier.expects(:for_billable_owner).with(@user).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, "reason"))
        Codespaces::Tier.expects(:for_billable_owner).with(org).at_most_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, "reason"))
        Codespaces::Tier.expects(:for_billable_owner).with(business).at_most_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, "reason"))
        assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, "reason"), Codespaces::Tier.for_user(@user)
      end

      test "only uses orgs the user is able to bill codespaces to; org member and allowed to bill codespaces" do
        org = create(:codespaces_credit_card_organization)
        org.add_member(@user)
        Codespaces::OrgPolicy.grant_billing_permission!(@user, org)
        Codespaces::Tier.expects(:for_billable_owner).with(@user).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, "reason"))
        Codespaces::Tier.expects(:for_billable_owner).with(org).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, "reason"))
        assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, "reason"), Codespaces::Tier.for_user(@user)
      end

      test "only uses orgs the user is able to bill codespaces to; outside collaborator and allowed to bill codespaces" do
        org = create(:codespaces_credit_card_organization)
        repo = create(:repository, owner: org)
        repo.add_member(@user)
        Codespaces::OrgPolicy.grant_billing_permission!(@user, org)
        Codespaces::Tier.expects(:for_billable_owner).with(@user).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, "reason"))
        Codespaces::Tier.expects(:for_billable_owner).with(org).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, "reason"))
        assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, "reason"), Codespaces::Tier.for_user(@user)
      end

      test "only uses orgs the user is able to bill codespaces to; org member and allowed to bill codespaces gets business's tier" do
        business = create(:business)
        org = create(:codespaces_credit_card_organization)
        business.add_organization(org)
        org.add_member(@user)
        Codespaces::OrgPolicy.grant_billing_permission!(@user, org)
        Codespaces::Tier.expects(:for_billable_owner).with(@user).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, "reason"))
        Codespaces::Tier.expects(:for_billable_owner).with(org).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, "reason"))
        Codespaces::Tier.expects(:for_billable_owner).with(business).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, "reason"))
        assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, "reason"), Codespaces::Tier.for_user(@user)
      end

      test "orgs used for final tier result are logged" do
        business = create(:business, name: "business1")
        org1 = create(:codespaces_credit_card_organization, login: "org1")
        org2 = create(:codespaces_credit_card_organization, login: "org2")
        org3 = create(:codespaces_credit_card_organization, login: "org3")
        org4 = create(:codespaces_credit_card_organization, login: "org4")
        business.add_organization(org3)
        [org1, org2, org3, org4].each do |org|
          org.add_member(@user)
          Codespaces::OrgPolicy.grant_billing_permission!(@user, org)
        end
        Codespaces::Tier.expects(:for_billable_owner).with(@user).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, "reason"))
        Codespaces::Tier.expects(:for_billable_owner).with(org1).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, "reason"))
        Codespaces::Tier.expects(:for_billable_owner).with(org2).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, "reason"))
        Codespaces::Tier.expects(:for_billable_owner).with(org3).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, "reason"))
        Codespaces::Tier.expects(:for_billable_owner).with(org4).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, "reason"))
        Codespaces::Tier.expects(:for_billable_owner).with(business).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, "reason"))
        GitHub.logger.expects(:info).with(
          "Codespaces tier calculation results",
          "gh.user.login" => @user.login,
          "gh.codespaces.user_tier" => 1,
          "gh.codespaces.calculated_tier" => 1,
          "gh.codespaces.tier_deciding_logins" => ["org:org1", "org:org2", "business:business1", "user:#{@user.login}"].sort,
          "gh.codespaces.nonspendable_tier_deciding_logins" => ["org:org1", "org:org2"].sort,
          "code.namespace" => "Codespaces::Tier",
          "code.function" => "for_user",
        )
        GitHub.logger.stubs(:info).with(anything, Not(equals({
          "gh.user.login" => @user.login,
          "gh.codespaces.user_tier" => 1,
          "gh.codespaces.calculated_tier" => 1,
          "gh.codespaces.tier_deciding_logins" => ["org:org1", "org:org2", "business:business1", "user:#{@user.login}"].sort,
          "gh.codespaces.nonspendable_tier_deciding_logins" => ["org:org1", "org:org2"].sort,
          "code.namespace" => "Codespaces::Tier",
          "code.function" => "for_user",
        })))
        assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, "reason"), Codespaces::Tier.for_user(@user)
      end

      test "emits codespaces_trust_tier_calculated event" do
        business = create(:business, name: "business1")
        org1 = create(:codespaces_credit_card_organization, login: "org1")
        org2 = create(:codespaces_credit_card_organization, login: "org2")
        org3 = create(:codespaces_credit_card_organization, login: "org3")
        org4 = create(:codespaces_credit_card_organization, login: "org4")
        business.add_organization(org3)
        [org1, org2, org3, org4].each do |org|
          org.add_member(@user)
          Codespaces::OrgPolicy.grant_billing_permission!(@user, org)
        end
        Codespaces::Tier.expects(:for_billable_owner).with(@user).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, "reason"))
        Codespaces::Tier.expects(:for_billable_owner).with(org1).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, "reason"))
        Codespaces::Tier.expects(:for_billable_owner).with(org2).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, "reason"))
        Codespaces::Tier.expects(:for_billable_owner).with(org3).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, "reason"))
        Codespaces::Tier.expects(:for_billable_owner).with(org4).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, "reason"))
        Codespaces::Tier.expects(:for_billable_owner).with(business).at_least_once.returns(TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, "reason"))

        message = {
          actor: Hydro::EntitySerializer.user(@user),
          calculated_trust_tier: 1,
          tier_deciding_accounts: ["org:org1", "org:org2", "business:business1", "user:#{@user.login}"].sort,
        }

        Codespaces::Tier.for_user(@user)
        assert_hydro_published(message, schema: "github.codespaces.v0.CodespacesTrustTierCalculated")
      end

      context "multi-tenant enterprise" do
        test "returns tier 1 for proxima users less than 30 days old" do
          on_multi_tenant_enterprise(tenant: @business) do
            emu = create :emu
            assert_equal(Codespaces::Tier.for_user(emu), TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::BUSINESS_OR_INVOICED))
          end
        end

        test "returns tier 1 for proxima users more than 30 days old and are not system/admin users" do
          on_multi_tenant_enterprise(tenant: @business) do
            emu = create :emu
            Timecop.travel(TrustTiers::TierDetails::NEUTRAL_FREE_AGE_LIMIT) do
              assert_equal(Codespaces::Tier.for_user(emu), TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::BUSINESS_OR_INVOICED))
            end
          end
        end

        test "returns tier 1 for proxima users more than 30 days old and are are system or admin users that don't belong to an EMU business" do
          on_multi_tenant_enterprise(tenant: @business) do
            Timecop.travel(TrustTiers::TierDetails::NEUTRAL_FREE_AGE_LIMIT) do
              assert_equal(Codespaces::Tier.for_user(@emu), TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::BUSINESS_OR_INVOICED))
            end
          end
        end

        test "returns tier 1 for proxima users less than 30 days old and are are system or admin users that don't belong to an EMU business" do
          on_multi_tenant_enterprise(tenant: @business) do
            assert_equal(Codespaces::Tier.for_user(@emu), TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::BUSINESS_OR_INVOICED))
          end
        end
      end

      context "Enterprise managed users" do
        test "returns tier 1 for emu less than 30 days old" do
          assert_equal(Codespaces::Tier.for_user(@emu), TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::BUSINESS_OR_INVOICED))
        end

        test "returns tier 1 for emu more than 30 days old" do
          Timecop.travel(TrustTiers::TierDetails::NEUTRAL_FREE_AGE_LIMIT) do
            assert_equal(Codespaces::Tier.for_user(@emu), TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::BUSINESS_OR_INVOICED))
          end
        end
      end
    end

    context "#config_for_tier" do
      test "returns config for tier 1" do
        config = Codespaces::Tier.config_for_tier(TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, "reason"), @user)
        assert_equal config.codespaces_per_user, 30
        assert_equal config.concurrent_cores, 64
        assert_equal config.concurrent_codespaces, 5
      end

      test "returns config for tier 2" do
        config = Codespaces::Tier.config_for_tier(TrustTiers::TierResult.new(TrustTiers::Tier::NEUTRAL, "reason"), @user)
        assert_equal config.codespaces_per_user, 30
        assert_equal config.concurrent_cores, 16
        assert_equal config.concurrent_codespaces, 2
      end

      test "returns config for tier 3" do
        config = Codespaces::Tier.config_for_tier(TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, "reason"), @user)
        assert_equal config.codespaces_per_user, 30
        assert_equal config.concurrent_cores, 16
        assert_equal config.concurrent_codespaces, 2
      end

      test "validates CODESPACES_PER_USER" do
        assert_equal Codespaces::Tier::CODESPACES_PER_USER, 30
      end
    end

    context "#billable_enterprise_managed_business" do
      test "return nil when actor doesn't respond to is_enterprise_managed?" do
        assert_nil Codespaces::Tier.billable_enterprise_managed_business(@business)
      end

      test "return business when in multi-tenant mode" do
        on_multi_tenant_enterprise(tenant: @business) do
          assert_equal @business, Codespaces::Tier.billable_enterprise_managed_business(@emu)
        end
      end

      test "returns business not in multi-tenant mode" do
        assert_equal @business, Codespaces::Tier.billable_enterprise_managed_business(@emu)
      end
    end
  end
end
