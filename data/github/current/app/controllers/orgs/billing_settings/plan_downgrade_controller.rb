# typed: true
# frozen_string_literal: true
class Orgs::BillingSettings::PlanDowngradeController < ApplicationController
  include OrganizationsHelper
  include PlanDowngradeHelper

  before_action :ensure_billing_enabled
  before_action :login_required
  before_action :org_billing_management_only
  before_action :ensure_has_target
  before_action :ensure_has_plan

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Iam,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    new_plan = GitHub::Plan.find(params[:plan])
    new_plan ||= GitHub::Plan.free
    target = current_organization_for_member_or_billing
    if target.plan.business_plus? && new_plan.business?
      render partial: "billing_settings/confirm_cancel_biz_plus_lightbox", locals: { target: target, new_plan: new_plan }
    else
      billable_codespaces_count = Codespace.where(billable_owner: target.id).count
      render partial: "billing_settings/confirm_cancel_seats_lightbox", locals: { target: target, new_plan: new_plan, billable_codespaces_count: billable_codespaces_count }
    end
  end

  private

  def ensure_billing_enabled
    render_404 unless GitHub.billing_enabled?
  end

  def ensure_has_target
    render_404 unless current_organization_for_member_or_billing
  end

  def ensure_has_plan
    render_404 unless downgrade_target_has_plan?
  end
end
