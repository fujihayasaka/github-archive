# typed: true
# frozen_string_literal: true
class BillingSettings::PlanDowngradeController < ApplicationController
  include OrganizationsHelper
  include PlanDowngradeHelper
  before_action :ensure_billing_enabled
  before_action :login_required
  before_action :ensure_has_plan

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    render partial: "billing_settings/confirm_cancel_pro_lightbox", locals: { target: current_user }
  end

  private

  def ensure_has_plan
    render_404 unless downgrade_target_has_plan?
  end

  def ensure_billing_enabled
    render_404 unless GitHub.billing_enabled?
  end
end
