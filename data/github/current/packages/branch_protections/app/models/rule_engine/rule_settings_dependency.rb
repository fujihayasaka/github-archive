# typed: true
# frozen_string_literal: true

module RuleEngine::RuleSettingsDependency
  extend T::Helpers
  include GitHub::Memoizer

  requires_ancestor { Kernel }

  class UnsupportedError < StandardError
  end

  # Generic handler for source feature flags
  # `check_enterprise_for_org` exists since the old version of this method did not check enterprise features correctly.
  # This exists for safe rollout, remove when confident it is okay to check the enterprise for all org-level features
  sig { params(feature_flag: T.any(Symbol, String), check_enterprise_for_org: T::Boolean).returns(T::Boolean) }
  def feature_enabled_for_source?(feature_flag, check_enterprise_for_org: true)
    T.bind(self, RuleEngine::Types::RuleSource)
    feature_flag = feature_flag.to_sym
    if self.is_a?(Repository)
      async_scoped_feature_flag_enabled?(feature_flag).sync
    elsif self.is_a?(Organization)
      feature_flag_enabled?(feature_flag, default: false) || (check_enterprise_for_org && !!business&.feature_flag_enabled?(feature_flag, default: false))
    else
      feature_flag_enabled?(feature_flag, default: false)
    end
  end

  # TODO: When removing this feature flag, remove the "beta" notes in the API
  # Search for rules_deploy_key_bypass
  sig { returns(T::Boolean) }
  def deploy_key_bypass_enabled?
    feature_enabled_for_source?(:rules_deploy_key_bypass, check_enterprise_for_org: false)
  end

  sig { returns(T::Boolean) }
  def a11y_add_bypass_dialog?
    feature_enabled_for_source?(:a11y_add_bypass_dialog, check_enterprise_for_org: false)
  end

  sig { returns(T::Boolean) }
  def member_privilege_rulesets_enabled?
    feature_enabled_for_source?(:member_privilege_rulesets)
  end

  sig { returns(T::Boolean) }
  def repo_policy_bypass_enabled?
    feature_enabled_for_source?(:repo_policy_bypass)
  end

  sig { returns(T::Boolean) }
  def rule_suite_event_actions_enabled?
    feature_enabled_for_source?(:rule_suite_event_actions)
  end

  sig { returns(T::Boolean) }
  def enterprise_rulesets_enterprise_teams_enabled?
    feature_enabled_for_source?(:enterprise_rulesets_enterprise_teams)
  end

  sig { returns(T::Boolean) }
  def enterprise_rulesets_enterprise_roles_enabled?
    feature_enabled_for_source?(:enterprise_rulesets_enterprise_roles)
  end

  sig { returns(T::Boolean) }
  def enterprise_rulesets_enterprise_apps_enabled?
    feature_enabled_for_source?(:enterprise_rulesets_enterprise_apps)
  end

  sig { returns(T::Boolean) }
  def ruleset_second_limit_enabled?
    feature_enabled_for_source?(:ruleset_second_limit)
  end

  def rules_validate_bypass_actors_on_import?
    feature_enabled_for_source?(:rules_validate_bypass_actors_on_import)
  end

  sig { returns(T::Boolean) }
  def rules_more_efficient_teams_for?
    feature_enabled_for_source?(:rules_more_efficient_teams_for)
  end

  sig { returns(T::Boolean) }
  def rules_import_export_local_storage?
    feature_enabled_for_source?(:rules_import_export_local_storage)
  end

  sig { returns(T::Boolean) }
  def prx_merge_improvements?
    feature_enabled_for_source?(:rulesets_prx_merge_improvements)
  end

  sig { returns(T::Boolean) }
  def merge_queue_squash_merge_improvements?
    return false unless prx_merge_improvements?

    feature_enabled_for_source?(:rulesets_merge_queue_squash_merge_improvements)
  end

  sig { params(actor: User).returns(T::Boolean) }
  def blocks_repository_rename?(actor)
    # This function should only be called from a repository
    return true unless self.is_a?(Repository)

    # Only organizations can have rename target blocks
    return false unless self.in_organization?

    # Check Organization rulesets to see if target protection is set
    rulesets = filtered_inherited_rulesets(targets: %w[branch tag push repository])
    rulesets.each do |ruleset|
      next unless ruleset.enabled?
      source = ruleset.source
      next unless source.is_a?(Organization) || source.is_a?(Business)

      condition = ruleset.conditions.find_by(target: "repository_name")
      next unless condition&.parameters&.[]("protected")

      targetable = RuleEngine::Conditions::Targets::Repository.new(repository: self)
      return true unless ruleset.rule_provider.ruleset_bypass_allowed?(ruleset, actor, targetable, is_pull_request: false)
    end

    false
  end

  sig { returns(T::Boolean) }
  def rules_disallow_deploy_key_org_bypass?
    feature_enabled_for_source?(:rules_disallow_deploy_key_org_bypass_optin, check_enterprise_for_org: false)
  end

  sig { returns(T::Boolean) }
  def dont_check_repos_integrations_limit?
    feature_enabled_for_source?(:dont_check_repos_integrations_limit, check_enterprise_for_org: false)
  end

  sig { returns(T::Boolean) }
  def merge_queue_bot_bypass_enabled?
    feature_enabled_for_source?(:merge_queue_bot_bypass)
  end

  sig { returns(T::Boolean) }
  def deprecate_integrations_for_enabled?
    feature_enabled_for_source?(:rules_deprecate_integrations_for)
  end

  sig { params(enabled_only: T::Boolean, targets: T::Array[String]).returns(T::Array[RepositoryRuleset]) }
  def filtered_inherited_rulesets(enabled_only: false, targets: %w[branch tag push])
    T.bind(self, RuleEngine::Types::RuleSource)

    rulesets = RepositoryRuleset.load_for(source: self, include_parents: true, targets:)

    source_priority = {
      [Business.class.name] => 0,
      [Organization.class.name] => 1,
      [Repository.class.name] => 2
    }

    rulesets.filter do |ruleset|
      ruleset.enabled? || (!enabled_only && self == ruleset.source)
    end.sort do |a, b|
      if a.source == b.source
        a.name <=> b.name || 0
      else
        source_priority.fetch(a.source.class.name, 10) <=> source_priority.fetch(b.source.class.name, 10)
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
        .source_result_exists(source: self)
    else
      RuleEngine::RuleSuite
        .where(repository: self)
    end

    base_sql.find_by(id: rule_suite_id)
  end

  class RuleInsightsTimeoutError < StandardError
  end

  RULE_SUITE_TIMEOUT = 8 # seconds
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
      organization: T.nilable(Organization),
      rule_status: String,
      evaluate_status: String,
      after_oid: T.nilable(String), # the after-oid of the ref update
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
    organization: nil,
    rule_status: "all", # all, pass, fail, bypass
    evaluate_status: "active", # all, active, evaluate
    after_oid: nil # combined with ref and repo to fetch suites for specific shas
  )
    T.bind(self, RuleEngine::Types::RuleSource)

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
      timeout = feature_enabled_for_source?(:rule_insights_timeout) ? RULE_SUITE_TIMEOUT : 0
      GitHub::Timer.timeout(timeout) do
        # This query will only return RuleSuites that include a rulesuite defined at the level of self.
        # EG: If self is an org, only RuleSuites that included an org-level ruleset should be included.
        base_sql = if self.is_a?(Organization)
          RuleEngine::RuleSuite
            .where(owner: self)
            .order(created_at: :desc)
            .limit(page_size + 1)
        elsif self.is_a?(Business)
          RuleEngine::RuleSuite
            .where(business: self)
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
          # only suites that included rules from this ruleset.
          # the provided ruleset MUST be defined at the current level (self).
          # enforcement currently happens here: repository_rules::check_rule_suite_filters
          base_sql = base_sql.for_ruleset(ruleset)
        elsif !self.is_a?(Repository)
          # Only include suites where a rule ran at this level
          base_sql = base_sql.source_result_exists(source: self)
        end

        if feature_enabled_for_source?(:repos_rule_suites_list_by_sha) && after_oid.present? && self.is_a?(Repository)
          # after_sha filtering only works if called on a repository directly.
          base_sql = base_sql.where(after_oid: after_oid)
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
        base_sql = base_sql.where(owner: organization) if organization.present?

        # remove when we want to show repo policies in rule insights
        base_sql = base_sql.where.not(event_action_type: RuleEngine::EventActionRepositoryOperation)

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

        GitHub::PrefillAssociations.prefill_associations(suites, [:actor, :rule_runs, :source_results])

        return suites, has_more
      end
    end
  rescue GitHub::Timer::Error
    GitHub.logger.info("Rule insights timed out", {
      "code.namespace" => "RuleSettingsDependency",
      "code.function" => "fetch_rule_suites",
    })

    raise RuleInsightsTimeoutError, "Rule insights timed out"
  end

  sig do
    params(
      repository: T.nilable(Repository),
      organization: T.nilable(Organization),
      page_size: Integer,
      page: T.nilable(Integer),
      requester: T.untyped,
      approver: T.untyped,
      time_period: T.nilable(String),
      request_status: T.nilable(String),
      request_types: T::Array[String],
    ).returns([T::Array[Exemptions::ExemptionRequest], T::Boolean])
  end
  def fetch_bypass_requests(
    repository: nil,
    organization: nil,
    page_size: 10,
    page: nil,
    requester: nil,
    approver: nil,
    time_period: "day",
    request_status: "all",
    request_types: []
  )
    T.bind(self, RuleEngine::Types::RuleSource)
    base_sql = Exemptions::BatchExemptionRequestQuery.base_sql_for_exemption_requests(self, request_types:, repository:, organization:, request_status:, approver:, requester:, time_period:, limit: page_size + 1)
    if page.present? && page > 1
      base_sql = base_sql.offset((page - 1) * page_size)
    end

    exemption_requests = base_sql.to_a

    has_more = exemption_requests.size > page_size
    exemption_requests.slice!(page_size..) if has_more

    Exemptions::BatchExemptionRequestQuery.mark_exemption_requests_as_deleted_if_necessary(exemption_requests)

    [exemption_requests, has_more]
  end

  sig { params(exemption_request_number: Integer).returns(T.nilable(Exemptions::ExemptionRequest)) }
  def fetch_bypass_request_by_number(exemption_request_number)
    Exemptions::ExemptionRequest.for_ruleset_source(self).find_by(number: exemption_request_number)
  end

  def update_ruleset_from_json(current_ruleset, ruleset_json, current_user)
    changes = current_ruleset.name != ruleset_json["name"] ||
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
      if FeatureFlag.vexi.enabled_or_raise?(:ruleset_backfill_source) && condition["target"] == "repository_property" # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
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
    rescue RepositoryRuleset::ConditionValidationError => e
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
    rescue RepositoryRuleset::BypassActorsValidationError, RepositoryRulesetBypassActor::ValidationError => e
      failed_rules = e.errors.map { |error| error.message }
      error_message = failed_rules.uniq.join("\', \'")
    end

    [error_message, detailed_errors]
  end

  # TODO: Move to RepositoryRuleCondition or another helper class
  sig { params(property_condition: RepositoryRuleCondition).returns(String) }
  def es_query_property_ruleset_conditions(property_condition)
    org = T.bind(self, Organization)

    "org:#{org.display_login} #{build_phrase_from_property_condition(property_condition)}"
  end

  # TODO: Move to RepositoryRuleCondition or another helper class
  sig { params(property_condition: RepositoryRuleCondition).returns(String) }
  def build_phrase_from_property_condition(property_condition)
    raise ArgumentError, "Condition must target repository_property" unless property_condition.target == "repository_property"

    include_string = property_condition.parameters["include"].map { |property| property_to_query_param(property, "") }.join(" ")
    exclude_string = property_condition.parameters["exclude"].map { |property| property_to_query_param(property, "-") }.join(" ")

    "#{include_string} #{exclude_string}".strip
  end

  sig { returns(T::Array[T.untyped]) }
  def inherited_sources
    T.bind(self, RuleEngine::Types::RuleSource)

    if self.is_a?(Repository)
      if owner.present? && emu_user_owned?
        [enterprise_managed_business].compact
      else
        # `async_business` and `business` do different things :(
        # `async_business` loads the business from the `owner` relationship while `business` loads it from the `organization` relationship
        # In the case of user owned forks of org repos, the `organization` is the original org, which is not what we want
        [owner.is_a?(Organization) ? owner : nil, async_business.sync].compact
      end
    elsif self.is_a?(Organization)
      [business].compact
    else
      []
    end
  end

  sig { returns(T::Boolean) }
  def delegated_bypass_banner_enhancements?
    feature_enabled_for_source?(:delegated_bypass_banner_enhancements)
  end

  sig { returns(T::Boolean) }
  def exemption_repos_query?
    feature_enabled_for_source?(:exemption_repos_query)
  end

  sig { returns(T::Boolean) }
  def rules_selectpanel_cancel?
    feature_enabled_for_source?(:rules_selectpanel_cancel)
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def system_properties_effective_values
    if self.is_a?(Repository)
      ::RepositoryRulesets::SystemProperties.get_values(self)
    else
      {}
    end
  end

  sig { returns(T::Boolean) }
  def rules_improved_panel_header?
    feature_enabled_for_source?(:rules_improved_panel_header)
  end

  sig { returns(T::Boolean) }
  def rule_engine_rule_timeout?
    feature_enabled_for_source?(:rule_engine_rule_timeout)
  end

  sig { returns(T::Boolean) }
  def dynamic_rule_engine_rule_timeout?
    feature_enabled_for_source?(:dynamic_rule_engine_rule_timeout)
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

  # TODO: Move to RepositoryRuleCondition or another helper class
  sig { params(property: T::Hash[String, T.untyped], prefix: String).returns(String) }
  def property_to_query_param(property, prefix)
    value_string = property["property_values"].map { |value| value.include?(" ") ? "\"#{value}\"" : value  }.join(",")
    prop_name = property["source"] == "system" ? property["name"] : "props.#{property["name"]}"
    "#{prefix}#{prop_name}:#{value_string}"
  end

  class RepositoryNotFound < StandardError; end
end
