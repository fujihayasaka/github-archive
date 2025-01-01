# typed: true
# frozen_string_literal: true

module RuleEngine
  # Represents a set of policy runs against a ref_update
  class RuleSuite < ApplicationRecord::Domain::RuleInsights
    include GitHub::Memoizer
    include GitHub::BatchMethod
    include Instrumentation::Model

    self.table_name = "repository_rule_suites"

    include ApplicationRecord::Sharding
    configure_sharding(sharding_key: :repository_id, should_shard: -> (_, _) { true })

    include ::Repositories::BelongsToRepository
    belongs_to_repository_via_domain legacy_return_type: true
    destroy_in_background_with :repository, sharding_key: :repository_id, sharding_value_key: :id
    belongs_to :owner, class_name: "User"
    belongs_to :business

    belongs_to :actor, polymorphic: true

    belongs_to :event_action, ->(rule_suite) { where(repository_id: rule_suite.repository_id) },
      polymorphic: true, autosave: true, dependent: :destroy
    EventAction = T.type_alias { T.any(EventActionRefUpdate, EventActionRepositoryOperation) }

    has_one :merge_queue_entry, inverse_of: :enqueued_rule_suite, class_name: :MergeQueueEntry, required: false

    has_many :rule_runs, ->(rule_suite) { where(repository_id: rule_suite.repository_id) },
      class_name: "RuleEngine::RuleRun", foreign_key: :repository_rule_suite_id, inverse_of: :rule_suite
    destroy_dependents_in_background :rule_runs,
      sharding_key: :repository_id,
      sharding_value_key: :repository_id,
      parent_sharding_key: :repository_id,
      parent_sharding_value_key: :repository_id

    has_many :source_results, ->(rule_suite) { where(repository_id: rule_suite.repository_id) },
      class_name: "RuleEngine::RuleSuiteSourceResult", foreign_key: :repository_rule_suite_id, inverse_of: :rule_suite
    destroy_dependents_in_background :source_results,
      sharding_key: :repository_id,
      sharding_value_key: :repository_id,
      parent_sharding_key: :repository_id,
      parent_sharding_value_key: :repository_id

    validates :repository, presence: true

    scope :for_ruleset, ->(ruleset) {
      provider_string = RuleProviders::RulesetRuleProvider::RULESET_PROVIDERS.map { |provider| "'#{provider}'" }.join(", ")
      where(<<-SQL)
        EXISTS (
          SELECT  1
          FROM  repository_rule_runs
          WHERE repository_rule_runs.repository_rule_suite_id = repository_rule_suites.id
          AND   repository_rule_runs.repository_id = repository_rule_suites.repository_id
          AND   repository_rule_runs.rule_provider IN (#{provider_string})
          AND   repository_rule_runs.rule_provider_id = #{ruleset.id}
        )
      SQL
    }

    scope :source_result_exists, ->(source: nil, result: nil, evaluate_result: nil, result_not: nil, evaluate_result_not: nil) {
      source_result_filter(match: true, source:, result:, evaluate_result:, result_not:, evaluate_result_not:)
    }
    scope :source_result_not_exists, ->(source: nil, result: nil, evaluate_result: nil, result_not: nil, evaluate_result_not: nil) {
      source_result_filter(match: false, source:, result:, evaluate_result:, result_not:, evaluate_result_not:)
    }

    scope :source_result_filter, ->(match: true, source: nil, result: nil, evaluate_result: nil, result_not: nil, evaluate_result_not: nil) {
      where(<<-SQL)
        #{match ? "" : "NOT "}EXISTS (
          SELECT  1
          FROM    repository_rule_suite_source_results
          WHERE   repository_rule_suite_source_results.repository_rule_suite_id = repository_rule_suites.id
          AND     repository_rule_suite_source_results.repository_id = repository_rule_suites.repository_id
          #{"AND  repository_rule_suite_source_results.result = (#{result.map { RuleSuiteSourceResult::RESULTS[_1] }.join(",")})" if result}
          #{"AND  repository_rule_suite_source_results.evaluate_result IN (#{evaluate_result.map { RuleSuiteSourceResult::EVALUATE_RESULTS[_1] }.join(",")})" if evaluate_result}
          #{"AND  repository_rule_suite_source_results.result NOT IN (#{result_not.map { RuleSuiteSourceResult::RESULTS[_1] }.join(",")})" if result_not}
          #{"AND  repository_rule_suite_source_results.evaluate_result NOT IN (#{evaluate_result_not.map { RuleSuiteSourceResult::EVALUATE_RESULTS[_1] }.join(",")})" if evaluate_result_not}
          #{"AND  repository_rule_suite_source_results.source_type = '#{source.class.base_class.name}'" if source}
          #{"AND  repository_rule_suite_source_results.source_id = #{source.id}" if source}
        )
      SQL
    }

    RESULTS = {
      allowed: 0,
      failed: 1,
      git_error: 2,
      bypassed: 3,
      push_rejected: 4, # indicates this ref update was rejected due to another rejected ref update in the same push
      entered_queue: 5, # Stores the result of evaluating rules at the moment merge queue was entered. No ref update has
      #                   yet occurred; therefore suites in this state should never be visible to users / APIs.
      enter_queue_failed: 6, # Attempted to enter merge queue but rejected by policy.
    }.with_indifferent_access.freeze
    enum :result, RESULTS

    before_save :populate_source_results!

    after_initialize :initialize_json_fields
    before_save :normalize_json_fields

    after_commit :initialize_json_fields, on: [:create, :update] # props are frozen after a destroy operation

    after_commit :instrument_event, on: [:create, :update]

    sig { returns(T.nilable(String)) }
    attr_accessor :additional_cli_message

    sig { params(repository: Repository, ref_update: T.nilable(Git::Ref::Update), actor: Types::Actor).returns(RuleSuite) }
    def self.success(repository, ref_update, actor)
      new(repository:, owner: repository.owner, business: repository.owner&.business, ref_update:, actor:)
    end

    sig { params(repository: Repository, actor: Types::Actor, ref_update: T.nilable(Git::Ref::Update)).returns(RuleSuite) }
    def self.object_missing(repository, actor, ref_update: nil)
      new(repository:, owner: repository.owner, business: repository.owner&.business, actor:, ref_update:, result: :git_error)
    end

    sig { params(action: T.nilable(RuleEvent::EventAction)).returns(T.nilable(RuleSuite::EventAction)) }
    def self.new_event_action(action)
      return nil if action.nil?
      return EventActionRefUpdate.from_ref_update(nil, action) if action.is_a?(Git::Ref::Update)
      return action if action.is_a?(EventActionRepositoryOperation)
      nil
    end

    sig do
      params(
        event: RuleEvent,
        action: RuleEvent::EventAction,
        rule_runs: T::Enumerable[RuleRun],
        evaluation_metadata: T::Hash[T.any(String, Symbol), T.untyped],
      ).returns(RuleSuite)
    end
    def self.for_event_action(event:, action:, rule_runs: [], evaluation_metadata: {})
      event_action = self.new_event_action(action)

      suite = new(
        repository: event_action&.repository,
        owner: event_action&.repository&.owner,
        # TODO: Support insights for EMU users
        business: (org = event_action&.repository&.owner).is_a?(Organization) ? org.business : nil,
        rule_runs: rule_runs.to_a,
        result: rule_runs.any?(&:failed?) ? :failed : :allowed,
        event_action:,
        ref_update: action.is_a?(Git::Ref::Update) ? action : nil,
        actor: event.actor,
        evaluation_metadata:
      )
      suite
    end

    sig do
      params(
        ref_update: Git::Ref::Update,
        rule_runs: T::Enumerable[RuleRun],
        result: T.nilable(Symbol),
        actor: T.nilable(RuleEngine::Types::Actor),
        evaluation_metadata: T::Hash[T.any(String, Symbol), T.untyped],
      ).returns(RuleSuite)
    end
    def self.for_ref_update(ref_update:, rule_runs: [], result: nil, actor: nil, evaluation_metadata: {})
      suite = new(
        repository: ref_update.repository,
        owner: ref_update.repository.owner,
        business: ref_update.repository.owner&.business,
        rule_runs: rule_runs.to_a,
        result: result || (rule_runs.any?(&:failed?) ? :failed : :allowed),
        ref_update: ref_update,
        actor: actor,
        evaluation_metadata:
      )
      suite
    end

    sig do
      params(
        suite: RuleSuite,
        ref_update: Git::Ref::Update,
        rule_runs: T::Enumerable[RuleRun],
        actor: T.nilable(RuleEngine::Types::Actor)
      ).returns(RuleSuite)
    end
    def self.merge(suite:, ref_update:, rule_runs: [], actor: nil)
      raise ArgumentError, "ref_update must be the same" unless suite.ref_name == ref_update.refname || suite.ref_name == GitHub::UNKNOWN_REF_NAME

      suite.ref_update = ref_update
      suite.rule_runs.concat(rule_runs)
      suite.actor = actor
      suite.result = suite.rule_runs.any?(&:failed?) ? :failed : :allowed

      suite
    end

    sig do
      params(
        merge_queue_entry: MergeQueueEntry,
        merge_method: MergeQueues::IConfiguration::MergeMethod,
        group_pr_ids: T::Array[Integer],
        required_status_checks: T.nilable(T::Array[T.any(Status, CombinedStatus::CheckRunAdapter)])
      ).void
    end
    def merge_queue_entry_merged!(merge_queue_entry, merge_method:, group_pr_ids:, required_status_checks:)
      GitHub.tracer.in_span("RuleEngine::RuleSuite.merge_queue_entry_merged!", kind: :internal,
        attributes: {
          "gh.required_status_checks.size" => required_status_checks&.size
      }) do
        GitHub.dogstats.time("RuleSuite::merge_queue_entry_merged.all") do
          return if result != "entered_queue"

          check_results = GitHub.dogstats.time("RuleSuite::merge_queue_entry_merged.check_results") do
            if required_status_checks
              required_status_checks.map do |check|
                check_type = case check
                when Status
                  "Status"
                when CombinedStatus::CheckRunAdapter
                  "CheckRun"
                end

                {
                  type: check_type,
                  id: check.id,
                  context: check.context,
                  state: check.state,
                  integration_id: check.integration_id,
                  duration: check.duration_in_seconds,
                }
              end
            end
          end

          merge_queue_metadata = GitHub.dogstats.time("RuleSuite::merge_queue_entry_merged.merge_queue_metadata") do
            {
              merge_queue: {
                merge_method: merge_method.serialize,
                group_pr_ids:,
                check_results:,
              }.compact
            }
          end

          GitHub.dogstats.time("RuleSuite::merge_queue_entry_merged.update_scalars") do
            self.event_action.before_oid = T.must(merge_queue_entry.base_sha)
            self.event_action.after_oid = T.must(merge_queue_entry.head_sha)
            self.before_oid = T.must(merge_queue_entry.base_sha)
            self.after_oid = T.must(merge_queue_entry.head_sha)
            self.result = :allowed
          end

          GitHub.dogstats.time("RuleSuite::merge_queue_entry_merged.update_evaluation_metadata") do
            # Intentionally not calling deep_merge!, in order to overwrite :merge_queue section with latest data
            self.evaluation_metadata.merge!(merge_queue_metadata)
          end

          GitHub.dogstats.time("RuleSuite::merge_queue_entry_merged.save") do
            save!
          end
        end
      end
    end

    sig do
      params(
        merge_method: T.nilable(MergeQueues::IConfiguration::MergeMethod),
        group_pr_ids: T.nilable(T::Array[Integer]),
        removal_reason: T.nilable(MergeQueues::Entry::RemovalReason),
      ).void
    end
    def merge_queue_group_failed!(merge_method: nil, group_pr_ids: nil, removal_reason: nil)
      self.result = :failed
      # Intentionally not calling deep_merge!, in order to overwrite :merge_queue section with latest data
      self.evaluation_metadata.merge!({
        merge_queue: {
          merge_method: merge_method&.serialize,
          group_pr_ids:,
          removal_reason: removal_reason&.serialize,
        }.compact
      })
      save!
    end

    sig { returns(Git::Ref::Update) }
    def ref_update
      return @ref_update if defined?(@ref_update)

      @ref_update = if policy_oid
        Git::Branch::Update.new(repository:, refname: ref_name, before_oid:, after_oid:, policy_oid:)
      else
        Git::Ref::Update.new(repository:, refname: ref_name, before_oid:, after_oid:)
      end
    end

    def ref_update=(ref_update)
      @ref_update = ref_update

      if ref_update
        self.event_action = RuleEngine::EventActionRefUpdate.from_ref_update(self.event_action, ref_update)
        self.ref_name = ref_update.refname
        self.before_oid = ref_update.before_oid
        self.after_oid = ref_update.after_oid
        self.policy_oid = ref_update.try(:policy_oid)
      end
    end

    sig { returns(T::Boolean) }
    def post_approval_action?
      return false unless event_action.is_a?(EventActionRepositoryOperation)

      event_action&.post_approval_action? || false
    end

    # For some reason, Sorbet doesn't support `alias_method` for AR enums
    sig { returns(T::Boolean) }
    def rules_fulfilled?
      allowed?
    end
    alias_method :rules_fulfilled, :rules_fulfilled?

    def failed?
      super || push_rejected?
    end

    sig { params(rule_type: T.any(Symbol, String)).returns(T::Array[RuleRun]) }
    def runs_by_rule_type(rule_type)
      rule_type = rule_type.to_s
      rule_runs.filter { |run| run.rule_type == rule_type }
    end

    sig { params(rule_type: T.any(Symbol, String)).returns(T::Boolean) }
    def rule_type_failed?(rule_type)
      rule_type = rule_type.to_s
      rule_runs.any? { |run| run.rule_type == rule_type && run.failed? }
    end

    sig { params(filter_bypassable: T::Boolean).returns(T::Array[String]) }
    def failed_rule_types(filter_bypassable: false)
      runs = rule_runs.filter(&:failed?)
      runs = runs.reject(&:can_bypass?) if filter_bypassable

      runs.map(&:rule_type).compact.uniq
    end

    sig { returns(T.nilable(String)) }
    def message
      message = rule_runs.filter(&:failed?).map(&:message).compact.reject(&:empty?).join(" ")
      message unless message.empty?
    end

    sig { params(include_bypassed: T::Boolean, from_cli: T::Boolean, prefix: T.nilable(String), exclude_violations: T::Boolean, indicate_bypassed: T::Boolean).returns(T::Array[String]) }
    def failure_messages(include_bypassed: false, from_cli: false, prefix: "-", exclude_violations: true, indicate_bypassed: false)
      rule_runs.filter_map do |run|
        next unless run.failed?

        message = run.cli_message if from_cli
        message = run.message unless message.present?

        next unless message

        # Don't show errors for rules that can be bypassed
        unless include_bypassed
          next if run.can_bypass?
        end

        ##
        # This creates a bulletted list of messages. Because failed policy messages can be multi-line we are using the number
        # of characters from the prefix to add the proper identation.
        #
        prefix = prefix.present? ? "#{prefix.strip} " : ""
        spacing = prefix.present? ? " " * prefix.length : ""

        formatted_messages = message.strip.split("\n")
        if indicate_bypassed && run.can_bypass? && formatted_messages.any?
          formatted_messages[0] = T.must(formatted_messages[0]) + " (you can bypass)"
        end

        if !exclude_violations && run.violations.present?
          formatted_messages.push(
            "Found #{run.violations["total"]} #{"violation".pluralize(run.violations["total"])}#{" (showing first 10)" if run.violations["total"] > 10}:\n")

          run.violations["items"]&.take(10).each do |item|
            formatted_messages.push(item["candidate"])
          end
        end

        "#{prefix}#{formatted_messages.join("\n#{spacing}")}"
      end.uniq
    end

    sig { params(ignored_rule_types: T::Array[T.any(Symbol, String)]).returns(T.nilable(String)) }
    def message_without_rule_types(ignored_rule_types)
      ignored_rule_types = ignored_rule_types.map(&:to_s)
      rule_runs.filter(&:failed?).reject { |run| ignored_rule_types.include?(run.rule_type) }.map(&:message).join(" ")
    end

    sig { params(included_rule_types: T::Array[T.any(Symbol, String)]).returns(T.nilable(String)) }
    def message_for_rule_types(included_rule_types)
      included_rule_types = included_rule_types.map(&:to_s)
      rule_runs.filter(&:failed?).select { |run| included_rule_types.include?(run.rule_type) }.map(&:message).join(" ")
    end

    # Returns the reason a decision was rejected without including policies that could be overriden
    sig { returns(T.nilable(String)) }
    def message_without_bypassed_rules
      runs = rule_runs.reject(&:allowed?).reject do |run|
        run.can_bypass?
      end

      runs.map(&:message).uniq.join(" ")
    end

    sig { void }
    def check_bypasses!
      @bypass_checked = true

      if failed? && !push_rejected?
        GitHub.tracer.in_span("repository_rules_engine.rule_suite#can_bypass?", kind: :internal) do
          rulesets = rule_runs.map(&:rule_config).compact.flat_map(&:repository_ruleset).compact
          GitHub::PrefillAssociations.prefill_associations(rulesets, { bypass_actors: [:actor] })

          can_bypass = rule_runs.reject(&:allowed?).all? do |run|
            run.can_bypass?
          end

          if can_bypass
            self.result = :bypassed
            save if persisted?
          end
        end
      end
    end

    sig { params(rule_type: T.any(Symbol, String)).returns(T::Boolean) }
    def can_bypass_rule_type?(rule_type)
      rule_type = rule_type.to_s

      runs = rule_runs.filter { |run| run.rule_type == rule_type }.to_a

      # If there are no runs for this policy type, then it's not possible to override
      # If all runs are successful, return whether all policies can be overridden
      # If any runs fail, return whether just the failed policies can be overriden
      if runs.empty?
        false
      elsif runs.all?(&:allowed?)
        runs.all? { |run| run.can_bypass? }
      else
        runs.filter(&:failed?).all? { |run| run.can_bypass? }
      end
    end

    # Returns true if the ref update can be completed by the actor, consdering bypass
    sig { returns(T::Boolean) }
    def action_permitted?
      check_bypasses! unless @bypass_checked

      return true if rules_fulfilled?
      return false if push_rejected?
      bypassed?
    end

    sig { returns(T::Boolean) }
    def should_persist?
      ss_delegated_bypass = SecretScanning::Features::Repo::DelegatedBypass.new(T.must(repository)).feature_available?
      saved_ss_types = ss_delegated_bypass ? [Rules::SecretScanningRule::RULE_NAME, Rules::SecretScanningContentScanRule::RULE_NAME] : []

      rule_runs.any? { |run| run.rule_config&.repository_ruleset.present? || saved_ss_types.include?(run.rule_type) }
    end

    sig { returns(T::Boolean) }
    def contains_ruleset_backed_rule_run?
      rule_runs.any? { |run| run.rule_config&.repository_ruleset.present? }
    end

    sig { returns(Promise[T::Array[Exemptions::ExemptionRequest]]) }
    memoize def async_exemption_requests_used
      requests = evaluation_metadata["used_exemption_requests"]
      return Promise.resolve(T.cast([], T::Array[Exemptions::ExemptionRequest])) unless requests.present?

      Platform::Loaders::ActiveRecord.load_all(Exemptions::ExemptionRequest, requests).then do |loaded_requests|
        loaded_requests.compact
      end
    end

    sig { returns(T::Array[Exemptions::ExemptionRequest]) }
    def exemption_requests_used
      async_exemption_requests_used.sync
    end

    sig do
      params(
        viewing_source: Types::RuleSource,
        filter_mode: Symbol # active, evaluate, all
      ).returns(String)
    end
    def visible_result(viewing_source, filter_mode)
      return result unless %w[allowed failed bypassed].include?(result)
      return result if filter_mode == :active

      source_result = source_results.find_by(source: viewing_source)
      return result unless source_result

      if filter_mode == :evaluate
        # Since evaluate mode rules are only visible from the level they are evaluated from, we can rely fully on the source result
        return "failed" if source_result.evaluate_result_failed?
        return "bypassed" if source_result.evaluate_result_bypassed?
      else
        # For `all` mode, we need to consider the result of the full suite as well as the source result's evaluate mode
        return "failed" if failed? || source_result.evaluate_result_failed?
        return "bypassed" if bypassed? && !source_result.evaluate_result_failed?
      end

      "allowed"
    end

    def log_evaluation
      rule_run_data = GitHub::JSON.encode(rule_runs.map do |run|
        {
          rule_type: run.rule_type,
          result: run.result,
          reason_code: run.reason_code,
          message: run.message,
          rule_config_id: run.rule_config&.id,
          rule_provider: run.rule_config&.provider,
          ruleset_id: run.rule_config&.repository_ruleset_id,
          can_bypass: run.can_bypass?,
          evaluation_metadata: run.evaluation_metadata
        }
      end)

      data = {
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.actor.id": actor.try(:id),
        "gh.actor.type": actor.class.name,
        "gh.repo.id": repository&.id,
        "gh.branch_protection_rule.rule_suite.rules_fulfilled": rules_fulfilled?,
        "gh.branch_protection_rule.rule_suite.result": result,
        "gh.branch_protection_rule.rule_suite.rule_runs": rule_run_data,
      }

      if event_action
        data = data.merge(event_action.evaluation_data)
      else
        # temporary until we backfill event_data_ref_updates so all rule_suites have an event_action
        data = data.merge(
        {
          "gh.branch_protection_rule.rule_suite.ref_name": ref_update.refname.encode("UTF-8", "binary", invalid: :replace, undef: :replace, replace: ""),
          "gh.branch_protection_rule.rule_suite.before_commit": ref_update.before_oid,
          "gh.branch_protection_rule.rule_suite.after_commit": ref_update.after_oid,
          "gh.branch_protection_rule.rule_suite.rule_commit": ref_update.try(:policy_commit_oid),
        })
      end

      GitHub.logger.info("Rule engine evaluation results", data)
    end

    batch_method(:after_commit, T.nilable(Commit)) do |rule_suites|
      rule_suites = T.cast(rule_suites, T::Enumerable[RuleSuite])

      rule_suites_by_repo = rule_suites.group_by(&:repository)
      last_commits = rule_suites_by_repo.filter_map do |repo, repo_suites|
        next unless repo
        oids = repo_suites.map(&:after_oid).compact.filter { |oid| oid != GitHub::PENDING_OID }
        [repo, repo.read_objects(
          oids, :commit, true)
          .compact.map { |commit| Commit.new(repo, commit) }.map { |commit| [commit.oid, commit] }.to_h]
      end.to_h

      rule_suites.map do |rule_suite|
        commit = rule_suite.repository ? last_commits[T.must(rule_suite.repository)]&.[](rule_suite.after_oid) : nil
        [rule_suite, commit]
      end.to_h
    end

    # ====== Legacy instrumentation ======#
    # A lot of this code was copied directly from the old `Decision` object
    # For the initial refactor, I chose to keep this code in place to make sure
    # we maintain compatibility with anything using the existing telemetry (audit log?)
    #
    # A full reconsideration of how we log telemetry for the new Rule Engine will be
    # scheduled for a future PR

    # Private: Prefix used for instrumentation events
    def event_prefix
      :protected_branch
    end

    def legacy_reason_codes
      rule_runs.filter(&:failed?).map { |run| run.legacy_reason_code }.compact.uniq
    end

    def legacy_instrument_decision(payload)
      GitHub.dogstats.increment("repository_rules_engine.result", tags: ["allowed:#{rules_fulfilled?}"])

      instrument_payload(payload)
    end

    private

    def failures_overridden?(repository)
      !rules_fulfilled? && bypassed?
    end

    def instrument_payload(payload)
      return if payload.blank?
      return if rules_fulfilled?

      payload[:overridden_codes] = overridden_codes
      payload[:rule_suite_id] = id if id

      instrument(instrumentation_key(repository), payload)
    end

    def instrumentation_key(repository)
      failures_overridden?(repository) ? :policy_override : :rejected_ref_update
    end

    def overridden_codes
      legacy_reason_codes & overridable_codes
    end

    def overridable_codes
      @overridable_codes ||= Array.new.tap do |codes|
        codes << :review_policy_not_satisfied                     if can_bypass_rule_type?("pull_request")
        codes << :required_status_checks \
              << :required_status_check_integrations              if can_bypass_rule_type?("required_status_checks")
        codes << :invalid_signature                               if can_bypass_rule_type?("required_signatures")
        codes << :merge_commit                                    if can_bypass_rule_type?("required_linear_history")
        codes << :required_deployments_not_satisfied              if can_bypass_rule_type?("required_deployments")
        codes << :required_review_thread_resolution_not_satisfied if can_bypass_rule_type?("required_review_thread_resolution")
        codes << :merge_queue                                     if can_bypass_rule_type?("merge_queue")
        codes << :lock_branch                                     if can_bypass_rule_type?("lock_branch")
        codes.concat(non_protected_branch_rules)                  if can_bypass_non_protected_branch_rules?
      end
    end

    def non_protected_branch_rules
      RuleEngine::Evaluator::REGISTERED_RULES.keys - RuleEngine::Evaluator::BRANCH_PROTECTION_RULE_TYPES
    end

    def can_bypass_non_protected_branch_rules?
      new_rules = non_protected_branch_rules

      rule_runs.filter { |run| new_rules.include?(run.rule_type) }.all? do |run|
        run.can_bypass?
      end
    end

    def instrument_event
      GlobalInstrumenter.instrument("rule_suite.evaluate", {
        id: id,
        ref_name: ref_name,
        before_oid: before_oid,
        after_oid: after_oid,
        policy_oid: policy_oid,
        result: result,
        repository: repository,
        actor: actor,
        rule_runs: rule_runs
      })
    end

    sig { void }
    def populate_source_results!
      new_source_results = RuleSuiteSourceResult.create_for_runs(rule_runs)
      existing_source_results = self.source_results.to_ary
      new_source_results.each do |new_result|
        match = existing_source_results.find { |existing| existing.source == new_result.source }
        if match
          match.result = new_result.result
          match.evaluate_result = new_result.evaluate_result
          match.save if persisted?
        else
          self.source_results << new_result
        end
      end
    end

    def initialize_json_fields
      self.evaluation_metadata = {} if self.evaluation_metadata.nil?
    end

    def normalize_json_fields
      self.evaluation_metadata = nil if self.evaluation_metadata.blank?
    end
  end
end
