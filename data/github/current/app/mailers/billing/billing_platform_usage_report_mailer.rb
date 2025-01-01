# typed: true
# frozen_string_literal: true

class Billing::BillingPlatformUsageReportMailer < ApplicationMailer
  include BillingSettingsHelper
  include Billing::ProductsDependency

  self.mailer_name = "mailers/billing_platform_usage_report"

  layout "billing_email_layout"
  helper :application

  # NOTE: Normally, we wouldn't need to have the job resolve its own tenant context
  # as it inherits it from the context that enqueues it.
  # However, in the case the request came from a stafftools tenant, the ActiveJob will check
  # for and remove the tenant (resulting in a nil tenant).
  # Hence, we need to resolve the tenant context here to re-establish the stafftools tenant.
  # See: https://github.com/github/github/pull/308059
  def self.resolve_tenant(action_name, args)
    case action_name.to_sym
    when :usage_report_complete
      _, metered_export_records, * = args
      metered_export_records.first&.requester&.enterprise_managed_business
    when :usage_report_error
      _, billable_owner, * = args
      billable_owner
    else
      # Default to the current tenant
      GitHub::CurrentTenant.get
    end
  end

  def usage_report_complete(to, metered_export_records, usage_period_text, report_type)
    raise ArgumentError, "metered_export_records must not be empty" unless metered_export_records.present?

    if GitHub::CurrentTenant.stafftools_tenant?
      GitHub::CurrentTenant.unscope { mail_report_complete(to, metered_export_records, usage_period_text, report_type) }
    else
      mail_report_complete(to, metered_export_records, usage_period_text, report_type)
    end
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

  def mail_report_complete(to, metered_export_records, usage_period_text, report_type)
    @metered_export_records = metered_export_records
    @billable_owner = metered_export_records.first.billable_owner
    @usage_period_text = usage_period_text
    @usage_description = usage_description(enabled_products(@billable_owner), report_type)

    self.class.layout "layouts/primer_layout"
    @subject = "Your usage report for #{@billable_owner.name} is ready"
    @usage_report_header = "Usage report for #{@usage_period_text}"
    @mail_icon = "billing/document.png"
    @footer_text = "You are receiving this because you requested a report of usage from Billing on the #{@billable_owner.name} GitHub account."

    if is_summarized_report?(report_type)
      @additional_usage_description = <<~EOF
        Updates to organization or repository may take up to 24 hours.\n
        For the latest report, request again after that time.
      EOF
    else
      @additional_usage_description = <<~EOF
        Updates to organization, repository, or username may take up to 24 hours.\n
        For the latest report, request again after that time.
      EOF
    end


    premail(
      from: github,
      to: to,
      subject: "[GitHub] Your usage report is ready to download",
      template_name: "usage_report_complete_primer_layout",
    )
  end

  def usage_description(enabled_products, report_type)
    return "" if enabled_products.empty?

    enabled_products = enabled_products.map { |p| p[:friendlyProductName] }.sort.to_sentence

    if is_summarized_report?(report_type)
      "This summarized report features the usage of #{enabled_products}."
    else
      "This detailed report features the usage of #{enabled_products}."
    end
  end

  sig { params(report_type: Integer).returns(T::Boolean) }
  def is_summarized_report?(report_type)
    report_type == Hydro::Schemas::Billingplatform::V1::Entities::ReportType::SUMMARIZED
  end
end
