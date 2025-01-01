# typed: true
# frozen_string_literal: true

require "test_helper"

class RequiredDeploymentTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @org = create(:organization, admin: @owner)

    @repo = create(:repository, owner: @owner, from_example: :simple)

    @org_repo = create(:repository, owner: @org, from_example: :simple)

    @repo.deployments.create!(sha: @repo.default_branch_ref.target_oid, environment: "production", creator: @repo.user)
    @org_repo.deployments.create!(sha: @org_repo.default_branch_ref.target_oid, environment: "production", creator: @org_repo.user)

    branch_attributes = {
      name: "master",
      creator: @owner,
      required_deployments_enforcement_level: :non_admins,
    }
    @protected_branch = @repo.protected_branches.create(branch_attributes)
    @org_protected_branch = @org_repo.protected_branches.create(branch_attributes)
  end

  test "instruments create on a repo owned by a user" do
    events = subscribe "required_deployment.create"
    @protected_branch.replace_required_deployment_environments("production")
    required_deployments = @protected_branch.required_deployments

    expected_payload = {
      protected_branch_id: @protected_branch.id,
      protected_branch_name: @protected_branch.name,
      environment: "production",
      required_deployment_id: required_deployments.first.id,
      repo: @repo.nwo,
      repo_id: @repo.id,
      public_repo: @repo.public?,
    }

    assert event = events.pop, "expected event"
    assert_equal expected_payload, event.payload
  end

  test "instruments create on a repo owned by an org" do
    events = subscribe "required_deployment.create"
    @org_protected_branch.replace_required_deployment_environments("production")
    required_deployments = @org_protected_branch.required_deployments

    expected_payload = {
      protected_branch_id: @org_protected_branch.id,
      protected_branch_name: @org_protected_branch.name,
      required_deployment_id: required_deployments.first.id,
      environment: "production",
      repo: @org_repo.nwo,
      repo_id: @org_repo.id,
      public_repo: @org_repo.public?,
      org: @org.name,
      org_id: @org.id,
    }

    assert event = events.pop, "expected event"
    assert_equal expected_payload, event.payload
  end

  test "instruments destroy on a repo owned by a user" do
    events = subscribe "required_deployment.destroy"
    @protected_branch.replace_required_deployment_environments(["production"])
    required_deployments = @protected_branch.required_deployments

    required_deployments.first.destroy

    expected_payload = {
      protected_branch_id: @protected_branch.id,
      protected_branch_name: @protected_branch.name,
      environment: "production",
      required_deployment_id: required_deployments.first.id,
      repo: @repo.nwo,
      repo_id: @repo.id,
      public_repo: @repo.public?,
    }

    assert event = events.pop, "expected event"
    assert_equal expected_payload, event.payload
  end

  test "instruments destroy on a repo owned by an org" do
    events = subscribe "required_deployment.destroy"
    @org_protected_branch.replace_required_deployment_environments(["production"])
    required_deployments = @org_protected_branch.required_deployments

    required_deployments.first.destroy

    expected_payload = {
      protected_branch_id: @org_protected_branch.id,
      protected_branch_name: @org_protected_branch.name,
      environment: "production",
      required_deployment_id: required_deployments.first.id,
      repo: @org_repo.nwo,
      repo_id: @org_repo.id,
      public_repo: @org_repo.public?,
      org: @org.name,
      org_id: @org.id,
    }

    assert event = events.pop, "expected event"
    assert_equal expected_payload, event.payload
  end
end

class RuleEngineRequiredDeploymentValidationTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
    @ruleset = create :repository_ruleset, source: @repo
  end

  setup do
    @root = {
      "ruleset_id": @ruleset.id,
      "ruleset_source": @ruleset.source,
      "ruleset_target": @ruleset.target,
    }.with_indifferent_access.freeze
    @rule = RuleEngine::Rules::RequiredDeploymentsRule.new
  end

  context "#Custom parameter validation tests" do
    test "succeed on valid deployment environments input parameters" do
      env = create :environment, repository: @repo, name: "test"

      valid_environments = ["test"]
      valid_environment_rule_config = create_rule_config(true, environments: valid_environments)
      # no environments returned means all environment names are still valid to require for deployment
      refute @rule.validate_parameterized(valid_environment_rule_config, root: @root).any?
    end

    test "fail on invalid deployment environments input parameters" do
      env = create :environment, repository: @repo, name: "test"

      invalid_environments = ["best"]
      invalid_environment_rule_config = create_rule_config(true, environments: invalid_environments)

      # if any environment is returned, that is an invalid environment that got passed in
      assert @rule.validate_parameterized(invalid_environment_rule_config, root: @root).any?
    end
  end

  private

  def create_rule_config(admin_override, environments: ["test"], apply_on_create: true)
    @rule_config = build(
      :repository_rule_configuration,
      rule_type: "required_deployment",
      parameters: {
        required_deployment_environments: environments
      }
    )
  end
end
