# typed: true
# frozen_string_literal: true

# this class is responsible for mapping the form inputs from ->
# the security_analysis html form as submitted by our users into a controller
# into ->
# the specific set of services and options that are to be enabled.
#
# this allows us to separate the html form's implementation details from the
# actual service enablement procedure.
module SecurityProduct
  class SettingsForm
    # each one of these represents a toggle on the form page that is submitted
    # as a parameter into the controller, and maps it to its corresponding service
    FORM_INPUTS_MAPPING = {
      innersource_advisories_enabled: :innersource_advisories,
      private_vulnerability_reporting_enabled: :private_vulnerability_reporting,
      dependency_graph_enabled: :dependency_graph,
      dependency_graph_autosubmit_action_enabled: :dependency_graph_autosubmit_action,
      dependabot_config_file_enabled: :dependabot_config_file,
      dependabot_on_actions_enabled: :dependabot_on_actions,
      dependabot_self_hosted_enabled: :dependabot_self_hosted,
      dependabot_autofix_enabled: :dependabot_autofix,
      vulnerability_alerts_enabled: :vulnerability_alerts,
      vulnerability_updates_enabled: :vulnerability_updates,
      vulnerability_updates_grouping_enabled: :vulnerability_updates_grouping,
      advanced_security_enabled: :advanced_security,
      auto_codeql_enabled: :auto_codeql,
      token_scanning_enabled: :token_scanning,
      token_scanning_push_protection_enabled: :token_scanning_push_protection,
      token_scanning_validity_checks_enabled: :token_scanning_validity_checks,
      token_scanning_lower_confidence_patterns_enabled: :token_scanning_lower_confidence_patterns,
      token_scanning_generic_secrets_enabled: :token_scanning_generic_secrets,
      token_scanning_delegated_bypass_enabled: :token_scanning_delegated_bypass,
    }

    # These are actions we use to determine the context of the form submission
    # These action contexts should allow us to override security configuration
    # enforcement on a repository if forms were submitted from security products configuration page
    # or the enterprise bulk (enable all / disable all) enablement page
    VALID_ACTIONS = %w(security_configuration_enablement enterprise_bulk_enablement security_coverage_page_enablement)

    attr_reader :params, :repository
    def initialize(params, repository:)
      @params = params
      @repository = repository
    end

    def parsed_param_services
      if defined?(@parsed_param_services)
        return @parsed_param_services
      end

      disable_services = []
      enable_services = []

      FORM_INPUTS_MAPPING.each do |key, sym|
        if (toggle = params[key])
          if toggle == "0"
            disable_services << [sym, parse_options(sym)]
          elsif toggle == "1"
            enable_services  << [sym, parse_options(sym)]
          end
        end
      end

      @parsed_param_services = { enable: enable_services, disable: disable_services }
    end

    # sometimes background jobs will provide an additional option
    # for the service being enabled, so here we parse it out
    def parse_options(service_sym)
      opt = {}

      case service_sym
      when :advanced_security
        # for dependent services that may be enabled, also pass along any of their options
        opt[:skip_backfill_request] = params[:skip_backfill_request] == "1"
      when :auto_codeql
        opt[:fail_on_manual_workflow?] = params[:fail_on_manual_workflow] == "1"
        opt[:bulk?] = params[:bulk] == "1"
        opt[:query_suite] = params[:auto_codeql_query_suite] if params[:auto_codeql_query_suite].present?
      when :token_scanning
        opt[:skip_backfill_request] = params[:skip_backfill_request] == "1"
      when :vulnerability_updates
        skip_install_param = params[:skip_vulnerability_updates_dependabot_install]
        opt[:skip_install] = (skip_install_param == true)
      when :vulnerability_alerts
        opt[:dependabot_alerts_global_rule_enabled] = params[:dependabot_alerts_global_rule_enabled] == "1"
      when :dependency_graph_autosubmit_action
        opt[:labeled_runners] = params[:dependency_graph_autosubmit_action_use_labeled_runners] == "1"
      end

      opt[:is_repo_creation] = params[:is_repo_creation] if params[:is_repo_creation].present?
      opt[:skip_if_enabled] = params[:skip_if_enabled] if params[:skip_if_enabled].present?
      opt[:skip_if_disabled] = params[:skip_if_disabled] if params[:skip_if_disabled].present?

      if params[:enablement_action].present? && VALID_ACTIONS.include?(params[:enablement_action])
        opt[:enablement_action] = params[:enablement_action]
      end

      opt
    end

    def services_to_enable
      parsed_param_services[:enable]
    end

    def services_to_disable
      parsed_param_services[:disable]
    end
  end
end
