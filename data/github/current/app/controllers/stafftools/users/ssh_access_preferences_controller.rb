# typed: true
# frozen_string_literal: true

class Stafftools::Users::SshAccessPreferencesController < StafftoolsController
  VALUE_NOTICE_MAPPING = {
    true => "Git SSH access enabled %{policy_level}.",
    false => "Git SSH access disabled %{policy_level}.",
    "_clear" => "Setting cleared. Instance default will be used.",
  }.freeze

  POLICY_MAPPING = {
    true => "and enforced on all repositories",
    false => "by default",
  }.freeze

  before_action :ensure_user_exists

  def update
    if request_to_clear?
      this_user.clear_ssh(current_user)
    elsif request_to_enable?
      this_user.enable_ssh(current_user, policy_param_provided?)
    else
      this_user.disable_ssh(current_user, policy_param_provided?)
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

  def request_to_enable?
    value_param
  end

  def value_param
    value = params[:value].presence || false

    if value.in? %w[true false]
      value = value == "true"
    end

    value
  end

  def policy_param_provided?
    params[:ssh_local_policy].present?
  end
end
