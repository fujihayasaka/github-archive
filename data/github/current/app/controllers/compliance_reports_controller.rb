# typed: true
# frozen_string_literal: true

class ComplianceReportsController < ApplicationController
  include ComplianceReportHelper

  before_action :login_required
  before_action :owner_required
  before_action :owner_admin_required
  before_action :report_required
  before_action :eligible_account_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: %i(show)

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    render_compliance_report(owner)
  end

  private

  memoize def this_report
    ComplianceReport
      .published
      .downloads
      .find_by(slug: params[:key])
  end

  def render_compliance_report(account)
    instrument_compliance_report_download(account, this_report.slug)


    storage = this_report.storage

    response.headers["Content-Type"] = this_report.content_type
    response.headers["Content-Length"] = storage.size.to_s
    response.headers["Content-Disposition"] = "attachment; filename=\"#{this_report.filename}\""
    self.response_body = Enumerator.new do |output|
      storage.get do |chunk|
        output << chunk
      end
    end
  end

  def instrument_compliance_report_download(account, key)
    GlobalInstrumenter.instrument("security_report.download",
      account_type: account.is_a?(::Business) ? "Business" : "Organization",
      account_id: account.id,
      actor_id: current_user.id,
      report_key: key
    )
  end

  memoize def owner
    if organization_login_param.present?
      Organization.find_by(login: organization_login_param)
    elsif business_slug_param.present?
      Business.find_by(slug: business_slug_param)
    end
  end

  def owner_required
    render_404 unless owner
  end

  def owner_admin_required
    render_404 unless owner.adminable_by?(current_user)
  end

  def report_required
    render_404 unless this_report
  end

  def eligible_account_required
    render_404 unless compliance_reports_available_for_account?(owner)
    render_404 unless this_report.available_to?(owner)
  end

  def business_slug_param
    params[:slug]
  end

  def organization_login_param
    params[:organization_id]
  end

  # Safe because :owner_required 404s if owner is nil
  def target_for_conditional_access
    return :no_target_for_conditional_access unless owner # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    owner
  end
end
