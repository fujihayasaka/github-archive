# typed: true
# frozen_string_literal: true

class Businesses::ModelsSettingsController < Businesses::BusinessController
  before_action :dotcom_required
  before_action :business_owner_required
  before_action :feature_or_enterprise_managed_business_required

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:show]

  def show
    render "businesses/settings/models", locals: { business: this_business }
  end

  def update
    if params[:enable_models] == "on"
      this_business.enable_models_access(current_user)
      flash[:notice] = "Models access enabled"
    else
      this_business.disable_models_access(current_user)
      flash[:notice] = "Models access disabled"
    end

    redirect_to settings_models_enterprise_path(this_business)
  end

  private

  def feature_or_enterprise_managed_business_required
    unless (this_business&.enterprise_managed? && this_business.seats_plan_full?) || user_feature_enabled?(:github_models_toggle_for_non_emu_enterprises)
      render_404
    end
  end
end
