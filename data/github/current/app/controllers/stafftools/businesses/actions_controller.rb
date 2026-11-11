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

        # Billing and concurrency information
        if GitHub.billing_enabled?
          actions_plan_owner = ActionsPlanOwner.new(this_business)
          plan_name = actions_plan_owner.plan_name.titleize
          max_concurrent_jobs = actions_plan_owner.max_concurrent_jobs_guess
          max_concurrent_macos_jobs = actions_plan_owner.max_concurrent_macos_jobs_guess
        end

        # Fetch trust tier information
        tier_result = ::TrustTiers::Tier.for_billable_owner(this_business)
        trust_tier = tier_result.tier
        trust_tier_name = ::TrustTiers::Tier.tier_name(trust_tier)

        # Fetch concurrency limits from Launch service
        # Returns nil if no overrides are set (which is normal)
        concurrency_limits = fetch_concurrency_limits(this_business)

        render "stafftools/businesses/actions/show", locals: {
          runner_groups: runner_groups,
          runners: runners,
          hosted_runner_group: hosted_runner_group,
          disabled_runner_group_ids: disabled_runner_group_ids,
          plan_name: plan_name,
          max_concurrent_jobs: max_concurrent_jobs,
          max_concurrent_macos_jobs: max_concurrent_macos_jobs,
          concurrency_limits: concurrency_limits,
          trust_tier: trust_tier,
          trust_tier_name: trust_tier_name
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

      def update_concurrency_limits # rubocop:todo GitHub/UseRestfulActions
        total_limit = params[:total_limit].to_i
        macos_limit = params[:macos_limit].to_i

        if total_limit < 0 || macos_limit < 0
          flash[:error] = "Limits cannot be negative"
          redirect_to stafftools_actions_path(this_business)
          return
        end

        if total_limit > 0 && macos_limit > total_limit
          flash[:error] = "macOS limit cannot be greater than total limit"
          redirect_to stafftools_actions_path(this_business)
          return
        end

        # Get plan-based limits for validation
        actions_plan_owner = ActionsPlanOwner.new(this_business)
        plan_max_concurrent_jobs = actions_plan_owner.max_concurrent_jobs_guess
        plan_max_concurrent_macos_jobs = actions_plan_owner.max_concurrent_macos_jobs_guess

        # Validate total limit is at most double the plan-based limit
        if total_limit > (plan_max_concurrent_jobs * 2)
          flash[:error] = "Total limit (#{total_limit}) cannot exceed double the plan-based limit (#{plan_max_concurrent_jobs * 2})"
          redirect_to stafftools_actions_path(this_business)
          return
        end

        # Validate macOS limit is not increased beyond plan-based limit (can only be decreased)
        if macos_limit > plan_max_concurrent_macos_jobs
          flash[:error] = "macOS limit (#{macos_limit}) cannot exceed the plan-based limit (#{plan_max_concurrent_macos_jobs})"
          redirect_to stafftools_actions_path(this_business)
          return
        end

        success = Launch::Twirp.concurrency_limit_overrides_client.update_concurrency_limit_overrides(
          owner: this_business,
          total_limit: total_limit,
          macos_limit: macos_limit
        )

        if success
          flash[:notice] = "Concurrency limits updated successfully: Total=#{total_limit}, macOS=#{macos_limit}"

          # Log audit event
          audit_payload = {
            business: this_business.slug,
            business_id: this_business.id,
            total_limit: total_limit,
            macos_limit: macos_limit,
            plan_max_concurrent_jobs: plan_max_concurrent_jobs,
            plan_max_concurrent_macos_jobs: plan_max_concurrent_macos_jobs,
            from: "stafftools/businesses/actions#update_concurrency_limits"
          }
          GitHub.logger.info("About to instrument audit event", audit_payload)
          instrument("business.update_actions_concurrency_limits", audit_payload)
          GitHub.logger.info("Audit event instrumented successfully")

          GitHub.logger.info("Concurrency limits updated from stafftools",
            {
              "success" => true,
              "owner_id" => this_business.id,
              "owner_login" => this_business.slug,
              "owner_type" => "business",
              "total_limit" => total_limit,
              "macos_limit" => macos_limit,
              "plan_max_concurrent_jobs" => plan_max_concurrent_jobs,
              "plan_max_concurrent_macos_jobs" => plan_max_concurrent_macos_jobs,
            }
          )
        else
          flash[:error] = "Failed to update concurrency limits"
          GitHub.logger.error("Failed to update concurrency limits from stafftools",
            {
              "success" => false,
              "owner_id" => this_business.id,
              "owner_login" => this_business.slug,
              "owner_type" => "business",
            }
          )
        end

        redirect_to stafftools_actions_path(this_business)
      end

      private

      def fetch_concurrency_limits(owner)
        limits = Launch::Twirp.concurrency_limit_overrides_client.get_concurrency_limit_overrides(owner: owner)
        if limits.present? && (limits[:total].present? || limits[:macos].present?)
          {
            total: limits[:total],
            macos: limits[:macos],
            source: "launch_service"
          }
        else
          # No overrides set for this owner - this is a normal case
          nil
        end
      rescue => e
        GitHub.logger.error("Exception fetching concurrency limits from Launch service",
          {
            "owner_id" => owner.id,
            "owner_login" => owner.respond_to?(:login) ? owner.login : owner.slug,
            "owner_type" => "business",
            "exception" => e.message,
          }
        )
        nil
      end

      def ensure_actions_enabled # rubocop:todo GitHub/UseRestfulActions
        render_404 unless GitHub.actions_enabled?
      end
    end
  end
end
