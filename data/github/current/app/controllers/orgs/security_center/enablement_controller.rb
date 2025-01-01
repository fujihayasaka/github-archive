# typed: true
# frozen_string_literal: true

module Orgs
  module SecurityCenter
    class EnablementController < AbstractSecurityCenterController
      extend T::Sig
      include ApplicationHelper
      include SecurityAnalysisSettingsHelper
      include ControllerMethods::SecurityAnalysisSettings

      # Access
      before_action :organization_read_required
      before_action :security_center_required
      before_action :redirect_if_repo_not_found, only: [:update]
      before_action :repo_manage_code_security_settings_required

      after_action :log_update_result_to_datadog, only: [:update]

      depends_on_clusters \
        ApplicationRecord::Billing,
        ApplicationRecord::Collab,
        ApplicationRecord::Configurations,
        ApplicationRecord::Iam,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Mysql1,
        ApplicationRecord::Mysql2,
        ApplicationRecord::Mysql5,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Repositories,
        ApplicationRecord::Spokes,
        ApplicationRecord::Notify,
        only: [:index]

      depends_on_clusters \
       ApplicationRecord::Copilot,
        ApplicationRecord::SecurityOverviewAnalytics,
        only: [:index],
        optional: true

      def index
        begin
          advanced_security_contributor_count = AdvancedSecurityLicense.contributors_for_repos(
            entity: current_repository.organization,
            repository_ids: [params[:repo_id].to_i],
          )
        rescue AdvancedSecurityLicense::TurboghasError => e
          Failbot.report(e, catalog_service: "github/advanced_security_billing")
          advanced_security_contributor_count = 0
        end

        render partial: "orgs/security_center/coverage/security_settings/enablement_dialog_content", locals: {
          repo: current_repository,
          repo_id: params[:repo_id],
          repo_name: params[:repo_name],
          repo_visibility: params[:repo_visibility],
          advanced_security_contributor_count: advanced_security_contributor_count,
          enablement_data: settings_model,
        }
      end

      def update
        dependencies_not_satisfied, message = dependencies_not_satisfied?(params)
        if dependencies_not_satisfied
          GitHub.logger.warn("Failed to update settings: Dependencies not satisfied: #{message}", "code.namespace": self.class.name, "code.function": __method__)
          flash[:error] = message
          return redirect_to :back
        end

        filtered_params = enablement_params
          .then { |params| strip_features_blocked_by_policy(params) }
          .then { |params| strip_features_not_updated(params) }
          .then { |params| add_auto_codeql_param_if_changing_query_suite(params) }

        update_types, update_options = filtered_params.partition { |_k, v| v == "1" || v == "0" }.map(&:to_h)
        update_options = nil if update_options.blank?
        GitHub.logger.with_named_tags(
          "gh.security_center.enablement.update_types": update_types.keys.join(","),
          "gh.security_center.enablement.update_options": update_options&.map { |k, v| "#{k}:#{v}" }&.join(","),
        ) do
          advanced_security_params = filtered_params.slice(:advanced_security_enabled)
          error_type, error_message = update_ghas_settings(advanced_security_params, owner)
          if error_type.present?
            GitHub.logger.warn("Failed to update advanced security settings: #{error_message}", "code.namespace": self.class.name, "code.function": __method__)
            flash[:error] = error_message
            return redirect_to :back
          end

          security_params = filtered_params.except(:advanced_security_enabled)
          error_type, error_message = update_security_products_settings(security_params, owner)
          if error_type.present?
            GitHub.logger.warn("Failed to update security products settings: #{error_message}", "code.namespace": self.class.name, "code.function": __method__)
            flash[:error] = error_message
            return redirect_to :back
          end
        end

        flash[:notice] = "Repository settings saved."
        flash[:enablement_updated] = { current_repository.id => filtered_params.keys }
        redirect_to :back
      end

      private

      # SecurityAnalysisSettingsHelper requires owner to be defined
      memoize def owner
        this_organization
      end

      sig { returns(BlockedSettings) }
      memoize def blocked_settings
        BlockedSettings.new(this_organization)
      end

      sig { returns(::Repositories::Settings::SecurityAnalysisEnablementFormComponent::Data) }
      memoize def settings_model
        create_toggled_settings_model(blocked_settings: blocked_settings)
      end

      # SecurityAnalysisSettingsHelper requires current_repository to be defined
      memoize def current_repository
        Repository.find_by(id: params[:repo_id], owner_id: owner.id)
      end

      memoize def enablement_params
        # Can't extract the data from params like 'params.slice(:key1, :key2)'
        # because of error: "unable to convert unpermitted parameters to hash"
        [
          :advanced_security_enabled,
          :dependency_graph_enabled,
          :vulnerability_alerts_enabled,
          :vulnerability_updates_enabled,
          :auto_codeql_enabled,
          :auto_codeql_query_suite,
          :token_scanning_enabled,
          :token_scanning_push_protection_enabled
        ].filter_map { |p| [p, params[p]] if params[p] }.to_h
      end

      def dependencies_not_satisfied?(params)
        return [true, "Dependabot alerts requires dependency graph to be enabled"] if params[:vulnerability_alerts_enabled] == "1" &&
          params[:dependency_graph_enabled] != "1"

        return [true, "Dependabot security updates requires Dependabot alerts to be enabled"] if params[:vulnerability_updates_enabled] == "1" &&
          params[:vulnerability_alerts_enabled] != "1"

        return [true, "Code scanning requires Advanced Security to be enabled"] if params[:auto_codeql_enabled] == "1" &&
          params[:advanced_security_enabled] != "1" && !current_repository.public?

        return [true, "Secret scanning requires Advanced Security to be enabled"] if params[:token_scanning_enabled] == "1" &&
          params[:advanced_security_enabled] != "1" && !current_repository.public?

        return [true, "Push protection requires secret scanning to be enabled"] if params[:token_scanning_push_protection_enabled] == "1" &&
          params[:token_scanning_enabled] != "1"
      end

      def update_ghas_settings(advanced_security_params, owner)
        return unless advanced_security_params.present?
        GitHub.logger.info("Updating advanced security settings", "code.namespace": self.class.name, "code.function": __method__)

        return "not_allowed_on_public_repo", "GitHub Advanced Security cannot be enabled on public repos" unless current_repository.advanced_security_configurable?

        # Abort if enabling GHAS is not allowed (due to the business policy)
        if advanced_security_params[:advanced_security_enabled] == "1" &&
          !current_repository.advanced_security_enabled? &&
          advanced_security_blocked_by_policy?

          return "blocked_by_policy", "GitHub Advanced Security could not be enabled because of a policy setting for the organization"
        end

        return "blocked_by_toggling_in_progress", blocked_settings.repo_message if blocked_settings.advanced_security?

        # Abort if enabling GHAS would push the license over its seat limit.
        # The UI for this should be disabled in this case, but we check here too
        # to prevent against accidentally going over the license limit by viewing an
        # outdated page, or to a lesser extent by deliberate manipulation of the
        # form submission.
        if current_repository.enforce_advanced_security_committers_limits? &&
          advanced_security_params[:advanced_security_enabled] == "1" &&
          !current_repository.advanced_security_enabled? &&
          current_repository.enabling_advanced_security_would_exceed_seat_allowance?

          preamble = if owner.is_a?(Organization) && owner.advanced_security_billable_entity?
            "the parent organization"
          else
            "the parent enterprise"
          end

          return "ghas_seat_limit_reached", "GitHub Advanced Security could not be enabled because #{preamble} " +
            advanced_security_blocked_by_seat_count_message(target: current_repository, seats_needed: current_repository.seat_usage_increase_if_advanced_security_enabled)
        end

        if can_manage_security_products?
          advanced_security_params.merge!(enablement_action: "security_coverage_page_enablement")
        end

        result = SecurityProduct::ServiceManager.new(current_repository).toggle_services_with_form_inputs(current_user, params: advanced_security_params, use_human_readable_error: true)
        if result.error?
          ["update_failed", "Could not update repository settings. #{result.error}"]
        end
      end

      def update_security_products_settings(security_params, owner)
        return unless security_params.present?
        GitHub.logger.info("Updating security products settings", "code.namespace": self.class.name, "code.function": __method__)

        # ServiceManager is currently an untyped file while this file is typed, so Sorbet was complaining about changing the result type
        # from typed to untyped when we get the result from ServiceManager. As a workaround, we need to explicitly cast result to untyped.
        result = T.let(nil, T.untyped)

        if can_manage_security_products?
          security_params.merge!(enablement_action: "security_coverage_page_enablement")
        end

        result = SecurityProduct::ServiceManager.new(current_repository).toggle_services_with_form_inputs(current_user, params: security_params, use_human_readable_error: true)

        if result.error?
          ["update_failed", "Error saving your changes. #{result.error}"]
        elsif current_repository.errors.any?
          ["update_failed", "Error saving your changes."]
        end
      rescue CodeScanning::AutoCodeqlError => e
        ["auto_codeql_error", "Error saving your changes."]
      end

      def strip_features_blocked_by_policy(security_params)
        security_params.select do |param|
          case param.to_s
          when "dependency_graph_enabled"
            next false if settings_model.dependency_graph_blocked_by_policy
          when "vulnerability_alerts_enabled"
            next false if settings_model.dependabot_alerts_blocked_by_policy
          when "vulnerability_updates_enabled"
            next false if settings_model.dependabot_security_updates_blocked_by_policy
          when "advanced_security_enabled"
            next false if settings_model.advanced_security_blocked_by_policy
          when "token_scanning_enabled"
            next false if settings_model.secret_scanning_blocked_by_policy
          when "token_scanning_push_protection_enabled"
            next false if settings_model.secret_scanning_push_protection_blocked_by_policy
          end

          true
        end
      end

      # strip features if the form value is equal to the current value
      def strip_features_not_updated(security_params)
        security_params.select do |param|
          case param.to_s
          when "dependency_graph_enabled"
            next false if make_boolean(security_params[:dependency_graph_enabled]) == settings_model.dependency_graph_enabled
          when "vulnerability_alerts_enabled"
            next false if make_boolean(security_params[:vulnerability_alerts_enabled]) == settings_model.dependabot_alerts_enabled
          when "vulnerability_updates_enabled"
            next false if make_boolean(security_params[:vulnerability_updates_enabled]) == settings_model.dependabot_security_updates_enabled
          when "advanced_security_enabled"
            next false if make_boolean(security_params[:advanced_security_enabled]) == settings_model.advanced_security_enabled
          when "auto_codeql_enabled"
            next false if make_boolean(security_params[:auto_codeql_enabled]) == settings_model.code_scanning_default_setup_user_has_enabled
          when "auto_codeql_query_suite"
            next false if security_params[:auto_codeql_query_suite] == settings_model.code_scanning_default_setup_active_suite
          when "token_scanning_enabled"
            next false if make_boolean(security_params[:token_scanning_enabled]) == settings_model.secret_scanning_enabled
          when "token_scanning_push_protection_enabled"
            next false if make_boolean(security_params[:token_scanning_push_protection_enabled]) == settings_model.secret_scanning_push_protection_enabled
          end

          true
        end
      end

      def add_auto_codeql_param_if_changing_query_suite(security_params)
        security_params = security_params.clone

        # If the query suite is changing and auto codeql is staying enabled,
        # we need to mark auto codeql for enablement so ServiceManager processes the update.
        if (
          security_params.include?(:auto_codeql_query_suite) &&
          security_params.exclude?(:auto_codeql_enabled) &&
          settings_model.code_scanning_default_setup_user_has_enabled
        )
          security_params[:auto_codeql_enabled] = "1"
        end

        security_params
      end

      def make_boolean(input_value)
        input_value == "1"
      end

      def repo_manage_code_security_settings_required
        if current_repository.nil?
          GitHub.logger.warn("Repository not found", "code.namespace": self.class.name, "code.function": __method__)
          log_update_result_to_datadog
          return render_404
        end

        render_404 unless SecurityProduct::Permissions::RepoAuthz.new(current_repository, actor: current_user).can_manage_security_products?
      end

      def redirect_if_repo_not_found
        if current_repository.nil?
          GitHub.logger.warn("Repository not found", "code.namespace": self.class.name, "code.function": __method__)
          log_update_result_to_datadog
          flash[:error] = "Repository not found."
          redirect_to :back
        end
      end

      def set_log_context
        args = {
          "gh.owner.id": current_repository&.owner_id, # Can't use `owner` or `this_organization` in case the repo provided in the params isn't part of this org
          "gh.owner.login": current_repository&.owner_display_login, # Can't use `owner` or `this_organization` in case the repo provided in the params isn't part of this org
          "gh.repo.id": params[:repo_id],
          "gh.repo.name": params[:repo_name],
        }

        super do
          GitHub.logger.with_named_tags(args) { yield }
        end
      end

      # This method is duplicated from the SettingsController. We need this because it's used by our data component,
      # otherwise it'll error out.
      def used_by_selection_view_packages # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
        @used_by_selection_view_packages ||= Platform::Loaders::Dependencies.load_packages({
          package_filter: {
            repository_id: current_repository.id,
            first: 100,
            preview: current_repository.dependency_graph_preview?,
          },
          dependents_filter: { type: :repository },
          include_dependent_counts: true,
        }).sync.value { [] }
      end

      def log_update_result_to_datadog
        result = flash[:enablement_updated].present? ? "success" : "failure"
        GitHub.dogstats.increment("security_center.coverage_enablement_settings", tags: datadog_tags + [
          "is_org_admin:#{owner.adminable_by?(current_user)}",
          "result:#{result}",
        ])
      end
    end
  end
end
