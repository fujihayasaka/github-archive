# typed: strict
# frozen_string_literal: true

class RepositoryRuleState < RuleEngine::RuleState
  include GitHub::Memoizer

  sig { params(repository_model: RuleEngine::Events::RepositoryOperationEvent::RepositoryModel).returns(RepositoryRuleState) }
  def self.for_repository(repository_model)
    targetable = if repository_model.is_a?(Repositories::IRepository)
      RuleEngine::Conditions::Targets::Repository.new(repository: repository_model)
    else
      repository_model
    end
    new(targetable)
  end

  # Helper to find rules that apply to all repositories in an organization
  sig { params(organization: Organization).returns(RepositoryRuleState) }
  def self.for_organization(organization)
    targetable = RuleEngine::Events::RepositoryOperationEvent::RepositoryAttributes.new(
      name: "",
      custom_properties_effective_values_proc: -> { {} },
      system_properties_effective_values_proc: -> { {} },
      owner: organization,
    )
    new(targetable)
  end

  include RuleEngine::Rules::RepositoryVisibilityRule::StatusMethods
  include RuleEngine::Rules::RepositoryNameRestrictionRule::StatusMethods

  private

  sig { returns(Regex::RE2Helper) }
  memoize def regex_validator
    Regex::RE2Helper.new
  end
end
