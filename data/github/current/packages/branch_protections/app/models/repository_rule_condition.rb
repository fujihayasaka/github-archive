# typed: true
# frozen_string_literal: true

class RepositoryRuleCondition < ApplicationRecord::Repositories
  include RuleEngine::Timing

  belongs_to :repository_ruleset, class_name: "RepositoryRuleset"
  validates :repository_ruleset, presence: true

  before_validation :transform_parameters

  validates :target, uniqueness: { scope: [:repository_ruleset],
    message: ->(object, _data) {
      "'#{object.target}' is already used for this ruleset. Only one instance of this target is allowed per ruleset."
    }
  }

  enum :target, { ref_name: 0, repository_name: 1, repository_id: 2, repository_property: 3, organization_name: 4, organization_id: 5, organization_property: 6 }

  validate :ensure_valid_configuration

  AUDITABLE_FIELDS = %i[target parameters].freeze

  after_initialize :init
  after_initialize :transform_parameters

  sig do
    params(
      condition: RepositoryRuleCondition,
      source: RuleEngine::Types::RuleSource
    ).returns(T::Boolean)
  end
  def self.supports_source?(condition, source)
    !!condition.target_evaluator&.supported_sources&.include?(source.class.name&.downcase&.to_sym)
  end

  sig do
    params(
      condition: RepositoryRuleCondition,
      target: String
    ).returns(T::Boolean)
  end
  def self.supports_ruleset_target?(condition, target)
    !!condition.target_evaluator&.supported_ruleset_targets&.include?(target.to_sym)
  end

  def init
    self.condition_type = "fnmatch" # deprecated. We should delete the column
  end

  sig { returns(T.nilable(RuleEngine::Conditions::ConditionTarget::TargetObject)) }
  def target_object
    target_evaluator&.target_object
  end

  sig { returns(T.nilable(RuleEngine::Conditions::ConditionTarget)) }
  def target_evaluator
    RuleEngine::Conditions::Evaluator::TARGET_TYPES[target]
  end

  sig { returns(T::Boolean) }
  def supports_source?
    self.class.supports_source?(self, T.must(repository_ruleset).source)
  end

  sig { returns(T::Boolean) }
  def supports_ruleset_target?
    self.class.supports_ruleset_target?(self, T.must(repository_ruleset).target)
  end

  def parameter_errors
    # TODO: repository_ruleset should be non-nil but the database currently allows it to be nil
    root = {
      "ruleset_id": repository_ruleset_id,
      "ruleset_source": T.must(repository_ruleset).source,
      "ruleset_target": T.must(repository_ruleset).target,
    }.with_indifferent_access.freeze

    target_evaluator&.validate_parameterized(self, root: root)
  end

  def event_payload
    {
      id: id,
      target: target,
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

  private

  def transform_parameters
    return unless parameters
    return unless (schema = target_evaluator&.parameter_schema)

    target_evaluator&.transform_parameters!(parameters)

    # Apply defaults for the source for fields that opt-in to setting defaults on load
    schema.apply_defaults_for_source(nil, parameters, on_load: true)
  end

  def ensure_valid_configuration
    impl = target_evaluator
    if impl.nil? || repository_ruleset&.source_type.nil?
      errors.add(:target, "is not supported")
    elsif !supports_source?
      errors.add(:target, "#{target} is not supported for #{repository_ruleset&.display_source_type} rulesets")
    elsif !supports_ruleset_target?
      errors.add(:target, "#{target} is not supported for #{repository_ruleset&.target} rulesets")
    elsif parameter_errors.any?
      errors.add(:parameters, "are invalid for this target: #{parameter_errors.map { |e| e[:message] }.join(', ')}")
    end
  end
end
