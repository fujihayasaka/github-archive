# typed: true
# frozen_string_literal: true

module RuleEngine
  # Represents a single rule run and its result
  class RuleRun < ApplicationRecord::Repositories
    include GitHub::BatchMethod
    include GitHub::Memoizer

    self.table_name = "repository_rule_runs"

    belongs_to :rule_suite, class_name: "RuleEngine::RuleSuite", foreign_key: :repository_rule_suite_id, inverse_of: :rule_runs
    belongs_to :rule_config, class_name: "RepositoryRuleConfiguration", foreign_key: :repository_rule_configuration_id, inverse_of: :rule_runs

    validates :rule_suite, presence: true

    after_initialize :initialize_json_fields
    before_save :normalize_json_fields
    after_commit :initialize_json_fields, on: [:create, :update] # props are frozen after a destroy operation

    MAX_MESSAGE_LENGTH = 1024 # Maximum length of the message field in the database
    TRUNCATED_MESSAGE = "...(truncated)"
    before_save :truncate_message

    # Holds the action this RuleRun applies to during evaluation. Use to populate RuleSuites
    sig { returns(T.nilable(RuleEngine::RuleEvent::EventAction)) }
    attr_accessor :event_action

    # Holds the ref_update this RuleRun applies to during evaluation. Use to populate RuleSuites
    sig { returns(T.nilable(Git::Ref::Update)) }
    attr_accessor :ref_update

    # The optional message to display to the user when the rule fails via the git CLI
    sig { returns(T.nilable(String)) }
    attr_accessor :cli_message

    sig { returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
    attr_accessor :delegation_metadata

    # Rule providers that are configured in the protected branches/tags UI
    LEGACY_RULE_PROVIDERS = %w[
      protected_branch
      merge_queue_locked_ref
      tag_permission
    ].freeze

    RESULTS = {
      allowed: 0,
      failed: 1,
      evaluate_allowed: 2,
      evaluate_failed: 3
    }.with_indifferent_access.freeze
    enum :result, RESULTS

    sig do
      params(
        rule_config: RepositoryRuleConfiguration,
        ref_update: T.nilable(Git::Ref::Update),
        event_action: T.nilable(RuleEvent::EventAction),
        evaluation_metadata: T::Hash[T.any(String, Symbol), T.untyped]
      )
      .returns(RuleRun)
    end
    def self.success(rule_config:, ref_update: nil, event_action: nil, evaluation_metadata: {})
      result = rule_config.repository_ruleset&.evaluate? ? :evaluate_allowed : :allowed

      new(rule_config: rule_config, rule_type: rule_config.rule_type, result: result,
        rule_provider: rule_config.provider_name, rule_provider_id: rule_config.provider_id,
        rule_history_id: rule_config.history_id, ref_update: ref_update, event_action: event_action || ref_update, evaluation_metadata:)
    end

    sig do
      params(
        rule_config: RepositoryRuleConfiguration,
        message: String,
        ref_update: T.nilable(Git::Ref::Update),
        event_action: T.nilable(RuleEvent::EventAction),
        cli_message: T.nilable(String),
        violations: T.nilable(T::Array[{
          candidate: String,
        }]),
        evaluation_metadata: T::Hash[T.any(String, Symbol), T.untyped],
      )
      .returns(RuleRun)
    end
    def self.failure(rule_config:, message:, ref_update: nil, event_action: nil, cli_message: nil, violations: nil, evaluation_metadata: {})
      result = rule_config.repository_ruleset&.evaluate? ? :evaluate_failed : :failed

      violations = {
        total: violations.size,
        items: violations.take(10),
      } if violations.present?

      new(rule_config:, rule_type: rule_config.rule_type, result: result, message:, cli_message:, violations:, evaluation_metadata:,
        rule_provider: rule_config.provider_name, rule_provider_id: rule_config.provider_id, rule_history_id: rule_config.history_id,
        ref_update:, event_action: event_action || ref_update)
    end

    sig { returns(T::Boolean) }
    def allowed?
      super || evaluate_allowed? || evaluate_failed?
    end

    sig { returns(T::Boolean) }
    def evaluate_mode?
      evaluate_allowed? || evaluate_failed?
    end

    # Indicates which commit the rule was evaluated against (either a merge commit or the PR head commit)
    # This is used by the status check rule
    def basis_commit
      return @basis_commit if defined?(@basis_commit)

      @basis_commit = rule_suite&.repository&.commits.
        find(evaluation_metadata["basis_commit_oid"]) if evaluation_metadata.has_key?("basis_commit_oid")
    end

    def instrumentation_payload
      evaluation_metadata["instrumentation_payload"]&.symbolize_keys
    end

    def reason_code
      (evaluation_metadata["reason_code"] || rule_type)&.to_sym
    end

    sig { returns(T::Boolean) }
    memoize def can_bypass?
      return false unless config = rule_config
      return false unless repo = rule_suite&.repository
      return false unless actor = rule_suite&.actor

      rule_impl&.can_bypass?(config, actor, repo, self) || false
    end

    def insights_ui_metadata
      rule_impl&.insights_ui_metadata(self)
    end

    sig { returns(T.nilable(RuleEngine::BaseRule)) }
    def rule_impl
      RuleEngine::Evaluator.rule_impl_for_rule_type(rule_type)
    end

    sig { returns(T::Boolean) }
    def ruleset_provider?
      RuleEngine::RuleProviders::RulesetRuleProvider::RULESET_PROVIDERS.include?(rule_provider)
    end

    batch_method(:source_ruleset, T.nilable(RepositoryRuleset)) do |rule_runs|
      rule_runs = T.cast(rule_runs, T::Array[RuleRun])
      ids = rule_runs.filter(&:ruleset_provider?).map(&:rule_provider_id).compact.uniq
      rulesets = RepositoryRuleset.where(id: ids).to_h { |ruleset| [ruleset.id, ruleset] }

      rule_runs.index_with { |run| rulesets[run.repository_ruleset_id] if run.repository_ruleset_id }
    end

    sig { returns(T.nilable(Integer)) }
    def repository_ruleset_id
      rule_provider_id if ruleset_provider?
    end

    sig { returns(T::Boolean) }
    def source_out_of_date?
      return false unless rule_history_id.present? && rule_provider_id.present? && ruleset_provider?
      ruleset = source_ruleset

      ruleset.present? && ruleset.latest_history_id.present? && ruleset.latest_history_id != rule_history_id || false
    end

    def legacy_reason_code
      return unless failed?

      case rule_type
      when "pull_request"
        :review_policy_not_satisfied
      when "required_status_checks"
        reason_code.to_sym
      when "non_fast_forward"
        :force_push
      when "deletion"
        :branch_deletion
      when "authorization"
        :unauthorized
      when "required_signatures"
        :invalid_signature
      when "required_linear_history"
        :merge_commit
      when "required_deployments"
        :required_deployments_not_satisfied
      when "required_review_thread_resolution"
        :required_review_thread_resolution_not_satisfied
      when "tag"
        reason_code.to_sym
      else
        rule_type.to_sym
      end
    end

    def legacy_rule_provider?
      LEGACY_RULE_PROVIDERS.include?(rule_provider)
    end

    sig { returns(T.nilable(RuleProvider)) }
    def rule_provider_impl
      Evaluator::RULE_PROVIDERS.find { |rp| rp.identifier == rule_provider }
    end

    sig { params(viewing_source: RuleEngine::Types::RuleSource, filter_mode: Symbol).returns(T::Boolean) }
    def show_in_insights?(viewing_source, filter_mode)
      raise ArgumentError, "filter_mode must be :all, :active, or :evaluate" unless %i[all active evaluate].include?(filter_mode)

      return false unless rule_insights_category.present?

      # Filter based on evaluation_status
      return false if filter_mode == :active && evaluate_mode?
      return false if filter_mode == :evaluate && !evaluate_mode?

      return true if source_ruleset.nil?

      # Don't show evaluate mode results from other sources
      T.must(source_ruleset).source == viewing_source || !evaluate_mode?
    end

    sig { returns(T.nilable({ name: String, id: T.nilable(Integer), link: T.nilable(String), view_link: T.nilable(String) })) }
    memoize def rule_insights_category
      # 'repository_ruleset' is the legacy provider name used for rulesets before they were moved to their own provider
      name = if rule_provider.nil? || rule_provider == "repository_ruleset"
        source_ruleset&.name || "Deleted ruleset(s)"
      else
        rule_provider_impl&.insights_category(self)
      end

      link, view_link = if ruleset_provider? && (ruleset = source_ruleset).present?
        links = []
        links << if ruleset.source&.rules_history? && source_out_of_date?
          ruleset.definition.history_url(T.must(ruleset.id), T.must(rule_history_id))
        else
          ruleset.definition.edit_url(T.must(ruleset.id))
        end
        links << ruleset.definition.url(T.must(ruleset.id)) if rule_suite&.repository && repository_ruleset_id
        links
      end

      { name: name, id: rule_provider_id, link: link, view_link: view_link } if name
    end

    sig { returns(Promise[T::Array[Exemptions::ExemptionResponse]]) }
    memoize def async_exemption_responses
      responses = evaluation_metadata["exemption_responses"]
      return Promise.resolve(T.cast([], T::Array[Exemptions::ExemptionResponse])) unless responses.present?

      Platform::Loaders::ActiveRecord.load_all(Exemptions::ExemptionResponse, responses).then do |loaded_responses|
        loaded_responses.compact
      end
    end

    sig { returns(T::Array[Exemptions::ExemptionResponse]) }
    def exemption_responses
      async_exemption_responses.sync
    end

    def platform_type_name
      "RepositoryRuleRun"
    end

    def initialize_json_fields
      self.evaluation_metadata = {} if self.evaluation_metadata.nil?
      self.violations = {} if self.violations.nil?
    end

    def normalize_json_fields
      self.evaluation_metadata = nil if self.evaluation_metadata.blank?
      self.violations = nil if self.violations.blank?
    end

    def truncate_message
      msg = message || ""
      if msg.length > MAX_MESSAGE_LENGTH
        GitHub.dogstats.increment("repository_rules_engine.rule_run.message_truncated", tags: ["rule_type:#{rule_type}"])
        self.message = msg.truncate(MAX_MESSAGE_LENGTH, omission: TRUNCATED_MESSAGE)
      end
    end
  end
end
