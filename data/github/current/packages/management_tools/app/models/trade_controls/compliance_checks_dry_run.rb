# typed: true
# frozen_string_literal: true

module TradeControls
  class ComplianceChecksDryRun
    REASONS = %i[
      organization_billing_manager
      organization_admin
      billing_email
      profile_email
      website_url
    ]

    attr_reader :violations

    def initialize(actor, **kwargs)
      @actor = actor
      @violations = {}
      @reason = kwargs[:reason]
    end

    # perform dry run checks
    def run
      if @reason.present?
        check_reason @reason
      else
        REASONS.each do |reason|
          check_reason reason
        end
      end
    end

    def check_reason(reason)
      case reason
      when :billing_email
        if @actor.organization?
          if TradeControls::OrgBillingEmailCompliance.new(organization: @actor).violation?
            @violations[:billing_email] = TradeControls::Notices.billing_email_restriction_reason
          elsif @actor.billing_external_emails.detect { |external_email| TradeControls::EmailCompliance.new(email: external_email.email).violation? }
            @violations[:billing_email] = TradeControls::Notices.external_billing_email_restriction_reason
          end
        end
      when :profile_email
        if @actor.organization?
          compliance = TradeControls::OrgProfileEmailCompliance.new(organization: @actor)
          if compliance.violation?
            @violations[:profile_email] = TradeControls::Notices.profile_email_restriction_reason
          end
        else
          if TradeControls::EmailCompliance.new(email: @actor.profile_email).violation?
            @violations[:profile_email] = TradeControls::Notices.profile_email_restriction_reason
          elsif @actor.emails.detect { |user_email| TradeControls::EmailCompliance.new(email: user_email.email).violation? }
            @violations[:profile_email] = TradeControls::Notices.user_emails_restriction_reason
          end
        end
      when :website_url
        compliance = TradeControls::WebsiteUrlCompliance.new(organization: @actor, website_url: @actor.profile_blog)
        if compliance.violation?
          @violations[:website_url] = TradeControls::Notices.website_url_restriction_reason
        end
      when :organization_admin
        if @actor.organization?
          compliance = TradeControls::OrgAdminThresholdCompliance.new(organization: @actor)
          if compliance.violation?
            restriction_reason = TradeControls::Notices.percentage_restriction_reason(percent: compliance.current_threshold, type: "owners")
            @violations[:organization_admin] = restriction_reason
          end
        end
      when :organization_billing_manager
        if @actor.organization?
          compliance = TradeControls::BillingManagersCompliance.new(organization: @actor)
          if compliance.violation?
            restriction_reason = TradeControls::Notices.percentage_restriction_reason(percent: compliance.current_threshold, type: "billing managers")
            @violations[:organization_billing_manager] = restriction_reason
          end
        end
      end
    end

    def humanize_violations
      @violations.values
    end
  end
end
