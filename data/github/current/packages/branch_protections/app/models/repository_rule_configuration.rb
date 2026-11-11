# typed: true
# frozen_string_literal: true

# Class containing instructions to the policy engine on how to evaluate a policy
class RepositoryRuleConfiguration < ApplicationRecord::Repositories
  include RuleEngine::IRuleConfig

  sig { returns(RuleEngine::RulesetImplementationPayload) }
  def self.impl_payload
    RepositoryRuleset.impl_payload
  end
  include RuleEngine::RuleConfigurationBase

  # TODO: Temporary until we update the other references
  alias_attribute :policy_type, :rule_type

  before_validation :retain_workflow_rule_allow_invalid_path
  before_validation :remove_pb_parameters

  validates :rule_type, presence: true, length: { maximum: 100 }, uniqueness: { scope: [:repository_ruleset],
    message: ->(object, _data) {
      "'#{object.rule_type}' is already used for this ruleset. Only one instance of this type is allowed per ruleset."
    }
  }

  after_commit :log_changes_to_rule_config

  sig { override.returns(T.nilable(RuleEngine::RulesetBase)) }
  def ruleset
    repository_ruleset
  end

  sig { override.returns(T.nilable(Integer)) }
  def ruleset_id
    repository_ruleset_id
  end

  def platform_type_name
    "RepositoryRule"
  end

  sig { override.returns(RuleEngine::DomainAccessorBase[T.untyped]) }
  def domain
    Repositories.domain.rulesets
  end

  private

  # These internal parameters got added to some rule_configurations
  # Now that they are removed, we shouldn't fail validation if they exist
  # TODO: Remove this once all rule_configs in the DB no longer have these parameters
  def remove_pb_parameters
    parameters.delete("admin_override")
    parameters.delete("apply_on_create")
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
