# typed: true
# frozen_string_literal: true

# Class containing instructions to the policy engine on how to evaluate a policy
class RepositoryRuleConfiguration < ApplicationRecord::Repositories
  include RuleEngine::IRuleConfig

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

  sig { override.returns(T.nilable(T::Array[RuleEngine::RuleEvent::EventAction])) }
  attr_accessor :matching_event_actions
  sig { override.returns(T.nilable(T::Array[String])) }
  attr_accessor :matching_ref_names

  AUDITABLE_FIELDS = %i[rule_type parameters].freeze

  sig { override.returns(RuleEngine::RuleProvider) }
  def provider
    repository_ruleset&.rule_provider || T.must(RuleEngine::Evaluator::RULE_PROVIDERS.find { |rp| rp.identifier == "ref_ruleset" })
  end

  sig { override.returns(String) }
  def provider_name
    provider.identifier
  end

  sig { override.returns(T.nilable(Integer)) }
  def provider_id
    repository_ruleset_id
  end

  sig { override.returns(T.nilable(Integer)) }
  def history_id
    repository_ruleset&.latest_history_id
  end

  sig { override.params(parameter_name: String).returns(T.untyped) }
  def param(parameter_name)
    parameters[parameter_name]
  end

  sig { override.params(parameter_name: String).returns(T::Boolean) }
  def has_param(parameter_name)
    parameters.has_key?(parameter_name)
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

  sig { override.returns(T::Boolean) }
  def enabled?
    repository_ruleset&.enabled? || false
  end

  sig { override.returns(T::Boolean) }
  def evaluate_mode?
    repository_ruleset&.evaluate? || false
  end

  sig { override.returns(T.untyped) }
  def source
    repository_ruleset&.source
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

  def recognized_parameters
    return {} unless parameters
    return parameters unless (schema = evaluator&.parameter_schema)

    allowed_keys = schema.fields.map(&:name)
    parameters.select { |key, _value| allowed_keys.include?(key) }
  end

  private

  def transform_parameters
    return unless rule_type && parameters
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
