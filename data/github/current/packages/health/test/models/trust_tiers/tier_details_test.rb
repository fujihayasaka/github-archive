# typed: true
# frozen_string_literal: true

require "test_helper"

class TierDetailsTest < GitHub::TestCase
  fixtures do
    @educational_coupon = create(:coupon, group: Coupon::EDUCATION_GROUP_NAMES.first)
    @non_educational_coupon = create(:coupon, group: "internal")
  end

  context "coupon details" do
    test "returns false if the account has a Pro plan and the coupon is educational" do
      account = create(:user, plan: "pro")
      account.redeem_coupon(@educational_coupon)
      details = TrustTiers::TierDetails.new(account)
      refute_predicate details, :has_eligible_coupon?
    end

    test "returns true if the account has a Pro plan and the coupon is not educational" do
      account = create(:user, plan: "pro")
      account.redeem_coupon(@non_educational_coupon)
      details = TrustTiers::TierDetails.new(account)
      assert_predicate details, :has_eligible_coupon?
    end

    test "returns true if the account has a non-Pro plan and the coupon is educational" do
      account = create(:business_org)
      account.redeem_coupon(@educational_coupon)
      details = TrustTiers::TierDetails.new(account)
      assert_predicate details, :has_eligible_coupon?
    end

    test "returns false if no coupon is redeemed for this org" do
      account = create(:business_org)
      details = TrustTiers::TierDetails.new(account)
      refute_predicate details, :has_eligible_coupon?
    end
  end

  context "payment details" do
    test "is false for an organization with no billing transactions" do
      org = create(:organization)
      details = TrustTiers::TierDetails.new(org)

      refute details.has_paid_money?
    end

    test "is false for an organization whose only billing transactions were refunded" do
      org = create(:organization)
      create(:billing_transaction, :zuora, :refunded_sale, user: org, asset_packs_total: 5)
      create(:billing_transaction, :zuora, :refunded_sale, user: org, asset_packs_total: 5)
      details = TrustTiers::TierDetails.new(org)

      refute details.has_paid_money?
    end

    test "is false for an organization whose only billing transactions were not successful" do
      org = create(:organization)
      create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, last_status: :failed)
      create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, last_status: :failed)
      details = TrustTiers::TierDetails.new(org)

      refute details.has_paid_money?
    end

    test "is false for an organization whose only billing transactions were for zero cents" do
      org = create(:organization)
      create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, amount_in_cents: 0)
      create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, amount_in_cents: 0)

      details = TrustTiers::TierDetails.new(org)

      refute details.has_paid_money?
    end

    test "is true for an organization who has a billing transaction that was a successful, non-refunded, non-zero charge" do
      org = create(:organization)
      create(:billing_transaction, :zuora, user: org, asset_packs_total: 5)
      create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, last_status: :failed)
      create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, amount_in_cents: 0)
      create(:billing_transaction, :zuora, :refunded_sale, user: org, asset_packs_total: 5)
      details = TrustTiers::TierDetails.new(org)

      assert details.has_paid_money?
    end

    test "is true for an organization that is invoiced" do
      org = create(:invoiced_organization)
      details = TrustTiers::TierDetails.new(org)

      assert details.has_paid_money?
    end
  end

  context "established billing history details" do
    test "is false for an organization whose only billing transactions was yesterday" do
      org = create(:organization)
      create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, created_at: 1.day.ago)
      details = TrustTiers::TierDetails.new(org)

      refute details.has_established_billing_history?
    end

    test "is false for an organization whose only billing transactions was a month ago" do
      org = create(:organization)
      create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, created_at: 1.month.ago)
      details = TrustTiers::TierDetails.new(org)

      refute details.has_established_billing_history?
    end

    test "is true for an organization that has a successful transaction three months back" do
      org = create(:organization)
      create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, created_at: 3.months.ago)
      details = TrustTiers::TierDetails.new(org)

      assert details.has_established_billing_history?
    end

    test "is false for an organization that has a successful transaction three months back, but for zero amount" do
      org = create(:organization)
      create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, amount_in_cents: 0, created_at: 3.months.ago)
      details = TrustTiers::TierDetails.new(org)

      refute details.has_established_billing_history?
    end

    test "is false for an organization that has a successful transaction three months back, but refunded" do
      org = create(:organization)
      create(:billing_transaction, :zuora, :refunded_sale, user: org, asset_packs_total: 5, created_at: 3.months.ago)
      details = TrustTiers::TierDetails.new(org)

      refute details.has_established_billing_history?
    end
  end

  context "plan details" do
    test "returns false for free org" do
      account = create(:free_org)
      details = TrustTiers::TierDetails.new(account)
      refute details.is_paid_plan?
    end

    test "returns false for enterprise trial" do
      account = create(:business_plus_organization)
      Billing::EnterpriseCloudTrial.new(account).create
      details = TrustTiers::TierDetails.new(account)
      refute details.is_paid_plan?
    end

    test "returns true for team org" do
      account = create(:business_org)
      details = TrustTiers::TierDetails.new(account)
      assert details.is_paid_plan?
    end

    test "returns true for ghec org" do
      account = create(:business_plus_organization)
      details = TrustTiers::TierDetails.new(account)
      assert details.is_paid_plan?
    end
  end

  context "trusted couponed age check" do
    test "returns false if owner was created since TRUSTED_COUPONED_AGE_LIMIT.ago" do
      @user = create(:user, created_at: TrustTiers::TierDetails::TRUSTED_COUPONED_AGE_LIMIT.ago + 1.day)
      account = create(:free_org, admins: [@user])
      details = TrustTiers::TierDetails.new(account.reload)
      refute details.oldest_owner_older_than_trusted_couponed_age_limit?
    end

    test "returns true if owner was created before TRUSTED_COUPONED_AGE_LIMIT.ago" do
      @user = create(:user, created_at: TrustTiers::TierDetails::TRUSTED_COUPONED_AGE_LIMIT.ago - 1.day)
      account = create(:free_org, admins: [@user])
      details = TrustTiers::TierDetails.new(account.reload)
      assert details.oldest_owner_older_than_trusted_couponed_age_limit?
    end

    test "returns true if one of the owners was before TRUSTED_COUPONED_AGE_LIMIT.ago" do
      @user = create(:user, created_at: TrustTiers::TierDetails::TRUSTED_COUPONED_AGE_LIMIT.ago - 1.day)
      @user2 = create(:user, created_at: TrustTiers::TierDetails::TRUSTED_COUPONED_AGE_LIMIT.ago + 1.day)
      account = create(:free_org, admins: [@user, @user2])
      details = TrustTiers::TierDetails.new(account.reload)
      assert details.oldest_owner_older_than_trusted_couponed_age_limit?
    end

    test "returns false if owners were created since TRUSTED_COUPONED_AGE_LIMIT.ago" do
      @user = create(:user, created_at: TrustTiers::TierDetails::TRUSTED_COUPONED_AGE_LIMIT.ago + 1.day)
      @user2 = create(:user, created_at: TrustTiers::TierDetails::TRUSTED_COUPONED_AGE_LIMIT.ago + 2.days)
      account = create(:free_org, admins: [@user, @user2])
      details = TrustTiers::TierDetails.new(account.reload)
      refute details.oldest_owner_older_than_trusted_couponed_age_limit?
    end

    test "returns false if no owners" do
      @user = create(:user)
      account = create(:free_org, admins: [@user])
      # mocking empty active record relation
      account.expects(:admins).returns(User.none)
      details = TrustTiers::TierDetails.new(account.reload)
      refute details.oldest_owner_older_than_trusted_couponed_age_limit?
    end
  end

  context "neutral paid/couponed age check" do
    test "returns false if owner was created since NEUTRAL_PAID_OR_COUPONED_AGE_LIMIT.ago" do
      @user = create(:user, created_at: TrustTiers::TierDetails::NEUTRAL_PAID_OR_COUPONED_AGE_LIMIT.ago + 1.day)
      account = create(:free_org, admins: [@user])
      details = TrustTiers::TierDetails.new(account.reload)
      refute details.oldest_owner_older_than_neutral_paid_or_couponed_age_limit?
    end

    test "returns true if owner was created before NEUTRAL_PAID_OR_COUPONED_AGE_LIMIT.ago" do
      @user = create(:user, created_at: TrustTiers::TierDetails::NEUTRAL_PAID_OR_COUPONED_AGE_LIMIT.ago - 1.day)
      account = create(:free_org, admins: [@user])
      details = TrustTiers::TierDetails.new(account.reload)
      assert details.oldest_owner_older_than_neutral_paid_or_couponed_age_limit?
    end

    test "returns true if one of the owners was before NEUTRAL_PAID_OR_COUPONED_AGE_LIMIT.ago" do
      @user = create(:user, created_at: TrustTiers::TierDetails::NEUTRAL_PAID_OR_COUPONED_AGE_LIMIT.ago - 1.day)
      @user2 = create(:user, created_at: TrustTiers::TierDetails::NEUTRAL_PAID_OR_COUPONED_AGE_LIMIT.ago + 1.day)
      account = create(:free_org, admins: [@user, @user2])
      details = TrustTiers::TierDetails.new(account.reload)
      assert details.oldest_owner_older_than_neutral_paid_or_couponed_age_limit?
    end

    test "returns false if owners were created since NEUTRAL_PAID_OR_COUPONED_AGE_LIMIT.ago" do
      @user = create(:user, created_at: TrustTiers::TierDetails::NEUTRAL_PAID_OR_COUPONED_AGE_LIMIT.ago + 1.day)
      @user2 = create(:user, created_at: TrustTiers::TierDetails::NEUTRAL_PAID_OR_COUPONED_AGE_LIMIT.ago + 2.days)
      account = create(:free_org, admins: [@user, @user2])
      details = TrustTiers::TierDetails.new(account.reload)
      refute details.oldest_owner_older_than_neutral_paid_or_couponed_age_limit?
    end

    test "returns false if no owners" do
      @user = create(:user)
      account = create(:free_org, admins: [@user])
      # mocking empty active record relation
      account.expects(:admins).returns(User.none)
      details = TrustTiers::TierDetails.new(account.reload)
      refute details.oldest_owner_older_than_neutral_paid_or_couponed_age_limit?
    end
  end

  context "neutral free account age check" do
    test "returns false if owner was created since NEUTRAL_FREE_AGE_LIMIT.ago" do
      @user = create(:user, created_at: TrustTiers::TierDetails::NEUTRAL_FREE_AGE_LIMIT.ago + 1.day)
      account = create(:free_org, admins: [@user])
      details = TrustTiers::TierDetails.new(account.reload)
      refute details.oldest_owner_older_than_neutral_free_age_limit?
    end

    test "returns true if owner was created before NEUTRAL_FREE_AGE_LIMIT.ago" do
      @user = create(:user, created_at: TrustTiers::TierDetails::NEUTRAL_FREE_AGE_LIMIT.ago - 1.day)
      account = create(:free_org, admins: [@user])
      details = TrustTiers::TierDetails.new(account.reload)
      assert details.oldest_owner_older_than_neutral_free_age_limit?
    end

    test "returns true if one of the owners was before NEUTRAL_FREE_AGE_LIMIT.ago" do
      @user = create(:user, created_at: TrustTiers::TierDetails::NEUTRAL_FREE_AGE_LIMIT.ago - 1.day)
      @user2 = create(:user, created_at: TrustTiers::TierDetails::NEUTRAL_FREE_AGE_LIMIT.ago + 1.day)
      account = create(:free_org, admins: [@user, @user2])
      details = TrustTiers::TierDetails.new(account.reload)
      assert details.oldest_owner_older_than_neutral_free_age_limit?
    end

    test "returns false if owners were created since NEUTRAL_FREE_AGE_LIMIT.ago" do
      @user = create(:user, created_at: TrustTiers::TierDetails::NEUTRAL_FREE_AGE_LIMIT.ago + 1.day)
      @user2 = create(:user, created_at: TrustTiers::TierDetails::NEUTRAL_FREE_AGE_LIMIT.ago + 2.days)
      account = create(:free_org, admins: [@user, @user2])
      details = TrustTiers::TierDetails.new(account.reload)
      refute details.oldest_owner_older_than_neutral_free_age_limit?
    end

    test "returns false if no owners" do
      @user = create(:user)
      account = create(:free_org, admins: [@user])
      # mocking empty active record relation
      account.expects(:admins).returns(User.none)
      details = TrustTiers::TierDetails.new(account.reload)
      refute details.oldest_owner_older_than_neutral_free_age_limit?
    end
  end

  context "multiple owner age details" do
    test "returns nil if no owners" do
      @user = create(:user)
      account = create(:free_org, admins: [@user])
      # mocking empty active record relation
      account.expects(:admins).returns(User.none)
      details = TrustTiers::TierDetails.new(account.reload)
      assert_nil details.oldest_owner_age
    end

    test "returns single owner created_at if 1 owners" do
      @user = create(:user)
      account = create(:free_org, admins: [@user])
      details = TrustTiers::TierDetails.new(account.reload)
      assert_equal @user.created_at, details.oldest_owner_age
    end

    test "returns oldest owner created_at if 2 owners" do
      @user = create(:user, created_at: 1.day.ago)
      @user2 = create(:user, created_at: 2.days.ago)
      account = create(:free_org, admins: [@user, @user2])
      details = TrustTiers::TierDetails.new(account.reload)
      assert_equal @user2.created_at, details.oldest_owner_age
    end
  end

  context "last payment failed details" do
    test "is false for an organization whose most recent billing transaction failed" do
      org = create(:organization)
      create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, created_at: 65.days.ago)
      create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, created_at: 35.days.ago)
      create(:billing_transaction, :failed, :zuora, user: org, asset_packs_total: 5, created_at: 5.days.ago)
      details = TrustTiers::TierDetails.new(org)

      refute details.last_payment_failed?
    end

    test "is true for an organization whose most recent billing transaction succeeded" do
      org = create(:organization)
      create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, created_at: 5.days.ago)
      details = TrustTiers::TierDetails.new(org)

      refute details.last_payment_failed?
    end

    test "is true for an business whose most recent billing transaction failed" do
      GitHub.flipper[:billing_update_trust_tier_rules].enable
      business = create(:business, customer: create(:customer, billing_attempts: 1))

      details = TrustTiers::TierDetailsV2.new(business)

      assert details.last_payment_failed?
    end

    test "is false for an business whose most recent billing transaction succeeded" do
      GitHub.flipper[:billing_update_trust_tier_rules].enable
      business = create(:business)
      create(:billing_transaction, :zuora, customer: business.customer, asset_packs_total: 5, created_at: 5.days.ago)
      details = TrustTiers::TierDetailsV2.new(business)

      refute details.last_payment_failed?
    end
  end
end
