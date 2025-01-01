# typed: true
# frozen_string_literal: true

class Settings::MeteredExportsController < ApplicationController
  include BillingSettingsHelper
  include OrganizationsHelper

  before_action :ensure_billing_enabled
  before_action :login_required
  before_action :ensure_target_is_billable

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    export = target.metered_usage_exports.find(params[:id])

    redirect_to export.generate_expiring_url
  end

  def create
    if valid_date_range?
      Billing::MeteredReportExportJob.perform_later(current_user, target, params[:days].to_i)

      flash[:notice] = "We're preparing your report! We’ll send an email to #{Billing::MeteredUsageReportGenerator.email_for_export(requester: current_user, target: target)} when it’s ready."
    else
      flash[:error] = "We're having issues preparing your report. Please contact support or try again later."
    end

    redirect_back fallback_location: path_for_billing_settings
  end

  private

  def valid_date_range?
    Billing::MeteredUsageReportGenerator::VALID_DURATIONS.include?(params[:days].to_i)
  end

  def target_for_conditional_access
    # CAP is not needed if there is no target. We'd 404 in that case.
    return :no_target_for_conditional_access unless target # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    target
  end

  def target # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @target ||= target!
  end

  def target!
    if params[:target] == "organization"
      org = current_organization_for_member_or_billing
      if org && org.billing_manageable_by?(current_user)
        org
      end
    else
      current_user
    end
  end

  def ensure_target_is_billable
    render_404 unless target&.billable?
  end

  def path_for_billing_settings
    if target.organization?
      settings_org_billing_path(target)
    else
      billing_path
    end
  end
end
