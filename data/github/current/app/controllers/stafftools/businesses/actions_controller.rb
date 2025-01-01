# typed: true
# frozen_string_literal: true

module Stafftools
  module Businesses
    class ActionsController < Stafftools::Businesses::BusinessBaseController
      include Actions::LargerRunnersHelper
      include NetworkConfigurationsHelper

      before_action :ensure_actions_enabled

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Collab,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Ballast,
        ApplicationRecord::Configurations,
        ApplicationRecord::Repositories,
        ApplicationRecord::Billing,
        only: [:show]

      depends_on_clusters ApplicationRecord::Copilot,
        only: [:show], optional: true

      def show
        all_runner_groups = Actions::RunnerGroup.for_entity(this_business, include_runners: true, include_hosted_runner_groups: true, is_ui_read: true)
        runner_groups = all_runner_groups.filter { |group| !group.hosted? }
        hosted_runner_group = all_runner_groups.find { |group| group.hosted? }

        if this_business.can_use_larger_runners?
          larger_runners = Actions::LargerRunner.larger_runners_for(entity: this_business)
          larger_runners.each do |larger_runner|
            group = runner_groups.detect { |runner_group| runner_group.id == larger_runner.runner_group_id }
            if group.present?
              group.runners.append(larger_runner)
            end
          end
        end

        runners = runner_groups.flat_map(&:runners)
        disabled_runner_group_ids = list_disabled_network_configuration_ids(this_business)

        render "stafftools/businesses/actions/show", locals: {
          runner_groups: runner_groups,
          runners: runners,
          hosted_runner_group: hosted_runner_group,
          disabled_runner_group_ids: disabled_runner_group_ids
        }
      end

      def onboard_larger_runners # rubocop:todo GitHub/UseRestfulActions
        unless this_business.is_eligible_to_onboard_larger_runners?
          flash[:error] = "Business is not eligible to onboard to larger runners"
          redirect_to stafftools_actions_path(this_business)
          return
        end

        # Setup tenant in Actions
        result = Launch::Twirp.deployer_client.setup_tenant(this_business)
        unless result.call_succeeded?
          flash[:error] = "Failed to set up tenant for Business"
          redirect_to stafftools_actions_path(this_business)
          return
        end

        # Onboard account on dotcom side
        this_business.onboard_larger_runners(actor: ::User.staff_user)

        # Make any call to Runner service to fault-in account
        Actions::LargerRunner.larger_runners_for(entity: this_business)

        flash[:notice] = "Business has been successfully onboarded to larger runners"
        redirect_to stafftools_actions_path(this_business)
      end

      def larger_runners_manage_beta_features # rubocop:todo GitHub/UseRestfulActions
        unless this_business.is_larger_runners_onboarded? && this_business.can_use_larger_runners?
          flash[:error] = "Business is not onboarded to larger runners"
          redirect_to stafftools_actions_path(this_business)
          return
        end

        if params[:feature_name].present?
          feature_name = params[:feature_name]
        else
          flash[:error] = "Feature name is required"
          redirect_to stafftools_actions_path(this_business)
          return
        end

        if params[:feature_new_state] == "true"
          feature_new_state = true
        elsif params[:feature_new_state] == "false"
          feature_new_state = false
        else
          flash[:error] = "Feature new state is required"
          redirect_to stafftools_actions_path(this_business)
          return
        end

        result = Launch::Twirp::larger_runners_client.set_beta_feature(this_business, feature_name: feature_name, enabled: feature_new_state)
        unless result.call_succeeded?
          flash[:error] = "Failed to switch feature '#{feature_name}' to #{feature_new_state} for business."
          redirect_to stafftools_actions_path(this_business)
          return
        end

        flash[:notice] = "Feature #{feature_name} was #{feature_new_state ? "enabled" : "disabled" } for business successfully."
        redirect_to stafftools_actions_path(this_business)
      end

      def ensure_actions_enabled # rubocop:todo GitHub/UseRestfulActions
        render_404 unless GitHub.actions_enabled?
      end
    end
  end
end
