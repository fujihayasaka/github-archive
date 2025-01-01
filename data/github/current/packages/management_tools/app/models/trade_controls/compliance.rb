# typed: strict
# frozen_string_literal: true

module TradeControls
  module Compliance

    ComplianceType = T.type_alias do
      T.any(
        NullCompliance,
        ManualCompliance,
        EmailCompliance,
        IpCompliance,
        WebsiteUrlCompliance,
        BillingManagersCompliance,
        OrgAdminThresholdCompliance,
        OrgProfileEmailCompliance,
        OrgBillingEmailCompliance,
      )
    end

    sig { params(options: T.untyped).returns(ComplianceType) }
    def self.for(**options)
      #TODO guard for mutual exclusion and minimum args

      if options[:actor].present? then ManualCompliance
      elsif options[:email].present? then EmailCompliance
      elsif options[:ip].present? || options[:location].present? then IpCompliance
      elsif options[:website_url].present? then WebsiteUrlCompliance
      elsif options[:check_billing_managers].present? then BillingManagersCompliance
      elsif options[:check_admin].present? then OrgAdminThresholdCompliance
      elsif options[:check_profile_email].present? then OrgProfileEmailCompliance
      elsif options[:check_billing_email].present? then OrgBillingEmailCompliance
      else NullCompliance # rubocop:disable Lint/ElseLayout
      end.new(**T.unsafe(options))
    end

    sig { returns(T.nilable(T.any(::User, ::Organization))) }
    def organization
      nil
    end

    sig { returns(T.any(String, Symbol)) }
    def reason
      ""
    end

    sig { returns(T.nilable(String)) }
    def event_source
      nil
    end

    sig { returns(T::Boolean) }
    def violation?
      false
    end

    sig { returns(T::Boolean) }
    def sdn_suspend?
      false
    end

    # checks if organization has passed a tier 0 restriction threshold
    sig { returns(T::Boolean) }
    def tier_0_restriction_violation?
      false
    end

    # checks if organization has passed a tier 1 restriction threshold
    sig { returns(T::Boolean) }
    def tier_1_restriction_violation?
      false
    end

    # checks if organization has passed a full restriction threshold
    sig { returns(T::Boolean) }
    def full_restriction_violation?
      false
    end

    sig { returns(T.nilable(Symbol)) }
    def restriction_tier
      if tier_1_restriction_violation?
        :tier_1
      elsif tier_0_restriction_violation?
        :tier_0
      elsif full_restriction_violation?
        :full
      else
        nil
      end
    end

    sig { returns(T::Hash[T.any(Symbol, String), T.untyped]) }
    def to_hydro
      {}
    end

    # Internal: invoked by Instrumentation::Model when expanding event_payload
    sig { params(kwargs: T.untyped).returns(T.untyped) }
    def event_context(**kwargs)
      Context::Expander.expand to_hydro
    end

    sig { void }
    def check_and_enforce!
      return unless violation?
      case restriction_tier
      when :full
        T.must(organization).trade_controls_restriction.enforce!(compliance: self)
      when :tier_1
        T.must(organization).trade_controls_restriction.tier_1_enforce!(compliance: self)
      when :tier_0
        T.must(organization).trade_controls_restriction.tier_0_enforce!(compliance: self)
      end
    end
  end
end
