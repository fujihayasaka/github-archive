# typed: true
# frozen_string_literal: true

class Stafftools::Users::TrialLimitsController < Stafftools::Users::BillingController
  before_action :ensure_user_exists
  before_action :dotcom_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Repositories,
    only: [:index]

  def index
    render "stafftools/users/trial_limits/index", locals: { user: this_user }
  end

  def update
    enterprise_trial_limit = EnterpriseTrialLimit.new(user: this_user)

    previous_limit = enterprise_trial_limit.limit

    if params[:limit_type] == "default"
      enterprise_trial_limit.reset_to_default!
      action_description = "Trial limit reset to default"
    elsif params[:limit_type] == "custom"
      limit_value = params[:limit]&.to_i || 0
      enterprise_trial_limit.set_limit!(limit_value)
      action_description = "Trial limit set to #{limit_value}"
    end

    payload = {
      user: this_user,
      action: action_description,
      limit_value: params[:limit_type] == "default" ? EnterpriseTrialLimit.default_limit : params[:limit]&.to_i,
      previous_limit: previous_limit,
    }.merge(GitHub.guarded_audit_log_staff_actor_entry(current_user))

    instrument("user.change_enterprise_trial_limit", payload)

    flash[:notice] = action_description
    redirect_to stafftools_user_trial_limits_path(this_user)
  end
end
