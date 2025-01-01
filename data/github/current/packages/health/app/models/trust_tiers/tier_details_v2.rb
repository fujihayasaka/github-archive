# typed: true
# frozen_string_literal: true

module TrustTiers
  class TierDetailsV2
    TRUSTED_COUPONED_AGE_LIMIT = 14.days
    NEUTRAL_PAID_OR_COUPONED_AGE_LIMIT = 3.days
    NEUTRAL_FREE_AGE_LIMIT = 30.days
    BILLING_HISTORY_MATURATION_PERIOD = 2.months

    attr_reader :account

    def initialize(account)
      @account = account
      @coupon = account.coupon
    end

    # Checks if the account has an eligible coupon present.
    # For Pro (aka "Developer") accounts, eligible coupons are non-education coupons.
    # For non-Pro accounts, all coupons are eligible, including education coupons.
    # @return [Boolean]
    def has_eligible_coupon?
      return @has_eligible_coupon if defined?(@has_eligible_coupon)
      return @has_eligible_coupon = @coupon.present? && !@coupon.education_coupon? if @account.plan.pro?
      @has_eligible_coupon = @coupon.present?
    end

    # Checks if the account has an established billing history.
    # Established billing history is defined as having at least one
    # billing transaction with the following characteristics:
    #
    # - Successfully billed
    # - Non-refunded
    # - Non-zero amount in cents
    # - At least BILLING_HISTORY_MATURATION_PERIOD old
    #
    # This also checks if the account is a business, and if it was
    # upgraded from an organization that may have mature billing history.
    #
    # For bot accounts, false is always returned.
    # For invoiced accounts, true is always returned.
    #
    # See: https://support-kb.githubapp.com/support/process/trust/tier-calculations/
    def has_established_billing_history?
      return @has_established_billing_history if defined?(@has_established_billing_history)

      if @account.feature_enabled?(:org_upgraded_trust_tiers_v2)
        @has_established_billing_history = has_mature_payment_history?(@account)

        # if the account is business, we need to check if they've upgraded from an organization that may have mature billing history
        if !@has_established_billing_history && is_business?
          upgraded_org = account_upgraded_from
          @has_established_billing_history = upgraded_org.present? && has_mature_payment_history?(upgraded_org)
        end
      else
        @has_established_billing_history = has_paid_money? && GitHub::SpamChecker.billing_success_in_period(account, 50.years.ago, BILLING_HISTORY_MATURATION_PERIOD.ago)
      end

      @has_established_billing_history
    end

    # Checks if the account has any successful billing transactions.
    # If this account was upgraded from an organization, we also check
    # if the organization has any successful billing transactions.
    #
    # For bot accounts, false is always returned.
    # For invoiced accounts, true is always returned.
    def has_paid_money?
      return @has_paid_money if defined?(@has_paid_money)

      @has_paid_money = GitHub::SpamChecker.has_actually_paid_money?(@account)

      if @account.feature_enabled?(:org_upgraded_trust_tiers_v2)
        # if the account is a business, we need to check if they've upgraded from an organization that may have paid previously
        if !@has_paid_money && is_business?
          upgraded_org = account_upgraded_from
          @has_paid_money = upgraded_org.present? && GitHub::SpamChecker.has_actually_paid_money?(upgraded_org)
        end
      end

      @has_paid_money
    end

    def has_trial?
      return @has_trial if defined?(@has_trial)

      if @account.plan.business_plus?
        trial = Billing::PlanTrial.find_by(
          user: @account,
          plan: GitHub::Plan::BUSINESS_PLUS,
        )
        return @has_trial = trial.present?
      end

      @has_trial = false
    end

    def is_paid_plan?
      return @is_paid_plan if defined?(@is_paid_plan)

      # if the plan is a business plus plan (lowercase e-nterprise), check if it's a trial
      if @account.plan.business_plus?
        trial = Billing::PlanTrial.find_by(
          user: @account,
          plan: GitHub::Plan::BUSINESS_PLUS,
        )
        return @is_paid_plan = !trial.present?
      end

      @is_paid_plan = @account.plan.paid?
    end

    def last_payment_failed?
      return @last_payment_failed if defined?(@last_payment_failed)

      @last_payment_failed = @account.dunning?
    end

    def oldest_owner_older_than_trusted_couponed_age_limit?
      return @oldest_owner_older_than_trusted_couponed_age_limit if defined?(@oldest_owner_older_than_trusted_couponed_age_limit)

      # A handful of orgs seem to not have an associated admin, so we ignore orgs without one for this check
      @oldest_owner_older_than_trusted_couponed_age_limit = oldest_owner_age.present? && oldest_owner_age < TRUSTED_COUPONED_AGE_LIMIT.ago
    end

    def oldest_owner_older_than_neutral_free_age_limit?
      return @oldest_owner_older_than_neutral_free_age_limit if defined?(@oldest_owner_older_than_neutral_free_age_limit)

      # A handful of orgs seem to not have an associated admin, so we ignore orgs without one for this check
      @oldest_owner_older_than_neutral_free_age_limit = oldest_owner_age.present? && oldest_owner_age < NEUTRAL_FREE_AGE_LIMIT.ago
    end

    def oldest_owner_older_than_neutral_paid_or_couponed_age_limit?
      return @oldest_owner_older_than_neutral_paid_or_couponed_age_limit if defined?(@oldest_owner_older_than_neutral_paid_or_couponed_age_limit)

      # A handful of orgs seem to not have an associated admin, so we ignore orgs without one for this check
      @oldest_owner_older_than_neutral_paid_or_couponed_age_limit = oldest_owner_age.present? && oldest_owner_age < NEUTRAL_PAID_OR_COUPONED_AGE_LIMIT.ago
    end

    def oldest_owner_age
      return @oldest_owner_age if defined?(@oldest_owner_age)

      @oldest_owner_age = oldest_owner&.created_at
    end

    def oldest_owner
      return @oldest_owner if defined?(@oldest_owner)

      admins = @account.admins

      if admins.is_a?(ActiveRecord::Relation)
        @oldest_owner = admins.order(:created_at).first
      else
        @oldest_owner = admins.sort_by(&:created_at).first
      end

      @oldest_owner
    end

    def is_business?
      return @is_a_business if defined?(@is_a_business)

      @is_a_business = @account.is_a?(Business)
    end

    def has_mature_payment_history?(account)
      GitHub::SpamChecker.billing_success_in_period(account, 50.years.ago, BILLING_HISTORY_MATURATION_PERIOD.ago)
    end

    def account_upgraded_from
      return @upgraded_from if defined?(@upgraded_from)
      return unless is_business?

      if @account.feature_enabled?(:org_upgraded_trust_tiers_v2_5)
        if @account.upgraded_from.present?
          @upgraded_from = @account.upgraded_from
        else
          @upgraded_from = @account.upgrade_initiated_from_organization
        end
      else
        @upgraded_from = @account.upgraded_from
      end

      @upgraded_from
    end
  end
end
