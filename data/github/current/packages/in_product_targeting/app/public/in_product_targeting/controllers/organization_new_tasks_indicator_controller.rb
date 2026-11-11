# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module Controllers
    class OrganizationNewTasksIndicatorController < ApplicationController
      include InProductTargeting::OrganizationNudgeConcern

      depends_on_clusters ApplicationRecord::Domain::Users,
        ApplicationRecord::Mysql1,
        ApplicationRecord::Collab,
        ApplicationRecord::IamAbilities

      before_action :login_required

      MAX_ORGANIZATIONS_TO_CHECK = 100

      sig { void }
      def show
        is_user_eligible_for_experiment =
          !GitHub.multi_tenant_enterprise? &&
          !GitHub.enterprise? &&
          !current_user.is_enterprise_managed? &&
          current_user.subscribed_to_in_product_messages? &&
          current_user.feature_flag_enabled?(:organization_new_tasks_nudges, default: false)

        org_has_nudge = is_user_eligible_for_experiment && current_user.organizations.limit(MAX_ORGANIZATIONS_TO_CHECK).any? do |org|
          nudge_to_show_settings_page(current_user, org) != nil
        end

        render json: {
          # Whether to render the experiment at all
          # If false, then the page will render completely normally
          # If true, then we show the New Tasks button
          enableOrganizationNewTasksExperiment: org_has_nudge,

          # Show the New Tasks button when experiment is enabled
          showNewTasksButton: org_has_nudge
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
