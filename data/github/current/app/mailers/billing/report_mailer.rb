# typed: true
# frozen_string_literal: true

class Billing::ReportMailer < ApplicationMailer
  include ApplicationHelper
  include CodespacesHelper

  self.mailer_name = "mailers/billing_report"

  layout "billing_email_layout"
  helper :application

  def metered_export_complete(metered_export, report_type: :default, billable_owner: nil)
    @export = metered_export
    @report_type = report_type
    @download_url = url_for_export

    if codespaces_billing_enabled?(billable_owner)
      @usage_description = "This report features the usage of GitHub Actions, GitHub Packages, their shared storage, and GitHub Codespaces."
    else
      @usage_description = "This report features the usage of GitHub Actions, GitHub Packages and their shared storage."
    end

    mail(
      from: github,
      to: Billing::MeteredUsageReportGenerator.email_for_export(requester: metered_export.requester, target: metered_export.billable_owner),
      subject: "[GitHub] Your usage report is ready to download",
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
    if @export.billable_owner.is_a?(Business)
      metered_export_enterprise_url(@export.billable_owner, @export)
    elsif @export.billable_owner.organization?
      org_metered_export_url(@export.billable_owner, @export)
    else
      metered_export_url(@export)
    end
  end

  helper_method :url_for_export
end
