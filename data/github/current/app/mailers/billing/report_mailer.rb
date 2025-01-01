# typed: true
# frozen_string_literal: true

class Billing::ReportMailer < ApplicationMailer
  include ApplicationHelper
  include CodespacesHelper

  self.mailer_name = "mailers/billing_report"

  layout "billing_email_layout"
  helper :application

  def metered_export_complete_primer_layout(metered_export, report_type: :default, billable_owner: nil)
    @export = metered_export
    @report_type = report_type
    @download_url = url_for_export

    @report_period_header = "Usage report for #{metered_export.starts_on.strftime('%B %d, %Y')} - #{metered_export.ends_on.strftime('%B %d, %Y')}"
    @mail_icon = "billing/document.png"
    billable_owner = metered_export.billable_owner
    account_name = billable_owner.name
    @subject = "Your usage report for #{account_name} is ready"
    @footer_text = "You are receiving this because you requested a report of usage from Billing on the #{account_name} GitHub account."

    if codespaces_billing_enabled?(billable_owner)
      @usage_description = "This detailed report features the usage of GitHub Actions, GitHub Packages, their shared storage, and GitHub Codespaces."
    else
      @usage_description = "This detailed report features the usage of GitHub Actions, GitHub Packages and their shared storage."
    end

    @additional_usage_description = <<~EOF
      Updates to organization, repository, or username may take up to 24 hours.\n
      For the latest report, request again after that time.
    EOF

    self.class.layout "layouts/primer_layout"

    premail(
      from: github,
      to: Billing::MeteredUsageReportGenerator.email_for_export(requester: metered_export.requester, target: billable_owner),
      subject: "[GitHub] Your usage report is ready to download",
      template_name: "metered_export_complete_primer_layout",
    )
  end

  def metered_export_error(billable_owner, requester, report_type: :default)
    @billable_owner = billable_owner
    @usage_type = "Actions and Packages"
    @usage_type = "Codespaces" if report_type == :codespaces

    mail(
      from: github,
      to: Billing::MeteredUsageReportGenerator.email_for_export(requester: requester, target: billable_owner),
      subject: "[GitHub] We were unable to process your usage export request",
    )
  end

  private

  def url_for_export
    staff = @export.requester&.employee? && @export.requester&.site_admin?
    if @export.billable_owner.is_a?(Business)
      staff ? stafftools_metered_export_url(@export.billable_owner, @export) : metered_export_enterprise_url(@export.billable_owner, @export)
    elsif @export.billable_owner.organization?
      staff ? stafftools_user_metered_export_url(@export.billable_owner, @export) : org_metered_export_url(@export.billable_owner, @export)
    else
      staff ? stafftools_user_metered_export_url(@export.billable_owner, @export) : metered_export_url(@export)
    end
  end

  helper_method :url_for_export
end
