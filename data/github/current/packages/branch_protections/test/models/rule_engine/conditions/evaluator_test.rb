# typed: true
# frozen_string_literal: true

require "test_helper"

class RuleEngineConditionEvaluatorTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)

    @org = create(:business_plus_organization, admin: @user)
    @org_repo = create(:repository, owner: @org)
    @org_repo_2 = create(:repository, owner: @org)
  end

  test "batches targetables" do
    targetables = [@org_repo, @org_repo_2].map { |repo| RuleEngine::Conditions::Targets::Repository.new(repository: repo) }

    assert_same_elements targetables, RuleEngine::Conditions::Evaluator.evaluate(targetables, {
      "organization_id" => {
        "organization_ids" => [@org.global_relay_id]
      },
      "repository_name" => {
        "include" => ["~ALL"],
        "exclude" => []
      }
    })

    assert_dogstats_distribution(1, "repository_rules_engine.condition_evaluation.duration", tags: ["target:organization_id", "target_object:organization"])
    assert_dogstats_distribution(2, "repository_rules_engine.condition_evaluation.duration", tags: ["target:repository_name", "target_object:repository"])
  end

  test "does not batch refs with the same name from different repos" do
    # The ref_name target depends on the repository (for default branch)
    # Therefore, it cannot be batched even if the ref_name is the same
    targetables = [
      RuleEngine::Conditions::Targets::Ref.new(repository: @org_repo, ref_name: "refs/heads/main"),
      RuleEngine::Conditions::Targets::Ref.new(repository: @org_repo_2, ref_name: "refs/heads/main"),
    ]

    assert_same_elements targetables, RuleEngine::Conditions::Evaluator.evaluate(targetables, {
      "repository_name" => {
        "include" => ["~ALL"],
        "exclude" => []
      },
      "ref_name" => {
        "include" => ["refs/heads/main"],
        "exclude" => []
      }
    })

    assert_dogstats_distribution(2, "repository_rules_engine.condition_evaluation.duration", tags: ["target:repository_name", "target_object:repository"])
    assert_dogstats_distribution(2, "repository_rules_engine.condition_evaluation.duration", tags: ["target:ref_name", "target_object:ref"])
  end

end
