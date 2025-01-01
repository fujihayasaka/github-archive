# typed: true
# frozen_string_literal: true

require "test_helper"

# TODO: These test should rely on a "fake" configuration class once the registry is added.
class RepositoryRuleConfigurationTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @user = create(:user)
    @org = create(:organization, admin: @user)
    @owner = create(:user, plan: "business_plus")
    @repo = create(:repository, owner: @owner, from_example: :simple)

    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  test "validates policy type" do
    ruleset = create(:repository_ruleset, source: @repo)
    rule_config = build(:repository_rule_configuration, rule_type: "invalid", repository_ruleset: ruleset)

    refute rule_config.save
    assert rule_config.errors[:rule_type]
    assert_equal "does not have a registered rule implementation.", rule_config.errors[:rule_type].first
  end

  test "validates unique policy type scoped to the ruleset" do
    ruleset = create(:repository_ruleset, source: @repo)
    rule_config = build(
      :repository_rule_configuration,
      repository_ruleset: ruleset,
      rule_type: "commit_message_pattern",
      parameters: {
        operator: "starts_with",
        pattern: "\\d+"
      }
    )

    assert rule_config.save

    # Can add different metadata rule
    rule_config = build(
      :repository_rule_configuration,
      repository_ruleset: ruleset,
      rule_type: "commit_author_email_pattern",
      parameters: {
        operator: "ends_with",
        pattern: "@github.com"
      }
    )

    assert rule_config.save

    # Cannot add same metadata rule type
    rule_config = build(
      :repository_rule_configuration,
      repository_ruleset: ruleset,
      rule_type: "commit_message_pattern",
      parameters: {
        operator: "starts_with",
        pattern: "\\d+"
      }
    )
    refute rule_config.save
    assert rule_config.errors[:rule_type]
    assert_equal "'commit_message_pattern' is already used for this ruleset. Only one instance of this type is allowed per ruleset.", rule_config.errors[:rule_type].first
  end

  test "validates parameters" do
    ruleset = create(:repository_ruleset, source: @repo)
    rule_config = build(
      :repository_rule_configuration,
      repository_ruleset: ruleset,
      rule_type: "commit_author_email_pattern",
      parameters: {
        "pattern": "@github.com"
      }
    )

    refute rule_config.save
    assert rule_config.errors[:parameters]
    assert_equal "is invalid for this rule type: Missing required parameter `operator`", rule_config.errors[:parameters].first
  end

  test "validates complex parameter schema" do
    ruleset = create(:repository_ruleset, source: @repo)
    rule_config = build(
      :repository_rule_configuration,
      repository_ruleset: ruleset,
      rule_type: "required_status_checks",
      parameters: {}
    )

    refute rule_config.save
    assert rule_config.errors[:parameters]
    assert_equal "is invalid for this rule type: Missing required parameter `strict_required_status_checks_policy`, Missing required parameter `required_status_checks`",
      rule_config.errors[:parameters].first
  end

  test "validates complex paramter schema with incorrect nested objects" do
    ruleset = create(:repository_ruleset, source: @repo)
    rule_config = build(
      :repository_rule_configuration,
      repository_ruleset: ruleset,
      rule_type: "required_status_checks",
      parameters: {
        strict_required_status_checks_policy: true,
        required_status_checks: [
          {
            invalid: "format"
          }
        ]
      }
    )

    refute rule_config.save
    assert rule_config.errors[:parameters]
    assert_equal "is invalid for this rule type: Invalid parameter required_status_checks: Invalid array contents. Errors at index 0: Missing required parameter `context`, Unexpected parameter `invalid`",
      rule_config.errors[:parameters].first
  end

  test "validates complex parameter schema with some incorrect nested objects in array" do
    ruleset = create(:repository_ruleset, source: @repo)
    rule_config = build(
      :repository_rule_configuration,
      repository_ruleset: ruleset,
      rule_type: "required_status_checks",
      parameters: {
        strict_required_status_checks_policy: true,
        required_status_checks: [
          {
            context: "valid"
          },
          {
            invalid: "format"
          }
        ]
      }
    )

    refute rule_config.save
    assert rule_config.errors[:parameters]
    assert_equal "is invalid for this rule type: Invalid parameter required_status_checks: Invalid array contents. Errors at index 1: Missing required parameter `context`, Unexpected parameter `invalid`",
      rule_config.errors[:parameters].first
  end

  test "validates complex parameter schema with correct nested objects" do
    ruleset = create(:repository_ruleset, source: @repo)
    rule_config = build(
      :repository_rule_configuration,
      repository_ruleset: ruleset,
      rule_type: "required_status_checks",
      parameters: {
        strict_required_status_checks_policy: true,
        required_status_checks: [
          {
            context: "valid"
          }
        ]
      }
    )

    assert rule_config.save
  end

  test "validates supported target type" do
    ruleset = create(:repository_ruleset, target: :branch, source: @repo)
    rule_config = build(
      :repository_rule_configuration,
      repository_ruleset: ruleset,
      rule_type: "tag_name_pattern",
      parameters: {
        pattern: "^v[0-9]\\.[0-9]$",
        operator: "regex",
        negate: false
      }
    )

    refute rule_config.save
    assert rule_config.errors[:rule_type]
    assert_equal "tag_name_pattern is not supported on rulesets that target branches.", rule_config.errors[:rule_type].first
  end

  context "#changes_payload" do
    test "should be empty if no changes were saved" do
      ruleset = create(:repository_ruleset, source: @repo)
      rule_config = create(:repository_rule_configuration, repository_ruleset: ruleset)

      rule_config.reload
      assert_empty rule_config.changes_payload
    end

    test "should be empty if no changes were saved when save is false" do
      ruleset = create(:repository_ruleset, source: @repo)
      rule_config = create(:repository_rule_configuration, repository_ruleset: ruleset)

      rule_config.reload
      assert_equal [nil, {}], rule_config.changes_payload(save: false)[:old_parameters]
    end

    test "parameters should be tracked with the old value" do
      ruleset = create(:repository_ruleset, source: @repo)
      rule_config = create(:repository_rule_configuration, :metadata_pattern, repository_ruleset: ruleset)

      rule_config.parameters = { operator: "ends_with", negate: true, pattern: "@github.com" }
      rule_config.save!

      refute_empty rule_config.changes_payload
      refute_nil rule_config.changes_payload[:old_parameters]
      assert_equal "ends_with", rule_config.changes_payload[:old_parameters]["operator"]
      assert_nil rule_config.changes_payload[:old_parameters]["negate"]
      assert_equal "@github.com", rule_config.changes_payload[:old_parameters]["pattern"]
    end

    test "parameters should be tracked with the old value when save is false" do
      ruleset = create(:repository_ruleset, source: @repo)
      rule_config = create(:repository_rule_configuration, :metadata_pattern, repository_ruleset: ruleset)

      rule_config.parameters = { operator: "ends_with", negate: true, pattern: "@github.com" }

      assert_equal  [{ "operator" => "ends_with", "pattern" => "@github.com" },
                      { "operator" => "ends_with", "negate" => true, "pattern" => "@github.com" }],
                   rule_config.changes_payload(save: false)[:old_parameters]
    end

    test "rule_type should be tracked with the old value" do
      ruleset = create(:repository_ruleset, source: @repo)
      rule_config = create(:repository_rule_configuration, repository_ruleset: ruleset)

      rule_config.rule_type = "deletion"
      rule_config.save!

      refute_empty rule_config.changes_payload
      refute_nil rule_config.changes_payload[:old_rule_type]
      assert_equal "creation", rule_config.changes_payload[:old_rule_type]
    end

    test "rule_type should be tracked with the old value when save is false" do
      ruleset = create(:repository_ruleset, source: @repo)
      rule_config = create(:repository_rule_configuration, repository_ruleset: ruleset)

      rule_config.rule_type = "deletion"

      assert_equal %w[creation deletion], rule_config.changes_payload(save: false)[:old_rule_type]
    end
  end

  test "logs information about rule when config is created, updated, or destroyed" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    repo = create(:repository, owner: @org)
    ruleset = create(:repository_ruleset, source: @org)
    ruleset_workflow_path = ".github/workflows/ruleset-workflow.yaml"
    ruleset_workflow_ref = repo.heads.read(repo.default_branch)
    ruleset_workflow_ref.append_commit({ message: "add workflow", committer: @user }, @user) do |files|
      files.add(ruleset_workflow_path, "some content")
    end
    ruleset_workflow_path_2 = ".github/workflows/ruleset-workflow-2.yaml"
    ruleset_workflow_ref.append_commit({ message: "add workflow", committer: @user }, @user) do |files|
      files.add(ruleset_workflow_path_2, "some content")
    end

    rule_config = build(
      :repository_rule_configuration,
      repository_ruleset: ruleset,
      rule_type: "workflows",
      parameters: {
        "workflows": [{ "ref": repo.default_branch, "path": ruleset_workflow_path, "repository_id": repo.id }]
      }
    )

    rule_config.save!
    rule_config.update(parameters: {
      "workflows": [{ "ref": repo.default_branch, "path": ruleset_workflow_path_2, "repository_id": repo.id }]
    })

    rule_config.destroy

    assert_equal 3, GitHub.dogstats.increments("repository_rule_configuration_changed").length
    assert_includes GitHub.dogstats.increments("repository_rule_configuration_changed").first.tags, "enforcement:enabled"
    assert_includes GitHub.dogstats.increments("repository_rule_configuration_changed").first.tags, "action:create"
    assert_includes GitHub.dogstats.increments("repository_rule_configuration_changed").first.tags, "rule_type:workflows"
    assert_includes GitHub.dogstats.increments("repository_rule_configuration_changed")[1].tags, "enforcement:enabled"
    assert_includes GitHub.dogstats.increments("repository_rule_configuration_changed")[1].tags, "action:update"
    assert_includes GitHub.dogstats.increments("repository_rule_configuration_changed")[1].tags, "rule_type:workflows"
    assert_includes GitHub.dogstats.increments("repository_rule_configuration_changed").last.tags, "enforcement:enabled"
    assert_includes GitHub.dogstats.increments("repository_rule_configuration_changed").last.tags, "rule_type:workflows"
    assert_includes GitHub.dogstats.increments("repository_rule_configuration_changed").last.tags, "action:destroy"
  end

  test "#transform_parameters" do
    parameters = { "foo" => "bar ", "baz" => "boogle " }

    RepositoryRuleConfiguration.any_instance.stubs(:evaluator).returns(TestRefRule.new)

    # Transformation applies on initialization
    rc = RepositoryRuleConfiguration.new(rule_type: "test_ref_rule", parameters:)

    # This param is not transformed
    assert_equal "bar ", rc.parameters["foo"]
    # this param is transformed
    assert_equal "boogle", rc.parameters["baz"]
  end

  test "applies default on load for parameters with apply_default_on_load" do
    RepositoryRuleConfiguration.any_instance.stubs(:evaluator).returns(TestRefRule.new)

    # Applying defaults on load occurs at initialization
    rc = RepositoryRuleConfiguration.new(rule_type: "test_ref_rule", parameters: {})

    assert_equal({ "baz" => "bar1" }, rc.parameters)
  end

  class TestRefRule < RuleEngine::RefUpdateRule
    def initialize
      super(rule_name: "test_ref_rule", display_name: "For testing only")
    end

    def parameter_schema
      schema = RuleEngine::ParameterSchema::Object.root
      schema.add_field(RuleEngine::ParameterSchema::Field.new(name: "foo", display_name: "Foo", description: "Foo", default_value: "foo1", type: :string, required: true))
      schema.add_field(RuleEngine::ParameterSchema::Field.new(
        name: "baz",
        display_name: "Baz",
        description: "Baz",
        default_value: "bar1",
        type: :string,
        required: true,
        transform_fn: -> (value) { value.strip },
        apply_default_on_load: true,
      ))
      schema
    end
  end
end
