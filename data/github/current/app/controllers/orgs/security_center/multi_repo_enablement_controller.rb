# typed: strict
# frozen_string_literal: true

module Orgs
  module SecurityCenter
    class MultiRepoEnablementController < AbstractSecurityCenterController
      extend T::Sig
      include ApplicationHelper

      MultiRepoEnablementContentComponent = ::SecurityCenter::Coverage::Enablement::MultiRepoEnablementContentComponent

      MAX_NUM_SELECTED_REPO_IDS = ::Orgs::SecurityCenter::CoverageController::PER_PAGE

      # Access
      before_action :organization_read_required
      before_action :security_center_required
      before_action :validate_request_and_redirect_if_invalid, only: [:update]

      # Telemetry
      before_action :track_enablement_usage, only: [:update]

      depends_on_clusters \
        ApplicationRecord::Billing,
        ApplicationRecord::Collab,
        ApplicationRecord::Configurations,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Mysql1,
        ApplicationRecord::Mysql2,
        ApplicationRecord::Mysql5,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Repositories,
        ApplicationRecord::Spokes,
        ApplicationRecord::Iam,
        only: [:index]

      depends_on_clusters \
        ApplicationRecord::Copilot,
        ApplicationRecord::Notify,
        ApplicationRecord::SecurityOverviewAnalytics,
        only: [:index], optional: true

      sig { void }
      def index
        enablement_data = enablement_helper.content_component_data
        return render_404 if enablement_data.nil?

        render(
          MultiRepoEnablementContentComponent.new(enablement_data),
          layout: false,
        )
      end

      sig { void }
      def update
        ::SecurityCenter::OrganizationEnablementJob.perform_later(
          actor_id: current_user.id,
          organization_id: this_organization.id,
          repositories_scope: use_query? ? query : selected_repo_ids,
          update_types: params_to_update_types,
          update_options: params_to_update_options,
          user_session_id: user_session.id
        )

        flash_and_redirect_back(notice: "Security settings are being updated for the selected repositories.")
      end

      private

      sig { returns(::SecurityCenter::Coverage::Enablement::MultiRepoEnablement) }
      memoize def enablement_helper
        ::SecurityCenter::Coverage::Enablement::MultiRepoEnablement.new(
          actor: current_user,
          org: this_organization,
          repo_ids_or_query_string: use_query? ? query : selected_repo_ids,
          user_session:
        )
      end

      sig { params(messages: T::Hash[Symbol, String]).void }
      def flash_and_redirect_back(messages)
        flash.update(messages)
        redirect_back_or_to(security_center_coverage_path(org: this_organization))
      end

      sig { returns(T.nilable(String)) }
      def invalid_request_message
        return "No settings were selected for update." if params_to_update_types.empty?
        return "No repositories selected." if !use_query? && selected_repo_ids.empty?
        return "Invalid request." unless valid_num_selected_repos?
      end

      sig { returns(T::Array[Symbol]) }
      memoize def params_to_update_types
        [
          [:dependency_graph, :dependency_graph_enable_all, :dependency_graph_disable_all],
          [:dependabot_alerts, :security_alerts_enable_all, :security_alerts_disable_all],
          [:dependabot_security_updates, :vulnerability_updates_enable_all, :vulnerability_updates_disable_all],
          [:advanced_security, :advanced_security_enable_all, :advanced_security_disable_all],
          [:codeql_default_setup, :auto_codeql_enable_all, :auto_codeql_disable_all],
          [:secret_scanning_alerts, :secret_scanning_enable_all, :secret_scanning_disable_all],
          [:secret_scanning_validity_checks, :secret_scanning_validity_checks_enable_all, :secret_scanning_validity_checks_disable_all],
          [:secret_scanning_lower_confidence_patterns, :secret_scanning_lower_confidence_patterns_enable_all, :secret_scanning_lower_confidence_patterns_disable_all],
          [:secret_scanning_push_protection, :secret_scanning_push_protection_enable_all, :secret_scanning_push_protection_disable_all]
        ].map do |param_key, enable_type, disable_type|
          next unless params[param_key].present?
          next unless %w[0 1].include?(params[param_key])

          ActiveRecord::Type::Boolean.new.cast(params[param_key]) ? enable_type : disable_type
        end.compact
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      memoize def params_to_update_options
        options = {}
        [:auto_codeql_query_suite].each do |param_key|
          next unless params[param_key].present?
          options[param_key] = params[param_key]
        end

        if can_manage_security_products?
          options.merge!(enablement_action: "security_coverage_page_enablement")
        end

        options.compact
      end

      sig { returns(T::Array[Integer]) }
      memoize def selected_repo_ids
        return [] if use_query?
        Array(params[:selected_repo_ids]&.split(",")).map(&:to_i)
      end

      sig { returns(T::Boolean) }
      memoize def valid_num_selected_repos?
        return true if use_query?
        return false if selected_repo_ids.empty?
        return false if selected_repo_ids.size > MAX_NUM_SELECTED_REPO_IDS
        true
      end

      sig { returns(String) }
      memoize def query
        String(params[:query])
      end

      sig { returns(T::Boolean) }
      memoize def use_query?
        ActiveRecord::Type::Boolean.new.cast(params[:use_query]) == true
      end

      sig { void }
      def validate_request_and_redirect_if_invalid
        error_message = invalid_request_message
        flash_and_redirect_back(error: error_message) if error_message
      end

      sig { void }
      def track_enablement_usage
        # If the user is selecting only the first page of repos vs. "Select all"
        stats_tags = ["repo_selection:#{use_query? ? "by_query" : "by_repo_ids"}"]
        log_tags = { "gh.security_center.enablement.repo_scope": use_query? ? "by_query" : "by_repo_ids" }

        if use_query?
          # Filters that are used to get to the subset of repos selected
          filter_keys = ::Search::Queries::SecurityCenter::CoverageQueryParser.new(query).used_qualifiers
          stats_tags.push(*T.unsafe(filter_keys).map { |filter_key| "has_filter:#{filter_key}" })
          log_tags.merge!("gh.security_center.enablement.query_filters": filter_keys.join(","))
        else
          # How many repos users are selecting at once, and maybe the ids
          GitHub.dogstats.distribution("security_center.multi_repo_enablement.selected_repo_count", selected_repo_ids.count)
          log_tags.merge!("gh.security_center.enablement.selected_repo_ids": selected_repo_ids.join(","))
        end

        # Overall initial and desired states of features for the selected repos
        params_to_update_types.each { |update_type| stats_tags << "has_update_type:#{update_type}" }
        log_tags.merge!("gh.security_center.enablement.update_types": params_to_update_types.join(","))

        update_options = params_to_update_options.map { |k, v| "#{k}:#{v}" }.join(",")
        log_tags.merge!("gh.security_center.enablement.update_options": update_options) unless update_options.blank?

        GitHub.dogstats.increment("security_center.multi_repo_enablement.usage", tags: stats_tags)
        log_info("Enablement update requested", **log_tags)
      end
    end
  end
end
