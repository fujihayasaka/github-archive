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
    ApplicationRecord::Profiles,
    only: [:index]

  def index
    render "stafftools/users/trial_limits/index", locals: { user: this_user }
  end

  def update
    trial_limiter = EnterpriseTrialLimit.new(user: this_user)
    previous_limit = trial_limiter.created_trials_limit

    if params[:limit_type] == "default"
      trial_limiter.reset_to_default!
      action_description = "Trial limit reset to default"
    elsif params[:limit_type] == "custom"
      limit_value = params[:limit]&.to_i || 0
      trial_limiter.set_limit!(limit_value)
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
