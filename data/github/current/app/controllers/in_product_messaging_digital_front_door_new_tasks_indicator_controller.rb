# typed: true
# frozen_string_literal: true

class InProductMessagingDigitalFrontDoorNewTasksIndicatorController < ApplicationController
  include DigitalFrontDoor::NudgeConcern
  depends_on_clusters ApplicationRecord::Domain::Users,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab

  before_action :login_required

  def show
    is_user_eligible_for_experiment =
      !GitHub.multi_tenant_enterprise? &&
      !GitHub.enterprise? &&
      !current_user.is_enterprise_managed? &&
      current_user.businesses(membership_type: :admin).any? &&
      current_user&.feature_flag_enabled?(:dfd_new_tasks, default: false)

    business_has_nudge = current_user&.businesses.any? do |business|
      business_has_nudge_to_show?(current_user, business)
    end

    enable_dfd_new_tasks_experiment = is_user_eligible_for_experiment && business_has_nudge

    render json: {
      # Whether to render the experiment at all
      # If false, then the page will render completely normally
      # If true, then we will track the A/B impression and render one of the variants
      enableDfdNewTasksExperiment: enable_dfd_new_tasks_experiment,
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
