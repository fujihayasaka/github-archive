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
      else
        [reason]
      end
    end
  end
end
