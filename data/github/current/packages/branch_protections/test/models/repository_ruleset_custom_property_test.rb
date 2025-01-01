# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryRulesetCustomPropertyTest < GitHub::TestCase
  include RepositoriesTestHelper
  include BackgroundDeletesTestHelpers

  fixtures do
    @user = create(:user)
    @repo = create(:repository, from_example: :simple)
    @fork = create(:fork_repository, forker: @user, fork_repo: @repo)

    @user2 = create(:user, plan: "medium")
    @priv_repo = create(:private_repository, owner: @user2)
    @priv_repo.add_member(@user)
    @priv_fork = create(:fork_repository, forker: @user, fork_repo: @priv_repo)

    @enterprise = create(:business)
    @org = create(:business_plus_organization, name: "org1", admin: @user, business: @enterprise)
    @org_repo = create(:private_repository, owner: @org)
    @org_public_repo = create(:repository, owner: @org)
    @org.allow_private_repository_forking(actor: @org.admin, policy: Configurable::AllowPrivateRepositoryForking::EVERYWHERE)
    @org_fork = create(:fork_repository, forker: @user, organization: @org, fork_repo: @org_repo, new_name: "org_fork")
    @another_org_fork = create(:fork_repository, forker: @user, organization: @org, fork_repo: @org_repo)
  end

  test "matches repository_property conditions" do
    definition = create :custom_property_definition, :single_select, source: @org, property_name: "test", allowed_values: %w[somevalue anotheroption thirdoption]

    ruleset = create(:repository_ruleset, :targets_default_branch, source: @org)
    create(:repository_rule_condition, target: "repository_property", parameters: {
      include: [
        { name: "test", property_values: %w[somevalue anotheroption], source: "custom" }
      ],
      exclude: []
      }, repository_ruleset: ruleset)
    ruleset.reload

    create :custom_property_value, target: @org_repo, definition: definition, value: "somevalue"

    context = RuleEngine::Conditions::Targets::Ref.new(repository: @org_repo, ref_name: "refs/heads/#{@org_repo.default_branch}")
    assert ruleset.should_evaluate?(context)

    @another_org_repo = create(:repository, owner: @org)

    context = RuleEngine::Conditions::Targets::Ref.new(repository: @another_org_repo, ref_name: "refs/heads/#{@another_org_repo.default_branch}")
    refute ruleset.should_evaluate?(context)
  end

  test "repository_property condition performs check using case insensitive property name" do
    definition = create :custom_property_definition, :string, source: @org, property_name: "version"

    ruleset = create(:repository_ruleset, :targets_default_branch, source: @org)
    create(:repository_rule_condition, target: "repository_property", parameters: {
      include: [
        { name: "version", property_values: %w[v1.0.0], source: "custom" }
      ],
      exclude: []
      }, repository_ruleset: ruleset)
    ruleset.reload

    # We need to trick validation to allow the same property name with different case
    definition.destroy!
    definition = create :custom_property_definition, :string, source: @org, property_name: "VERSION"

    create :custom_property_value, target: @org_repo, definition: definition, value: "v1.0.0"

    context = RuleEngine::Conditions::Targets::Ref.new(repository: @org_repo, ref_name: "refs/heads/#{@org_repo.default_branch}")
    assert ruleset.should_evaluate?(context)
  end

  test "matches repository_property conditions (multiple includes: AND)" do
    definition_a = create :custom_property_definition, :single_select, source: @org, property_name: "test", allowed_values: %w[somevalue anotheroption thirdoption]
    definition_b = create :custom_property_definition, :single_select, source: @org, property_name: "second", allowed_values: %w[value another nomatch]

    ruleset = create(:repository_ruleset, :targets_default_branch, source: @org)
    create(:repository_rule_condition, target: "repository_property", parameters: {
      include: [
        { name: "test", property_values: %w[somevalue anotheroption], source: "custom" },
        { name: "second", property_values: %w[another value], source: "custom" }
      ],
      exclude: []
    }, repository_ruleset: ruleset)
    ruleset.reload

    create :custom_property_value, target: @org_repo, definition: definition_a, value: "somevalue"
    create :custom_property_value, target: @org_repo, definition: definition_b, value: "another"

    context = RuleEngine::Conditions::Targets::Ref.new(repository: @org_repo, ref_name: "refs/heads/#{@org_repo.default_branch}")
    assert ruleset.should_evaluate?(context)

    @another_org_repo = create(:repository, owner: @org)
    create :custom_property_value, target: @another_org_repo, definition: definition_a, value: "somevalue"
    create :custom_property_value, target: @another_org_repo, definition: definition_b, value: "nomatch"

    context = RuleEngine::Conditions::Targets::Ref.new(repository: @another_org_repo, ref_name: "refs/heads/#{@another_org_repo.default_branch}")
    refute ruleset.should_evaluate?(context)
  end

  test "matches repository_property conditions for multiselect property" do
    definition = create :custom_property_definition, :multi_select, source: @org, allowed_values: %w[android ios firetv ipadOS, macOS]

    ruleset = create(:repository_ruleset, :targets_default_branch, source: @org)
    create(:repository_rule_condition, target: "repository_property", parameters: {
      include: [
        { name: "platform", property_values: %w[android ios], source: "custom" }
      ],
      exclude: []
    }, repository_ruleset: ruleset)
    ruleset.reload

    create :custom_property_value, target: @org_repo, definition: definition, value: "ios"
    create :custom_property_value, target: @org_repo, definition: definition, value: "web"

    context = RuleEngine::Conditions::Targets::Ref.new(repository: @org_repo, ref_name: "refs/heads/#{@org_repo.default_branch}")
    assert ruleset.should_evaluate?(context)
  end

  test "doesn't match repository_property conditions for multiselect property when no values overlap" do
    definition = create :custom_property_definition, :multi_select, source: @org, allowed_values: %w[android ios firetv ipadOS, macOS]

    ruleset = create(:repository_ruleset, :targets_default_branch, source: @org)
    create(:repository_rule_condition, target: "repository_property", parameters: {
      include: [
        { name: "platform", property_values: %w[ios macOS], source: "custom" }
      ],
      exclude: []
    }, repository_ruleset: ruleset)
    ruleset.reload

    create :custom_property_value, target: @org_repo, definition: definition, value: "android"
    create :custom_property_value, target: @org_repo, definition: definition, value: "web"

    context = RuleEngine::Conditions::Targets::Ref.new(repository: @org_repo, ref_name: "refs/heads/#{@org_repo.default_branch}")
    refute ruleset.should_evaluate?(context)
  end

  test "doesn't match repository_property conditions with exclude" do
    definition_a = create :custom_property_definition, source: @org, property_name: "test"
    definition_b = create :custom_property_definition, source: @org, property_name: "another"

    ruleset = create(:repository_ruleset, :targets_default_branch, source: @org)
    create(:repository_rule_condition, target: "repository_property", parameters: {
      include: [
        { name: "test", property_values: ["somevalue"], source: "custom" }
      ],
      exclude: [
        { name: "another", property_values: ["fail"], source: "custom" }
      ]
    }, repository_ruleset: ruleset)
    ruleset.reload

    create :custom_property_value, target: @org_repo, definition: definition_a, value: "somevalue"
    create :custom_property_value, target: @org_repo, definition: definition_b, value: "fail"

    context = RuleEngine::Conditions::Targets::Ref.new(repository: @org_repo, ref_name: "refs/heads/#{@org_repo.default_branch}")
    refute ruleset.should_evaluate?(context)
  end

  test "doesn't match repository_property conditions for new, unpersisted repositories without property injection" do
    create :custom_property_definition, :single_select, source: @org, property_name: "test", allowed_values: %w[somevalue anotheroption thirdoption]

    ruleset = create(:repository_ruleset, :targets_default_branch, source: @org)
    create(:repository_rule_condition, target: "repository_property", parameters: {
      include: [
        { name: "test", property_values: %w[somevalue anotheroption], source: "custom" }
      ],
      exclude: []
      }, repository_ruleset: ruleset)
    ruleset.reload

    repo = Repository.new(owner: @org)

    context = RuleEngine::Conditions::Targets::Ref.new(repository: repo, ref_name: "refs/heads/#{repo.default_branch}")
    refute ruleset.should_evaluate?(context)
  end

  test "supports custom property injection for new repos" do
    enable_feature_flag(:member_privilege_rulesets)

    create :custom_property_definition, :single_select, source: @org, property_name: "test", allowed_values: %w[somevalue anotheroption thirdoption]

    ruleset = create(:repository_ruleset, source: @org, target: "repository")
    create(:repository_rule_condition, target: "repository_property", parameters: {
      include: [
        { name: "test", property_values: ["anotheroption"], source: "custom" }
      ],
      exclude: []
    }, repository_ruleset: ruleset)
    ruleset.reload

    new_repo = @org.repositories.build(name: "new-repo")

    event1 = RuleEngine::Events::RepositoryOperationEvent.new(new_repo, @user, { delete: nil }, persist_results: false,
      repo_create_custom_properties: { "test" => "somevalue" })
    refute ruleset.should_evaluate?(event1.event_actions[0])

    event2 = RuleEngine::Events::RepositoryOperationEvent.new(new_repo, @user, { delete: nil }, persist_results: false,
      repo_create_custom_properties: { "test" => "anotheroption" })
    assert ruleset.should_evaluate?(event2.event_actions[0])
  end

  test "supports system property injection for new repos" do
    enable_feature_flag(:member_privilege_rulesets)

    ruleset = create(:repository_ruleset, source: @org, target: "repository")
    create(:repository_rule_condition, target: "repository_property", parameters: {
      include: [
        { name: "visibility", property_values: ["private"], source: "system" }
      ],
      exclude: []
    }, repository_ruleset: ruleset)
    ruleset.reload

    new_private_repo = @org.repositories.build(name: "new-repo", private: true)
    private_repo_event = RuleEngine::Events::RepositoryOperationEvent.new(new_private_repo, @user, { delete: nil }, persist_results: false)
    assert ruleset.should_evaluate?(private_repo_event.event_actions[0])

    new_public_repo = @org.repositories.build(name: "new-repo")
    public_repo_event = RuleEngine::Events::RepositoryOperationEvent.new(new_public_repo, @user, { delete: nil }, persist_results: false)
    refute ruleset.should_evaluate?(public_repo_event.event_actions[0])
  end

  test "use custom source when no source is provided" do
    environment_def = create :custom_property_definition, source: @org, property_name: "environment"

    ruleset = create(:repository_ruleset, :targets_default_branch, source: @org)
    create(:repository_rule_condition, target: "repository_property", parameters: {
      include: [
        { name: "environment", property_values: ["production"] }
      ],
      exclude: []
    }, repository_ruleset: ruleset)
    ruleset.reload

    create :custom_property_value, target: @org_repo, definition: environment_def, value: "production"

    context = RuleEngine::Conditions::Targets::Ref.new(repository: @org_repo, ref_name: "refs/heads/#{@org_repo.default_branch}")
    assert ruleset.should_evaluate?(context)
  end

  test "matches the system fork property condition" do
    ruleset = create(:repository_ruleset, :targets_default_branch, source: @org)
    create(:repository_rule_condition, target: "repository_property", parameters: {
      include: [
        { name: "fork", property_values: ["true"], source: "system" }
      ],
      exclude: []
    }, repository_ruleset: ruleset)
    ruleset.reload

    fork_repo_context = RuleEngine::Conditions::Targets::Ref.new(repository: @org_fork, ref_name: "refs/heads/#{@org_fork.default_branch}")
    org_repo_context = RuleEngine::Conditions::Targets::Ref.new(repository: @org_repo, ref_name: "refs/heads/#{@org_repo.default_branch}")

    assert ruleset.should_evaluate?(fork_repo_context)
    refute ruleset.should_evaluate?(org_repo_context)
  end

  test "matches the system visibility property condition" do
    ruleset = create(:repository_ruleset, :targets_default_branch, source: @org)
    create(:repository_rule_condition, target: "repository_property", parameters: {
      include: [
        { name: "visibility", property_values: ["public"], source: "system" }
      ],
      exclude: []
    }, repository_ruleset: ruleset)
    ruleset.reload

    private_repo_context = RuleEngine::Conditions::Targets::Ref.new(repository: @org_repo, ref_name: "refs/heads/#{@org_repo.default_branch}")
    public_repo_context = RuleEngine::Conditions::Targets::Ref.new(repository: @org_public_repo, ref_name: "refs/heads/#{@org_public_repo.default_branch}")

    refute ruleset.should_evaluate?(private_repo_context)
    assert ruleset.should_evaluate?(public_repo_context)
  end

  test "matches the system language property condition" do
    ruby_repo = create(:repository, owner: @org, primary_language: create(:language_name, name: "Ruby"))
    go_repo = create(:repository, owner: @org, primary_language: create(:language_name, name: "Go"))

    ruleset = create(:repository_ruleset, :targets_default_branch, source: @org)
    create(:repository_rule_condition, target: "repository_property", parameters: {
      include: [
        { name: "language", property_values: ["Ruby"], source: "system" }
      ],
      exclude: []
    }, repository_ruleset: ruleset)
    ruleset.reload

    ruby_repo_context = RuleEngine::Conditions::Targets::Ref.new(repository: ruby_repo, ref_name: "refs/heads/#{ruby_repo.default_branch}")
    go_repo_context = RuleEngine::Conditions::Targets::Ref.new(repository: go_repo, ref_name: "refs/heads/#{go_repo.default_branch}")

    assert ruleset.should_evaluate?(ruby_repo_context)
    refute ruleset.should_evaluate?(go_repo_context)
  end

  test "matches system and custom properties conditions" do
    environment_def = create :custom_property_definition, source: @org, property_name: "environment"

    ruleset = create(:repository_ruleset, :targets_default_branch, source: @org)
    create(:repository_rule_condition, target: "repository_property", parameters: {
      include: [
        { name: "fork", property_values: ["true"], source: "system" },
        { name: "environment", property_values: ["production"] },
      ],
      exclude: []
    }, repository_ruleset: ruleset)
    ruleset.reload

    create :custom_property_value, target: @org_fork, definition: environment_def, value: "production"
    fork_context = RuleEngine::Conditions::Targets::Ref.new(repository: @org_fork, ref_name: "refs/heads/#{@org_fork.default_branch}")
    assert ruleset.should_evaluate?(fork_context)

    create :custom_property_value, target: @another_org_fork, definition: environment_def, value: "testing"
    another_org_fork_context = RuleEngine::Conditions::Targets::Ref.new(repository: @another_org_fork, ref_name: "refs/heads/#{@another_org_fork.default_branch}")
    refute ruleset.should_evaluate?(another_org_fork_context)

    create :custom_property_value, target: @org_repo, definition: environment_def, value: "production"
    org_repo_context = RuleEngine::Conditions::Targets::Ref.new(repository: @org_repo, ref_name: "refs/heads/#{@org_repo.default_branch}")
    refute ruleset.should_evaluate?(org_repo_context)
  end

  test "matches system and custom properties conditions (case insensitive)" do
    environment_def = create :custom_property_definition, source: @org, property_name: "environment"

    ruleset = create(:repository_ruleset, :targets_default_branch, source: @org)
    create(:repository_rule_condition, target: "repository_property", parameters: {
      include: [
        { name: "fork", property_values: ["true"], source: "system" },
        { name: "environment", property_values: ["PRODUCTION"] },
      ],
      exclude: []
    }, repository_ruleset: ruleset)
    ruleset.reload

    create :custom_property_value, target: @org_fork, definition: environment_def, value: "production"
    fork_context = RuleEngine::Conditions::Targets::Ref.new(repository: @org_fork, ref_name: "refs/heads/#{@org_fork.default_branch}")
    assert ruleset.should_evaluate?(fork_context)

    create :custom_property_value, target: @another_org_fork, definition: environment_def, value: "testing"
    another_org_fork_context = RuleEngine::Conditions::Targets::Ref.new(repository: @another_org_fork, ref_name: "refs/heads/#{@another_org_fork.default_branch}")
    refute ruleset.should_evaluate?(another_org_fork_context)

    create :custom_property_value, target: @org_repo, definition: environment_def, value: "production"
    org_repo_context = RuleEngine::Conditions::Targets::Ref.new(repository: @org_repo, ref_name: "refs/heads/#{@org_repo.default_branch}")
    refute ruleset.should_evaluate?(org_repo_context)
  end

  test "matches a condition with system, custom and properties with no source" do
    environment_def = create :custom_property_definition, source: @org, property_name: "environment"
    language_def = create :custom_property_definition, source: @org, property_name: "language"

    ruleset = create(:repository_ruleset, :targets_default_branch, source: @org)
    create(:repository_rule_condition, target: "repository_property", parameters: {
      include: [
        { name: "fork", property_values: ["true"], source: "system" },
        { name: "language", property_values: ["ruby"], source: "custom" },
        { name: "environment", property_values: ["production"] },
      ],
      exclude: []
    }, repository_ruleset: ruleset)
    ruleset.reload

    create :custom_property_value, target: @org_fork, definition: environment_def, value: "production"
    create :custom_property_value, target: @org_fork, definition: language_def, value: "ruby"
    fork_context = RuleEngine::Conditions::Targets::Ref.new(repository: @org_fork, ref_name: "refs/heads/#{@org_fork.default_branch}")
    assert ruleset.should_evaluate?(fork_context)

    another_org_fork = create(:fork_repository, forker: @user, organization: @org, fork_repo: @org_repo)
    create :custom_property_value, target: another_org_fork, definition: environment_def, value: "testing"
    create :custom_property_value, target: another_org_fork, definition: environment_def, value: "ruby"
    another_fork_context = RuleEngine::Conditions::Targets::Ref.new(repository: another_org_fork, ref_name: "refs/heads/#{another_org_fork.default_branch}")
    refute ruleset.should_evaluate?(another_fork_context)
  end

  test "matches system and custom properties conditions with exclude" do
    environment_def = create :custom_property_definition, source: @org, property_name: "environment"

    ruleset = create(:repository_ruleset, :targets_default_branch, source: @org)
    create(:repository_rule_condition, target: "repository_property", parameters: {
      include: [
        { name: "fork", property_values: ["true"], source: "system" },
      ],
      exclude: [
        { name: "environment", property_values: ["production"], source: "custom" },
      ]
    }, repository_ruleset: ruleset)
    ruleset.reload

    create :custom_property_value, target: @org_fork, definition: environment_def, value: "production"
    fork_context = RuleEngine::Conditions::Targets::Ref.new(repository: @org_fork, ref_name: "refs/heads/#{@org_fork.default_branch}")
    refute ruleset.should_evaluate?(fork_context)

    create :custom_property_value, target: @another_org_fork, definition: environment_def, value: "testing"
    another_org_fork_context = RuleEngine::Conditions::Targets::Ref.new(repository: @another_org_fork, ref_name: "refs/heads/#{@another_org_fork.default_branch}")
    assert ruleset.should_evaluate?(another_org_fork_context)

    create :custom_property_value, target: @org_repo, definition: environment_def, value: "testing"
    org_repo_context = RuleEngine::Conditions::Targets::Ref.new(repository: @org_repo, ref_name: "refs/heads/#{@org_repo.default_branch}")
    refute ruleset.should_evaluate?(org_repo_context)
  end

  test "matches system and custom properties conditions with intrinsic property as exclude" do
    environment_def = create :custom_property_definition, source: @org, property_name: "environment"

    ruleset = create(:repository_ruleset, :targets_default_branch, source: @org)
    create(:repository_rule_condition, target: "repository_property", parameters: {
      include: [
        { name: "environment", property_values: ["production"], source: "custom" },
      ],
      exclude: [
        { name: "fork", property_values: ["true"], source: "system" },
      ]
    }, repository_ruleset: ruleset)
    ruleset.reload


    create :custom_property_value, target: @org_fork, definition: environment_def, value: "production"
    fork_context = RuleEngine::Conditions::Targets::Ref.new(repository: @org_fork, ref_name: "refs/heads/#{@org_fork.default_branch}")
    refute ruleset.should_evaluate?(fork_context)

    create :custom_property_value, target: @org_repo, definition: environment_def, value: "production"
    org_repo_context = RuleEngine::Conditions::Targets::Ref.new(repository: @org_repo, ref_name: "refs/heads/#{@org_repo.default_branch}")
    assert ruleset.should_evaluate?(org_repo_context)

    another_org_repo = create(:private_repository, owner: @org)
    create :custom_property_value, target: another_org_repo, definition: environment_def, value: "testing"
    another_org_context = RuleEngine::Conditions::Targets::Ref.new(repository: another_org_repo, ref_name: "refs/heads/#{another_org_repo.default_branch}")
    refute ruleset.should_evaluate?(another_org_context)
  end

  test "matches all other repositories when only exclusions are present when feature flag enabled" do
    disable_feature_flag(:rulesets_property_condition_include_all_with_exclude_disabled)
    enable_feature_flag(:rulesets_property_condition_include_all_with_exclude)

    definition = create :custom_property_definition, :single_select, source: @org, property_name: "test", allowed_values: %w[somevalue anotheroption thirdoption]

    ruleset = create(:repository_ruleset, :targets_default_branch, source: @org)
    create(:repository_rule_condition, target: "repository_property", parameters: {
      include: [],
      exclude: [
        { name: "test", property_values: %w[somevalue anotheroption], source: "custom" },
        { name: "visibility", property_values: ["public"], source: "system" },
        { name: "fork", property_values: ["true"], source: "system" }
      ]
    }, repository_ruleset: ruleset)
    ruleset.reload

    create :custom_property_value, target: @org_repo, definition: definition, value: "thirdoption"

    context = RuleEngine::Conditions::Targets::Ref.new(repository: @org_repo, ref_name: "refs/heads/#{@org_repo.default_branch}")
    assert ruleset.should_evaluate?(context)

    @another_org_repo = create(:repository, owner: @org)
    create :custom_property_value, target: @another_org_repo, definition: definition, value: "somevalue"

    context = RuleEngine::Conditions::Targets::Ref.new(repository: @another_org_repo, ref_name: "refs/heads/#{@another_org_repo.default_branch}")
    refute ruleset.should_evaluate?(context)
  end

  test "excludes using any match when feature flag enabled" do
    disable_feature_flag(:rulesets_property_condition_include_all_with_exclude_disabled)

    definition = create :custom_property_definition, :single_select, source: @org, property_name: "test", allowed_values: %w[somevalue anotheroption thirdoption]

    ruleset = create(:repository_ruleset, :targets_default_branch, source: @org)
    create(:repository_rule_condition, target: "repository_property", parameters: {
      include: [
        { name: "visibility", property_values: ["private"], source: "system" },
      ],
      exclude: [
        { name: "test", property_values: %w[somevalue anotheroption], source: "custom" },
        { name: "fork", property_values: ["false"], source: "system" },
      ]
    }, repository_ruleset: ruleset)
    ruleset.reload

    create :custom_property_value, target: @org_repo, definition: definition, value: "thirdoption"

    context = RuleEngine::Conditions::Targets::Ref.new(repository: @org_repo, ref_name: "refs/heads/#{@org_repo.default_branch}")

    if GitHub.flipper[:rulesets_property_condition_include_all_with_exclude].enabled?
      refute ruleset.should_evaluate?(context)
    else
      assert ruleset.should_evaluate?(context)
    end

    @another_org_repo = create(:repository, owner: @org)
    create :custom_property_value, target: @another_org_repo, definition: definition, value: "somevalue"

    context = RuleEngine::Conditions::Targets::Ref.new(repository: @another_org_repo, ref_name: "refs/heads/#{@another_org_repo.default_branch}")
    refute ruleset.should_evaluate?(context)
  end

  %w[custom system].each do |source|
    test "cannot create a rule condition with an invalid #{source} property name" do
      environment_def = create :custom_property_definition, source: @org, property_name: "environment"

      ruleset = build(:repository_ruleset, :targets_default_branch, source: @org)
      ruleset_condition = build(:repository_rule_condition,
        target: "repository_property",
        parameters: {
          include: [
            { name: "invalid_name", property_values: ["true"], source: source },
          ],
          exclude: []
      }, repository_ruleset: ruleset)

      refute ruleset_condition.save
      assert_equal ["are invalid for this target: Invalid property 'invalid_name' with source '#{source}'"], ruleset_condition.errors.map(&:message)
    end
  end

  [
    { type: :single_select, allowed_values: %w[prod test], values: %w[staging] },
    { type: :multi_select, allowed_values: %w[prod test], values: %w[staging test] },
    { type: :true_false, allowed_values: nil, values: %w[test] },
  ].each do |scenario|
    test "cannot create a rule condition with an invalid value (#{scenario[:type]})" do
      environment_def = create :custom_property_definition, scenario[:type], source: @org, property_name: "environment", allowed_values: scenario[:allowed_values]

      ruleset = build(:repository_ruleset, :targets_default_branch, source: @org)
      ruleset_condition = build(:repository_rule_condition,
        target: "repository_property",
        parameters: {
          include: [
            { name: "environment", property_values: scenario[:values], source: "custom" },
          ],
          exclude: []
      }, repository_ruleset: ruleset)

      refute ruleset_condition.save
      assert_equal ["are invalid for this target: Invalid value(s) for the custom property 'environment'"], ruleset_condition.errors.map(&:message)
    end
  end

  test "cannot create a rule condition with an invalid language property value" do
    ruleset = build(:repository_ruleset, :targets_default_branch, source: @org)
    ruleset_condition = build(:repository_rule_condition,
        target: "repository_property",
        parameters: {
          include: [
            { name: "language", property_values: %w[Ruby Spanish], source: "system" },
          ],
          exclude: []
      }, repository_ruleset: ruleset)

    refute ruleset_condition.save
    assert_equal ["are invalid for this target: Invalid value(s) for the system property 'language'"], ruleset_condition.errors.map(&:message)
  end

  test "cannot create an rule condition with an invalid source" do
    create :custom_property_definition, source: @org, property_name: "environment"

    ruleset = build(:repository_ruleset, :targets_default_branch, source: @org)
    ruleset_condition = build(:repository_rule_condition,
      target: "repository_property",
      parameters: {
        include: [
          { name: "environment", property_values: ["true"], source: "foo" },
        ],
        exclude: []
    }, repository_ruleset: ruleset)

    refute ruleset_condition.save
    assert_equal ["are invalid for this target: Invalid parameter include: Invalid array contents. Errors at index 0: Expected value to be one of custom, system, got foo"], ruleset_condition.errors.map(&:message)
  end

  test "create a custom property ruleset fails if no include condition" do
    disable_feature_flag(:rulesets_property_condition_include_all_with_exclude_disabled)

    create :custom_property_definition, source: @org, property_name: "test"

    ruleset = build(
      :repository_ruleset,
      :targets_default_branch,
      source: @org,
      conditions: [
        build(
          :repository_rule_condition,
          target: "repository_property",
          parameters: {
            include: [],
            exclude: [
              { name: "test", property_values: %w[somevalue anotheroption], source: "custom" }
            ]
          }
        )
      ]
    )

    if !GitHub.flipper[:rulesets_property_condition_include_all_with_exclude].enabled?
      refute ruleset.save
      invalid_condition = ruleset.conditions.select { |condition| !condition.valid? }
      assert_equal 1, invalid_condition.size
      assert_includes invalid_condition.first.errors.first.message, "Invalid parameter include: At least one target is required"
    else
      assert ruleset.save
    end
  end
end
