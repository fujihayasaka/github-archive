# typed: true
# frozen_string_literal: true

class Stafftools::Users::ForcePushPreferencesController < StafftoolsController
  VALUE_NOTICE_MAPPING = {
    false => "Force pushing allowed %{policy_level}.",
    "all" => "Force pushing blocked %{policy_level}.",
    "default" => "Force pushing blocked on the default branch %{policy_level}.",
    "_clear" => "Setting cleared. Instance default will be used.",
  }.freeze

  POLICY_MAPPING = {
    true => "and enforced on all repositories",
    false => "by default",
  }.freeze

  before_action :ensure_user_exists

  def update
    if request_to_clear?
      this_user.clear_force_push_rejection(current_user)
    elsif value_persisted?
      this_user.set_force_push_rejection(this_user.force_push_rejection, current_user, policy_param_provided?)
    else
      this_user.set_force_push_rejection(value_param, current_user, policy_param_provided?)
    end

    redirect_to(
      stafftools_user_administrative_tasks_path(this_user),
      notice: VALUE_NOTICE_MAPPING[value_param] % {
        policy_level: POLICY_MAPPING[policy_param_provided?],
      },
    )
  end

  private

  def request_to_clear?
    value_param == "_clear"
  end

  def value_persisted?
    params[:value] != "" && params[:value].nil?
  end

  def value_param
    params[:value].presence || false
  end

  def policy_param_provided?
    params[:policy].present?
  end
end
