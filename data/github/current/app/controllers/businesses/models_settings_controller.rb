# typed: true
# frozen_string_literal: true

class Businesses::ModelsSettingsController < Businesses::BusinessController
  before_action :github_models_required
  before_action :business_owner_required
  before_action :check_copilot_licensing

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
    if params[:enable_models] == "force_on"
      this_business.force_models_access_on(actor: current_user, instrument: true)
      flash[:notice] = "Models access enabled"
    elsif params[:enable_models] == "false"
      this_business.force_models_access_off(actor: current_user, instrument: true)
      flash[:notice] = "Models access forced disabled"
    else
      this_business.remove_models_access_policy(actor: current_user, instrument: true)
      flash[:notice] = "Models access has no set policy. Organizations choose whether to enable."
    end

    redirect_to settings_models_enterprise_path(this_business)
  end

  private

  def check_copilot_licensing
    render_404 if this_business.copilot_licensing_enabled?
  end
end
