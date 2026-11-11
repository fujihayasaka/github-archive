# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module Controllers
    class EnterpriseNewTasksIndicatorController < ApplicationController
      include InProductTargeting::DfdNudgeConcern
      include InProductTargeting::EnterpriseNudgeConcern

      depends_on_clusters ApplicationRecord::Domain::Users,
        ApplicationRecord::Mysql1,
        ApplicationRecord::Collab

      before_action :login_required

      sig { void }
      def show
        is_user_eligible_for_experiment =
          !GitHub.multi_tenant_enterprise? &&
          !GitHub.enterprise? &&
          !current_user.is_enterprise_managed?

        # Short-circuit: skip expensive business iteration + billing RPCs when user is ineligible.
        # Matches the pattern used in OrganizationNewTasksIndicatorController.
        is_admin = is_user_eligible_for_experiment && current_user.businesses(membership_type: :admin).any?
        business_has_nudge = is_user_eligible_for_experiment && current_user&.businesses.any? do |business|
          next true if is_admin && business_has_dfd_nudge_to_show?(current_user, business)
          next true if nudge_to_show(current_user, business) != nil
        end

        render json: {
          # deprecated: use `enableEnterpriseNewTasksExperiment` and `showNewTasksButton`.
          # This field is provided for a smooth transition, but once this change goes live we can remove this now unused field
          enableDfdNewTasksExperiment: business_has_nudge,

          # Whether to render the experiment at all
          # If false, then the page will render completely normally
          # If true, then we will track the A/B impression and render one of the variants
          enableEnterpriseNewTasksExperiment: is_user_eligible_for_experiment,

          # returns false if enableEnterpriseNewTasksExperiment is false
          # If false, track the A/B impression but dont show anything different OR the experiment is disabled
          # If true, track the A/B impression and show the New Tasks button
          showNewTasksButton: business_has_nudge # if we ever want to A|B the New Task Label, this is where we check the variant
        }
      end

      private

      # Since we're only dismissing notices for the current user, return current_user as the target
      sig { returns(T.any(Symbol, User)) }
      def resource_for_conditional_access
        return :no_target_for_conditional_access unless logged_in?
        return :no_target_for_conditional_access if GitHub::DeniedLogins.include? current_user.display_login.downcase
        current_user
      end

      sig { returns(Symbol) }
      def target_for_conditional_access
        :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      end
    end
  end
end
