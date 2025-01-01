# typed: true
# frozen_string_literal: true

require "test_helper"

class TierDetailsV2Test < GitHub::TestCase
  fixtures do
    @educational_coupon = create(:coupon, group: Coupon::EDUCATION_GROUP_NAMES.first)
    @non_educational_coupon = create(:coupon, group: "internal")
    enable_feature_flag(:org_upgraded_trust_tiers_v2)
    enable_feature_flag(:org_upgraded_trust_tiers_v2_5)
  end

  if !GitHub.single_tenant_enterprise?
    context "has_eligible_coupon?" do
      test "returns false if the account has a Pro plan and the coupon is educational" do
        account = create(:user, plan: "pro")
        assert account.redeem_coupon(@educational_coupon)
        details = TrustTiers::TierDetailsV2.new(account)
        refute_predicate details, :has_eligible_coupon?
      end

      test "returns true if the account has a Pro plan and the coupon is not educational" do
        account = create(:user, plan: "pro")
        assert account.redeem_coupon(@non_educational_coupon)
        details = TrustTiers::TierDetailsV2.new(account)
        assert_predicate details, :has_eligible_coupon?
      end

      test "returns true if the account has a non-Pro plan and the coupon is educational" do
        account = create(:business_org)
        assert account.redeem_coupon(@educational_coupon)
        details = TrustTiers::TierDetailsV2.new(account)
        assert_predicate details, :has_eligible_coupon?
      end

      test "returns false if no coupon is redeemed for this org" do
        account = create(:business_org)
        details = TrustTiers::TierDetailsV2.new(account)
        refute_predicate details, :has_eligible_coupon?
      end

      test "returns false if the account is a business and no coupon is redeemed" do
        owner = create(:user)
        account = create(:business, owners: [owner])
        details = TrustTiers::TierDetailsV2.new(account)
        refute_predicate details, :has_eligible_coupon?
      end

      test "returns true if the account is a business and a coupon is redeemed" do
        owner = create(:user)
        account = create(:business, owners: [owner])
        # coupons can only be redeemed by self-serve accounts, i.e. billing type card
        account.customer.update(billing_type: Customer::BILLING_TYPE_CARD)
        assert account.redeem_coupon(@non_educational_coupon, actor: owner)
        details = TrustTiers::TierDetailsV2.new(account)
        assert_predicate details, :has_eligible_coupon?
      end
    end

    context "has_paid_money?" do
      test "is false for an account with no billing transactions" do
        org = create(:organization)
        details = TrustTiers::TierDetailsV2.new(org)

        refute details.has_paid_money?
      end

      test "is false for an account whose only billing transactions were refunded" do
        org = create(:organization)
        create(:billing_transaction, :zuora, :refunded_sale, user: org, asset_packs_total: 5)
        create(:billing_transaction, :zuora, :refunded_sale, user: org, asset_packs_total: 5)
        details = TrustTiers::TierDetailsV2.new(org)

        refute details.has_paid_money?
      end

      test "is false for an account whose only billing transactions were not successful" do
        org = create(:organization)
        create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, last_status: :failed)
        create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, last_status: :failed)
        details = TrustTiers::TierDetailsV2.new(org)

        refute details.has_paid_money?
      end

      test "is false for an account whose only billing transactions were for zero cents" do
        org = create(:organization)
        create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, amount_in_cents: 0)
        create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, amount_in_cents: 0)

        details = TrustTiers::TierDetailsV2.new(org)

        refute details.has_paid_money?
      end

      test "is true for an account who has a billing transaction that was a successful, non-refunded, non-zero charge" do
        org = create(:organization)
        create(:billing_transaction, :zuora, user: org, asset_packs_total: 5)
        create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, last_status: :failed)
        create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, amount_in_cents: 0)
        create(:billing_transaction, :zuora, :refunded_sale, user: org, asset_packs_total: 5)
        details = TrustTiers::TierDetailsV2.new(org)

        assert details.has_paid_money?
      end

      test "is true for an account that is invoiced" do
        org = create(:invoiced_organization)
        details = TrustTiers::TierDetailsV2.new(org)

        assert details.has_paid_money?
      end

      test "is false for a self-serve business with no billing transactions" do
        business = create(:business, :with_self_serve_payment)
        details = TrustTiers::TierDetailsV2.new(business)

        refute details.has_paid_money?
      end

      test "is false for a self-serve business with only zero cent and refunded billing transactions" do
        business = create(:business, :with_self_serve_payment)
        create(:billing_transaction, :zuora, :refunded_sale, customer: business.customer, asset_packs_total: 5)
        create(:billing_transaction, :zuora, customer: business.customer, asset_packs_total: 5, amount_in_cents: 0)
        details = TrustTiers::TierDetailsV2.new(business)

        refute details.has_paid_money?
      end

      test "is false for a self-serve business with no billing transactions upgraded from an organization with no billing transactions" do
        org = create(:organization)
        business = create(:business, :with_self_serve_payment, upgraded_from: org)
        details = TrustTiers::TierDetailsV2.new(business)

        refute details.has_paid_money?
      end

      test "is false for a self-serve business with no billing transactions upgraded from an organization with only zero cent and refunded billing transactions" do
        org = create(:organization)
        create(:billing_transaction, :zuora, :refunded_sale, user: org, asset_packs_total: 5)
        create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, amount_in_cents: 0)
        business = create(:business, :with_self_serve_payment, upgraded_from: org)
        details = TrustTiers::TierDetailsV2.new(business)

        refute details.has_paid_money?
      end

      test "is false for a self-serve business with only zero cent and refunded billing transactions upgraded from an organization with no billing transactions" do
        org = create(:organization)
        business = create(:business, :with_self_serve_payment, upgraded_from: org)
        create(:billing_transaction, :zuora, :refunded_sale, customer: business.customer, asset_packs_total: 5)
        create(:billing_transaction, :zuora, customer: business.customer, asset_packs_total: 5, amount_in_cents: 0)
        details = TrustTiers::TierDetailsV2.new(business)

        refute details.has_paid_money?
      end

      test "is false for a self-serve business with no billing transactions upgraded from an organization with a successful billing transaction when ff is disabled" do
        disable_feature_flag(:org_upgraded_trust_tiers_v2)
        org = create(:organization)
        create(:billing_transaction, :zuora, user: org, asset_packs_total: 5)
        business = create(:business, :with_self_serve_payment, upgraded_from: org)
        details = TrustTiers::TierDetailsV2.new(business)

        refute details.has_paid_money?
      end

      test "is true for a self-serve business with a successful billing transaction" do
        business = create(:business, :with_self_serve_payment)
        create(:billing_transaction, :zuora, customer: business.customer, asset_packs_total: 5)
        details = TrustTiers::TierDetailsV2.new(business)

        assert details.has_paid_money?
      end

      test "is true for a self-serve business with a successful billing transaction upgraded from an organization with no billing transactions" do
        org = create(:organization)
        business = create(:business, :with_self_serve_payment, upgraded_from: org)
        create(:billing_transaction, :zuora, customer: business.customer, asset_packs_total: 5)
        details = TrustTiers::TierDetailsV2.new(business)

        assert details.has_paid_money?
      end

      test "is true for a self-serve business with no billing transactions upgraded from an organization with a successful billing transaction" do
        org = create(:organization)
        create(:billing_transaction, :zuora, user: org, asset_packs_total: 5)
        business = create(:business, :with_self_serve_payment, upgraded_from: org)
        details = TrustTiers::TierDetailsV2.new(business)

        assert details.has_paid_money?
      end

      test "is true for a self-serve business with a successful billing transaction upgraded from an organization with a successful billing transaction" do
        org = create(:organization)
        create(:billing_transaction, :zuora, user: org, asset_packs_total: 5)
        business = create(:business, :with_self_serve_payment, upgraded_from: org)
        create(:billing_transaction, :zuora, customer: business.customer, asset_packs_total: 5)
        details = TrustTiers::TierDetailsV2.new(business)

        assert details.has_paid_money?
      end
    end

    context "has_established_billing_history?" do
      test "is false for an organization with no billing history" do
        org = create(:organization)
        details = TrustTiers::TierDetailsV2.new(org)

        refute details.has_established_billing_history?
      end

      test "is false for an organization whose only billing transactions was yesterday" do
        org = create(:organization)
        create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, created_at: 1.day.ago)
        details = TrustTiers::TierDetailsV2.new(org)

        refute details.has_established_billing_history?
      end

      test "is false for an organization whose only billing transactions was a month ago" do
        org = create(:organization)
        create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, created_at: 1.month.ago)
        details = TrustTiers::TierDetailsV2.new(org)

        refute details.has_established_billing_history?
      end

      test "is true for an organization that has a successful transaction three months back" do
        org = create(:organization)
        create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, created_at: 3.months.ago)
        details = TrustTiers::TierDetailsV2.new(org)

        assert details.has_established_billing_history?
      end

      test "is false for an organization that has a successful transaction three months back, but for zero amount" do
        org = create(:organization)
        create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, amount_in_cents: 0, created_at: 3.months.ago)
        details = TrustTiers::TierDetailsV2.new(org)

        refute details.has_established_billing_history?
      end

      test "is false for an organization that has a successful transaction three months back, but refunded" do
        org = create(:organization)
        create(:billing_transaction, :zuora, :refunded_sale, user: org, asset_packs_total: 5, created_at: 3.months.ago)
        details = TrustTiers::TierDetailsV2.new(org)

        refute details.has_established_billing_history?
      end

      test "is false for a self-serve business that has no billing transactions" do
        business = create(:business, :with_self_serve_payment)
        details = TrustTiers::TierDetailsV2.new(business)

        refute details.has_established_billing_history?
      end

      test "is false for a self-serve business that has no billing transactions and is upgraded from an organization with no billing transactions" do
        org = create(:organization)
        business = create(:business, :with_self_serve_payment, upgraded_from: org)
        details = TrustTiers::TierDetailsV2.new(business)

        refute details.has_established_billing_history?
      end

      test "is false for a self-serve business with billing transactions less than two months old and is upgraded from an organization with no billing transactions" do
        org = create(:organization)
        business = create(:business, :with_self_serve_payment, upgraded_from: org)
        create(:billing_transaction, :zuora, customer: business.customer, asset_packs_total: 5, created_at: 1.month.ago)
        details = TrustTiers::TierDetailsV2.new(business)

        refute details.has_established_billing_history?
      end

      test "is false for a self-serve business with no billing transactions and is upgraded from an organization with billing transactions less than two months old" do
        org = create(:organization)
        create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, created_at: 1.month.ago)
        business = create(:business, :with_self_serve_payment, upgraded_from: org)
        details = TrustTiers::TierDetailsV2.new(business)

        refute details.has_established_billing_history?
      end

      test "is false for a self-serve business with no billing transactions and is upgraded from an organization whose only billing transactions are zero cents and more than two months old" do
        org = create(:organization)
        create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, amount_in_cents: 0, created_at: 3.months.ago)
        business = create(:business, :with_self_serve_payment, upgraded_from: org)
        details = TrustTiers::TierDetailsV2.new(business)

        refute details.has_established_billing_history?
      end

      test "is false for a self-serve business with no billing transactions and is upgraded from an organization whose only billing transactions were refunded and are more than two months old" do
        org = create(:organization)
        create(:billing_transaction, :zuora, :refunded_sale, user: org, asset_packs_total: 5, created_at: 3.months.ago)
        business = create(:business, :with_self_serve_payment, upgraded_from: org)
        details = TrustTiers::TierDetailsV2.new(business)

        refute details.has_established_billing_history?
      end

      test "is false for a self-serve business with no billing transactions and is upgraded from an organization with billing transactions more than two months old when ff is disabled" do
        disable_feature_flag(:org_upgraded_trust_tiers_v2)
        org = create(:organization)
        create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, created_at: 3.months.ago)
        business = create(:business, :with_self_serve_payment, upgraded_from: org)
        details = TrustTiers::TierDetailsV2.new(business)

        refute details.has_established_billing_history?
      end

      test "is true for a self-serve business with billing transactions more than two months old and is upgraded from an organization with no billing transactions" do
        org = create(:organization)
        business = create(:business, :with_self_serve_payment, upgraded_from: org)
        create(:billing_transaction, :zuora, customer: business.customer, asset_packs_total: 5, created_at: 3.months.ago)
        details = TrustTiers::TierDetailsV2.new(business)

        assert details.has_established_billing_history?
      end

      test "is true for a self-serve business with no billing transactions and is upgraded from an organization with billing transactions more than two months old" do
        org = create(:organization)
        create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, created_at: 3.months.ago)
        business = create(:business, :with_self_serve_payment, upgraded_from: org)
        details = TrustTiers::TierDetailsV2.new(business)

        assert details.has_established_billing_history?
      end

      test "is true for a self-serve business with billing transactions more than two months old and is upgraded from an organization with billing transactions more than two months old" do
        org = create(:organization)
        create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, created_at: 3.months.ago)
        business = create(:business, :with_self_serve_payment, upgraded_from: org)
        create(:billing_transaction, :zuora, customer: business.customer, asset_packs_total: 5, created_at: 3.months.ago)
        details = TrustTiers::TierDetailsV2.new(business)

        assert details.has_established_billing_history?
      end

      test "is true for business with upgraded_from missing but upgrade_initiated_from_organization set to trusted organization" do
        org = create(:organization)
        create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, created_at: 3.months.ago)
        business = create(:business, :with_self_serve_payment, upgrade_initiated_from_organization: org)
        details = TrustTiers::TierDetailsV2.new(business)

        assert details.has_established_billing_history?
      end

      test "is false with ff disabled for business with upgraded_from missing but upgrade_initiated_from_organization set to trusted organization" do
        disable_feature_flag(:org_upgraded_trust_tiers_v2_5)
        org = create(:organization)
        create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, created_at: 3.months.ago)
        business = create(:business, :with_self_serve_payment, upgraded_from: nil, upgrade_initiated_from_organization: org)
        details = TrustTiers::TierDetailsV2.new(business)

        refute details.has_established_billing_history?
      end

      test "is true for an invoiced business regardless of billing history" do
        business = create(:business)
        details = TrustTiers::TierDetailsV2.new(business)

        assert details.has_established_billing_history?
      end
    end

    context "is_paid_plan?" do
      test "returns false for free account" do
        account = create(:free_org)
        details = TrustTiers::TierDetailsV2.new(account)
        refute details.is_paid_plan?
      end

      test "returns true for team plan account" do
        account = create(:business_org)
        details = TrustTiers::TierDetailsV2.new(account)
        assert details.is_paid_plan?
      end

      test "returns false for an enterprise plan trial account" do
        account = create(:business_plus_organization)
        Billing::EnterpriseCloudTrial.new(account).create
        details = TrustTiers::TierDetailsV2.new(account)
        refute details.is_paid_plan?
      end

      test "returns true for an enterprise plan account" do
        account = create(:business_plus_organization)
        details = TrustTiers::TierDetailsV2.new(account)
        assert details.is_paid_plan?
      end
    end

    context "oldest_owner_older_than_trusted_couponed_age_limit?" do
      test "returns false if owner was created since TRUSTED_COUPONED_AGE_LIMIT.ago" do
        @user = create(:user, created_at: TrustTiers::TierDetailsV2::TRUSTED_COUPONED_AGE_LIMIT.ago + 1.day)
        account = create(:free_org, admins: [@user])
        details = TrustTiers::TierDetailsV2.new(account.reload)
        refute details.oldest_owner_older_than_trusted_couponed_age_limit?
      end

      test "returns true if owner was created before TRUSTED_COUPONED_AGE_LIMIT.ago" do
        @user = create(:user, created_at: TrustTiers::TierDetailsV2::TRUSTED_COUPONED_AGE_LIMIT.ago - 1.day)
        account = create(:free_org, admins: [@user])
        details = TrustTiers::TierDetailsV2.new(account.reload)
        assert details.oldest_owner_older_than_trusted_couponed_age_limit?
      end

      test "returns true if one of the owners was created before TRUSTED_COUPONED_AGE_LIMIT.ago" do
        @user = create(:user, created_at: TrustTiers::TierDetailsV2::TRUSTED_COUPONED_AGE_LIMIT.ago - 1.day)
        @user2 = create(:user, created_at: TrustTiers::TierDetailsV2::TRUSTED_COUPONED_AGE_LIMIT.ago + 1.day)
        account = create(:free_org, admins: [@user, @user2])
        details = TrustTiers::TierDetailsV2.new(account.reload)
        assert details.oldest_owner_older_than_trusted_couponed_age_limit?
      end

      test "returns false if all owners were created since TRUSTED_COUPONED_AGE_LIMIT.ago" do
        @user = create(:user, created_at: TrustTiers::TierDetailsV2::TRUSTED_COUPONED_AGE_LIMIT.ago + 1.day)
        @user2 = create(:user, created_at: TrustTiers::TierDetailsV2::TRUSTED_COUPONED_AGE_LIMIT.ago + 2.days)
        account = create(:free_org, admins: [@user, @user2])
        details = TrustTiers::TierDetailsV2.new(account.reload)
        refute details.oldest_owner_older_than_trusted_couponed_age_limit?
      end

      test "returns false if the account has no owners" do
        account = create(:free_org)
        # mocking empty active record relation
        account.expects(:admins).returns(User.none)
        details = TrustTiers::TierDetailsV2.new(account.reload)
        refute details.oldest_owner_older_than_trusted_couponed_age_limit?
      end
    end

    context "oldest_owner_older_than_neutral_paid_or_couponed_age_limit?" do
      test "returns false if owner was created since NEUTRAL_PAID_OR_COUPONED_AGE_LIMIT.ago" do
        @user = create(:user, created_at: TrustTiers::TierDetailsV2::NEUTRAL_PAID_OR_COUPONED_AGE_LIMIT.ago + 1.day)
        account = create(:free_org, admins: [@user])
        details = TrustTiers::TierDetailsV2.new(account.reload)
        refute details.oldest_owner_older_than_neutral_paid_or_couponed_age_limit?
      end

      test "returns true if owner was created before NEUTRAL_PAID_OR_COUPONED_AGE_LIMIT.ago" do
        @user = create(:user, created_at: TrustTiers::TierDetailsV2::NEUTRAL_PAID_OR_COUPONED_AGE_LIMIT.ago - 1.day)
        account = create(:free_org, admins: [@user])
        details = TrustTiers::TierDetailsV2.new(account.reload)
        assert details.oldest_owner_older_than_neutral_paid_or_couponed_age_limit?
      end

      test "returns true if one of the owners was before NEUTRAL_PAID_OR_COUPONED_AGE_LIMIT.ago" do
        @user = create(:user, created_at: TrustTiers::TierDetailsV2::NEUTRAL_PAID_OR_COUPONED_AGE_LIMIT.ago - 1.day)
        @user2 = create(:user, created_at: TrustTiers::TierDetailsV2::NEUTRAL_PAID_OR_COUPONED_AGE_LIMIT.ago + 1.day)
        account = create(:free_org, admins: [@user, @user2])
        details = TrustTiers::TierDetailsV2.new(account.reload)
        assert details.oldest_owner_older_than_neutral_paid_or_couponed_age_limit?
      end

      test "returns false if all owners were created since NEUTRAL_PAID_OR_COUPONED_AGE_LIMIT.ago" do
        @user = create(:user, created_at: TrustTiers::TierDetailsV2::NEUTRAL_PAID_OR_COUPONED_AGE_LIMIT.ago + 1.day)
        @user2 = create(:user, created_at: TrustTiers::TierDetailsV2::NEUTRAL_PAID_OR_COUPONED_AGE_LIMIT.ago + 2.days)
        account = create(:free_org, admins: [@user, @user2])
        details = TrustTiers::TierDetailsV2.new(account.reload)
        refute details.oldest_owner_older_than_neutral_paid_or_couponed_age_limit?
      end

      test "returns false if account has no owners" do
        account = create(:free_org)
        # mocking empty active record relation
        account.expects(:admins).returns(User.none)
        details = TrustTiers::TierDetailsV2.new(account.reload)
        refute details.oldest_owner_older_than_neutral_paid_or_couponed_age_limit?
      end
    end

    context "oldest_owner_older_than_neutral_free_age_limit?" do
      test "returns false if owner was created since NEUTRAL_FREE_AGE_LIMIT.ago" do
        @user = create(:user, created_at: TrustTiers::TierDetailsV2::NEUTRAL_FREE_AGE_LIMIT.ago + 1.day)
        account = create(:free_org, admins: [@user])
        details = TrustTiers::TierDetailsV2.new(account.reload)
        refute details.oldest_owner_older_than_neutral_free_age_limit?
      end

      test "returns true if owner was created before NEUTRAL_FREE_AGE_LIMIT.ago" do
        @user = create(:user, created_at: TrustTiers::TierDetailsV2::NEUTRAL_FREE_AGE_LIMIT.ago - 1.day)
        account = create(:free_org, admins: [@user])
        details = TrustTiers::TierDetailsV2.new(account.reload)
        assert details.oldest_owner_older_than_neutral_free_age_limit?
      end

      test "returns true if one of the owners was before NEUTRAL_FREE_AGE_LIMIT.ago" do
        @user = create(:user, created_at: TrustTiers::TierDetailsV2::NEUTRAL_FREE_AGE_LIMIT.ago - 1.day)
        @user2 = create(:user, created_at: TrustTiers::TierDetailsV2::NEUTRAL_FREE_AGE_LIMIT.ago + 1.day)
        account = create(:free_org, admins: [@user, @user2])
        details = TrustTiers::TierDetailsV2.new(account.reload)
        assert details.oldest_owner_older_than_neutral_free_age_limit?
      end

      test "returns false if all owners were created since NEUTRAL_FREE_AGE_LIMIT.ago" do
        @user = create(:user, created_at: TrustTiers::TierDetailsV2::NEUTRAL_FREE_AGE_LIMIT.ago + 1.day)
        @user2 = create(:user, created_at: TrustTiers::TierDetailsV2::NEUTRAL_FREE_AGE_LIMIT.ago + 2.days)
        account = create(:free_org, admins: [@user, @user2])
        details = TrustTiers::TierDetailsV2.new(account.reload)
        refute details.oldest_owner_older_than_neutral_free_age_limit?
      end

      test "returns false if account has no owners" do
        account = create(:free_org)
        # mocking empty active record relation
        account.expects(:admins).returns(User.none)
        details = TrustTiers::TierDetailsV2.new(account.reload)
        refute details.oldest_owner_older_than_neutral_free_age_limit?
      end
    end

    context "oldest_owner_age" do
      test "returns nil if account has no owners" do
        account = create(:free_org)
        # mocking empty active record relation
        account.expects(:admins).returns(User.none)
        details = TrustTiers::TierDetailsV2.new(account.reload)
        assert_nil details.oldest_owner_age
      end

      test "returns single owner created_at if 1 owner" do
        @user = create(:user)
        account = create(:free_org, admins: [@user])
        details = TrustTiers::TierDetailsV2.new(account.reload)
        assert_equal @user.created_at, details.oldest_owner_age
      end

      test "returns oldest owner created_at if 2 owners" do
        @user = create(:user, created_at: 1.day.ago)
        @user2 = create(:user, created_at: 2.days.ago)
        account = create(:free_org, admins: [@user, @user2])
        details = TrustTiers::TierDetailsV2.new(account.reload)
        assert_equal @user2.created_at, details.oldest_owner_age
      end
    end

    context "last_payment_failed" do
      # Failed payments are simulated by incrementing the billing attempts to be > 0
      # this puts the account into dunning state, which is what we're checking for
      test "is true for an organization whose most recent billing transaction failed" do
        # billings attempts are on the organization, not the customer
        org = create(:organization, billing_attempts: 1)
        details = TrustTiers::TierDetailsV2.new(org)

        assert details.last_payment_failed?
      end

      test "is false for an organization whose most recent billing transaction did not fail" do
        org = create(:organization)
        details = TrustTiers::TierDetailsV2.new(org)

        refute details.last_payment_failed?
      end

      test "is true for a business whose most recent billing transaction failed" do
        # billing attempts are on the customer, not the business
        business = create(:business, customer: create(:customer, billing_attempts: 1))
        details = TrustTiers::TierDetailsV2.new(business)

        assert details.last_payment_failed?
      end

      test "is false for a business whose most recent billing transaction succeeded" do
        business = create(:business)
        details = TrustTiers::TierDetailsV2.new(business)

        refute details.last_payment_failed?
      end
    end
  end
end
