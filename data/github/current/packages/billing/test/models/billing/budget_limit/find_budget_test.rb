# typed: true
# frozen_string_literal: true

require "test_helper"

class FindBudgetTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @known_user = create(:user, created_at: TrustTiers::TierDetails::NEUTRAL_FREE_AGE_LIMIT.ago - 1.day)
    @new_user = create(:user, created_at: TrustTiers::TierDetails::NEUTRAL_PAID_OR_COUPONED_AGE_LIMIT.ago + 1.day)

    @neutral_paid_user = create(:user, created_at: TrustTiers::TierDetails::NEUTRAL_PAID_OR_COUPONED_AGE_LIMIT.ago - 1.day)
    @neutral_couponed_user = create(:user, created_at: TrustTiers::TierDetails::NEUTRAL_PAID_OR_COUPONED_AGE_LIMIT.ago - 1.day)

    @neutral_couponed_user = create(:user, created_at: TrustTiers::TierDetails::TRUSTED_COUPONED_AGE_LIMIT.ago + 1.day)
    @trusted_couponed_user = create(:user, created_at: TrustTiers::TierDetails::TRUSTED_COUPONED_AGE_LIMIT.ago - 1.day)

    @educational_coupon = create(:coupon, group: Coupon::EDUCATION_GROUP_NAMES.first)
    @non_educational_coupon = create(:coupon, group: "internal")
  end

  if GitHub.enterprise?
    test "trusted for all users" do
      result = TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::GITHUB_ENTERPRISE)
      assert_equal result, TrustTiers::Tier.for_billable_owner(@new_user.reload)
      assert_equal ["GitHub Enterprise"], result.verbose_reason
    end
  end

  context "#for_billable_owner", skip_enterprise: true do
    # **************** TRUSTED ****************
    # * Sales serve accounts (invoiced Organization or Enterprise)
    #    *************   OR    *************
    # * Accounts with established billing history
    #     * Most recent payment was successful
    #     * One successful payment at least two months ago
    #    *************   OR    *************
    # * Oldest account owner > 14 days old AND has eligible coupon
    context "TRUSTED" do
      test "returns TRUSTED if the billing plan owner is an Enterprise Account" do
        org = create(:enterprise_linked_organization)
        assert_equal Billing::BudgetLimit::FindBudget::TRUSTED_TIER_SPENDING_LIMIT, Billing::BudgetLimit::FindBudget.for_account(org.reload, false)
      end

      test "returns TRUSTED if the billing plan owner is invoiced" do
        org = create(:invoiced_organization, plan: "business_plus")
        assert_equal Billing::BudgetLimit::FindBudget::TRUSTED_TIER_SPENDING_LIMIT, Billing::BudgetLimit::FindBudget.for_account(org.reload, false)
      end

      test "returns TRUSTED if account is older than limit and has non-educational coupon" do
        org = create(:business_plus_organization, admin: @trusted_couponed_user)
        org.redeem_coupon(@non_educational_coupon)
        assert_equal Billing::BudgetLimit::FindBudget::TRUSTED_TIER_SPENDING_LIMIT, Billing::BudgetLimit::FindBudget.for_account(org.reload, true)
      end

      test "does not return TRUSTED if account has non-educational coupon but is younger than the limit" do
        org = create(:business_plus_organization, admin: @neutral_couponed_user)
        org.redeem_coupon(@non_educational_coupon)
        refute_equal Billing::BudgetLimit::FindBudget::TRUSTED_TIER_SPENDING_LIMIT, Billing::BudgetLimit::FindBudget.for_account(org.reload, false)
      end

      test "returns TRUSTED if account has established billing history" do
        org = create(:team_org, admins: [@known_user])
        create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, created_at: 10.days.ago)
        create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, created_at: 66.days.ago)

        assert_equal Billing::BudgetLimit::FindBudget::TRUSTED_TIER_SPENDING_LIMIT, Billing::BudgetLimit::FindBudget.for_account(org.reload, false)
      end

      test "does not return TRUSTED if only billing has been zero cents" do
        org = create(:team_org, admins: [@known_user])
        create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, amount_in_cents: 0, created_at: 10.days.ago)
        create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, amount_in_cents: 0, created_at: 36.days.ago)

        refute_equal Billing::BudgetLimit::FindBudget::TRUSTED_TIER_SPENDING_LIMIT, Billing::BudgetLimit::FindBudget.for_account(org.reload, false)
      end

      test "does not return TRUSTED if only billing has been refunded" do
        org = create(:team_org, admins: [@known_user])
        create(:billing_transaction, :zuora, :refunded_sale, user: org, asset_packs_total: 5, created_at: 10.days.ago)
        create(:billing_transaction, :zuora, :refunded_sale, user: org, asset_packs_total: 5, created_at: 39.days.ago)

        refute_equal Billing::BudgetLimit::FindBudget::TRUSTED_TIER_SPENDING_LIMIT, Billing::BudgetLimit::FindBudget.for_account(org.reload, false)
      end

      test "does not return TRUSTED if billing is out of previous billing period" do
        org = create(:team_org, admins: [@known_user])
        create(:billing_transaction, :zuora, :refunded_sale, user: org, asset_packs_total: 5, created_at: 10.days.ago)
        create(:billing_transaction, :zuora, :refunded_sale, user: org, asset_packs_total: 5, created_at: 89.days.ago)

        refute_equal Billing::BudgetLimit::FindBudget::TRUSTED_TIER_SPENDING_LIMIT, Billing::BudgetLimit::FindBudget.for_account(org.reload, false)
      end

      test "not TRUSTED if only owner was created less than limit" do
        org = create(:team_org, admins: [@known_user])
        refute_equal Billing::BudgetLimit::FindBudget::TRUSTED_TIER_SPENDING_LIMIT, Billing::BudgetLimit::FindBudget.for_account(org.reload, false)
      end

      test "not TRUSTED if enterprise trial" do
        org = create(:business_plus_organization, admins: [@known_user])
        Billing::EnterpriseCloudTrial.new(org).create
        refute_equal Billing::BudgetLimit::FindBudget::TRUSTED_TIER_SPENDING_LIMIT, Billing::BudgetLimit::FindBudget.for_account(org.reload, false)
      end

      test "not TRUSTED if free org" do
        org = create(:free_org, admins: [@known_user], plan: GitHub::Plan.free)
        refute_equal Billing::BudgetLimit::FindBudget::TRUSTED_TIER_SPENDING_LIMIT, Billing::BudgetLimit::FindBudget.for_account(org.reload, false)
      end
    end

  end
end
