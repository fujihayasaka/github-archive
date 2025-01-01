# typed: true
# frozen_string_literal: true

module RuleEngine::RuleSettingsDependency
  extend T::Sig
  extend T::Helpers
  include GitHub::Memoizer
  include ApplicationHelper
  include TextHelper


  class UnsupportedError < StandardError
  end

  # Generic handler for source feature flags
  # `check_enterprise_for_org` exists since the old version of this method did not check enterprise features correctly.
  # This exists for safe rollout, remove when confident it is okay to check the enterprise for all org-level features
  sig { params(feature_flag: Symbol, check_enterprise_for_org: T::Boolean).returns(T::Boolean) }
  def feature_enabled_for_source?(feature_flag, check_enterprise_for_org: false)
    T.bind(self, RuleEngine::Types::RuleSource)

    if self.is_a?(Repository)
      async_scoped_feature_flag_enabled?(feature_flag).sync
    elsif self.is_a?(Organization)
      feature_enabled?(feature_flag) || (check_enterprise_for_org && !!business&.feature_enabled?(feature_flag))
    else
      feature_enabled?(feature_flag)
    end
  end

  sig { returns(T::Boolean) }
  def only_show_published_rules?
    feature_enabled_for_source?(:rulesets_fix_api_rule_visibility)
  end

  sig { returns(T::Boolean) }
  def push_rulesets_enabled?
    feature_enabled_for_source?(:push_rulesets)
  end

  sig { params(user: T.nilable(User)).returns(T::Boolean) }
  def property_ruleset_async_preview_enabled?(user)
    T.bind(self, RuleEngine::Types::RuleSource)

    ::RulesEngine::RulesetMatcher.async_preview_ff_enabled?(self, user)
  end

  sig { returns(T::Boolean) }
  def rules_history?
    feature_enabled_for_source?(:rules_history)
  end

  sig { returns(T::Boolean) }
  def rules_import_export?
    feature_enabled_for_source?(:rules_import_export)
  end

  sig { returns(T::Boolean) }
  def rules_exclude_public_repositories_from_targeting?
    feature_enabled_for_source?(:rules_exclude_public_repositories_from_targeting)
  end

  sig { returns(T::Boolean) }
  def delegated_bypass_enabled?
    T.bind(self, RuleEngine::Types::RuleSource)

    if self.is_a?(Repository)
      return true if SecretScanning::Features::Repo::DelegatedBypass.new(self).enabled?
      self.async_scoped_feature_flag_enabled?(:push_ruleset_delegated_bypass).sync
    elsif self.is_a?(Organization)
      return true if SecretScanning::Features::Org::DelegatedBypass.new(self).enabled?
      self.feature_enabled?(:push_ruleset_delegated_bypass) ||
        !!self.business&.feature_enabled?(:push_ruleset_delegated_bypass)
    else
      false
    end
  end

  sig { returns(T::Boolean) }
  def delegated_bypass_notifications_enabled?
    T.bind(self, RuleEngine::Types::RuleSource)

    if self.is_a?(Repository)
      return true if SecretScanning::Features::Repo::DelegatedBypass.new(self).enabled?
      self.async_scoped_feature_flag_enabled?(:push_ruleset_delegated_bypass_notifications).sync
    elsif self.is_a?(Organization)
      return true if SecretScanning::Features::Org::DelegatedBypass.new(self).enabled?
      self.feature_enabled?(:push_ruleset_delegated_bypass_notifications) ||
        !!owner&.feature_enabled?(:push_ruleset_delegated_bypass_notifications)
    else
      false
    end
  end

  sig { returns(T::Boolean) }
  def delegated_bypass_background_notifications_enabled?
    feature_enabled_for_source?(:push_ruleset_delegated_bypass_background_notifications)
  end

  sig { returns(T::Boolean) }
  def delegated_bypass_hydro_events_enabled?
    feature_enabled_for_source?(:delegated_bypass_hydro_events)
  end

  # TODO: When removing this feature flag, remove the "beta" notes in the API
  # Search for rules_deploy_key_bypass
  sig { returns(T::Boolean) }
  def deploy_key_bypass_enabled?
    feature_enabled_for_source?(:rules_deploy_key_bypass)
  end

  sig { returns(T::Boolean) }
  def check_bypass_actor_presence?
    feature_enabled_for_source?(:rulesets_check_bypass_actor_presence)
  end

  sig { returns(T::Boolean) }
  def convert_toasts_to_flashes?
    feature_enabled_for_source?(:convert_toasts_to_flashes)
  end

  sig { returns(T::Boolean) }
  def push_ruleset_delegated_bypass?
    feature_enabled_for_source?(:push_ruleset_delegated_bypass)
  end

  sig { returns(T::Boolean) }
  def a11y_add_bypass_dialog?
    feature_enabled_for_source?(:a11y_add_bypass_dialog)
  end

  sig { returns(T::Boolean) }
  def member_privilege_rulesets_enabled?
    feature_enabled_for_source?(:member_privilege_rulesets, check_enterprise_for_org: true)
  end

  sig { returns(T::Boolean) }
  def add_bypass_dialog_select_panel_v1?
    feature_enabled_for_source?(:add_bypass_dialog_select_panel_v1)
  end

  sig { returns(T::Boolean) }
  def enterprise_rulesets_enabled?
    feature_enabled_for_source?(:enterprise_rulesets, check_enterprise_for_org: true)
  end

  sig { returns(T::Boolean) }
  def enterprise_rulesets_enterprise_teams_enabled?
    feature_enabled_for_source?(:enterprise_rulesets_enterprise_teams, check_enterprise_for_org: true)
  end

  sig { returns(T::Boolean) }
  def enterprise_owner_bypass_enabled?
    feature_enabled_for_source?(:enterprise_owner_bypass, check_enterprise_for_org: true)
  end

  def required_status_checks_perf_improvements?
    feature_enabled_for_source?(:rulesets_required_status_checks_perf_improvements)
  end

  sig { params(actor: User).returns(T::Boolean) }
  def blocks_repository_rename?(actor)
    # This function should only be called from a repository
    return true unless self.is_a?(Repository)

    # Only organizations can have rename target blocks
    return false unless self.in_organization?

    # Check Organization rulesets to see if target protection is set
    rulesets = filtered_inherited_rulesets(targets: %w[branch tag push member_privilege])
    rulesets.each do |ruleset|
      next unless ruleset.enabled?
      source = ruleset.source
      next unless source.is_a?(Organization) || source.is_a?(Business)

      condition = ruleset.conditions.find_by(target: "repository_name")
      next unless condition&.parameters["protected"]

      return true unless ruleset.rule_provider.ruleset_bypass_allowed?(ruleset, actor, self, is_pull_request: false)
    end

    false
  end

  sig { returns(T::Boolean) }
  def rules_disallow_deploy_key_org_bypass?
    feature_enabled_for_source?(:rules_disallow_deploy_key_org_bypass_optin)
  end

  sig { returns(T::Boolean) }
  def fetch_roles_with_source_type?
    feature_enabled_for_source?(:rulesets_fetch_roles_with_source_type)
  end

  sig { returns(T::Boolean) }
  def more_efficient_permissions_query?
    feature_enabled_for_source?(:more_efficient_permissions_query)
  end

  sig { returns(T::Boolean) }
  def dont_check_repos_integrations_limit?
    feature_enabled_for_source?(:dont_check_repos_integrations_limit)
  end

  sig { params(enabled_only: T::Boolean, targets: T::Array[String]).returns(T::Array[RepositoryRuleset]) }
  def filtered_inherited_rulesets(enabled_only: false, targets: %w[branch tag push])
    T.bind(self, RuleEngine::Types::RuleSource)

    rulesets = RepositoryRuleset.load_for(source: self, include_parents: true, targets:)

    return rulesets unless self.is_a?(Repository) && self.in_organization?

    rulesets.filter do |ruleset|
      ruleset.enabled? || (!enabled_only && self == ruleset.source)
    end.sort do |a, b|
      if a.source == b.source
        a.name <=> b.name || 0
      else
        (a.source.is_a?(Repository) ? 1 : -1)
      end
    end
  end

  sig { params(qualified_ref_name: String).returns(T::Array[RepositoryRuleset]) }
  def rulesets_for_ref(qualified_ref_name)
    return [] unless is_a?(Repository)

    rulesets = filtered_inherited_rulesets

    rulesets.filter do |ruleset|
      RulesEngine::RulesetMatcher.should_evaluate_ref?(ruleset, self, qualified_ref_name)
    end
  end

  sig { params(ruleset_id: Integer, include_inherited: T::Boolean, targets: T::Array[String]).returns(T.nilable(RepositoryRuleset)) }
  def ruleset_from_id(ruleset_id, include_inherited: false, targets: %w[branch tag push])
    T.bind(self, RuleEngine::Types::RuleSource)

    rulesets = include_inherited ? filtered_inherited_rulesets(targets:) : RepositoryRuleset.load_for(source: self)
    rulesets.find { |ruleset| ruleset.id == ruleset_id }
  end

  sig { params(target: String, enforcement: T.nilable(String)).returns(T.nilable(RepositoryRuleset)) }
  def new_ruleset_with_defaults(target, enforcement:)
    T.bind(self, RuleEngine::Types::RuleSource)

    # TODO: Move to RepositoryRuleset.new_with_default_rules once rule registry exposes schemas
    return nil unless RepositoryRuleset.targets.include?(target)
    return nil if target == "push" && !push_rulesets_enabled?

    ruleset = RepositoryRuleset.new
    ruleset.target = target
    ruleset.source = self
    ruleset.enforcement = enforcement.present? && RepositoryRuleset.enforcements.include?(enforcement) ? enforcement : "disabled"

    ruleset.rule_configurations = RulesEngine::ReactPayload.available_rule_schemas(ruleset).filter_map do |rule_schema|
      next nil if RuleEngine::Evaluator::DEFAULT_RULES.exclude?(rule_schema[:type])

      RepositoryRuleConfiguration.new(
        rule_type: rule_schema[:type],
        parameters: ruleset.apply_default_parameters(rule_schema[:type], {})
      )
    end

    ruleset
  end

  def fetch_rule_suite(rule_suite_id)
    base_sql = if self.is_a?(Organization)
      RuleEngine::RuleSuite
        .where(owner: self)
        .for_ruleset_source(self)
    else
      RuleEngine::RuleSuite
        .where(repository: self)
    end

    base_sql = base_sql.where(id: rule_suite_id)

    base_sql.includes(:rule_runs).first
  end

  RESULT_MAP = {
    "pass" => ["allowed"],
    "fail" =>  %w[failed git_error enter_queue_failed],
    "bypass" => ["bypassed"]
  }
  EVALUATE_RESULT_MAP = RESULT_MAP.merge({ "fail" => ["failed"] })
  sig do
    params(
      page_size: Integer,
      page: T.nilable(Integer),
      ref: T.nilable(String), # qualified or unqualified ref name (unqualified will search for heads and tags)
      ruleset: T.nilable(RepositoryRuleset),
      actor: T.untyped,
      time_period: T.nilable(String),
      repository: T.nilable(Repository),
      rule_status: String,
      evaluate_status: String
    ).returns([T::Array[RuleEngine::RuleSuite], T::Boolean])
  end
  def fetch_rule_suites(
    page_size: 10,
    page: nil,
    ref: nil,
    ruleset: nil,
    actor: nil,
    time_period: "day", # hour, day, week, month
    repository: nil,
    rule_status: "all", # all, pass, fail, bypass
    evaluate_status: "active" # all, active, evaluate
  )
    T.bind(self, RuleEngine::Types::RuleSource)

    org_scoped = self.is_a?(Organization)
    tags = [
      "source:#{self.class.name}",
      "ref_filter:#{ref.present?}",
      "ruleset_filter:#{ruleset.present?}",
      "actor_filter:#{actor.present?}",
      "repository_filter:#{repository.present?}",
      "status_filter:#{rule_status}",
      "time_filter:#{time_period}",
    ]
    GitHub.dogstats.distribution_time("repository_rules_engine.fetch_rule_suites", tags:) do
      base_sql = if org_scoped
        RuleEngine::RuleSuite
          .where(owner: self)
          .order(created_at: :desc)
          .limit(page_size + 1)
      else
        RuleEngine::RuleSuite
          .where(repository: self)
          .order(created_at: :desc)
          .limit(page_size + 1)
      end

      if page.present? && page > 1
        base_sql = base_sql.offset((page - 1) * page_size)
      end

      if ruleset.present?
        base_sql = base_sql.for_ruleset(ruleset)
      elsif org_scoped
        # Only include suites where a rule ran at this level
        base_sql = base_sql.source_result_exists(source: self)
      end

      if ref.present?
        ref_query = if ref.match?(/\Arefs\/(heads|tags)\//)
          [ref]
        else
          ["refs/heads/#{ref}", "refs/tags/#{ref}"]
        end
        base_sql = base_sql.where(ref_name: ref_query)
      end

      base_sql = base_sql.where(repository: repository) if repository.present?

      case time_period
      when "hour"
        base_sql = base_sql.where(created_at: 1.hour.ago..)
      when "day"
        base_sql = base_sql.where(created_at: 1.day.ago..)
      when "week"
        base_sql = base_sql.where(created_at: 1.week.ago..)
      when "month"
        base_sql = base_sql.where(created_at: 1.month.ago..)
      end

      base_sql = base_sql.where(actor:) if actor.present?

      if evaluate_status == "evaluate"
        if rule_status != "all"
          base_sql = base_sql.source_result_exists(source: self, evaluate_result: EVALUATE_RESULT_MAP[rule_status])
        else
          # At least one evaluate mode rule exists at this level
          base_sql = base_sql.source_result_exists(source: self, evaluate_result_not: ["none"])
        end
      elsif evaluate_status == "active"
        # At least one active mode rule exists
        base_sql = base_sql.source_result_exists(result_not: ["none"])
        if rule_status != "all"
          base_sql = base_sql.where(result: RESULT_MAP[rule_status])
        end
      else
        case rule_status
        when "pass"
          # Find where
          # Final result was allowed
          # AND
          # There are some active rules OR there are some rules at this level (of which, evaluate rules if any are passing)
          base_sql = base_sql.where(result: RESULT_MAP[rule_status])
          base_sql = base_sql.source_result_exists(result_not: ["none"]).or(
            base_sql.source_result_exists(evaluate_result: %w[allowed none], source: self)
          )
        when "fail"
          # Find actual failures OR evaluation failures where an evaluate failure exists at this level
          base_sql = base_sql.where(result: RESULT_MAP[rule_status]).or(
            base_sql.source_result_exists(evaluate_result: ["failed"], source: self)
          )
        when "bypass"
          # Find where
          # Active rules were bypassed and all evaluate rules at this level were bypassed (or none existed)
          # OR
          # Evaluate mode result was bypassed at this level and no active rules failed
          base_sql = base_sql.where(result: "bypassed").source_result_not_exists(evaluate_result: ["failed"], source: self).or(
            base_sql.where.not(result: RESULT_MAP["fail"]).source_result_exists(evaluate_result: ["bypassed"], source: self)
          )
        else
          # Only return RuleSuites where a rule exists at this level or there are some active rules
          base_sql = base_sql.source_result_exists(source: self).or(
            base_sql.source_result_exists(result_not: ["none"])
          )
        end
      end

      # Rule suite records in the entered_queue state should never be user-visible
      base_sql = base_sql.where.not(result: "entered_queue")

      suites = base_sql.to_ary

      has_more = suites.size > page_size
      suites.slice!(page_size..) if has_more

      GitHub::PrefillAssociations.prefill_associations(suites, [:actor, :rule_runs])

      return suites, has_more
    end
  end

  sig do
    params(
      repository_id: T.nilable(Integer),
      page_size: Integer,
      page: T.nilable(Integer),
      requester: T.untyped,
      approver: T.untyped,
      time_period: T.nilable(String),
      request_status: T.nilable(String),
      request_type: T.nilable(String),
    ).returns([T::Array[Exemptions::ExemptionRequest], T::Boolean])
  end
  def fetch_bypass_requests(
    repository_id: nil,
    page_size: 10,
    page: nil,
    requester: nil,
    approver: nil,
    time_period: "day",
    request_status: "all",
    request_type: nil
  )
    base_sql = if self.is_a?(Organization)
      # returning org level (ruleset) exemptions
      # TODO: Replace with org_id when available
      rule_suites_by_org_owner_ids = RuleEngine::RuleSuite
      .where(owner: self)
      .where(created_at: 1.month.ago..)
      .for_ruleset_source(self)
      .ids

      return [], false unless rule_suites_by_org_owner_ids.any?

      base_sql = if self.feature_enabled?(:use_exemption_request_index)
        Exemptions::ExemptionRequest
      .from("exemption_requests FORCE INDEX(index_exemption_requests_resource_owner)")
      .where("exemption_requests.resource_owner_type = 'RuleEngine::RuleSuite'")
      .where("exemption_requests.resource_owner_id IN (?)", rule_suites_by_org_owner_ids)
      else
        Exemptions::ExemptionRequest
        .where("exemption_requests.resource_owner_type = 'RuleEngine::RuleSuite'")
        .where("exemption_requests.resource_owner_id IN (?)", rule_suites_by_org_owner_ids)
      end

      if repository_id
        base_sql = base_sql.where(repository_id: repository_id)
      end

      base_sql
    else
      Exemptions::ExemptionRequest.where(repository_id: repository_id)
    end.order(created_at: :desc).limit(page_size + 1)

    if page.present? && page > 1
      base_sql = base_sql.offset((page - 1) * page_size)
    end

    if request_type.present?
      base_sql = base_sql.where(request_type:)
    end

    case request_status
    when "completed"
      base_sql = base_sql.where(status: "completed")
    when "cancelled"
      base_sql = base_sql.where(status: "cancelled")
    when "expired"
      base_sql = base_sql.where(status: "pending").and(base_sql.where(expires_at: ..Time.now))
    when "denied"
      base_sql = base_sql.where(status: "rejected")
    when "open"
      base_sql = base_sql.where(status: "pending").and(base_sql.not_expired)
    end

    case time_period
    when "hour"
      base_sql = base_sql.where(created_at: 1.hour.ago..)
    when "day"
      base_sql = base_sql.where(created_at: 1.day.ago..)
    when "week"
      base_sql = base_sql.where(created_at: 1.week.ago..)
    when "month"
      base_sql = base_sql.where(created_at: 1.month.ago..)
    end

    if requester.present?
      base_sql = base_sql.where(requester_id: requester.id)
    end

    if approver.present?
      base_sql = base_sql.joins(:responses).where(responses: { reviewer: approver }).distinct
    end

    exemption_requests = base_sql.to_a

    has_more = exemption_requests.size > page_size
    exemption_requests.slice!(page_size..) if has_more

    [exemption_requests, has_more]
  end

  # Given an array of unqualified branch names, return the subset of branches that are protected by rules
  # Remove when `use_branch_evaluator_for_branches_api` FF is removed
  sig { params(ref_names: T::Array[String]).returns(T::Array[String]) }
  def protected_by_rulesets(ref_names)
    return [] unless is_a?(Repository)

    enabled_only = repository.feature_enabled?(:protected_branches_api_enabled_rulesets_only) || !!owner&.feature_enabled?(:protected_branches_api_enabled_rulesets_only)

    rulesets = filtered_inherited_rulesets(enabled_only:)

    protected_branches = []
    ref_names.filter do |ref_name|
      rulesets.each do |ruleset|
        if RulesEngine::RulesetMatcher.should_evaluate_ref?(ruleset, self, "refs/heads/#{ref_name}")
          protected_branches << ref_name
          break
        end
      end
    end
    protected_branches
  end

  def update_ruleset_from_json(current_ruleset, ruleset_json, current_user)
    bypass_mode_changed = current_ruleset.bypass_mode != ruleset_json.fetch("orgAdminBypassMode", :no_org_bypass)
    deploy_key_bypass_changed = current_ruleset.deploy_key_bypass != ruleset_json.fetch("deployKeyBypass", false)
    current_ruleset.bypass_mode = ruleset_json.fetch("orgAdminBypassMode", :no_org_bypass)
    current_ruleset.deploy_key_bypass = ruleset_json.fetch("deployKeyBypass", false)

    changes = bypass_mode_changed ||
              deploy_key_bypass_changed ||
              current_ruleset.name != ruleset_json["name"] ||
              current_ruleset.target != ruleset_json["target"] ||
              current_ruleset.enforcement != ruleset_json["enforcement"]

    current_ruleset.name = ruleset_json["name"]
    current_ruleset.target = ruleset_json["target"]
    current_ruleset.enforcement = ruleset_json["enforcement"]

    save_changes(current_ruleset, ruleset_json, current_user, changes:)
  end

  sig { params(rules: T.nilable(T::Array[T::Hash[String, T.untyped]])).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def filter_and_translate_rules_for_save(rules)
    rules_to_save = []

    rules&.each do |raw_rule|
      type = group_raw_rule(raw_rule)

      next if type == :delete

      raw_rule["id"] = nil if raw_rule["id"].blank?
      raw_rule["rule_type"] = raw_rule["ruleType"] if raw_rule["ruleType"].present?
      raw_rule.except!("_id", "_dirty", "_enabled")

      rules_to_save << raw_rule.deep_symbolize_keys
    end

    rules_to_save
  end

  sig { params(bypass_actors: T.nilable(T::Array[T::Hash[String, T.untyped]])).returns(T::Array[T::Hash[String, T.untyped]]) }
  def filter_and_translate_bypass_actors_for_save(bypass_actors)
    bypass_actors_to_save = []

    bypass_actors&.each do |raw_bypass_actor|
      type = group_raw_rule(raw_bypass_actor)

      next if type == :delete

      raw_bypass_actor.delete("id")
      raw_bypass_actor.except!("_id", "_dirty", "_enabled")

      bypass_actors_to_save << raw_bypass_actor.deep_transform_keys { |key| key.to_s.underscore.to_sym }
    end

    bypass_actors_to_save
  end

  sig { params(conditions: T.nilable(T::Array[T::Hash[String, T.untyped]])).returns(T::Array[T::Hash[String, T.untyped]]) }
  def translate_conditions_for_save(conditions)
    conditions&.map do |condition|
      # Update the repository property condition to use the new format with the source field
      if GitHub.flipper[:ruleset_backfill_source].enabled? && condition["target"] == "repository_property"
        %w[include exclude].each do |type|
          condition["parameters"][type].each { |property| property["source"] ||= "custom" }
        end
      end

      condition.except!("_dirty")
    end || []
  end

  # Take a rule request object (hash) and return a Symbol to group by
  # (:create, :update, :delete) or nil if it doesn't need to be saved
  sig { params(raw_rule: T.untyped).returns(T.nilable(Symbol)) }
  def group_raw_rule(raw_rule)
    # skip rules that don't have an ID and are not enabled, _or_ are not marked 'dirty' (needs to be saved)
    if (raw_rule["id"].blank? && !raw_rule["_enabled"]) || !raw_rule["_dirty"]
      return nil
    end

    # Group rules by update and delete based on the enabled flag
    if (raw_rule["id"].blank?) && raw_rule["_enabled"]
      :create
    elsif raw_rule["_enabled"]
      :update
    # If a rule is found and not enabled, delete it
    else
      :delete
    end
  end

  sig { params(ruleset_target: String).returns(T::Array[String]) }
  def supported_condition_target_objects(ruleset_target)
    definition = RulesetDefinitions::RulesetDefinition.factory(self, nil, ruleset_target)
    definition.required_condition_targets
  end

  sig do
    params(query: String, current_user: User).returns(T::Array[{
      actorId: Integer,
      actorType: Symbol,
      name: String,
    }])
  end
  def bypass_actors_suggestions(query, current_user)
    suggestions = filter_base_roles(query)
    suggestions += filter_custom_roles(query)
    suggestions += filter_teams(query, current_user)
    if self.is_a?(Repository)
      suggestions += filter_integrations(query)
    end
    suggestions
  end

  # save to the database in a transaction
  sig do
    params(
      ruleset: RepositoryRuleset,
      ruleset_json: T::Hash[String, T.untyped],
      current_user: T.untyped,
      changes: T::Boolean
    ).returns([T.nilable(String), T::Hash[Symbol, T::Hash[String, String]]])
  end
  def save_changes(ruleset, ruleset_json, current_user, changes: true)
    error_message = T.let(nil, T.nilable(String))
    detailed_errors = { general: Hash.new { |h, k| h[k] = [] }, rules: {}, bypass_actors: {}, conditions: Hash.new { |h, k| h[k] = [] } }

    rules_to_save = filter_and_translate_rules_for_save(ruleset_json["rules"])
    bypass_actors_to_save = filter_and_translate_bypass_actors_for_save(ruleset_json["bypassActors"])
    conditions_to_save = translate_conditions_for_save(ruleset_json["conditions"])

    begin
      RepositoryRuleset.transaction do
        ruleset.target = ruleset_json["target"] || "branch"

        conditions_changed = ruleset.upsert_conditions(T.unsafe(conditions_to_save))
        bypass_actors_changed = ruleset.upsert_bypass_actors(T.unsafe(bypass_actors_to_save))
        rules_changed = ruleset.upsert_rules(T.unsafe(rules_to_save), apply_default_parameters: true, actor_id: current_user.id)

        changed = ruleset.changed? || conditions_changed || bypass_actors_changed || rules_changed

        if !changed
          error_message = "No changes have been made"
          next
        end

        ruleset.save!
      end
    rescue RepositoryRuleset::ParametersValidationError => e
      error_message = e.parse_error_messages.to_sentence

      if e.parameter_instance.is_a?(RepositoryRuleCondition)
        detailed_errors[:conditions][e.parameter_instance.target_object] << {
          field: e.parameter_instance.target,
          message: error_message
        }
      end
    rescue RepositoryRuleset::RuleValidationError => e
      failed_rules = e.errors.map { |error| error.base.rule_type.humanize }

      e.errors.each do |error|
        detailed_errors[:rules][error.base.rule_type] = error.base.parameter_errors
      end

      error_message = "Invalid rules: \'#{failed_rules.uniq.join("\', \'")}\'"
    rescue ActiveRecord::RecordInvalid => e
      error_message = e.record.errors.full_messages.to_sentence
      e.record.errors.each do |error|
        detailed_errors[:general][error.attribute] << {
            error_code: error.type,
            message: error.full_message,
            field: error.attribute
          }
      end
    rescue RepositoryRuleset::BypassActorsValidationError => e
      failed_rules = e.errors.map { |error| error.message }
      error_message = failed_rules.uniq.join("\', \'")
    end

    [error_message, detailed_errors]
  end

  sig { params(ruleset: RepositoryRuleset).returns(String) }
  def es_query_property_ruleset_conditions(ruleset)
    org = T.bind(self, Organization)
    property_conditions = ruleset.conditions.find { |condition| condition.target == "repository_property" }

    "org:#{org.display_login} #{build_phrase_from_property_conditions(property_conditions.parameters)}"
  end

  sig { returns(T::Array[T.untyped]) }
  def inherited_sources
    T.bind(self, RuleEngine::Types::RuleSource)

    if self.is_a?(Repository)
      if enterprise_rulesets_enabled?
        if feature_enabled_for_source?(:emu_inherit_rulesets_from_business) && emu_user_owned?
          [enterprise_managed_business].compact
        else
          # `async_business` and `business` do different things :(
          # `async_business` loads the business from the `owner` relationship while `business` loads it from the `organization` relationship
          # In the case of user owned forks of org repos, the `organization` is the original org, which is not what we want
          [owner.is_a?(Organization) ? owner : nil, async_business.sync].compact
        end
      else
        [owner.is_a?(Organization) ? owner : nil].compact
      end
    elsif self.is_a?(Organization)
      enterprise_rulesets_enabled? ? [business].compact : []
    else
      []
    end
  end

  private

  sig do
    params(query: String).returns(T::Array[{
      actorId: Integer,
      actorType: Symbol,
      name: String,
    }])
  end
  def filter_base_roles(query)
    lower_query = query.downcase

    @cached_base_roles ||= RepositoryRole.select { |role| role.owner_id.nil? }
    return_array = []
    @cached_base_roles.filter_map do |role|
      next unless role.name.downcase.include?(lower_query)
      next unless role.name == "admin"
      return_array.push(
        {
          actorId: role.id,
          actorType: :RepositoryRole,
          name: role.name,
        }
      )
    end
    @cached_base_roles.filter_map do |role|
      next unless role.name.downcase.include?(lower_query)
      next unless role.name != "admin"
      return_array.push(
        {
          actorId: role.id,
          actorType: :RepositoryRole,
          name: role.name,
        }
      )
    end
    return_array
  end

  sig do
    params(query: String).returns(T::Array[{
      actorId: Integer,
      actorType: Symbol,
      name: String,
    }])
  end
  def filter_custom_roles(query)
    T.bind(self, RuleEngine::Types::RuleSource)

    if self.is_a?(Organization)
      corresponding_org = self
    else
      org_owner = Repository.where(id: id).org_owned.pluck(:owner_id)
      if org_owner
        corresponding_org = Organization.where(id: org_owner[0])[0]
      else
        []
      end
    end
    lower_query = query.downcase
    RepositoryRole.custom_roles_for_org(corresponding_org).filter_map do |role|
      next unless role.name.downcase.include?(lower_query)
      {
        actorId: T.must(role.id),
        actorType: :RepositoryRole,
        name: role.name,
      }
    end
  end

  sig do
    params(query: String).returns({
      actorId: Integer,
      actorType: Symbol,
      name: String,
    })
  end
  def filter_integrations(query)
    lower_query = query.downcase
    installations = T.let([], T::Array[IntegrationInstallation])

    if self.is_a?(Repository)
      installations = T.unsafe(IntegrationInstallation.user_installable).with_repository(self)
    else
      installations = T.unsafe(IntegrationInstallation.user_installable).with_target(self)
    end

    installations = installations.filter_map do |installation|
      next unless installation.integration.name.downcase.include?(lower_query)
      installation
    end

    GitHub::PrefillAssociations.prefill_associations(installations, [:integration])

    installations.map do |installation|
      {
        actorId: installation.integration.id,
        actorType: :Integration,
        name: installation.integration.name
      }
    end
  end

  sig do
    params(query: String, current_user: User).returns(T::Array[{
      actorId: Integer,
      actorType: Symbol,
      name: String,
    }])
  end
  def filter_teams(query, current_user)
    T.bind(self, RuleEngine::Types::RuleSource)
    return [] if self.is_a?(Business)

    organization = nil
    repository = nil

    if self.is_a?(Organization)
      organization = self
    elsif self.in_organization?
      organization = self.owner if self.owner.is_a?(Organization)
      repository = self
    else
      repository = self
    end

    query = AutocompleteQuery.new(
      current_user,
      query,
      organization: organization,
      repository: repository,
      teams_only: true
    )

    query.suggestions.filter_map do |team|
      next if !team.is_a?(Team) || team.secret?
      {
        actorId: team.id,
        actorType: :Team,
        name: team.name,
      }
    end
  end

  sig { params(conditions: T::Hash[String, T.untyped]).returns(String) }
  def build_phrase_from_property_conditions(conditions)
    include_string = conditions["include"].map { |property| property_to_query_param(property, "") }.join(" ")
    exclude_string = conditions["exclude"].map { |property| property_to_query_param(property, "-") }.join(" ")

    "#{include_string} #{exclude_string}".strip
  end

  sig { params(property: T::Hash[String, T.untyped], prefix: String).returns(String) }
  def property_to_query_param(property, prefix)
    value_string = property["property_values"].join(",")
    prop_name = property["source"] == "system" ? property["name"] : "props.#{property["name"]}"
    "#{prefix}#{prop_name}:#{value_string}"
  end

  class RepositoryNotFound < StandardError; end
end
