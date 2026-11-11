# typed: true
# frozen_string_literal: true

class InProductMessagingOrganizationNewTasksIndicatorController < ApplicationController # rubocop:todo GitHub/ControllersShouldHaveTests
  include InProductTargeting::OrganizationNudgeConcern

  depends_on_clusters ApplicationRecord::Domain::Users,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab

  before_action :login_required

  def show
    is_user_eligible_for_experiment =
      !GitHub.multi_tenant_enterprise? &&
      !GitHub.enterprise? &&
      !current_user.is_enterprise_managed?

    org_has_nudge = current_user&.organizations.any? do |org|
      next true if show_organization_tasks_nudge?(current_user, org, :raf_cb)
      next true if show_organization_tasks_nudge?(current_user, org, :win_cb_users_back_credit_offer_to_accept)
      next true if show_organization_tasks_nudge?(current_user, org, :win_cb_users_back_credit_assign_seats)
      next true if show_organization_tasks_nudge?(current_user, org, :win_cb_users_back_credit)
    end

    render json: {
      # Whether to render the experiment at all
      # If false, then the page will render completely normally
      # If true, then we show the New Tasks button
      enableOrganizationNewTasksExperiment: is_user_eligible_for_experiment && org_has_nudge,

      # Show the New Tasks button when experiment is enabled
      showNewTasksButton: is_user_eligible_for_experiment && org_has_nudge
    }
  end

  private

  # Since we're only dismissing notices for the current user, return current_user as the target
  def resource_for_conditional_access
    return :no_target_for_conditional_access unless logged_in?
    return :no_target_for_conditional_access if GitHub::DeniedLogins.include? current_user.display_login.downcase
    current_user
  end

  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
