# typed: true
# frozen_string_literal: true

# Class containing instructions to the policy engine on how to evaluate a policy
class RepositoryRuleConfiguration < ApplicationRecord::Repositories

  # TODO: Temporary until we update the other references
  alias_attribute :policy_type, :rule_type

  before_validation :retain_workflow_rule_allow_invalid_path
  before_validation :remove_pb_parameters
  before_validation :transform_parameters
  validate :ensure_valid_configuration

  belongs_to :repository_ruleset, class_name: "RepositoryRuleset", inverse_of: :rule_configurations
  validates :repository_ruleset, presence: true

  validates :rule_type, presence: true, length: { maximum: 100 }, uniqueness: { scope: [:repository_ruleset],
    message: ->(object, _data) {
      "'#{object.rule_type}' is already used for this ruleset. Only one instance of this type is allowed per ruleset."
    }
  }

  has_many :rule_runs, class_name: "RuleEngine::RuleRun"

  ## We want to ensure that the parameters object is never nil when accessed and also that an empty hash is never
  # stored in the database. When initializing a new object, we set the parameters object to an empty hash.
  # Before saving, we convert the empty hash to nil and back to an empty hash after the save attempt is completed. This
  # works regardless of the result of the save attempt.
  after_initialize :initialize_parameters
  after_initialize :transform_parameters
  before_save :normalize_parameters
  after_commit :log_changes_to_rule_config
  after_save :initialize_parameters
  after_destroy :initialize_parameters

  # These values are used for provider-backed rules
  sig { params(provider: RuleEngine::RuleProvider).returns(RuleEngine::RuleProvider) }
  attr_writer :provider
  sig { returns(T.nilable(Integer)) }
  attr_accessor :provider_backing_id

  sig { returns(T.nilable(T::Array[RuleEngine::RuleEvent::EventAction])) }
  attr_accessor :matching_event_actions
  attr_accessor :matching_ref_names
  attr_accessor :provider_source

  AUDITABLE_FIELDS = %i[rule_type parameters].freeze

  sig do
    params(
      provider: RuleEngine::RuleProvider,
      source: T.any(ProtectedBranch, RuleEngine::Types::RuleSource),
      rule_type: String,
      matching_ref_names: T::Array[String],
      parameters: T::Hash[String, T.untyped],
      lazy_parameters: T::Hash[String, T.proc.returns(T.untyped)],
      provider_id: T.nilable(Integer)
    ).returns(RepositoryRuleConfiguration)
  end
  def self.create_provider_rule(provider:, source:, rule_type:, matching_ref_names:, parameters: {}, lazy_parameters: {}, provider_id: nil)
    config = RepositoryRuleConfiguration.new(
      provider_source: source,
      rule_type: rule_type,
      parameters: parameters,
      lazy_parameters: lazy_parameters.map { |k, v| [k.to_s, v] }.to_h,
      provider_backing_id: provider_id
    )
    config.provider = provider
    config.matching_ref_names = matching_ref_names

    config
  end

  sig { returns(RuleEngine::RuleProvider) }
  def provider
    return @provider if @provider

    repository_ruleset&.rule_provider || T.must(RuleEngine::Evaluator::RULE_PROVIDERS.find { |rp| rp.identifier == "ref_ruleset" })
  end

  sig { returns(T::Boolean) }
  def ruleset_backed?
    return true if provider.nil?
    RuleEngine::RuleProviders::RulesetRuleProvider::RULESET_PROVIDERS.include?(provider_name)
  end

  sig { returns(T.nilable(String)) }
  def provider_name
    provider.identifier
  end

  sig { returns(T.nilable(Integer)) }
  def provider_id
    provider_backing_id || repository_ruleset_id
  end

  sig { returns(T.nilable(Integer)) }
  def history_id
    repository_ruleset&.latest_history_id
  end

  sig { params(ref_name: String).returns(T::Boolean) }
  def provider_rule_matches_ref?(ref_name)
    matching_ref_names&.include?(ref_name)
  end

  sig { params(action: RuleEngine::RuleEvent::EventAction).returns(T::Boolean) }
  def provider_rule_matches_action?(action)
    matching_event_actions&.include?(action) || false
  end

  sig { returns(T.nilable(RuleEngine::BaseRule)) }
  def evaluator
    return nil unless rule_type.present?
    RuleEngine::Evaluator.rule_impl_for_rule_type(rule_type)
  end

  sig { params(actor: T.nilable(RuleEngine::Types::Actor), repository: Repository).returns(T::Boolean) }
  def can_bypass?(actor, repository)
    return false unless actor
    provider.can_bypass?(self, actor, repository)
  end

  sig { params(parameter_name: String).returns(T.untyped) }
  def param(parameter_name)
    if parameters.has_key?(parameter_name)
      parameters[parameter_name]
    elsif @lazy_generated_parameters&.has_key?(parameter_name)
      @lazy_generated_parameters[parameter_name]
    elsif @lazy_parameters&.has_key?(parameter_name)
      @lazy_generated_parameters[parameter_name] = @lazy_parameters[parameter_name].call
    else
      nil
    end
  end

  sig { params(parameter_name: String).returns(T::Boolean) }
  def has_param(parameter_name)
    parameters.has_key?(parameter_name) ||
      @lazy_generated_parameters&.has_key?(parameter_name) ||
      @lazy_parameters&.has_key?(parameter_name) ||
      false
  end

  attr_reader :lazy_parameters

  def lazy_parameters=(lazy_parameters)
    @lazy_parameters = (lazy_parameters || {}).map { |k, v| [k.to_s, v] }.to_h
    @lazy_generated_parameters = {}
  end

  def visible_parameters
    ruleset_source = repository_ruleset&.source
    return {} unless ruleset_source

    rule_impl = evaluator
    return {} unless rule_impl

    parameter_schema = rule_impl.parameter_schema_for_source(ruleset_source)

    visible_parameters_for_schema(parameters, parameter_schema.fields)
  end

  def visible_parameters_for_schema(parameters, schema_fields)
    visible_params = {}

    schema_fields.each do |field|
      key = field.name
      next unless parameters.key?(key)

      if field.respond_to?(:content_object) && !field.content_object.nil? && parameters[key].is_a?(Enumerable)
        visible_params[key] = parameters[key].map do |child_params|
          child_fields = field.content_object.fields
          visible_parameters_for_schema(child_params, child_fields)
        end
      else
        visible_params[key] = parameters[key]
      end
    end

    visible_params
  end

  def platform_type_name
    "RepositoryRule"
  end

  def event_payload
    {
      id: id,
      type: rule_type,
      parameters: parameters
    }
  end

  def changes_payload(save: true)
    {}.tap do |changes|
      AUDITABLE_FIELDS.each do |field|
        if save
          changes["old_#{field}".to_sym] = attribute_before_last_save(field) if saved_change_to_attribute?(field)
        else
          changes["old_#{field}".to_sym] = attribute_change_to_be_saved(field) if will_save_change_to_attribute?(field)
        end
      end
    end
  end

  sig { returns(T::Boolean) }
  def enabled?
    return true unless ruleset_backed?

    repository_ruleset&.enabled? || false
  end

  sig { returns(T::Boolean) }
  def evaluate_mode?
    repository_ruleset&.evaluate? || false
  end

  def source
    provider_source || repository_ruleset&.source
  end

  def ruleset_ui_metadata
    evaluator&.ruleset_ui_metadata(self)
  end

  def parameter_errors
    impl = evaluator
    return [] unless impl

    # TODO: repository_ruleset should be non-nil but the database currently allows it to be nil
    root = {
      "ruleset_id": repository_ruleset_id,
      "ruleset_source": T.must(repository_ruleset).source,
      "ruleset_target": T.must(repository_ruleset).target,
      "ruleset_ref_targets": T.must(repository_ruleset).conditions.to_ary.find { |c| c.target == "ref_name" }&.parameters&.dig("include"),
    }.with_indifferent_access.freeze

    impl.validate_parameterized(self, root: root)
  end

  private

  def transform_parameters
    return unless parameters
    return unless (schema = evaluator&.parameter_schema)

    evaluator&.transform_parameters!(parameters)

    # Apply defaults for the source for fields that opt-in to setting defaults on load
    schema.apply_defaults_for_source(nil, parameters, on_load: true)
  end

  # These internal parameters got added to some rule_configurations
  # Now that they are removed, we shouldn't fail validation if they exist
  # TODO: Remove this once all rule_configs in the DB no longer have these parameters
  def remove_pb_parameters
    parameters.delete("admin_override")
    parameters.delete("apply_on_create")
  end

  def ensure_valid_configuration
    unless ruleset_backed?
      errors.add(:base, "This rule cannot be saved")
      return
    end

    impl = evaluator
    if impl.nil?
      errors.add(:rule_type, "does not have a registered rule implementation.")
    elsif !impl.is_feature_enabled?(repository_ruleset&.source) || !impl.is_user_configurable?(repository_ruleset&.source)
      errors.add(:rule_type, "is not supported by this ruleset.")
    elsif !impl.is_supported_by_source_type?(repository_ruleset&.source)
      errors.add(:source, "is invalid for this rule type.")
    elsif !impl.is_supported_by_target?(repository_ruleset&.target)
      errors.add(:rule_type, "#{rule_type} is not supported on rulesets that target #{repository_ruleset&.target&.pluralize}.")
    elsif !impl.is_supported_by_plan?(repository_ruleset&.source, allow_upsell: true)
      errors.add(:rule_type, "#{rule_type} is not supported on this plan. Please upgrade to enable this rule type.")
    else
      param_errors = parameter_errors
      if param_errors.any?
        errors.add(:parameters, "is invalid for this rule type: #{param_errors.map { |e| e[:message] }.join(', ')}")
      end
    end
  end

  def initialize_parameters
    self.parameters = {} if self.parameters.nil?
  end

  def normalize_parameters
    self.parameters = nil if self.parameters.nil? || self.parameters.empty?
  end

  def log_changes_to_rule_config
    if transaction_include_any_action?([:create])
      action = "create"
    elsif transaction_include_any_action?([:update])
      action = "update"
    elsif transaction_include_any_action?([:destroy])
      action = "destroy"
    else
      action = "unknown"
    end

    GitHub.dogstats.increment(
      "repository_rule_configuration_changed",
      tags: ["rule_type:#{self.rule_type}", "enforcement:#{self.repository_ruleset&.enforcement}", "action:#{action}"]
    )
  end

  def retain_workflow_rule_allow_invalid_path
    return unless rule_type == "workflows"
    return unless parameters_was

    # keep track of the paths that allow_invalid_path
    allowed_invalid_paths = {}
    parameters_was["workflows"].each do |wf|
      allowed_invalid_paths[wf["path"]] = true if wf["allow_invalid_path"]
    end

    # retain the allow_invalid_path property if the path hasn't changed
    self.parameters["workflows"].each do |wf|
      if allowed_invalid_paths[wf["path"]]
        wf["allow_invalid_path"] = true
      else
        wf.delete("allow_invalid_path")
      end
    end
  end
end
