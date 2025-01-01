# typed: true
# frozen_string_literal: true

class UpdateSecuritySettings
  include EscapeHelper
  include SecurityAnalysisSettingsHelper
  include GitHub::Memoizer
  include SecretScanning::Features::FeatureFlagHelper

  extend T::Sig

  PUSH_PROTECTION_CUSTOM_MSG_MAX_SIZE = 150

  # @param tenant [User] A user, organization, or business.
  # @param params [Hash] Setting names and their desired outcomes.
  #   Example: { advanced_security: "enable_all" }
  # @param actor [User, nil] The user performing the action.
  # @param source [string] The source of the perform request. Can be either "ui" or "rest-api"
  # @return [nil, Hash]
  #   - nil: If the update is successful.
  #   - Hash: If the update cannot be performed, a Hash with an :error key is returned.
  #       Example: { error: "GitHub Advanced Security could not be enabled because of a policy setting for the organization" }
  def self.perform(tenant, params, actor: nil, blocked_settings: nil, source: "ui")
    new(tenant, params, actor: actor, blocked_settings: blocked_settings, source: source).perform
  end

  attr_reader :blocked_settings

  def initialize(tenant, params, actor: nil, blocked_settings: nil, source: "ui")
    @tenant = tenant
    @params = params
    @actor = actor || tenant
    @blocked_settings = blocked_settings || BlockedSettings.new(tenant)
    @source = source
  end

  def perform
    # Abort if enabling GHAS is not allowed (due to the business policy)
    if @params[:advanced_security] == "enable_all" && !@tenant.policy_allows_advanced_security_enablement?
      return create_error_hash("GitHub Advanced Security could not be enabled because of a policy setting for the organization")
    end

    # Until enterprise teams have been reimplemented without org team sync, we will disable the ability to bulk enable GHAS across a business when ESM is enabled.
    # https://github.com/github/security-center/issues/6109
    if @params[:advanced_security] == "enable_all" && @tenant.is_a?(::Business) && EnterpriseTeam.enabled_for_organization_security_manager?(@tenant)
      return create_error_hash("GitHub Advanced Security could not be bulk enabled because the enterprise security managers feature is enabled")
    end

    if @params[:advanced_security_enabled_new_repos] == "enabled" && !@tenant.policy_allows_advanced_security_enablement?
      return create_error_hash("GitHub Advanced Security could not be enabled for new repositories because of a policy setting for the organization")
    end

    if @params[:advanced_security_enabled_new_user_namespace_repos] == "enabled" && !@tenant.policy_allows_advanced_security_enablement?
      return create_error_hash("GitHub Advanced Security could not be enabled for new user namespace repositories because of a policy setting for the enterprise")
    end

    if requested_security_product_is_blocked_by_in_progress_toggling?
      return create_error_hash(blocked_settings.message)
    end

    # Abort if enabling GHAS is not allowed (due to the business policy)
    if @params[:advanced_security_user_namespace] == "enable_all" && !@tenant.policy_allows_advanced_security_enablement?
      return create_error_hash("GitHub Advanced Security could not be enabled because of a policy setting for the organization")
    end

    # Abort if this operation would push the GHAS license over its seat limit
    # The UI for this should be disabled in this case, but we check here too
    # to prevent against accidentally going the license limit by viewing an
    # outdated page, or to a lesser extent by deliberate manipulation of the
    # form submission.
    if @tenant.enforce_advanced_security_committers_limits? &&
        (@params[:advanced_security] == "enable_all" || @params[:advanced_security_user_namespace] == "enable_all") &&
        @tenant.enabling_advanced_security_for_all_repos_would_exceed_seat_allowance?
      billable_owner = @tenant.billable_owner
      preamble = "the parent enterprise " if billable_owner.is_a?(Business) && billable_owner.advanced_security_billable_entity?

      return create_error_hash(
        "GitHub Advanced Security could not be enabled because #{preamble}" +
        advanced_security_blocked_by_seat_count_message(
          target: @tenant,
          seats_needed: @tenant.seat_usage_increase_if_advanced_security_enabled_for_all_repos
        )
      )
    end

    # Private Vulnerability Reporting
    if @params[:private_vulnerability_reporting] == "enable_all"
      update_settings_for_all_repos(:private_vulnerability_reporting_enable_all)
      instrument("private_vulnerability_reporting.enable")
    elsif @params[:private_vulnerability_reporting] == "disable_all"
      update_settings_for_all_repos(:private_vulnerability_reporting_disable_all)
      instrument("private_vulnerability_reporting.disable")
    end

    if @params[:private_vulnerability_reporting_new_repos] == "enabled"
      @tenant.enable_private_vulnerability_reporting_for_new_repos(actor: @actor)
      instrument("private_vulnerability_reporting_new_repos.enable")
    elsif @params[:private_vulnerability_reporting_new_repos] == "disabled"
      @tenant.disable_private_vulnerability_reporting_for_new_repos(actor: @actor)
      instrument("private_vulnerability_reporting_new_repos.disable")
    end

    # Dependency Graph
    if @params[:dependency_graph] == "enable_all"
      update_settings_for_all_repos(:dependency_graph_enable_all)
      instrument("dependency_graph.enable")
    elsif @params[:dependency_graph] == "disable_all"
      update_settings_for_all_repos(:dependency_graph_disable_all)
      instrument("dependency_graph.disable")
    end

    if @params[:dependency_graph_new_repos] == "enabled"
      @tenant.enable_dependency_graph_for_new_repos(actor: @actor)
      instrument("dependency_graph_new_repos.enable")
    elsif @params[:dependency_graph_new_repos] == "disabled"
      @tenant.disable_dependency_graph_for_new_repos(actor: @actor)
      instrument("dependency_graph_new_repos.disable")
    end

    # Dependabot Alerts
    if @params[:security_alerts] == "enable_all"
      update_settings_for_all_repos(:security_alerts_enable_all)

      event_name = @tenant.is_a?(Business) ? "business_dependabot_alerts.enable" : "dependabot_alerts.enable"
      instrument(event_name)
    elsif @params[:security_alerts] == "disable_all"
      update_settings_for_all_repos(:security_alerts_disable_all)

      event_name = @tenant.is_a?(Business) ? "business_dependabot_alerts.disable" : "dependabot_alerts.disable"
      instrument(event_name)
    end

    if @params[:security_alerts_new_repos] == "enabled"
      @tenant.enable_security_alerts_for_new_repos(actor: @actor)
      event_name = "dependabot_alerts_new_repos.enable"

      if @tenant.is_a?(Business)
        UpdateBusinessSecurityFeatureForNewReposJob.perform_later(@tenant, :security_alerts, :enable, @actor.id)
        event_name = "business_dependabot_alerts_new_repos.enable"
      end

      instrument(event_name)
    elsif @params[:security_alerts_new_repos] == "disabled"
      @tenant.disable_security_alerts_for_new_repos(actor: @actor)
      event_name = "dependabot_alerts_new_repos.disable"

      if @tenant.is_a?(Business)
        UpdateBusinessSecurityFeatureForNewReposJob.perform_later(@tenant, :security_alerts, :disable, @actor.id)
        event_name = "business_dependabot_alerts_new_repos.disable"
      end

      instrument(event_name)
    end

    # Dependabot security updates
    if @params[:vulnerability_updates] == "enable_all"
      update_settings_for_all_repos(:vulnerability_updates_enable_all)
      instrument("dependabot_security_updates.enable")
    elsif @params[:vulnerability_updates] == "disable_all"
      update_settings_for_all_repos(:vulnerability_updates_disable_all)
      instrument("dependabot_security_updates.disable")
    end

    if @params[:vulnerability_updates_new_repos] == "enabled"
      @tenant.enable_vulnerability_updates_for_new_repos(actor: @actor)
      instrument("dependabot_security_updates_new_repos.enable")
    elsif @params[:vulnerability_updates_new_repos] == "disabled"
      @tenant.disable_vulnerability_updates_for_new_repos(actor: @actor)
      instrument("dependabot_security_updates_new_repos.disable")
    end

    if Dependabot.grouped_security_updates_available_for?(@tenant)
      if @params[:vulnerability_updates_grouping] == "enable_all"
        update_settings_for_all_repos(:vulnerability_updates_grouping_enable_all)
        instrument("dependabot_security_updates_grouping.enable")
      elsif @params[:vulnerability_updates_grouping] == "disable_all"
        update_settings_for_all_repos(:vulnerability_updates_grouping_disable_all)
        instrument("dependabot_security_updates_grouping.disable")
      end

      if @params[:vulnerability_updates_grouping_new_repos] == "enabled"
        @tenant.enable_vulnerability_updates_grouping_for_new_repos(actor: @actor)
        instrument("dependabot_security_updates_grouping_new_repos.enable")
        if @tenant.is_a?(Organization) && @tenant.security_configurations_enabled?
          update_settings_for_all_repos(:vulnerability_updates_grouping_enable_all)
          instrument("dependabot_security_updates_grouping.enable")
        end
      elsif @params[:vulnerability_updates_grouping_new_repos] == "disabled"
        @tenant.disable_vulnerability_updates_grouping_for_new_repos(actor: @actor)
        instrument("dependabot_security_updates_grouping_new_repos.disable")
        if @tenant.is_a?(Organization) && @tenant.security_configurations_enabled?
          update_settings_for_all_repos(:vulnerability_updates_grouping_disable_all)
          instrument("dependabot_security_updates_grouping.disable")
        end
      end
    end

    if Dependabot.dependabot_on_actions_available_for?(@tenant)
      if @params[:dependabot_on_actions] == "enable_all"
        update_settings_for_all_repos(:dependabot_on_actions_enable_all)
        instrument("dependabot_on_actions.enable")
        @tenant.enable_dependabot_on_actions_for_new_repos(actor: @actor)
        instrument("dependabot_on_actions_new_repos.enable")
      elsif @params[:dependabot_on_actions] == "disable_all"
        update_settings_for_all_repos(:dependabot_on_actions_disable_all)
        instrument("dependabot_on_actions.disable")
      end

      if @params[:dependabot_on_actions_new_repos] == "enabled"
        @tenant.enable_dependabot_on_actions_for_new_repos(actor: @actor)
        instrument("dependabot_on_actions_new_repos.enable")
        if @tenant.is_a?(Organization) && @tenant.security_configurations_enabled?
          update_settings_for_all_repos(:dependabot_on_actions_enable_all)
          instrument("dependabot_on_actions.enable")
        end
      elsif @params[:dependabot_on_actions_new_repos] == "disabled"
        @tenant.disable_dependabot_on_actions_for_new_repos(actor: @actor)
        instrument("dependabot_on_actions_new_repos.disable")
        if @tenant.is_a?(Organization) && @tenant.security_configurations_enabled?
          update_settings_for_all_repos(:dependabot_on_actions_disable_all)
          instrument("dependabot_on_actions.disable")
        end
      end
    end

    if Dependabot.dependabot_self_hosted_available_for?(@tenant)
      if @params[:dependabot_self_hosted] == "enable_all"
        update_settings_for_all_repos(:dependabot_self_hosted_enable_all)
        instrument("dependabot_self_hosted.enable")
        @tenant.enable_dependabot_self_hosted_for_new_repos(actor: @actor)
        instrument("dependabot_self_hosted_new_repos.enable")
      elsif @params[:dependabot_self_hosted] == "disable_all"
        update_settings_for_all_repos(:dependabot_self_hosted_disable_all)
        instrument("dependabot_self_hosted.disable")
      end

      if @params[:dependabot_self_hosted_new_repos] == "enabled"
        @tenant.enable_dependabot_self_hosted_for_new_repos(actor: @actor)
        instrument("dependabot_self_hosted_new_repos.enable")
        if @tenant.is_a?(Organization) && @tenant.security_configurations_enabled?
          update_settings_for_all_repos(:dependabot_self_hosted_enable_all)
          instrument("dependabot_self_hosted.enable")
        end
      elsif @params[:dependabot_self_hosted_new_repos] == "disabled"
        @tenant.disable_dependabot_self_hosted_for_new_repos(actor: @actor)
        instrument("dependabot_self_hosted_new_repos.disable")
        if @tenant.is_a?(Organization) && @tenant.security_configurations_enabled?
          update_settings_for_all_repos(:dependabot_self_hosted_disable_all)
          instrument("dependabot_self_hosted.disable")
        end
      end
    end

    if Dependabot.dependabot_autofix_available_for?(@tenant)
      if @params[:dependabot_autofix] == "enable_all"
        update_settings_for_all_repos(:dependabot_autofix_enable_all)
        instrument("dependabot_autofix.enable")
        @tenant.enable_dependabot_autofix_for_new_repos(actor: @actor)
        instrument("dependabot_autofix_new_repos.enable")
      elsif @params[:dependabot_autofix] == "disable_all"
        update_settings_for_all_repos(:dependabot_autofix_disable_all)
        instrument("dependabot_autofix.disable")
      end

      if @params[:dependabot_autofix_new_repos] == "enabled"
        @tenant.enable_dependabot_autofix_for_new_repos(actor: @actor)
        instrument("dependabot_autofix_new_repos.enable")
        if @tenant.is_a?(Organization) && @tenant.security_configurations_enabled?
          update_settings_for_all_repos(:dependabot_autofix_enable_all)
          instrument("dependabot_autofix.enable")
        end
      elsif @params[:dependabot_autofix_new_repos] == "disabled"
        @tenant.disable_dependabot_autofix_for_new_repos(actor: @actor)
        instrument("dependabot_autofix_new_repos.disable")
        if @tenant.is_a?(Organization) && @tenant.security_configurations_enabled?
          update_settings_for_all_repos(:dependabot_autofix_disable_all)
          instrument("dependabot_autofix.disable")
        end
      end
    end

    if @tenant.advanced_security_configurable?
      # Advanced Security on existing repos
      if @params[:advanced_security] == "enable_all"
        update_settings_for_all_repos(:advanced_security_enable_all)
        event_name = @tenant.is_a?(Business) ? "business_advanced_security.enabled" : "org.advanced_security_enabled_on_all_repos"
        instrument(event_name)
      elsif @params[:advanced_security] == "disable_all"
        update_settings_for_all_repos(:advanced_security_disable_all)
        event_name = @tenant.is_a?(Business) ? "business_advanced_security.disabled" : "org.advanced_security_disabled_on_all_repos"
        instrument(event_name)
      end

      # Advanced Security on new repos
      if @params[:advanced_security_enabled_new_repos] == "enabled"
        # instrumentation called in enable_advanced_security_on_new_repos so no need to repeat
        @tenant.enable_advanced_security_on_new_repos(actor: @actor)
        if @tenant.is_a?(Business)
          UpdateBusinessSecurityFeatureForNewReposJob.perform_later(@tenant, :advanced_security, :enable, @actor.id)
          instrument("business_advanced_security.enabled_for_new_repos")
        end
      elsif @params[:advanced_security_enabled_new_repos] == "disabled"
        # instrumentation called in disable_advanced_security_on_new_repos so no need to repeat
        @tenant.disable_advanced_security_on_new_repos(actor: @actor)
        if @tenant.is_a?(Business)
          UpdateBusinessSecurityFeatureForNewReposJob.perform_later(@tenant, :advanced_security, :disable, @actor.id)
          instrument("business_advanced_security.disabled_for_new_repos")
        end
      end

      # Advanced Security on enterprise managed user repositories
      if @params[:advanced_security_user_namespace] == "enable_all"
        update_settings_for_all_repos(:advanced_security_enable_all, entity_type: :user)
        instrument("business_advanced_security.user_namespace_repos_enabled")
      elsif @params[:advanced_security_user_namespace] == "disable_all"
        update_settings_for_all_repos(:advanced_security_disable_all, entity_type: :user)
        instrument("business_advanced_security.user_namespace_repos_disabled")
      end

      # Advanced Security on new user namespace repos
      if @params[:advanced_security_enabled_new_user_namespace_repos] == "enabled"
        if @tenant.is_a?(Business)
          # method is only available on businesses
          @tenant.enable_advanced_security_on_new_user_namespace_repos(actor: @actor)
          instrument("business_advanced_security.enabled_for_new_user_namespace_repos")
        end
      elsif @params[:advanced_security_enabled_new_user_namespace_repos] == "disabled"
        if @tenant.is_a?(Business)
          # method is only available on businesses
          @tenant.disable_advanced_security_on_new_user_namespace_repos(actor: @actor)
          instrument("business_advanced_security.disabled_for_new_user_namespace_repos")
        end
      end
    end

    # Code Scanning on existing repos
    if @tenant.is_a?(Organization) && ::SecurityCenter::SecurityFeatures.code_scanning_enabled_for_instance?
      if @params[:code_scanning] == "enable_all"
        if @params.dig(:config, :query_suite) == "extended"
          update_settings_for_all_repos(:auto_codeql_enable_all_extended)
          instrument("org.codeql_enabled_extended")
        else
          update_settings_for_all_repos(:auto_codeql_enable_all)
          instrument("org.codeql_enabled")
        end
      elsif @params[:code_scanning] == "disable_all"
        update_settings_for_all_repos(:auto_codeql_disable_all)
        instrument("org.codeql_disabled")
      end

      # Code scanning recommend Extended query suite
      if @params[:code_scanning_recommend_extended_query_suite] == "enabled"
        @tenant.enable_code_scanning_recommend_extended_query_suite(actor: @actor)
        instrument("code_scanning_recommend_extended_query_suite.enabled")
      elsif @params[:code_scanning_recommend_extended_query_suite] == "disabled"
        @tenant.disable_code_scanning_recommend_extended_query_suite(actor: @actor)
        instrument("code_scanning_recommend_extended_query_suite.disabled")
      end

      # Code scanning Autofix
      if CodeScanning::Autofix.org_settings_configurable?(@tenant)
        case @params[:code_scanning_autofix]
        when "enabled"
          @tenant.enable_code_scanning_autofix_settings(actor: @actor)
          instrument("org.code_scanning_autofix_enabled")
        when "disabled"
          @tenant.disable_code_scanning_autofix_settings(actor: @actor)
          instrument("org.code_scanning_autofix_disabled")
        end
      end
    end

    # Secret Scanning on existing repos
    if @params[:secret_scanning] == "enable_all"
      update_settings_for_all_repos(:secret_scanning_enable_all, entity_type: :organization)
      update_settings_for_all_repos(:secret_scanning_enable_all, entity_type: :user) if @tenant.is_a?(Business)
      event_name = @tenant.is_a?(Business) ? "business_secret_scanning.enable" : "secret_scanning.enable"
      instrument(event_name)
    elsif @params[:secret_scanning] == "disable_all"
      update_settings_for_all_repos(:secret_scanning_disable_all, entity_type: :organization)
      update_settings_for_all_repos(:secret_scanning_disable_all, entity_type: :user) if @tenant.is_a?(Business)
      event_name = @tenant.is_a?(Business) ? "business_secret_scanning.disable" : "secret_scanning.disable"
      instrument(event_name)
    end

    # Secret Scanning on new repos
    if @params[:secret_scanning_new_repos] == "enabled"
      get_token_scanning_features.enable_secret_scanning_for_new_repos(actor: @actor)

      if @tenant.is_a?(Business)
        UpdateBusinessSecurityFeatureForNewReposJob.perform_later(@tenant, :secret_scanning, :enable, @actor.id)
      end

      event_name = @tenant.is_a?(Business) ? "business_secret_scanning.enabled_for_new_repos" : "secret_scanning_new_repos.enable"
      instrument(event_name)
    elsif @params[:secret_scanning_new_repos] == "disabled"
      get_token_scanning_features.disable_secret_scanning_for_new_repos(actor: @actor)

      if @tenant.is_a?(Business)
        UpdateBusinessSecurityFeatureForNewReposJob.perform_later(@tenant, :secret_scanning, :disable, @actor.id)
      end

      event_name = @tenant.is_a?(Business) ? "business_secret_scanning.disabled_for_new_repos" : "secret_scanning_new_repos.disable"
      instrument(event_name)
    end

    # Secret Scanning Validity Checks on existing repos
    if @params[:secret_scanning_validity_checks] == "enable_all"
      validity_checks = SecretScanning::Features::Owner::ValidityChecks.new(@tenant)
      unless validity_checks.feature_available?
        # Short-circuit early if push protection isn't available.
        # This still eventually returns a 204 to the user, as if it was were succesful, but we hope
        # to change that in the future.
        return nil
      end

      update_settings_for_all_repos(:secret_scanning_validity_checks_enable_all, entity_type: :organization)
      update_settings_for_all_repos(:secret_scanning_validity_checks_enable_all, entity_type: :user) if @tenant.is_a?(Business)
      event_name = @tenant.is_a?(Business) ? "business_secret_scanning_validity_checks.enable" : "org.secret_scanning_validity_checks_enable"
      instrument(event_name)
    elsif @params[:secret_scanning_validity_checks] == "disable_all"
      update_settings_for_all_repos(:secret_scanning_validity_checks_disable_all, entity_type: :organization)
      update_settings_for_all_repos(:secret_scanning_validity_checks_disable_all, entity_type: :user) if @tenant.is_a?(Business)
      event_name = @tenant.is_a?(Business) ? "business_secret_scanning_validity_checks.disable" : "org.secret_scanning_push_protection_disable"
      instrument(event_name)
    end

    # Secret Scanning Validity Checks on new repos
    if !@params[:secret_scanning_validity_checks_new_repos].nil?
      validity_checks = SecretScanning::Features::Owner::ValidityChecks.new(@tenant)
      if @params[:secret_scanning_validity_checks_new_repos] == "enabled"
        validity_checks.enable_for_new_repos(actor: @actor)
        if @tenant.is_a?(Business)
          UpdateBusinessSecurityFeatureForNewReposJob.perform_later(@tenant, :secret_scanning_validity_checks, :enable, @actor.id)
        end
        event_name = @tenant.is_a?(Business) ? "business_secret_scanning_validity_checks.enabled_for_new_repos" : "org.secret_scanning_validity_checks_new_repos_enable"
        instrument(event_name)
      elsif @params[:secret_scanning_validity_checks_new_repos] == "disabled"
        validity_checks.disable_for_new_repos(actor: @actor)
        if @tenant.is_a?(Business)
          UpdateBusinessSecurityFeatureForNewReposJob.perform_later(@tenant, :secret_scanning_validity_checks, :disable, @actor.id)
        end
        event_name = @tenant.is_a?(Business) ? "business_secret_scanning_validity_checks.disabled_for_new_repos" : "org.secret_scanning_validity_checks_new_repos_disable"
        instrument(event_name)
      end
    end

    # Secret Scanning Non-Provider Patterns on existing repos
    if @tenant.is_a?(Business)
      if @params[:secret_scanning_lower_confidence_patterns] == "enable_all"
        lower_confidence_patterns = SecretScanning::Features::Business::LowerConfidencePatterns.new(@tenant)
        unless lower_confidence_patterns.feature_available?
          # Short-circuit early if lower confidence patterns isn't available.
          # This still eventually returns a 204 to the user, as if it was were succesful, but we hope
          # to change that in the future.
          return nil
        end
        update_settings_for_all_repos(:secret_scanning_lower_confidence_patterns_enable_all, entity_type: :organization)
        update_settings_for_all_repos(:secret_scanning_lower_confidence_patterns_enable_all, entity_type: :user)
        instrument("business_secret_scanning_lower_confidence_patterns.enable_all")
      elsif @params[:secret_scanning_lower_confidence_patterns] == "disable_all"
        update_settings_for_all_repos(:secret_scanning_lower_confidence_patterns_disable_all, entity_type: :organization)
        update_settings_for_all_repos(:secret_scanning_lower_confidence_patterns_disable_all, entity_type: :user)
        instrument("business_secret_scanning_lower_confidence_patterns.disable_all")
      end
    end

    # Secret Scanning scan for non-provider patterns on new repos
    if @tenant.is_a?(Business)
      unless @params[:secret_scanning_lower_confidence_patterns_new_repos].nil?
        lower_confidence_patterns = SecretScanning::Features::Business::LowerConfidencePatterns.new(@tenant)
        if @params[:secret_scanning_lower_confidence_patterns_new_repos] == "enabled"
          lower_confidence_patterns.enable_for_new_repos(actor: @actor)
          UpdateBusinessSecurityFeatureForNewReposJob.perform_later(@tenant, :secret_scanning_lower_confidence_patterns, :enable, @actor.id)
          instrument("business_secret_scanning_lower_confidence_patterns.enabled_for_new_repos")
        elsif @params[:secret_scanning_lower_confidence_patterns_new_repos] == "disabled"
          lower_confidence_patterns.disable_for_new_repos(actor: @actor)
          UpdateBusinessSecurityFeatureForNewReposJob.perform_later(@tenant, :secret_scanning_lower_confidence_patterns, :disable, @actor.id)
          instrument("business_secret_scanning_lower_confidence_patterns.disabled_for_new_repos")
        end
      end
    end

    # Secret Scanning Push Protection on existing repos
    if @params[:secret_scanning_push_protection] == "enable_all"
      push_protection = SecretScanning::Features::Owner::PushProtection.new(@tenant)
      unless push_protection.feature_available?
        # Short-circuit early if push protection isn't available.
        # This still eventually returns a 204 to the user, as if it was were succesful, but we hope
        # to change that in the future.
        return nil
      end

      update_settings_for_all_repos(:secret_scanning_push_protection_enable_all, entity_type: :organization)
      update_settings_for_all_repos(:secret_scanning_push_protection_enable_all, entity_type: :user) if @tenant.is_a?(Business)
      event_name = @tenant.is_a?(Business) ? "business_secret_scanning_push_protection.enable" : "org.secret_scanning_push_protection_enable"
      instrument(event_name)
    elsif @params[:secret_scanning_push_protection] == "disable_all"
      update_settings_for_all_repos(:secret_scanning_push_protection_disable_all, entity_type: :organization)
      update_settings_for_all_repos(:secret_scanning_push_protection_disable_all, entity_type: :user) if @tenant.is_a?(Business)
      event_name = @tenant.is_a?(Business) ? "business_secret_scanning_push_protection.disable" : "org.secret_scanning_push_protection_disable"
      instrument(event_name)
    end

    # Secret Scanning Push Protection on new repos
    if !@params[:secret_scanning_push_protection_new_repos].nil?
      push_protection = SecretScanning::Features::Owner::PushProtection.new(@tenant)
      if @params[:secret_scanning_push_protection_new_repos] == "enabled"
        push_protection.enable_for_new_repos(actor: @actor)
        if @tenant.is_a?(Business)
          UpdateBusinessSecurityFeatureForNewReposJob.perform_later(@tenant, :secret_scanning_push_protection, :enable, @actor.id)
        end
        event_name = @tenant.is_a?(Business) ? "business_secret_scanning_push_protection.enabled_for_new_repos" : "org.secret_scanning_push_protection_new_repos_enable"
        instrument(event_name)
      elsif @params[:secret_scanning_push_protection_new_repos] == "disabled"
        push_protection.disable_for_new_repos(actor: @actor)
        if @tenant.is_a?(Business)
          UpdateBusinessSecurityFeatureForNewReposJob.perform_later(@tenant, :secret_scanning_push_protection, :disable, @actor.id)
        end
        event_name = @tenant.is_a?(Business) ? "business_secret_scanning_push_protection.disabled_for_new_repos" : "org.secret_scanning_push_protection_new_repos_disable"
        instrument(event_name)
      end
    end

    # Secret Scanning Push Protection anywhere for user
    if !@params[:push_protection_user].nil?
      push_protection = SecretScanning::Features::User::PushProtection.new(@actor)
      if @params[:push_protection_user] == "enabled"
        action = :START
        push_protection.enable(actor: @actor)
      elsif @params[:push_protection_user] == "disabled"
        push_protection.disable(actor: @actor)
        action = :CANCEL
      end
      # Emit Hydro BackfillGroupRequest message when user enables/disables push protection
      feature_flags = SecretScanning::Instrumentation::OwnerServiceFlags.new(@actor).group_backfill_service_flags
      if feature_flag_enabled?(@actor, FeatureFlags::USER_SCOPED_ANCESTOR_SCAN)
        feature_flags << FeatureFlags::USER_SCOPED_ANCESTOR_SCAN.to_s
      end

      GlobalInstrumenter.instrument("secret_scanning.backfill.group", {
        action: action,
        owner: @actor,
        requested_at: Time.current.utc,
        type: :FULL,
        feature_flags: feature_flags,
      })
    end

    # Secret Scanning Push Protection Custom Message
    if !@params[:push_protection_custom_message_status].nil?
      push_protection = if @tenant.is_a?(Business)
        SecretScanning::Features::Business::PushProtection.new(@tenant)
      else
        SecretScanning::Features::Org::PushProtection.new(@tenant)
      end
      if @params[:push_protection_custom_message_status] == "enabled"
        push_protection.enable_custom_message(actor: @actor)
        if @tenant.is_a?(Business)
          UpdateBusinessSecurityFeatureForNewReposJob.perform_later(@tenant, :push_protection_custom_message_toggle, :enable, @actor.id)
        end
        event_name = @tenant.is_a?(Business) ? "business_secret_scanning_push_protection_custom_message.enable" : "org.secret_scanning_push_protection_custom_message_enabled"
        instrument(event_name)
      elsif @params[:push_protection_custom_message_status] == "disabled"
        push_protection.disable_custom_message(actor: @actor)
        if @tenant.is_a?(Business)
          UpdateBusinessSecurityFeatureForNewReposJob.perform_later(@tenant, :push_protection_custom_message_toggle, :disable, @actor.id)
        end
        event_name = @tenant.is_a?(Business) ? "business_secret_scanning_push_protection_custom_message.disable" : "org.secret_scanning_push_protection_custom_message_disabled"
        instrument(event_name)
      end
    end

    push_protection_msg = @params[:push_protection_custom_message]
    error = set_push_protection_custom_message(message: push_protection_msg)
    if error != nil
      return error
    end

    # Secret Scanning validity checks enterprise setting
    if !@params[:secret_scanning_validity_checks].nil? && !GitHub.enterprise?
      validity_checks = if @tenant.is_a?(Business)
        SecretScanning::Features::Business::ValidityChecks.new(@tenant)
      else
        SecretScanning::Features::Org::ValidityChecks.new(@tenant)
      end
      validity_checks_new_enablement_value = @params[:secret_scanning_validity_checks]
      if validity_checks_new_enablement_value == "enabled"
        validity_checks.enable(actor: @actor)
        event_name = @tenant.is_a?(Business) ? "business_secret_scanning_automatic_validity_checks.enabled" : "org_secret_scanning_automatic_validity_checks.enabled"
        instrument(event_name)
      elsif validity_checks_new_enablement_value == "disabled"
        validity_checks.disable(actor: @actor)
        event_name = @tenant.is_a?(Business) ? "business_secret_scanning_automatic_validity_checks.disabled" : "org_secret_scanning_automatic_validity_checks.disabled"
        instrument(event_name)
      end
      if @tenant.is_a?(Business)
        PublishSecretScanningEnablementChangeJob.perform_later(enablement_level: :business, actor_id: @actor.id, business: @tenant, organization: nil)
      else
        PublishSecretScanningEnablementChangeJob.perform_later(enablement_level: :organization, actor_id: @actor.id, business: nil, organization: @tenant)
      end
    end

    # Secret Scanning Generic Secrets
    if !@params[:secret_scanning_generic_secrets].nil?
      generic_secrets = SecretScanning::Features::Owner::GenericSecrets.new(@tenant)
      generic_secretss_new_enablement_value = @params[:secret_scanning_generic_secrets]
      if generic_secretss_new_enablement_value == "enabled"
        # update setting
        generic_secrets.enable(actor: @actor)

        # Emit Hydro BackfillGroupRequest
        GitHub.logger.info("publishing TSS backfill message")
        GlobalInstrumenter.instrument("secret_scanning.backfill.group", {
          action: :START,
          owner: @tenant,
          requested_at: Time.current.utc,
          type: :GENERIC_SECRETS,
          feature_flags: [],
        })

        # emit audit event
        event_name = @tenant.is_a?(Business) ? "business_secret_scanning_generic_secrets.enabled" : "org_secret_scanning_generic_secrets.enabled"
        instrument(event_name)
      elsif generic_secretss_new_enablement_value == "disabled"
        # update setting
        generic_secrets.disable(actor: @actor)

        # Emit Hydro BackfillGroupRequest
        GitHub.logger.info("publishing TSS backfill message")
        GlobalInstrumenter.instrument("secret_scanning.backfill.group", {
          action: :CANCEL,
          owner: @tenant,
          requested_at: Time.current.utc,
          type: :GENERIC_SECRETS,
          feature_flags: [],
        })

        # emit audit event
        event_name = @tenant.is_a?(Business) ? "business_secret_scanning_generic_secrets.disabled" : "org_secret_scanning_generic_secrets.disabled"
        instrument(event_name)
      end

      if @tenant.is_a?(Business)
        PublishSecretScanningEnablementChangeJob.perform_later(enablement_level: :business, actor_id: @actor.id, business: @tenant, organization: nil)
      else
        PublishSecretScanningEnablementChangeJob.perform_later(enablement_level: :organization, actor_id: @actor.id, business: nil, organization: @tenant)
      end
    end

    # Secret Scanning Delegated Bypass
    unless @params[:token_scanning_delegated_bypass_enabled].nil?
      if @tenant.organization?
        delegated_bypass = SecretScanning::Features::Org::DelegatedBypass.new(@tenant)
        delegated_bypass_new_enablement_value = @params[:token_scanning_delegated_bypass_enabled]
        if delegated_bypass_new_enablement_value == "1" # enable
          delegated_bypass.enable(actor: @actor)

          # emit audit event
          instrument("org_secret_scanning_push_protection_bypass_list.enable")
        elsif delegated_bypass_new_enablement_value == "0" # disable
          delegated_bypass.disable(actor: @actor)

          # emit audit event
          instrument("org_secret_scanning_push_protection_bypass_list.disable")
        end
      end
    end

    # Innersource Advisories
    update_innersource_advisories_settings(@params)
  end

  protected

  def set_push_protection_custom_message(message:)
    validity_check = push_protection_custom_message_valid(message)
    if !validity_check[:valid] && validity_check[:reason] == :not_url
      return create_error_hash("Input should be a URL")
    end
    if !validity_check[:valid]
      return
    end

    if @tenant.is_a?(Business)
      UpdateBusinessSecurityFeatureForNewReposJob.perform_later(@tenant, :push_protection_custom_message, :enable, @actor.id, push_protection_custom_message: safe_uri(message))
    else
      @tenant.set_push_protection_custom_message(safe_uri(message), @actor)
    end

    event_name = @tenant.is_a?(Business) ? "business_secret_scanning_push_protection_custom_message.update" : "org.secret_scanning_push_protection_custom_message_updated"
    instrument(event_name)
    nil
  end

  def create_error_hash(error_message)
    { error: error_message }.with_indifferent_access
  end

  def get_token_scanning_features
    if @tenant.is_a?(Business)
      return SecretScanning::Features::Business::TokenScanning.new(@tenant)
    elsif @tenant.organization?
      return SecretScanning::Features::Org::TokenScanning.new(@tenant)
    elsif @tenant.is_a?(User)
      return SecretScanning::Features::User::TokenScanning.new(@tenant)
    end

    raise ArgumentError, "Invalid type: expected an Organization, Business, or User"
  end

  # Publish events for audit / metrics, etc
  def instrument(event_name)
    # Audit Log
    GitHub.instrument("#{event_name}", instrumentation_payload(event_name))
    if @tenant.is_a?(Business)
      owner_type = "business"
    elsif @tenant.organization?
      owner_type = "org"
    else
      owner_type = "user"
    end

    # Dogstats
    GitHub.dogstats.increment("security_analysis.update", tags: [
      "event_name:#{event_name}",
      "owner_id:#{@tenant.id}",
      "owner_type:#{owner_type}",
      "source:#{@source}"
    ])

    # Hydro - used for recording usage telemetry.
    GlobalInstrumenter.instrument("security_analysis.update", {
      event_name: event_name,
      owner: @tenant,
      actor: @actor
    })
  end

  def instrumentation_payload(event_name)
    return { user: @actor, business: @tenant } if @tenant.is_a?(Business)

    payload = { user: @actor, org: @tenant }

    if event_name == "org.advanced_security_enabled_on_all_repos" || event_name == "org.advanced_security_disabled_on_all_repos"
      if GitHub.single_business_environment?
        payload[:business] = GitHub.global_business
      elsif @tenant&.business.present?
        payload[:business] = @tenant.business
      end
    end

    payload
  end

  def requested_security_product_is_blocked_by_in_progress_toggling?
    return true if @params.key?(:advanced_security) && blocked_settings.advanced_security?
    return true if @params.key?(:advanced_security_user_namespace) && blocked_settings.advanced_security_user_namespace?
    return true if @params.key?(:code_scanning) && blocked_settings.code_scanning?
    return true if @params.key?(:secret_scanning) && blocked_settings.secret_scanning?
    return true if @params.key?(:secret_scanning_push_protection) && blocked_settings.push_protection?

    false
  end

  # Update the given settings for all repos owned by the organization or user
  # This is done asynchronously by queuing a job
  # @param update_type [Organization, User] the owner of the repos
  # @param entity_type [Symbol] The scope of entities to update if given a business. Either :organization or :user
  def update_settings_for_all_repos(update_type, entity_type: :organization)
    if @tenant.is_a?(Business)
      SecurityAnalysisSettingsBatchUpdateBusinessJob.perform_later(
        owner: @tenant,
        update_type: update_type,
        actor_id: @actor.id,
        entity_type: entity_type,
      )
      return
    end

    SecurityAnalysisSettingsUpdateJob.perform_later(
      actor: @actor,
      owner: @tenant,
      update_type: update_type
    )
  end

  private

  sig { params(params: T.any(ActionController::Parameters, T::Hash[Symbol, String])).void }
  def update_innersource_advisories_settings(params)
    if params[:innersource_advisories] == "enable_all"
      update_settings_for_all_repos(:innersource_advisories_enable_all)
      instrument("innersource_advisories.enable")
    elsif params[:innersource_advisories] == "disable_all"
      update_settings_for_all_repos(:innersource_advisories_disable_all)
      instrument("innersource_advisories.disable")
    end

    if params[:innersource_advisories_new_repos] == "enabled"
      @tenant.enable_innersource_advisories_for_new_repos(actor: @actor)
      instrument("innersource_advisories_new_repos.enable")
    elsif params[:innersource_advisories_new_repos] == "disabled"
      @tenant.disable_innersource_advisories_for_new_repos(actor: @actor)
      instrument("innersource_advisories_new_repos.disable")
    end
  end
end
