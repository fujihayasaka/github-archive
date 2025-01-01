# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryRulesetTest < GitHub::TestCase
  include RepositoriesTestHelper
  include BackgroundDeletesTestHelpers

  RULESET_LIMIT = 75

  fixtures do
    @user = create(:user)
    @repo = create(:repository, from_example: :simple)
    @fork = create(:fork_repository, forker: @user, fork_repo: @repo)

    @user2 = create(:user, plan: "medium")
    @priv_repo = create(:private_repository, owner: @user2)
    @priv_repo.add_member(@user)
    @priv_fork = create(:fork_repository, forker: @user, fork_repo: @priv_repo)

    @org = create(:business_plus_organization, name: "org1", admin: @user)
    @org_repo = create(:private_repository, owner: @org)
    @org_public_repo = create(:repository, owner: @org)
    @org_team = create(:team, organization: @org, privacy: :closed)
    @org.allow_private_repository_forking(actor: @org.admin, policy: Configurable::AllowPrivateRepositoryForking::EVERYWHERE)
    @org_fork = create(:fork_repository, forker: @user, organization: @org, fork_repo: @org_repo, new_name: "org_fork")
    @another_org_fork = create(:fork_repository, forker: @user, organization: @org, fork_repo: @org_repo)
    @user_org_fork = create(:fork_repository, forker: @user, fork_repo: @org_repo)

    @org2 = create(:business_plus_organization, name: "org2", admin: @user)
    @org2.allow_private_repository_forking(actor: @org.admin, policy: Configurable::AllowPrivateRepositoryForking::EVERYWHERE)
    @org2_fork = create(:fork_repository, forker: @user, fork_repo: @org_repo)

    GitHub.flipper[:dont_check_repos_integrations_limit].disable
    @permissions = { "metadata" => :read, "contents" => :write }
    @app = create(:integration, default_permissions: @permissions)
    make_integration_installation(integration: @app, repository: @org_repo)
    @ruleset = create(:repository_ruleset, source: @org, bypass_actors: [
      RepositoryRulesetBypassActor.new(actor_id: @app.id, actor_type: "Integration")
    ])
  end

  setup do
    # Enables the max_file_path_length rule
    GitHub.flipper[:push_rulesets].enable
  end

  test "create a ruleset" do
    ruleset = create(:repository_ruleset, :example_ruleset, source: @repo)

    ruleset.reload

    assert_equal 1, ruleset.rule_configurations.size
    assert_equal 1, ruleset.conditions.size
    assert_equal "creation", ruleset.rule_configurations.first.rule_type
    assert_equal "ref_name", ruleset.conditions.first.target
  end

  context "instrumentation - repo ruleset" do
    test "instruments create" do
      events = subscribe "repository_ruleset.create"

      ruleset = build(
        :repository_ruleset,
        name: "testing",
        source: @org_repo
      )

      RepositoryRuleset.transaction do
        ruleset.upsert_rules([{ rule_type: "max_file_path_length", parameters: { "max_file_path_length" => 255 } }])
        ruleset.upsert_conditions([{ target: "ref_name", parameters: { exclude: [], include: ["refs/heads/develop"] } }])
        ruleset.upsert_bypass_actors([{ actor_id: @org_team.id, actor_type: "Team" }])
        ruleset.save!
      end

      ruleset.reload

      refute_nil event = events.pop, "an event was expected"

      expected_payload = {
        ruleset_id: ruleset.id,
        ruleset_name: ruleset.name,
        ruleset_enforcement: "enabled",
        ruleset_source_type: "Repository",
        ruleset_rules: ruleset.rule_configurations.map(&:event_payload),
        ruleset_conditions: ruleset.conditions.map(&:event_payload),
        ruleset_bypass_actors: ruleset.bypass_actors.map(&:event_payload),
        repo: @org_repo.nwo,
        repo_id: @org_repo.id,
        public_repo: @org_repo.public?,
        org: @org.login,
        org_id: @org.id
      }

      assert_equal expected_payload, event.payload
    end

    test "instruments create - with org admin bypass" do
      events = subscribe "repository_ruleset.create"

      ruleset = build(
        :repository_ruleset,
        name: "testing",
        source: @org_repo
      )

      RepositoryRuleset.transaction do
        ruleset.bypass_mode = :org_bypass_any
        ruleset.save!
      end

      ruleset.reload

      refute_nil event = events.pop, "an event was expected"

      expected_keys = RepositoryRulesetBypassActor.new.event_payload.keys
      assert_equal expected_keys, event.payload[:ruleset_bypass_actors].first.keys
      assert_equal [{ id: nil, actor_id: RepositoryRuleset::ORG_ROLE_BYPASS_ACTOR_IDS[:org_admin], actor_type: "OrganizationAdmin", bypass_mode: "always" }], event.payload[:ruleset_bypass_actors]
    end

    test "instruments update - add org admin bypass" do
      events = subscribe "repository_ruleset.update"

      create(:repository_ruleset, :example_ruleset, name: "testing", source: @org_repo)

      ruleset = RepositoryRuleset.last

      RepositoryRuleset.transaction do
        T.must(ruleset).bypass_mode = :org_bypass_any
        T.must(ruleset).save!
      end

      refute_nil event = events.pop, "an event was expected"

      expected_org_admin = {
        id: nil,
        actor_id: RepositoryRuleset::ORG_ROLE_BYPASS_ACTOR_IDS[:org_admin],
        actor_type: "OrganizationAdmin",
        bypass_mode: "always",
      }

      expected_payload = {
        ruleset_bypass_actors_added: [expected_org_admin],
      }

      assert_equal expected_payload, event.payload.slice(:ruleset_bypass_actors_added)
      assert_nil event.payload[:ruleset_bypass_actors_updated]
      assert_nil event.payload[:ruleset_bypass_actors_deleted]
    end

    test "instruments update - update org admin bypass" do
      events = subscribe "repository_ruleset.update"

      create(
        :repository_ruleset,
        name: "testing",
        source: @org_repo,
        bypass_mode: 6
      )

      ruleset = RepositoryRuleset.last

      RepositoryRuleset.transaction do
        T.must(ruleset).bypass_mode = 5
        T.must(ruleset).save!
      end

      refute_nil event = events.pop, "an event was expected"

      expected_org_admin = {
        id: nil,
        actor_id: RepositoryRuleset::ORG_ROLE_BYPASS_ACTOR_IDS[:org_admin],
        actor_type: "OrganizationAdmin",
        bypass_mode: "pull_request",
        old_bypass_mode: "always"
      }

      expected_payload = {
        ruleset_bypass_actors_updated: [expected_org_admin],
      }

      assert_equal expected_payload, event.payload.slice(:ruleset_bypass_actors_updated)
      assert_nil event.payload[:ruleset_bypass_actors_added]
      assert_nil event.payload[:ruleset_bypass_actors_deleted]
    end

    test "instrument update - remove org admin bypass" do
      events = subscribe "repository_ruleset.update"

      create(:repository_ruleset, :example_ruleset, bypass_mode: 6, name: "testing", source: @org_repo)

      ruleset = RepositoryRuleset.last

      RepositoryRuleset.transaction do
        T.must(ruleset).bypass_mode = :no_org_bypass
        T.must(ruleset).save!
      end

      refute_nil event = events.pop, "an event was expected"

      expected_org_admin = {
        id: nil,
        actor_id: RepositoryRuleset::ORG_ROLE_BYPASS_ACTOR_IDS[:org_admin],
        actor_type: "OrganizationAdmin",
        bypass_mode: "always"
      }

      expected_payload = {
        ruleset_bypass_actors_deleted: [expected_org_admin],
      }

      assert_equal expected_payload, event.payload.slice(:ruleset_bypass_actors_deleted)
      assert_nil event.payload[:ruleset_bypass_actors_added]
      assert_nil event.payload[:ruleset_bypass_actors_updated]
    end

    test "instrument update - modify bypass actor bypass mode" do
      events = subscribe "repository_ruleset.update"

      ruleset = create(:repository_ruleset, :example_ruleset, name: "testing", source: @org_repo, bypass_actors: [
        RepositoryRulesetBypassActor.new(
          actor: @org_team,
          bypass_mode: 0
        )
      ])

      bypass_actor = ruleset.bypass_actors.first

      ruleset = RepositoryRuleset.last

      RepositoryRuleset.transaction do
        T.must(ruleset).upsert_bypass_actors([{ actor_id: bypass_actor.actor_id, actor_type: bypass_actor.actor_type, bypass_mode: 1 }])
        T.must(ruleset).save!
      end

      refute_nil event = events.pop, "an event was expected"

      expected_payload = {
        ruleset_bypass_actors_updated: [bypass_actor.reload.slice(:id, :actor_id, :actor_type).merge(bypass_mode: "pull_request", old_bypass_mode: "always").symbolize_keys]
      }

      assert_equal expected_payload, event.payload.slice(:ruleset_bypass_actors_updated)
      assert_nil event.payload[:ruleset_bypass_actors_added]
      assert_nil event.payload[:ruleset_bypass_actors_deleted]
    end

    test "instrument create - with deploy key bypass" do
      events = subscribe "repository_ruleset.create"

      ruleset = build(
        :repository_ruleset,
        name: "testing",
        source: @org_repo
      )

      RepositoryRuleset.transaction do
        ruleset.deploy_key_bypass = true
        ruleset.save!
      end

      ruleset.reload

      refute_nil event = events.pop, "an event was expected"

      expected_keys = RepositoryRulesetBypassActor.new.event_payload.keys
      assert_equal expected_keys, event.payload[:ruleset_bypass_actors].first.keys
      assert_equal [{ id: nil, actor_id: RepositoryRulesetBypassActor::DeployKey.id, actor_type: RepositoryRulesetBypassActor::DeployKey.type, bypass_mode: "always" }], event.payload[:ruleset_bypass_actors]
    end

    test "instrument update - add deploy key bypass" do
      events = subscribe "repository_ruleset.update"

      create(:repository_ruleset, :example_ruleset, name: "testing", source: @org_repo)

      ruleset = RepositoryRuleset.last

      RepositoryRuleset.transaction do
        T.must(ruleset).deploy_key_bypass = true
        T.must(ruleset).save!
      end


      expected_deploy_key_bypass = {
        id: nil,
        actor_id: RepositoryRulesetBypassActor::DeployKey.id,
        actor_type: RepositoryRulesetBypassActor::DeployKey.type,
        bypass_mode: "always",
      }

      expected_payload = {
        ruleset_bypass_actors_added: [expected_deploy_key_bypass],
      }

      refute_nil event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload.slice(:ruleset_bypass_actors_added)
      assert_nil event.payload[:ruleset_bypass_actors_updated]
      assert_nil event.payload[:ruleset_bypass_actors_deleted]
    end

    test "instrument update - remove deploy key bypass" do
      events = subscribe "repository_ruleset.update"

      create(:repository_ruleset, :example_ruleset, :deploy_key_bypass, name: "testing", source: @org_repo)

      ruleset = RepositoryRuleset.last

      RepositoryRuleset.transaction do
        T.must(ruleset).deploy_key_bypass = false
        T.must(ruleset).save!
      end

      expected_deploy_key_bypass = {
        id: nil,
        actor_id: RepositoryRulesetBypassActor::DeployKey.id,
        actor_type: RepositoryRulesetBypassActor::DeployKey.type,
        bypass_mode: "always",
      }

      expected_payload = {
        ruleset_bypass_actors_deleted: [expected_deploy_key_bypass],
      }

      refute_nil event = events.pop, "an event was expected"
      assert_nil event.payload[:ruleset_bypass_actors_updated]
      assert_nil event.payload[:ruleset_bypass_actors_added]
      assert_equal expected_payload, event.payload.slice(:ruleset_bypass_actors_deleted)
    end

    test "instruments destroy" do
      events = subscribe "repository_ruleset.destroy"

      ruleset = create(:repository_ruleset, :example_ruleset, name: "testing", source: @org_repo, bypass_mode: 6, bypass_actors: [
        RepositoryRulesetBypassActor.new(
            actor: @org_team,
          )
        ]
      )

      ruleset = RepositoryRuleset.last
      ruleset = T.must(ruleset)

      ruleset.destroy!

      refute_nil event = events.pop, "an event was expected"

      expected_org_admin = {
        id: nil,
        actor_id: RepositoryRuleset::ORG_ROLE_BYPASS_ACTOR_IDS[:org_admin],
        actor_type: "OrganizationAdmin",
        bypass_mode: "always"
      }

      bypass_actors = ruleset.bypass_actors.map(&:event_payload) + [expected_org_admin]

      expected_payload = {
        ruleset_id: ruleset.id,
        ruleset_name: "testing",
        ruleset_enforcement: "enabled",
        ruleset_source_type: "Repository",
        ruleset_rules: ruleset.rule_configurations.map(&:event_payload),
        ruleset_conditions: ruleset.conditions.map(&:event_payload),
        ruleset_bypass_actors: bypass_actors,
        repo: @org_repo.nwo,
        repo_id: @org_repo.id,
        public_repo: @org_repo.public?,
        org: @org.login,
        org_id: @org.id
      }

      assert_equal expected_payload, event.payload
    end

    test "instruments update" do
      events = subscribe "repository_ruleset.update"

      ruleset = create(:repository_ruleset, name: "testing", enforcement: :disabled, source: @org_repo, bypass_mode: 6, bypass_actors: [
        RepositoryRulesetBypassActor.new(
          actor: @org_team,
          bypass_mode: 0
        )
      ])

      create(:repository_rule_configuration, repository_ruleset: ruleset)

      ruleset = RepositoryRuleset.last # resets all instance variables
      ruleset = T.must(ruleset)
      rules_deleted = ruleset.reload.rule_configurations.map(&:event_payload)
      bypass_actors_deleted = ruleset.bypass_actors.map(&:event_payload)

      repo_role = T.must(RepositoryRole.find_by(name: "admin"))

      ruleset.name = "new-name"
      ruleset.enforcement = :enabled

      RepositoryRuleset.transaction do
        ruleset.bypass_mode = 5
        ruleset.upsert_rules([{ rule_type: "deletion", parameters: {} }])
        ruleset.upsert_conditions([{ target: "ref_name", parameters: { exclude: [], include: ["~DEFAULT_BRANCH"] } }])
        ruleset.upsert_bypass_actors([{ actor_id: repo_role.id, actor_type: "RepositoryRole", bypass_mode: 0 }])
        ruleset.save!
      end

      ruleset.reload

      refute_nil event = events.pop, "an event was expected"

      expected_payload = {
        ruleset_id: ruleset.id,
        ruleset_name: "new-name",
        ruleset_enforcement: "enabled",
        ruleset_source_type: "Repository",
        ruleset_old_enforcement: "disabled",
        ruleset_old_name: "testing",
        ruleset_rules_added: ruleset.rule_configurations.map(&:event_payload),
        ruleset_rules_deleted: rules_deleted,
        ruleset_conditions_added: ruleset.conditions.map(&:event_payload),
        ruleset_bypass_actors_added: ruleset.bypass_actors.map(&:event_payload),
        ruleset_bypass_actors_deleted: bypass_actors_deleted,
        repo: @org_repo.nwo,
        repo_id: @org_repo.id,
        public_repo: @org_repo.public?,
        org: @org.login,
        org_id: @org.id
      }

      expected_payload.merge!(ruleset_bypass_actors_updated: [{ id: nil, actor_id: 1, actor_type: "OrganizationAdmin", bypass_mode: "pull_request", old_bypass_mode: "always" }])

      assert_equal expected_payload, event.payload
    end
  end

  context "instrumentation - org ruleset" do
    test "instruments create" do
      events = subscribe "repository_ruleset.create"

      ruleset = build(
        :repository_ruleset,
        source: @org
      )

      RepositoryRuleset.transaction do
        ruleset.upsert_rules([{ rule_type: "max_file_path_length", parameters: { "max_file_path_length" => 255 } }])
        ruleset.upsert_conditions([{ target: "ref_name", parameters: { exclude: [], include: ["refs/heads/develop"] } }])
        ruleset.upsert_bypass_actors([{ actor_id: @org_team.id, actor_type: "Team" }])
        ruleset.save!
      end

      ruleset.reload

      refute_nil event = events.pop, "an event was expected"

      expected_payload = {
        ruleset_id: ruleset.id,
        ruleset_name: ruleset.name,
        ruleset_enforcement: "enabled",
        ruleset_source_type: "Organization",
        ruleset_rules: ruleset.rule_configurations.map(&:event_payload),
        ruleset_conditions: ruleset.conditions.map(&:event_payload),
        ruleset_bypass_actors: ruleset.bypass_actors.map(&:event_payload),
        org: @org.login,
        org_id: @org.id
      }

      assert_equal expected_payload, event.payload
    end

    test "instruments destroy" do
      events = subscribe "repository_ruleset.destroy"

      ruleset = create(:repository_ruleset, :example_ruleset, name: "testing", source: @org, bypass_actors: [
        RepositoryRulesetBypassActor.new(
            actor: @org_team,
          )
        ]
      )

      ruleset.reload

      ruleset.destroy!

      refute_nil event = events.pop, "an event was expected"

      expected_payload = {
        ruleset_id: ruleset.id,
        ruleset_name: "testing",
        ruleset_enforcement: "enabled",
        ruleset_source_type: "Organization",
        ruleset_rules: ruleset.rule_configurations.map(&:event_payload),
        ruleset_conditions: ruleset.conditions.map(&:event_payload),
        ruleset_bypass_actors: ruleset.bypass_actors.map(&:event_payload),
        org: @org.login,
        org_id: @org.id
      }

      assert_equal expected_payload, event.payload
    end

    test "instruments update" do
      events = subscribe "repository_ruleset.update"

      ruleset = create(:repository_ruleset, :example_ruleset, name: "testing", enforcement: :disabled, source: @org)

      rules_deleted = ruleset.rule_configurations.map(&:event_payload)
      conditions_deleted = ruleset.conditions.map(&:event_payload)

      ruleset.reload

      ruleset.name = "new-name"
      ruleset.enforcement = :enabled

      RepositoryRuleset.transaction do
        ruleset.upsert_rules([{ rule_type: "deletion", parameters: {} }])
        ruleset.upsert_conditions([{ target: "repository_name", parameters: { exclude: [], include: ["~ALL"] } }])
        ruleset.save!
      end

      refute_nil event = events.pop, "an event was expected"

      expected_payload = {
        ruleset_id: ruleset.id,
        ruleset_name: "new-name",
        ruleset_enforcement: "enabled",
        ruleset_source_type: "Organization",
        ruleset_old_enforcement: "disabled",
        ruleset_old_name: "testing",
        ruleset_rules_added: ruleset.rule_configurations.map(&:event_payload),
        ruleset_rules_deleted: rules_deleted,
        ruleset_conditions_added: ruleset.conditions.map(&:event_payload),
        ruleset_conditions_deleted: conditions_deleted,
        org: @org.login,
        org_id: @org.id,
      }

      assert_equal expected_payload, event.payload
    end
  end

  context "update_bypass_actors" do
    test "should remove all existing bypass_actors if they exist" do
      ruleset = create(:repository_ruleset, source: @org, bypass_actors: [
        RepositoryRulesetBypassActor.new(
          actor: @org_team,
        ),
        RepositoryRulesetBypassActor.new(
          actor: RepositoryRole.find_by(name: "admin", owner: nil)
        )
      ])

      assert_equal ruleset.bypass_actors.count, 2

      RepositoryRuleset.transaction do
        ruleset.upsert_bypass_actors([])
        ruleset.save!
      end

      ruleset.reload

      assert_equal ruleset.bypass_actors, []
    end

    test "should add new bypass_actors" do
      ruleset = create(:repository_ruleset, source: @org)

      assert_equal ruleset.bypass_actors, []

      RepositoryRuleset.transaction do
        ruleset.upsert_bypass_actors([{
          actor_id: @org_team.id,
          actor_type: "Team"
        }, {
          actor_id: 2,
          actor_type: "RepositoryRole"
        }])

        ruleset.save!
      end

      ruleset.reload

      assert_equal ruleset.bypass_actors.count, 2
      assert_equal ruleset.bypass_actors.first.actor_id, @org_team.id
      assert_equal ruleset.bypass_actors.first.actor_type, "Team"
      assert_equal ruleset.bypass_actors.last.actor_id, 2
      assert_equal ruleset.bypass_actors.last.actor_type, "RepositoryRole"
    end

    test "should add and remove bypass_actors within the same update" do
      ruleset = create(:repository_ruleset, source: @org, bypass_actors: [
        RepositoryRulesetBypassActor.new(
          actor: @org_team,
        )
      ])

      assert_equal ruleset.bypass_actors.count, 1
      assert_equal ruleset.bypass_actors.first.actor, @org_team

      RepositoryRuleset.transaction do
        ruleset.upsert_bypass_actors([{
          actor_id: 2,
          actor_type: "RepositoryRole"
        }])

        ruleset.save!
      end

      ruleset.reload

      assert_equal ruleset.bypass_actors.count, 1
      assert_equal ruleset.bypass_actors.first.actor_id, 2
      assert_equal ruleset.bypass_actors.first.actor_type, "RepositoryRole"
    end
  end

  test "organization needs repository and ref condition targets to pass" do
    context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @repo, ref_name: "refs/heads/#{@repo.default_branch}")
    ruleset = create(:repository_ruleset, :example_ruleset, source: @org)

    refute ruleset.should_evaluate?(context)

    ruleset.update!(conditions: [
        ruleset.conditions[0],
        build(:repository_rule_condition, :targets_repo, repo_name: @repo.name)
    ])

    ruleset.reload
    assert ruleset.should_evaluate?(context)
  end

  test "repository needs ref condition target to pass" do
    context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @repo, ref_name: "refs/heads/#{@repo.default_branch}")
    ruleset = create(:repository_ruleset, enforcement: :enabled, source: @repo)

    refute ruleset.should_evaluate?(context)

    ruleset.update!(conditions: [
      build(:repository_rule_condition, :targets_all_branches)
    ])

    ruleset.reload

    assert ruleset.should_evaluate?(context)
  end

  test "evaluate for org rules requires enterprise tier" do
    context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @org_repo, ref_name: "refs/heads/#{@org_repo.default_branch}")
    ruleset = create(:repository_ruleset, :targets_all_branches, enforcement: :evaluate, source: @org)
    create(:repository_rule_condition, :targets_repo, repo_name: @org_repo.name, repository_ruleset: ruleset)

    ruleset.reload

    assert ruleset.should_evaluate?(context)

    @org.plan = "silver"
    @org.save!

    ruleset.source.reload

    refute ruleset.should_evaluate?(context)
  end

  test "evaluate for repo rules requires an org at enterprise tier" do
    context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @org_repo, ref_name: "refs/heads/#{@org_repo.default_branch}")
    ruleset = create(:repository_ruleset, :targets_default_branch, enforcement: :evaluate, source: @org_repo)

    assert ruleset.should_evaluate?(context)

    # if the plan gets downgarded, the conditions should fail
    @org_repo.plan = "free"
    refute ruleset.should_evaluate?(context)

    @org_repo.plan = "pro"
    refute ruleset.should_evaluate?(context)
  end

  test "matches repository_id conditions" do
    ruleset = create(:repository_ruleset, :targets_default_branch, source: @org)
    create(:repository_rule_condition, target: "repository_id", parameters: {
      repository_ids: [@org_repo.global_relay_id]
    }, repository_ruleset: ruleset)
    ruleset.reload

    context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @org_repo, ref_name: "refs/heads/#{@org_repo.default_branch}")
    assert ruleset.should_evaluate?(context)

    @another_org_repo = create(:repository, owner: @org)

    context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @another_org_repo, ref_name: "refs/heads/#{@another_org_repo.default_branch}")
    refute ruleset.should_evaluate?(context)
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

    context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @org_repo, ref_name: "refs/heads/#{@org_repo.default_branch}")
    assert ruleset.should_evaluate?(context)

    @another_org_repo = create(:repository, owner: @org)

    context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @another_org_repo, ref_name: "refs/heads/#{@another_org_repo.default_branch}")
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

    context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @org_repo, ref_name: "refs/heads/#{@org_repo.default_branch}")
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

    context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @org_repo, ref_name: "refs/heads/#{@org_repo.default_branch}")
    assert ruleset.should_evaluate?(context)

    @another_org_repo = create(:repository, owner: @org)
    create :custom_property_value, target: @another_org_repo, definition: definition_a, value: "somevalue"
    create :custom_property_value, target: @another_org_repo, definition: definition_b, value: "nomatch"

    context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @another_org_repo, ref_name: "refs/heads/#{@another_org_repo.default_branch}")
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

    context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @org_repo, ref_name: "refs/heads/#{@org_repo.default_branch}")
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

    context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @org_repo, ref_name: "refs/heads/#{@org_repo.default_branch}")
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

    context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @org_repo, ref_name: "refs/heads/#{@org_repo.default_branch}")
    refute ruleset.should_evaluate?(context)
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

    context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @org_repo, ref_name: "refs/heads/#{@org_repo.default_branch}")
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

    fork_repo_context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @org_fork, ref_name: "refs/heads/#{@org_fork.default_branch}")
    org_repo_context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @org_repo, ref_name: "refs/heads/#{@org_repo.default_branch}")

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

    private_repo_context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @org_repo, ref_name: "refs/heads/#{@org_repo.default_branch}")
    public_repo_context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @org_public_repo, ref_name: "refs/heads/#{@org_public_repo.default_branch}")

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

    ruby_repo_context = RuleEngine::Conditions::RulesetTargetContext.new(repository: ruby_repo, ref_name: "refs/heads/#{ruby_repo.default_branch}")
    go_repo_context = RuleEngine::Conditions::RulesetTargetContext.new(repository: go_repo, ref_name: "refs/heads/#{go_repo.default_branch}")

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
    fork_context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @org_fork, ref_name: "refs/heads/#{@org_fork.default_branch}")
    assert ruleset.should_evaluate?(fork_context)

    create :custom_property_value, target: @another_org_fork, definition: environment_def, value: "testing"
    another_org_fork_context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @another_org_fork, ref_name: "refs/heads/#{@another_org_fork.default_branch}")
    refute ruleset.should_evaluate?(another_org_fork_context)

    create :custom_property_value, target: @org_repo, definition: environment_def, value: "production"
    org_repo_context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @org_repo, ref_name: "refs/heads/#{@org_repo.default_branch}")
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
    fork_context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @org_fork, ref_name: "refs/heads/#{@org_fork.default_branch}")
    assert ruleset.should_evaluate?(fork_context)

    another_org_fork = create(:fork_repository, forker: @user, organization: @org, fork_repo: @org_repo)
    create :custom_property_value, target: another_org_fork, definition: environment_def, value: "testing"
    create :custom_property_value, target: another_org_fork, definition: environment_def, value: "ruby"
    another_fork_context = RuleEngine::Conditions::RulesetTargetContext.new(repository: another_org_fork, ref_name: "refs/heads/#{another_org_fork.default_branch}")
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
    fork_context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @org_fork, ref_name: "refs/heads/#{@org_fork.default_branch}")
    refute ruleset.should_evaluate?(fork_context)

    create :custom_property_value, target: @another_org_fork, definition: environment_def, value: "testing"
    another_org_fork_context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @another_org_fork, ref_name: "refs/heads/#{@another_org_fork.default_branch}")
    assert ruleset.should_evaluate?(another_org_fork_context)

    create :custom_property_value, target: @org_repo, definition: environment_def, value: "testing"
    org_repo_context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @org_repo, ref_name: "refs/heads/#{@org_repo.default_branch}")
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
    fork_context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @org_fork, ref_name: "refs/heads/#{@org_fork.default_branch}")
    refute ruleset.should_evaluate?(fork_context)

    create :custom_property_value, target: @org_repo, definition: environment_def, value: "production"
    org_repo_context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @org_repo, ref_name: "refs/heads/#{@org_repo.default_branch}")
    assert ruleset.should_evaluate?(org_repo_context)

    another_org_repo = create(:private_repository, owner: @org)
    create :custom_property_value, target: another_org_repo, definition: environment_def, value: "testing"
    another_org_context = RuleEngine::Conditions::RulesetTargetContext.new(repository: another_org_repo, ref_name: "refs/heads/#{another_org_repo.default_branch}")
    refute ruleset.should_evaluate?(another_org_context)
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

      if GitHub.flipper[:ruleset_ensure_valid_props_and_values].enabled?
        refute ruleset_condition.save
        assert_equal ruleset_condition.errors.map(&:message), ["are invalid for this target: Invalid property 'invalid_name' with source '#{source}'"]
      else
        assert ruleset_condition.save
      end
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

      if GitHub.flipper[:ruleset_ensure_valid_props_and_values].enabled?
        refute ruleset_condition.save
        assert_equal ruleset_condition.errors.map(&:message), ["are invalid for this target: Invalid value(s) for the custom property 'environment'"]
      else
        assert ruleset_condition.save
      end
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

    if GitHub.flipper[:ruleset_ensure_valid_props_and_values].enabled?
      refute ruleset_condition.save
      assert_equal ruleset_condition.errors.map(&:message), ["are invalid for this target: Invalid value(s) for the system property 'language'"]
    else
      assert ruleset_condition.save
    end
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
    assert_equal ruleset_condition.errors.map(&:message), ["are invalid for this target: Invalid parameter include: Invalid array of property_target_definition objects: Expected value to be one of custom, system, got foo"]
  end

  test "cannot create a ruleset with duplicate rule types" do
    ruleset = build(
      :repository_ruleset,
      source: @repo,
      rule_configurations: [
        build(
          :repository_rule_configuration,
          rule_type: "max_file_path_length",
          parameters: {
            max_file_path_length: 32
          }
        ),
        build(
          :repository_rule_configuration,
          rule_type: "max_file_path_length",
          parameters: {
            max_file_path_length: 64
          }
        ),
      ]
    )

    refute ruleset.save
    assert ruleset.errors[:rule_configurations]
  end

  test "cannot update a ruleset to contain duplicate rule types" do
    ruleset = create(:repository_ruleset, source: @repo)

    ruleset.rule_configurations << [
      build(
        :repository_rule_configuration,
        rule_type: "max_file_path_length",
        parameters: {
          max_file_path_length: 32
        }
      ),
      build(
        :repository_rule_configuration,
        rule_type: "max_file_path_length",
        parameters: {
          max_file_path_length: 32
        }
      )
    ]

    refute ruleset.save
    assert ruleset.errors[:rule_configurations]
  end

  test "cannot update a ruleset to contain a rule type that is already in the ruleset" do
    ruleset = create(:repository_ruleset, source: @repo)

    ruleset.rule_configurations << build(
      :repository_rule_configuration,
      rule_type: "max_file_path_length",
      parameters: {
        max_file_path_length: 32
      }
    )

    assert ruleset.save

    ruleset.rule_configurations << build(
      :repository_rule_configuration,
      rule_type: "max_file_path_length",
      parameters: {
        max_file_path_length: 64
      }
    )

    refute ruleset.save
    assert ruleset.errors[:rule_configurations]
  end

  test "cannot create a ruleset with duplicate condition targets" do
    ruleset = build(
      :repository_ruleset,
      source: @repo,
      conditions: [
        build(:repository_rule_condition, :targets_all_branches),
        build(:repository_rule_condition, :targets_default_branch),
      ],
    )

    refute ruleset.save
    assert ruleset.errors[:conditions]
  end

  test "cannot update a ruleset to contain duplicate condition targets" do
    ruleset = create(:repository_ruleset, source: @repo)

    ruleset.conditions << [
      build(:repository_rule_condition, :targets_all_branches),
      build(:repository_rule_condition, :targets_default_branch),
    ]

    refute ruleset.save
    assert ruleset.errors[:conditions]
  end

  test "cannot update a ruleset to contain a condition target that is already in the ruleset" do
    ruleset = create(:repository_ruleset, source: @repo)

    ruleset.conditions << build(:repository_rule_condition, :targets_all_branches)

    assert ruleset.save

    ruleset.conditions << build(:repository_rule_condition, :targets_default_branch)

    refute ruleset.save
    assert ruleset.errors[:conditions]
  end

  test "create a custom property ruleset fails if no include condition" do
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

    if GitHub.flipper[:forbid_property_rule_without_include].enabled?
      refute ruleset.save
      invalid_condition = ruleset.conditions.select { |condition| !condition.valid? }
      assert_equal 1, invalid_condition.size
      assert_includes invalid_condition.first.errors.first.message, "Invalid parameter include: At least one target is required"
    else
      assert ruleset.save
    end
  end

  context "#changes_payload" do
    test "returns empty hash when no changes" do
      ruleset = create(:repository_ruleset, source: @repo)

      ruleset.reload

      assert_empty ruleset.changes_payload
    end

    test "ruleset name should be tracked" do
      ruleset = create(:repository_ruleset, name: "testing", source: @repo)

      ruleset.reload

      ruleset.name = "better name"
      ruleset.save!

      refute_empty ruleset.changes_payload
      assert_equal "testing", ruleset.changes_payload[:ruleset_old_name]
    end

    test "enforcement should be tracked" do
      ruleset = create(:repository_ruleset, source: @repo)

      ruleset.reload

      ruleset.enforcement = :disabled
      ruleset.save!

      refute_empty ruleset.changes_payload
      assert_equal "enabled", ruleset.changes_payload[:ruleset_old_enforcement]
    end

    test "should track new rules" do
      ruleset = create(:repository_ruleset, source: @repo)

      ruleset.reload

      ruleset.upsert_rules([{ rule_type: "deletion", parameters: {} }])
      ruleset.save!

      refute_empty ruleset.changes_payload
      refute_nil ruleset.changes_payload[:ruleset_rules_added]
      assert_nil ruleset.changes_payload[:ruleset_rules_updated]
      assert_nil ruleset.changes_payload[:ruleset_rules_deleted]
    end

    test "should track deleted rules" do
      ruleset = create(:repository_ruleset, :example_ruleset, source: @repo)

      ruleset.reload

      ruleset.upsert_rules([])
      ruleset.save!

      refute_empty ruleset.changes_payload
      refute_nil ruleset.changes_payload[:ruleset_rules_deleted]
      assert_nil ruleset.changes_payload[:ruleset_rules_updated]
      assert_nil ruleset.changes_payload[:ruleset_rules_added]
      assert_predicate ruleset.rule_configurations, :empty?
    end

    test "should track updated rules" do
      ruleset = create(:repository_ruleset, source: @org_repo)
      create(:repository_rule_configuration, :metadata_pattern, repository_ruleset: ruleset)

      existing_rule = ruleset.reload.rule_configurations.first

      ruleset.upsert_rules([{ id: existing_rule.id, rule_type: existing_rule.rule_type, parameters: existing_rule.parameters.merge({ negate: true }) }])
      ruleset.save!

      refute_empty ruleset.changes_payload
      refute_nil ruleset.changes_payload[:ruleset_rules_updated]
      assert_nil ruleset.changes_payload[:ruleset_rules_added]
      assert_nil ruleset.changes_payload[:ruleset_rules_deleted]
    end
  end

  test "should track new conditions" do
    ruleset = create(:repository_ruleset, source: @repo)

    ruleset.reload

    ruleset.upsert_conditions([{ target: "ref_name", parameters: { exclude: [], include: ["refs/heads/develop"] } }])
    ruleset.save!

    refute_empty ruleset.changes_payload
    refute_nil ruleset.changes_payload[:ruleset_conditions_added]
    assert_nil ruleset.changes_payload[:ruleset_conditions_updated]
    assert_nil ruleset.changes_payload[:ruleset_conditions_deleted]
  end

  test "should track updated conditions" do
    ruleset = create(:repository_ruleset, :targets_default_branch, source: @repo)

    ruleset.reload

    prev_condition_id = ruleset.conditions.first.id
    ruleset.upsert_conditions([{ id: ruleset.conditions.first.id, target: "ref_name", parameters: { exclude: [], include: ["~ALL"] } }])
    ruleset.save!

    refute_empty ruleset.changes_payload
    assert_equal prev_condition_id, ruleset.conditions.first.id
    assert_nil ruleset.changes_payload[:ruleset_conditions_added]
    refute_nil ruleset.changes_payload[:ruleset_conditions_updated]
    assert_nil ruleset.changes_payload[:ruleset_conditions_deleted]
  end

  test "should track deleted conditions" do
    ruleset = create(:repository_ruleset, :targets_default_branch, source: @repo)

    ruleset.reload

    ruleset.upsert_conditions([])
    ruleset.save!

    refute_empty ruleset.changes_payload
    assert_nil ruleset.changes_payload[:ruleset_conditions_added]
    assert_nil ruleset.changes_payload[:ruleset_conditions_updated]
    refute_nil ruleset.changes_payload[:ruleset_conditions_deleted]
  end

  test "should track new bypass actors" do
    ruleset = create(:repository_ruleset, source: @org_repo)

    ruleset.reload

    ruleset.upsert_bypass_actors([{ actor_id: @org_team.id, actor_type: "Team" }])
    ruleset.save!

    refute_empty ruleset.changes_payload
    refute_nil ruleset.changes_payload[:ruleset_bypass_actors_added]
    assert_nil ruleset.changes_payload[:ruleset_bypass_actors_deleted]
  end

  test "should track deleted bypass actors" do
    ruleset = create(
      :repository_ruleset,
      source: @org_repo,
      bypass_actors: [
        RepositoryRulesetBypassActor.new(
          actor: @org_team,
        )
      ]
    )

    ruleset.reload

    ruleset.upsert_bypass_actors([])
    ruleset.save!

    refute_empty ruleset.changes_payload
    assert_nil ruleset.changes_payload[:ruleset_bypass_actors_added]
    refute_nil ruleset.changes_payload[:ruleset_bypass_actors_deleted]
  end

  test "should track adding deploy key bypass" do
    ruleset = create(
      :repository_ruleset,
      source: @org_repo,
    )

    ruleset.deploy_key_bypass = true
    ruleset.save!

    bypass_actor = ruleset.changes_payload[:ruleset_bypass_actors_added]&.first
    assert_same_hash({
      id: nil,
      actor_id: RepositoryRulesetBypassActor::DeployKey.id,
      actor_type: RepositoryRulesetBypassActor::DeployKey.type,
      bypass_mode: "always"
    }, bypass_actor)
  end

  test "should track deleting deploy key bypass" do
    ruleset = create(
      :repository_ruleset,
      :deploy_key_bypass,
      source: @org_repo
    )

    ruleset.deploy_key_bypass = false
    ruleset.save!

    bypass_actor = ruleset.changes_payload[:ruleset_bypass_actors_deleted]&.first
    assert_same_hash({
      id: nil,
      actor_id: RepositoryRulesetBypassActor::DeployKey.id,
      actor_type: RepositoryRulesetBypassActor::DeployKey.type,
      bypass_mode: "always"
    }, bypass_actor)
  end

  test "validates ruleset target supports rules" do
    ruleset = build(
      :repository_ruleset,
      source: @repo,
      rule_configurations: [
        build(
          :repository_rule_configuration,
          rule_type: "max_file_path_length",
          parameters: {
            max_file_path_length: 32
          }
        ),
        build(
          :repository_rule_configuration,
          rule_type: "tag_name_pattern",
          parameters: {
            pattern: "^v[0-9]\\.[0-9]$",
            operator: "regex",
            negate: false
          }
        )
      ]
    )

    refute ruleset.save
    invalid_rules = ruleset.rule_configurations.select { |r| !r.valid? }
    assert_equal 1, invalid_rules.size
    assert_equal "tag_name_pattern is not supported on rulesets that target branches.", invalid_rules.first.errors[:rule_type].first
  end

  test "does not allow rulesets with duplicate names by source" do
    ruleset1 = create(:repository_ruleset, name: "testing", source: @repo)

    ruleset2 = build(
      :repository_ruleset,
      source: @repo,
      name: "testing"
    )

    refute ruleset2.save
    assert_includes ruleset2.errors[:name], "must be unique"
  end

  test "allow rulesets with duplicate names with different sources" do
    ruleset1 = create(:repository_ruleset, name: "testing", source: @repo)

    ruleset2 = build(
      :repository_ruleset,
      source: create(:repository),
      name: "testing"
    )

    assert ruleset2.save
  end

  test "should delete associated rules, conditions, and bypass_actors on destroy via background job" do
    ruleset = create(
      :repository_ruleset,
      :example_ruleset,
      source: @org,
      bypass_actors: [
        RepositoryRulesetBypassActor.new(
          actor: @org_team,
        )
      ]
    )

    prev_rule_id = ruleset.rule_configurations.first.id
    prev_condition_id = ruleset.conditions.first.id
    prev_bypass_actor_id = ruleset.bypass_actors.first.id

    perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
      ruleset.destroy!
    end

    assert_nil RepositoryRuleConfiguration.find_by(id: prev_rule_id)
    assert_nil RepositoryRuleCondition.find_by(id: prev_condition_id)
    assert_nil RepositoryRulesetBypassActor.find_by(id: prev_bypass_actor_id)
  end

  context "when ruleset api urls feature is enabled" do
    test "repository source url is correct" do
      ruleset = RepositoryRuleset.create!(
        source: @repo,
        name: "testing"
      )

      assert_includes ruleset.url, "#{ruleset.source.nwo}/rules/#{ruleset.id}"
    end

    test "organization source url is correct" do
      ruleset = RepositoryRuleset.create!(
        source: @org,
        name: "testing"
      )

      assert_includes ruleset.url, "#{@org.login}/settings/rules/#{ruleset.id}"
    end
  end

  test "should disallow creating a ruleset with a bypass actor team that doesn't exist" do
    ruleset = build(
      :repository_ruleset,
      source: @repo,
      name: "testing",
    )

    assert ruleset.save
    assert_nil ruleset.errors[:bypass_actors].first

    ruleset.bypass_actors << RepositoryRulesetBypassActor.new(
      actor_id: 98,
      actor_type: "Team"
    )

    refute ruleset.save
    assert_includes ruleset.errors[:bypass_actors], "must be GitHub Apps, roles, or public teams associated with the ruleset source."
  end

  test "should disallow creating a ruleset with a bypass actor integration that doesn't exist" do
    ruleset = build(
      :repository_ruleset,
      source: @repo,
      name: "testing",
    )

    assert ruleset.save
    assert_nil ruleset.errors[:bypass_actors].first

    ruleset.bypass_actors = []
    ruleset.bypass_actors << RepositoryRulesetBypassActor.new(
      actor_id: 99,
      actor_type: "Integration"
    )

    refute ruleset.save
    assert_includes ruleset.errors[:bypass_actors], "must be GitHub Apps, roles, or public teams associated with the ruleset source."
  end

  test "should disallow creating a ruleset with a bypass actor team not included in the org" do
    ruleset = build(
      :repository_ruleset,
      source: @repo,
      name: "testing",
    )

    other_org = create :organization
    other_team = create(:team, organization: other_org)

    assert ruleset.save
    assert_nil ruleset.errors[:bypass_actors].first

    ruleset.bypass_actors << RepositoryRulesetBypassActor.new(
      actor_id: other_team.id,
      actor_type: "Team"
    )

    refute ruleset.save
    assert_includes ruleset.errors[:bypass_actors], "must be GitHub Apps, roles, or public teams associated with the ruleset source."
  end

  test "should disallow creating a ruleset with a bypass actor integration not included in the org" do
    ruleset = build(
      :repository_ruleset,
      source: @repo,
      name: "testing",
    )

    other_org = create :organization
    other_integration = create(:integration, owner: other_org)

    assert ruleset.save
    assert_nil ruleset.errors[:bypass_actors].first

    ruleset.bypass_actors = []
    ruleset.bypass_actors << RepositoryRulesetBypassActor.new(
      actor_id: other_integration.id,
      actor_type: "Integration"
    )

    refute ruleset.save
    assert_includes ruleset.errors[:bypass_actors], "must be GitHub Apps, roles, or public teams associated with the ruleset source."
  end

  test "should disallow creating a ruleset with a bypass actor integration included in only one of the org's repos with FF on" do
    GitHub.flipper[:more_efficient_permissions_query].enable(@org)
    GitHub.flipper[:dont_check_repos_integrations_limit].enable(@org)
    GitHub.flipper[:dont_check_repos_integrations_limit_value].enable_percentage_of_time(0.00001)

    other_org_repo = create(:private_repository, owner: @org)
    other_app = create(:integration, default_permissions: @permissions)
    make_integration_installation(integration: other_app, repository: other_org_repo)
    @ruleset.bypass_actors << RepositoryRulesetBypassActor.new(actor_id: other_app.id, actor_type: "Integration")

    refute @ruleset.save
    assert_includes @ruleset.errors[:bypass_actors], "must be GitHub Apps, roles, or public teams associated with the ruleset source."

    @ruleset.reload
    assert_equal @ruleset.bypass_actors.count, 1
    assert_equal @ruleset.bypass_actors.first.actor_id, @app.id
    assert_equal @ruleset.bypass_actors.first.actor_type, "Integration"
  end

  context "#load_for" do
    test "should not return invalid/unpaid rulesets" do
      unpaid_org = create(:business_organization, name: "unpaid-org", admin: @user)
      unpaid_repo = create(:private_repository, owner: unpaid_org)

      # create an org ruleset which is invalid because the org is not enterprise tier
      branch_ruleset = create(:repository_ruleset, :targets_all_repos, :targets_default_branch, source: unpaid_org)

      rulesets = RepositoryRuleset.load_for(source: unpaid_repo, include_parents: true)
      assert_equal 0, rulesets.size
    end

    test "should only return rulesets with matching target" do
      push_rulesets_enabled = GitHub.flipper[:push_rulesets].enabled?

      branch_ruleset = create(:repository_ruleset, source: @org_repo, target: :branch)
      tag_ruleset = create(:repository_ruleset, source: @org_repo, target: :tag)
      push_ruleset = push_rulesets_enabled ? create(:repository_ruleset, source: @org_repo, target: :push) : nil

      rulesets = RepositoryRuleset.load_for(source: @org_repo, targets: ["push"])

      if push_rulesets_enabled
        assert_equal 1, rulesets.size
        assert_includes rulesets, push_ruleset
      else
        assert_empty rulesets
      end

      rulesets = RepositoryRuleset.load_for(source: @org_repo, targets: [])

      if push_rulesets_enabled
        assert_equal 3, rulesets.size
      else
        assert_equal 2, rulesets.size
      end
    end

    test "should not return org rulesets for user-owned forks of org repos" do
      @org.allow_private_repository_forking(actor: @user)

      fork_repo = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @org_repo.fork(forker: @user) }.first

      # sanity check for the weird case where organization != owner that this test is checking for
      assert_equal @org, fork_repo.organization
      assert_equal @user, fork_repo.owner

      ruleset = create(:repository_ruleset, :targets_all_repos, :targets_default_branch, source: @org)

      rulesets = RepositoryRuleset.load_for(source: fork_repo, include_parents: true)

      assert_equal 0, rulesets.size
    end
  end

  context "ruleset limit" do
    test "should not allow more than the RULESET_LIMIT amount of rulesets per repository" do
      GitHub.flipper[:rulesets_limit].enable(@repo)
      rulesets = create_list(:repository_ruleset, RULESET_LIMIT, source: @repo)

      assert_raises_with_message ActiveRecord::RecordInvalid, "Validation failed: The ruleset limit of #{RULESET_LIMIT} has been reached." do
        ruleset = create(:repository_ruleset, source: @repo)
      end
    end
  end

  context "histories" do
    test "should create new history records on creation" do
      GitHub.flipper[:rules_history].enable
      GitHub.context.push(actor_id: @user.id)

      ruleset = create(
        :repository_ruleset,
        :example_ruleset,
        enforcement: :enabled,
        bypass_mode: :org_bypass_any,
        source: @org_repo,
        name: "cool ruleset",
        bypass_actors: [
          RepositoryRulesetBypassActor.new(
            actor: @org_team,
            bypass_mode: 0
          )
        ]
      )
      history = ruleset.histories.first
      state = GitHub::JSON.parse(history.state)

      assert_equal ruleset.histories.count, 1
      assert_equal history.updated_by_id, @user.id
      assert_equal state["name"], "cool ruleset"
      assert_equal state["source_id"], @org_repo.id
      assert_equal state["source_type"], "Repository"
      assert_equal state["enforcement"], "enabled"
      assert_equal state["rule_configurations"].length, 1
      assert_equal state["conditions"].length, 1
      assert_equal state["bypass_actors"].length, 2
    end

    test "org admin bypass modes on a ruleset adds the org admin bypass actor to the history" do
      GitHub.flipper[:rules_history].enable
      GitHub.context.push(actor_id: @user.id)

      ruleset = create(
        :repository_ruleset,
        :example_ruleset,
        enforcement: :enabled,
        bypass_mode: :org_bypass_any,
        source: @org_repo,
        name: "cool ruleset",
      )
      history = ruleset.histories.first
      state = GitHub::JSON.parse(history.state)

      assert_equal ruleset.histories.count, 1
      assert_equal history.updated_by_id, @user.id
      assert_equal state["name"], "cool ruleset"
      assert_equal state["source_id"], @org_repo.id
      assert_equal state["source_type"], "Repository"
      assert_equal state["enforcement"], "enabled"
      assert_equal state["rule_configurations"].length, 1
      assert_equal state["conditions"].length, 1
      assert_equal state["bypass_actors"].length, 1
    end

    test "should create new history records on ruleset creation by a bot" do
      GitHub.flipper[:rules_history].enable
      bot = create :bot
      GitHub.context.push(actor_id: bot.id)

      ruleset = create(:repository_ruleset, :example_ruleset, source: @repo, name: "🤖 ruleset")
      history = ruleset.histories.first
      state = GitHub::JSON.parse(history.state)

      assert_equal ruleset.histories.count, 1
      assert_equal history.updated_by_id, bot.id
      assert_equal state["name"], "🤖 ruleset"
    end

    test "should create new history records on ruleset and default the updated_by id to Ghost" do
      GitHub.flipper[:rules_history].enable

      ruleset = create(:repository_ruleset, :example_ruleset, source: @repo, name: "👻 ruleset")
      history = ruleset.histories.first
      state = GitHub::JSON.parse(history.state)

      assert_equal ruleset.histories.count, 1
      assert_equal history.updated_by_id, User.ghost.id
      assert_equal state["name"], "👻 ruleset"
    end

    test "should create new history records each time a ruleset is saved" do
      GitHub.flipper[:rules_history].enable
      GitHub.context.push(actor_id: @user.id)

      ruleset = create(:repository_ruleset, :example_ruleset, source: @repo, name: "Regular ruleset")

      state = GitHub::JSON.parse(ruleset.histories.last.state)

      assert_equal ruleset.histories.count, 1
      assert_equal state["name"], "Regular ruleset"
      assert_equal state["enforcement"], "enabled"

      ruleset.name = "Better ruleset"
      ruleset.enforcement = :disabled
      ruleset.save!

      histories = RepositoryRulesetHistory.where(repository_ruleset: ruleset)

      assert_equal histories.count, 2

      state = GitHub::JSON.parse(T.must(histories.first).state)
      assert_equal state["name"], "Regular ruleset"
      assert_equal state["enforcement"], "enabled"

      state = GitHub::JSON.parse(T.must(histories.last).state)
      assert_equal state["name"], "Better ruleset"
      assert_equal state["enforcement"], "disabled"
    end
  end

  def create_push_ruleset(source, invalid: false, target_repo: nil)
    GitHub.flipper[:push_rulesets].enable
    ruleset = if source.is_a?(Organization)
      # calling create, not build, here because build doesn't create the necessary rule conditions
      if target_repo
        create(:repository_ruleset, :targets_repo, repo: target_repo, source: source, target: :push)
      else
        create(:repository_ruleset, :targets_all_repos, source: source, target: :push)
      end
    else
      build(:repository_ruleset, source: source, target: :push)
    end

    if invalid
      refute_predicate ruleset, :valid?, "creation should be blocked"
      ruleset.save!(validate: false)
    else
      ruleset.save!
    end

    create(:repository_rule_configuration, repository_ruleset: ruleset, rule_type: "max_file_path_length",
      parameters: { max_file_path_length: 1 })

    ruleset
  end

  context "push rules" do
    test "enforce network root rules on org-owned fork" do
      ruleset = create_push_ruleset(@org_repo)

      rulesets = RepositoryRuleset.load_for(source: @org_repo, include_parents: true)
      assert_includes rulesets, ruleset
      context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @org_repo, ref_name: "refs/heads/#{@org_repo.default_branch}")
      assert ruleset.should_evaluate?(context)

      assert_includes RepositoryRuleset.load_for(source: @user_org_fork, include_parents: true), ruleset
      context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @user_org_fork, ref_name: "refs/heads/#{@user_org_fork.default_branch}")
      assert ruleset.should_evaluate?(context)
    end

    test "enforce network root org rules" do
      ruleset = create_push_ruleset(@org, target_repo: @org_repo)

      rulesets = RepositoryRuleset.load_for(source: @org_repo, include_parents: true)
      assert_includes rulesets, ruleset
      context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @org_repo, ref_name: "refs/heads/#{@org_repo.default_branch}")
      assert ruleset.should_evaluate?(context)

      rulesets = RepositoryRuleset.load_for(source: @user_org_fork, include_parents: true)
      assert_equal 1, rulesets.size
      assert_includes rulesets, ruleset
      context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @user_org_fork, ref_name: "refs/heads/#{@user_org_fork.default_branch}")
      assert ruleset.should_evaluate?(context)

      rulesets = RepositoryRuleset.load_for(source: @org_fork, include_parents: true)
      # there should only be 1 push rule
      assert_equal 1, rulesets.size
      assert_includes rulesets, ruleset
      context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @user_org_fork, ref_name: "refs/heads/#{@user_org_fork.default_branch}")
      assert ruleset.should_evaluate?(context)
    end

    test "ignore network root rules on user-owned fork" do
      ruleset = create_push_ruleset(@priv_repo, invalid: true)

      rulesets = RepositoryRuleset.load_for(source: @priv_repo, include_parents: true)
      assert_includes rulesets, ruleset
      context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @priv_repo, ref_name: "refs/heads/#{@priv_repo.default_branch}")
      refute ruleset.should_evaluate?(context)

      assert_includes RepositoryRuleset.load_for(source: @priv_fork, include_parents: true), ruleset
      context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @priv_fork, ref_name: "refs/heads/#{@priv_fork.default_branch}")
      refute ruleset.should_evaluate?(context)
    end

    test "ignore fork repo rules" do
      ruleset = create_push_ruleset(@priv_fork, invalid: true)
      # assert the fork can see the ruleset, but the root repo cannot see the ruleset
      # in both cases the rule should not be evaluated because the rule is not on the root
      refute_includes RepositoryRuleset.load_for(source: @priv_repo, include_parents: true), ruleset
      context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @priv_repo, ref_name: "refs/heads/#{@priv_repo.default_branch}")
      refute ruleset.should_evaluate?(context)

      rulesets = RepositoryRuleset.load_for(source: @priv_fork, include_parents: true)
      assert_includes rulesets, ruleset
      context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @priv_fork, ref_name: "refs/heads/#{@priv_fork.default_branch}")
      refute ruleset.should_evaluate?(context)
    end

    test "ignore fork repo org rules" do
      # @org2_fork is a fork of @org_repo
      # @org2 has it's own push rules, but they should be ignored since they don't own the network root

      ruleset = create_push_ruleset(@org2)
      # assert no repo in the network can see the org rule
      refute_includes RepositoryRuleset.load_for(source: @org_repo, include_parents: true), ruleset
      refute_includes RepositoryRuleset.load_for(source: @org2_fork, include_parents: true), ruleset
    end

    test "ignored on public repos" do
      ruleset = create_push_ruleset(@repo, invalid: true)
      # We should show the rule on the public root, to give them an option to delete it. But we should not evaluate it.
      rulesets = RepositoryRuleset.load_for(source: @repo, include_parents: true)
      assert_includes rulesets, ruleset
      context = RuleEngine::Conditions::RulesetTargetContext.new(repository: @repo, ref_name: "refs/heads/#{@repo.default_branch}")
      refute ruleset.should_evaluate?(context)

      # We should not show the rule on the public forks, since they cannot do anything about it, and it won't be evaluated.
      refute_includes RepositoryRuleset.load_for(source: @fork, include_parents: true), ruleset
    end

    test "ignore org push rules targeting a forked repo when FF is enabled" do
      ruleset = create_push_ruleset(@org, target_repo: @org_fork)
      assert_includes RepositoryRuleset.load_for(source: @org, include_parents: true), ruleset
      refute_includes RepositoryRuleset.load_for(source: @org_fork, include_parents: true), ruleset
    end

    test "ignore org push rules targeting a public repo when FF is enabled" do
      GitHub.flipper[:rules_exclude_public_repositories_from_targeting].disable

      ruleset = create_push_ruleset(@org, target_repo: @org_public_repo)
      assert_includes RepositoryRuleset.load_for(source: @org, include_parents: true), ruleset
      refute_includes RepositoryRuleset.load_for(source: @org_public_repo, include_parents: true), ruleset
    end

    test "cannot target public repositories" do
      GitHub.flipper[:rules_exclude_public_repositories_from_targeting].enable

      assert_raises_with_message ActiveRecord::RecordInvalid, "Validation failed: Conditions is invalid" do
        ruleset = create_push_ruleset(@org, target_repo: @org_public_repo)
      end
    end
  end

  context "#serialize" do
    test "serialize deploy key bypass actor" do
      rs = create(:repository_ruleset, :deploy_key_bypass)
      serialized = rs.serialize
      refute JSON.parse(serialized)["bypass_actors"].empty?
    end
  end

  context "member_privileges" do
    test "fails to transfer the repo if blocked by a ruleset" do
      GitHub.flipper[:member_privilege_rulesets].enable
      ruleset = create :repository_ruleset, :member_privileges, source: @org
      o = RepositoryOrchestration.transfer(@org_repo, actor_id: @user.id, new_owner_id: create(:user).id)
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        o.execute(synchronous: false)
      end

      assert_equal :skipped, o.reload.state.to_sym
      assert_equal "Ruleset(s) are preventing this repository from being transferred.", o.error_message
    end
  end

  test "is deleted with repository" do
    ruleset = create(:repository_ruleset, :example_ruleset, source: @repo)
    other_ruleset = create(:repository_ruleset, :example_ruleset, source: @priv_repo)

    assert_destroyed_in_background_with_parent do |config|
      config.parent_record = @repo
      config.expect_destroyed = [ruleset]
      config.expect_not_destroyed = [other_ruleset]
    end
  end
end
