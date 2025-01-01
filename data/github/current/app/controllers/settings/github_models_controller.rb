# typed: true
# frozen_string_literal: true

class Settings::GitHubModelsController < ApplicationController
  include Settings::ControllerMethods

  before_action :login_required
  before_action :ensure_billing_section_visible
  before_action :github_models_required
  before_action :ensure_billing_enabled
  before_action :ensure_enterprise_managed_business_not_basic

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    only: [:index]

  def index
    render "settings/github_models/index", locals: {
      user: current_user,
      can_enable_models_billing: current_user.can_enable_models_billing?,
      models_billing_disabled_by_non_payment_method_reason: current_user.models_billing_disabled_by_non_payment_method_reason?,
      has_payment_method: current_user.has_payment_method?,
      billing_enabled: current_user.models_billing_enabled?,
      legacy: current_user.billable_owner.plan.legacy?,
    }
  end

  private

  def ensure_enterprise_managed_business_not_basic
    render_404 if current_user.is_enterprise_managed? && current_user.enterprise_managed_business&.copilot_licensing_enabled?
  end

  def ensure_billing_section_visible
    render_404 unless current_user.can_show_models_billing?
  end
end
