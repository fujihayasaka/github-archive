# typed: true
# frozen_string_literal: true

class Billing::BillingPlatformUsageReportMailer < ApplicationMailer
  include BillingSettingsHelper

  self.mailer_name = "mailers/billing_platform_usage_report"

  layout "billing_email_layout"
  helper :application

  def usage_report_complete(metered_export_records, usage_period_text)
    raise ArgumentError, "metered_export_records must not be empty" unless metered_export_records.present?

    @metered_export_records = metered_export_records
    @billable_owner = metered_export_records.first.billable_owner
    @usage_period_text = usage_period_text
    @usage_description = usage_description(@billable_owner.customer.products_billed_via_billing_platform_friendly_names)

    mail(
      from: github,
      to: metered_export_records.first.requester.default_notification_email,
      subject: "[GitHub] Your usage report is ready to download",
    )
  end

  def usage_report_error(to, billable_owner)
    @billable_owner = billable_owner
    mail(
      from: github,
      to: to,
      subject: "[GitHub] We were unable to process your usage export request",
    )
  end

  private

  def usage_description(enabled_products)
    return "" if enabled_products.empty?

    enabled_products = enabled_products.to_sentence
    "This report features the usage of #{enabled_products}"
  end
end
