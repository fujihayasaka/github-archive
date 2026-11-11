# typed: strict
# frozen_string_literal: true

class Copilot::UpgradeController < Copilot::Signup::BaseController
  include Copilot::VscodeRedirectConcern

  before_action :login_required
  before_action :restrict_emu_access
  before_action :set_vscode_return_to

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations

  sig { void }
  def show
    target_path = upgrade_target_path
    redirect_to preserve_tracking_params_path(target_path, return_to_params)
  end

  private

  sig { returns(String) }
  def upgrade_target_path
    if copilot_user.has_max_access?
      settings_billing_budgets_path
    elsif copilot_user.has_pro_plus_access?
      max_signup_enabled? ? copilot_max_signup_path : settings_billing_budgets_path
    elsif copilot_user.has_educational_access?
      copilot_pro_signup_path
    elsif copilot_user.has_pro_access?
      copilot_pro_plus_signup_path
    else
      copilot_pro_signup_path
    end
  end

  # Forward the validated return_to value so the target signup controller's
  # set_vscode_return_to before_action also picks it up.
  sig { returns(T::Hash[Symbol, String]) }
  def return_to_params
    validated_return_to = session[:copilot_vscode_return_to]
    return {} unless validated_return_to.present?
    { return_to: validated_return_to.to_s }
  end

  sig { returns(T::Boolean) }
  def max_signup_enabled?
    FeatureFlag.vexi.enabled?(:copilot_max_sku_signup, current_user, default: false)
  end
end
