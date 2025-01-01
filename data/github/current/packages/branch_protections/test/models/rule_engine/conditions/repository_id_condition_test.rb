# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryIdConditionTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)

    @org = create(:business_plus_organization, admin: @user)
    @org_repo = create(:repository, owner: @org)
    @org_repo_2 = create(:repository, owner: @org)
  end

  def attributes_from_repo(repo)
    {
      RuleEngine::Conditions::Targetable::Attribute::Repository => repo,
    }
  end

  test "evaluates to true for matching repo" do
    target = RuleEngine::Conditions::RepositoryIdTarget.new

    result = target.run_condition(attributes_from_repo(@org_repo), {
      "repository_ids" => [@org_repo.global_relay_id]
    })

    assert result
  end

  test "evaluates to false for non-matching repo" do
    target = RuleEngine::Conditions::RepositoryIdTarget.new

    result = target.run_condition(attributes_from_repo(@org_repo_2), {
      "repository_ids" => [@org_repo.global_relay_id]
    })

    refute result
  end

  test "validation succeeds wehen repo is in org" do
    target = RuleEngine::Conditions::RepositoryIdTarget.new

    ruleset = create(:repository_ruleset, source: @org)
    condition = RepositoryRuleCondition.new(target: "repository_id", repository_ruleset: ruleset, parameters: {
      repository_ids: [@org_repo.global_relay_id]
    })
    root = {
      "ruleset_id": ruleset.id,
      "ruleset_source": ruleset.source,
      "ruleset_target": ruleset.target,
    }.with_indifferent_access.freeze

    errors = target.validate_parameterized(condition, root: root)

    assert_equal 0, errors.size
  end

  test "validation fails wehen repo is not in org" do
    target = RuleEngine::Conditions::RepositoryIdTarget.new

    ruleset = create(:repository_ruleset, source: @org)
    condition = RepositoryRuleCondition.new(target: "repository_id", repository_ruleset: ruleset, parameters: {
      repository_ids: [@repo.global_relay_id]
    })
    root = {
      "ruleset_id": ruleset.id,
      "ruleset_source": ruleset.source,
      "ruleset_target": ruleset.target,
    }.with_indifferent_access.freeze

    errors = target.validate_parameterized(condition, root: root)

    assert_equal 1, errors.size
  end

end
