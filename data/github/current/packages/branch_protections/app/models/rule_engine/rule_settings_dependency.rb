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
  def member_privilege_rulesets_enabled?
    feature_enabled_for_source?(:member_privilege_rulesets)
  end

  sig { returns(T::Boolean) }
  def rule_api_include_metadata_enabled?
    feature_enabled_for_source?(:rule_api_include_metadata)
  end

  sig { returns(T::Boolean) }
  def repo_policy_bypass_enabled?
    feature_enabled_for_source?(:repo_policy_bypass)
  end

  sig { returns(T::Boolean) }
  def ruleset_second_limit_enabled?
    feature_enabled_for_source?(:ruleset_second_limit)
  end

  def rules_validate_bypass_actors_on_import?
    feature_enabled_for_source?(:rules_validate_bypass_actors_on_import)
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
    rulesets = Repositories.domain.rulesets.load_rulesets(self, targets: %w[branch tag push repository])
    rulesets.each do |ruleset|
      next unless ruleset.enabled?
      source = ruleset.source
      next unless source.is_a?(Organization) || source.is_a?(Business)

      condition = ruleset.conditions.find { |c| c.target == "repository_name" }
      next unless condition&.parameters&.[]("protected")

      targetable = Targeting::Targets::Repository.new(repository: self)
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

  sig { params(qualified_ref_name: String).returns(T::Array[RuleEngine::IRuleset]) }
  def rulesets_for_ref(qualified_ref_name)
    return [] unless is_a?(Repository)

    rulesets = Repositories.domain.rulesets.load_rulesets(self, targets: %w[branch tag push])

    rulesets.filter do |ruleset|
      RulesEngine::RulesetMatcher.should_evaluate_ref?(ruleset, self, qualified_ref_name)
    end
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
    "fail" =>  %w[failed git_error enter_queue_failed stack_merge_failed], # TODO: `push_rejected` should probably be included here as well
    "bypass" => ["bypassed"]
  }
  EVALUATE_RESULT_MAP = RESULT_MAP.merge({ "fail" => ["failed"] })
  MAX_LOOKBACK_DAYS = 30

  sig do
    params(
      page_size: Integer,
      page: T.nilable(Integer),
      ref: T.nilable(String), # qualified or unqualified ref name (unqualified will search for heads and tags)
      ruleset: T.nilable(RuleEngine::IRuleset),
      actor: T.untyped,
      time_period: T.nilable(String),
      repository: T.nilable(Repository),
      organization: T.nilable(Organization),
      rule_status: String,
      evaluate_status: String,
      after_oid: T.nilable(String), # the after-oid of the ref update
      is_ui: T::Boolean,
      created: T.nilable(String),
      for_dashboard: T::Boolean,
      skip_participation_filter: T::Boolean,
      user_timezone: T.nilable(ActiveSupport::TimeZone),
    ).returns(T.untyped)
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
    after_oid: nil, # combined with ref and repo to fetch suites for specific shas
    is_ui: false,
    created: nil, # raw date string (e.g. ">@today-1w", "@today", ">@today-30d")
    for_dashboard: false,
    skip_participation_filter: false,
    user_timezone: nil
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
      "created_filter:#{created.present?}",
    ]
    GitHub.dogstats.distribution_time("repository_rules_engine.fetch_rule_suites", tags:) do
      timeout = feature_enabled_for_source?(:rule_insights_timeout) ? RULE_SUITE_TIMEOUT : 0
      GitHub::Timer.timeout(timeout) do
        # This query will only return RuleSuites that include a rulesuite defined at the level of self.
        # EG: If self is an org, only RuleSuites that included an org-level ruleset should be included.
        base_sql = if self.is_a?(Organization)
          RuleEngine::RuleSuite.where(owner: self)
        elsif self.is_a?(Business)
          RuleEngine::RuleSuite.where(business: self)
        else
          RuleEngine::RuleSuite.where(repository: self)
        end

        unless for_dashboard
          base_sql = base_sql.order(created_at: :desc).limit(page_size + 1)
        end

        if !for_dashboard && page.present? && page > 1
          base_sql = base_sql.offset((page - 1) * page_size)
        end

        if ruleset.present?
          # only suites that included rules from this ruleset.
          # the provided ruleset MUST be defined at the current level (self).
          # enforcement currently happens here: repository_rules::check_rule_suite_filters
          base_sql = base_sql.for_ruleset(ruleset)
        elsif !self.is_a?(Repository) && !skip_participation_filter
          # Only include suites where a rule ran at this level
          base_sql = base_sql.source_result_exists(source: self)
        end

        if after_oid.present?
          if is_ui
            if self.is_a?(Repository)
              normalized = after_oid.strip.downcase
              # SHA256.valid_short_oid? validates 7-64 hex chars (covers short and full OIDs for SHA-1 and SHA-256)
              if GitHub::HashAlgorithm::SHA256.valid_short_oid?(normalized)
                is_full_oid = GitHub::HashAlgorithm::SHA1.valid_full_oid?(normalized) ||
                  GitHub::HashAlgorithm::SHA256.valid_full_oid?(normalized)
                if is_full_oid
                  base_sql = base_sql.where(after_oid: normalized)
                else
                  sanitized_oid = ActiveRecord::Base.sanitize_sql_like(normalized)
                  base_sql = base_sql.where("after_oid LIKE ?", "#{sanitized_oid}%")
                end
              end
            end
          elsif feature_enabled_for_source?(:repos_rule_suites_list_by_sha) && self.is_a?(Repository)
            base_sql = base_sql.where(after_oid: after_oid)
          end
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

        resolved_created = T.let(nil, T.nilable(T::Range[Date]))
        if created.present? && is_ui
          if for_dashboard
            timezone = FeatureFlag.vexi.enabled?(:rule_insights_utc, @user, default: false) ? ActiveSupport::TimeZone.new("UTC") : user_timezone
            time_range = Repos::Rules::CreatedDateFilter.resolve_dashboard_date_range(
              created, timezone: timezone, max_lookback_days: MAX_LOOKBACK_DAYS,
            )
            resolved_created = time_range.begin.to_date..time_range.end.to_date
            base_sql = base_sql.where(created_at: time_range)
          else
            current_date = user_timezone ? Time.current.in_time_zone(user_timezone).to_date : Date.current
            max_lookback = current_date - MAX_LOOKBACK_DAYS

            # if there is no user nor user_timezone (such as in tests) fallback to UTC to avoid timezone issues with CreatedDateFilter + clamping logic
            parsed = Repos::Rules::CreatedDateFilter.parse_created_date_value(created, timezone: user_timezone || ActiveSupport::TimeZone["UTC"], gt_lt_cap_days: MAX_LOOKBACK_DAYS)

            if parsed.nil?
              base_sql = base_sql.none
            else
              clamped = Repos::Rules::CreatedDateFilter.clamp_created_filter(parsed, max_lookback, current_date: current_date)

              range_begin = parsed.is_a?(Range) ? T.unsafe(parsed).begin : parsed
              if range_begin.is_a?(Date) && range_begin > current_date
                base_sql = base_sql.none
              else
                parsed_result = clamped || ((current_date - 7)..current_date)

                resolved_created = if parsed_result.is_a?(Date)
                  parsed_result..parsed_result
                else
                  T.cast(parsed_result, T::Range[Date])
                end

                from_time = T.must(resolved_created.begin).beginning_of_day
                to_time = T.must(resolved_created.end).end_of_day
                base_sql = base_sql.where(created_at: from_time..to_time)
              end
            end
          end
        else
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
            # evaluate rules at this level didn't fail or get bypassed
            # AND
            # There are some active rules OR there are some rules at this level (of which, evaluate rules if any are passing)
            base_sql = base_sql.where(result: RESULT_MAP[rule_status])
              .source_result_not_exists(evaluate_result: ["failed"], source: self)
              .source_result_not_exists(evaluate_result: ["bypassed"], source: self)
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

        return [base_sql, resolved_created] if for_dashboard

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
      sort: T.nilable(String),
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
    request_types: [],
    sort: nil
  )
    T.bind(self, RuleEngine::Types::RuleSource)
    base_sql = Exemptions::BatchExemptionRequestQuery.base_sql_for_exemption_requests(self, request_types:, repository:, organization:, request_status:, approver:, requester:, time_period:, limit: page_size + 1, sort:)
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

  # TODO: Move to RepositoryRuleCondition or another helper class
  sig { params(property_condition: RuleEngine::IRuleCondition).returns(String) }
  def es_query_property_ruleset_conditions(property_condition)
    org = T.bind(self, Organization)

    "org:#{org.display_login} #{build_phrase_from_property_condition(property_condition)}"
  end

  # TODO: Move to RepositoryRuleCondition or another helper class
  sig { params(property_condition: RuleEngine::IRuleCondition).returns(String) }
  def build_phrase_from_property_condition(property_condition)
    raise ArgumentError, "Condition must target repository_property" unless property_condition.target == "repository_property"

    include_string = property_condition.parameters["include"].map { |property| property_to_query_param(property, "") }.join(" ")
    exclude_string = property_condition.parameters["exclude"].map { |property| property_to_query_param(property, "-") }.join(" ")

    "#{include_string} #{exclude_string}".strip
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def system_properties_effective_values
    if self.is_a?(Repository)
      ::RepositoryRulesets::SystemProperties.get_values(self)
    else
      {}
    end
  end

  private

  # TODO: Move to RepositoryRuleCondition or another helper class
  sig { params(property: T::Hash[String, T.untyped], prefix: String).returns(String) }
  def property_to_query_param(property, prefix)
    value_string = property["property_values"].map { |value| value.include?(" ") ? "\"#{value}\"" : value  }.join(",")
    prop_name = property["source"] == "system" ? property["name"] : "props.#{property["name"]}"
    "#{prefix}#{prop_name}:#{value_string}"
  end
end
