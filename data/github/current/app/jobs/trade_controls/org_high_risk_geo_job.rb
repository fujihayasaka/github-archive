# typed: true
# frozen_string_literal: true

module TradeControls
  class OrgHighRiskGeoJob < ApplicationJob
    queue_as :trade_screening
    retry_on_dirty_exit

    discard_on ActiveRecord::RecordNotFound

    before_enqueue do |_job|
      throw(:abort) unless GitHub.billing_enabled?
    end

    def perform(organization_id, reason: nil)
      org = Organization.find(organization_id)

      return if org.trade_controls_restriction.trade_restricted_country_code.present?

      return if reason.nil?

      email = if reason == :profile_email
        org.profile_email
      elsif reason == :billing_email
        org.billing_email
      else
        nil
      end

      website_url = if reason == :website_url
        org.profile_blog
      else
        nil
      end

      return if email.nil? && website_url.nil?

      high_risk_geo = OrgHighRiskGeoManager.new(email: email, website_url: website_url).high_risk_geo

      if high_risk_geo.present?
        with_write { org.trade_controls_restriction.update(trade_restricted_country_code: high_risk_geo) }
      end
    end
  end
end
