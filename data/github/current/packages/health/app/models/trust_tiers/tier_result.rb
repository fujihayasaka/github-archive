# typed: true
# frozen_string_literal: true

module TrustTiers
  class TierResult
    attr_reader :tier, :reason

    # Descriptors
    BUSINESS_OR_INVOICED = "business_or_invoiced"
    CONSECUTIVE_BILLING  = "consecutive_billing"
    COUPON               = "coupon"
    ESTABLISHED_BILLING  = "established_billing"
    GITHUB_ENTERPRISE    = "github_enterprise"
    NO_MATCH             = "no_match"
    OLDEST_OWNER_AGE     = "oldest_owner"
    PAID                 = "paid_plan"
    SETTINGS_FORCED      = "settings_forced"
    TRUSTED_COUPON       = "trusted_coupon"
    USER                 = "user"
    ENGAGED_OSS          = "engaged_oss"
    ENTERPRISE_TRIAL     = "enterprise_trial"
    ESTABLISHED_BILLING_LAPSED_PAYMENT = "established_billing_lapsed_payment"
    MISMATCHED_TIMEZONE  = "mismatched_timezone"
    FARMABLE_DOMAIN      = "farmable_email_domain"
    DISPUTED_ACCOUNT     = "disputed_charges"
    AZURE_METERED_BILLING = "azure_metered_billing"

    def initialize(tier, reason)
      @tier = tier
      @reason = reason
    end

    def ==(other)
      tier == other.tier && reason == other.reason
    end

    def verbose_reason
      embellish_reason(reason)
    end

    def embellish_reason(reason)
      case reason
      when BUSINESS_OR_INVOICED
        ["Sales Serviced"]
      when CONSECUTIVE_BILLING
        ["Has had one payment each in current billing cycle and previous billing cycle"]
      when COUPON
        ["Account has non-educational coupon"]
      when ESTABLISHED_BILLING
        ["Last payment was successful and has at least one successful payment over 2 months ago"]
      when GITHUB_ENTERPRISE
        ["GitHub Enterprise"]
      when PAID
        ["Account is paid"]
      when TRUSTED_COUPON
        [COUPON, OLDEST_OWNER_AGE].map do |reason|
          embellish_reason(reason)
        end.flatten
      when NO_MATCH
        ["No Match"]
      when OLDEST_OWNER_AGE
        ["Oldest owner age was greater than the limit"]
      when ENGAGED_OSS
        ["Repo is an Engaged Open Source repo"]
      when ENTERPRISE_TRIAL
        ["GitHub Enterprise Trial"]
      when ESTABLISHED_BILLING_LAPSED_PAYMENT
        ["Last payment failed but has established billing history"]
      when MISMATCHED_TIMEZONE
        ["Time zone mismatch between account time zone and last IP address"]
      when FARMABLE_DOMAIN
        ["Email domain is farmable"]
      when DISPUTED_ACCOUNT
        ["Account has billing disputes"]
      when AZURE_METERED_BILLING
        ["Azure-metered account with substantial recent billed usage"]
      else
        [reason]
      end
    end
  end
end
