# typed: true
# frozen_string_literal: true

require "test_helper"

class RulesEngine::SuggestionsTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper

  fixtures do
    @repo = create :repository, from_example: :simple

    @org = create :organization, plan: "business_plus"
    @org_repo = create :repository, owner: @org, from_example: :simple
    @user_repo = create :repository, from_example: :simple, organization: @org

    @repo_integration_with_write_access = create :integration, name: "repo-writer"
    @repo_integration_with_read_access = create :integration, name: "repo-reader"
    @org_integration_with_write_access = create :integration, name: "org-writer"
    @org_integration_with_read_access = create :integration, name: "org-reader"

    @repo_installation_with_write_access = make_integration_installation integration: @repo_integration_with_write_access,
                                                                    repository: @repo,
                                                                    permissions: { statuses: "write" }

    @repo_installation_with_read_access = make_integration_installation integration: @repo_integration_with_read_access,
                                                                   repository: @repo,
                                                                   permissions: { statuses: "read" }

    @org_installation_with_write_access = make_integration_installation integration: @org_integration_with_write_access,
                                                                   target: @org,
                                                                   permissions: { statuses: "write" }

    @org_installation_with_read_access = make_integration_installation integration: @org_integration_with_read_access,
                                                                  target: @org,
                                                                  permissions: { statuses: "read" }

    @commit_status_1 = create :status, repository: @repo, context: "check-def", creator: @repo_integration_with_read_access.bot, created_at: Date.yesterday
    @commit_status_2 = create :status, repository: @repo, context: "check-def", creator: @repo_integration_with_write_access.bot
    @commit_status_3 = create :status, repository: @repo, context: "check-abc", creator: @repo_integration_with_read_access.bot

    @status = create :status, repository: @repo, context: "test"

    @deployment_environment_1 = create :environment, repository: @repo, name: "development"
    @deployment_environment_2 = create :environment, repository: @repo, name: "production"
  end

  test "returns integrations with write access for a repository" do
    integrations = RulesEngine::Suggestions.status_check_integrations_for(@repo)

    assert_equal 1, integrations.length

    integration = T.must(integrations.first)
    assert_equal @repo_integration_with_write_access.id, integration[:id]
    assert_equal @repo_integration_with_write_access.name, integration[:name]
    assert_equal @repo_integration_with_write_access.preferred_avatar_url, integration[:preferred_avatar_url]
  end

  test "returns integrations associated with pre-existing required status check rules for repository ruleset" do
    ruleset = create :repository_ruleset, source: @repo

    rule_config = build(
      :repository_rule_configuration,
      repository_ruleset: ruleset,
      rule_type: "required_status_checks",
      parameters: {
        strict_required_status_checks_policy: false,
        required_status_checks: [{
          "context": "test",
          integration_id: @repo_integration_with_read_access.id
        }]
      })

    rule_config.save!(validate: false)

    integrations = RulesEngine::Suggestions.status_check_integrations_for(@repo, ruleset_id: ruleset.id)
    assert_equal 2, integrations.length

    integration_1 = T.must(integrations.first)
    assert_equal @repo_integration_with_read_access.id, integration_1[:id]
    assert_equal @repo_integration_with_read_access.name, integration_1[:name]
    assert_equal @repo_integration_with_read_access.preferred_avatar_url, integration_1[:preferred_avatar_url]

    integration_2 = T.must(integrations.second)
    assert_equal @repo_integration_with_write_access.id, integration_2[:id]
    assert_equal @repo_integration_with_write_access.name, integration_2[:name]
    assert_equal @repo_integration_with_write_access.preferred_avatar_url, integration_2[:preferred_avatar_url]

  end

  test "returns integrations associated with pre-existing required status check rules for inherited ruleset" do
    ruleset = create :repository_ruleset, source: @org
    create(:repository_rule_condition, :targets_repo, repo_name: @org_repo.name, repository_ruleset: ruleset)

    rule_config = build(
      :repository_rule_configuration,
      repository_ruleset: ruleset,
      rule_type: "required_status_checks",
      parameters: {
        strict_required_status_checks_policy: false,
        required_status_checks: [{
          "context": "test",
          integration_id: @org_integration_with_read_access.id
        }]
      })

    rule_config.save!(validate: false)

    integrations = RulesEngine::Suggestions.status_check_integrations_for(@org_repo, ruleset_id: ruleset.id)
    assert_equal 2, integrations.length

    integration_1 = T.must(integrations.first)
    assert_equal @org_integration_with_read_access.id, integration_1[:id]
    assert_equal @org_integration_with_read_access.name, integration_1[:name]
    assert_equal @org_integration_with_read_access.preferred_avatar_url, integration_1[:preferred_avatar_url]

    integration_2 = T.must(integrations.second)
    assert_equal @org_integration_with_write_access.id, integration_2[:id]
    assert_equal @org_integration_with_write_access.name, integration_2[:name]
    assert_equal @org_integration_with_write_access.preferred_avatar_url, integration_2[:preferred_avatar_url]

  end

  test "returns integrations with write access for an organization" do
    integrations = RulesEngine::Suggestions.status_check_integrations_for(@org)

    assert_equal 1, integrations.length

    integration = T.must(integrations.first)
    assert_equal @org_integration_with_write_access.id, integration[:id]
    assert_equal @org_integration_with_write_access.name, integration[:name]
    assert_equal @org_integration_with_write_access.preferred_avatar_url, integration[:preferred_avatar_url]
  end

  test "returns integrations associated with pre-existing required status check rules for organization ruleset" do
    ruleset = create :repository_ruleset, source: @org

    rule_config = build(
      :repository_rule_configuration,
      repository_ruleset: ruleset,
      rule_type: "required_status_checks",
      parameters: {
        strict_required_status_checks_policy: false,
        required_status_checks: [{
          "context": "test",
          integration_id: @org_integration_with_read_access.id
        }]
      })

    rule_config.save!(validate: false)

    integrations = RulesEngine::Suggestions.status_check_integrations_for(@org, ruleset_id: ruleset.id)
    assert_equal 2, integrations.length

    integration1 = T.must(integrations.first)
    assert_equal @org_integration_with_read_access.id, integration1[:id]
    assert_equal @org_integration_with_read_access.name, integration1[:name]
    assert_equal @org_integration_with_read_access.preferred_avatar_url, integration1[:preferred_avatar_url]

    integration2 = T.must(integrations.second)
    assert_equal @org_integration_with_write_access.id, integration2[:id]
    assert_equal @org_integration_with_write_access.name, integration2[:name]
    assert_equal @org_integration_with_write_access.preferred_avatar_url, integration2[:preferred_avatar_url]

  end

  test "removes installations without integrations" do
    deleted_integration = create :integration, name: "delete-me"
    org_installation_with_write_access_and_without_an_integration =
      make_integration_installation integration: deleted_integration,
        target: @org,
        permissions: { statuses: "write" }

    deleted_integration.delete
    check_integrations =
      RulesEngine::Suggestions
      .status_check_integrations_for(org_installation_with_write_access_and_without_an_integration.organization)

    # 2 candidate installations - one with an integration, one without
    assert_equal 1, check_integrations.length
  end

  test "returns recent status checks for an repository" do
    status_checks = RulesEngine::Suggestions.recent_status_checks_for(@repo, "check")

    assert_equal 2, status_checks.length

    status_check_1 = T.must(status_checks.first)
    assert_equal "check-abc", status_check_1[:context]
    assert_equal @repo_integration_with_read_access.id, status_check_1[:latest_integration_id]

    status_check_2 = T.must(status_checks.second)
    assert_equal "check-def", status_check_2[:context]
    assert_equal @repo_integration_with_write_access.id, status_check_2[:latest_integration_id]
  end

  test "returns no status checks for an organization" do
    status_checks = RulesEngine::Suggestions.recent_status_checks_for(@org, "test")

    assert_equal 0, status_checks.length
  end

  test "returns deployment environments for a repository" do
    deployment_environments = RulesEngine::Suggestions.deployment_environments_for(@repo, "development")

    assert_equal 1, deployment_environments.length

    deployment_environment = T.must(deployment_environments.first)

    assert_equal @deployment_environment_1.name, deployment_environment
  end

  test "returns no deployment environments for an organization" do
    deployment_environments = RulesEngine::Suggestions.deployment_environments_for(@org, "development")

    assert_equal 0, deployment_environments.length
  end

  context "insights_users_for" do
    test "returns User who ran evaluation for a repository" do
      ref_update = create_branch_update(@repo, name: "main")
      RuleEngine::RuleSuite.for_ref_update(ref_update:, rule_runs: [], actor: @repo.owner).save!

      actors = RulesEngine::Suggestions.insights_users_for(@repo)

      assert_equal 1, actors.size
      assert_equal @repo.owner, actors.first
    end

    test "returns User who ran evaluation for an organization" do
      org_repo = create(:repository, owner: @org)

      ref_update = create_branch_update(org_repo, name: "main")
      RuleEngine::RuleSuite.for_ref_update(ref_update:, rule_runs: [], actor: @org.admin).save!

      actors = RulesEngine::Suggestions.insights_users_for(@org)

      assert_equal 1, actors.size
      assert_equal @org.admin, actors.first
    end

    test "returns user when user's PublicKey is used for evaluation" do
      key = create(:public_key, user: @repo.owner)

      ref_update = create_branch_update(@repo, name: "main")
      RuleEngine::RuleSuite.for_ref_update(ref_update:, rule_runs: [], actor: key).save!

      actors = RulesEngine::Suggestions.insights_users_for(@repo)

      assert_equal 1, actors.size
      assert_equal @repo.owner, actors.first
    end

    test "returns verifier when a deploy key is used for evaluation" do
      key = create(:public_key, repository: @repo, verifier: @repo.owner)

      ref_update = create_branch_update(@repo, name: "main")
      RuleEngine::RuleSuite.for_ref_update(ref_update:, rule_runs: [], actor: key).save!

      actors = RulesEngine::Suggestions.insights_users_for(@repo)

      assert_equal 1, actors.size
      assert_equal @repo.owner, actors.first
    end
  end

  context "teams_for" do
    test "returns Teams associated with the given org" do
      team = create(:team, name: "Team 1", organization: @org, privacy: :closed)

      teams = TeamBypassActor.suggest_bypassers(@org, @org.owner, nil)
      assert_equal 1, teams.size
      assert_equal team.id, teams[0]&.actor_id
    end

    test "returns Teams associated with the given repo" do
      team = create(:team, name: "Team 1", organization: @org, privacy: :closed)
      repo = create(:repository, owner: @org, organization: @org)

      teams = TeamBypassActor.suggest_bypassers(repo, repo.owner, nil)

      assert_equal 1, teams.size
      assert_equal team.id, teams[0]&.actor_id
    end

    test "returns Teams up to the given limit" do
      team = create(:team, name: "Team 1", organization: @org, privacy: :closed)
      team = create(:team, name: "Team 2", organization: @org, privacy: :closed)
      team = create(:team, name: "Team 3", organization: @org, privacy: :closed)
      repo = create(:repository, owner: @org, organization: @org)

      teams = TeamBypassActor.suggest_bypassers(repo, repo.owner, nil, limit: 2)

      assert_equal 2, teams.size
    end

    test "returns only non-secret Teams" do
      team_public_1 = create(:team, name: "Team public 1", organization: @org, privacy: :closed)
      team_public_2 = create(:team, name: "Team public 2", organization: @org, privacy: :closed)
      create(:team, name: "Team secret", organization: @org, privacy: :secret)

      teams = TeamBypassActor.suggest_bypassers(@org, @org.owner, nil)

      assert_equal 2, teams.size
      assert_equal team_public_1.id, teams[0]&.actor_id
      assert_equal team_public_2.id, teams[1]&.actor_id
    end

    test "returns Teams that match a given substring by name" do
      team_a = create(:team, name: "aaaaaa", organization: @org, privacy: :closed)
      team_b = create(:team, name: "bbbbbb", organization: @org, privacy: :closed)
      team_c = create(:team, name: "cccccc", organization: @org, privacy: :closed)
      team_abc = create(:team, name: "aabbcc", organization: @org, privacy: :closed)

      teams = TeamBypassActor.suggest_bypassers(@org, @org.owner, "aaaa")

      assert_equal 1, teams.size
      assert_equal team_a.id, teams[0]&.actor_id

      teams = TeamBypassActor.suggest_bypassers(@org, @org.owner, "cccc")

      assert_equal 1, teams.size
      assert_equal team_c.id, teams[0]&.actor_id

      team_ids = TeamBypassActor.suggest_bypassers(@org, @org.owner, "b").map { |t| t.actor_id }

      assert_equal 2, team_ids.count
      assert team_ids.include?(team_b.id)
      assert team_ids.include?(team_abc.id)
    end

    test "returns Teams that match regardless of casing" do
      team_a = create(:team, name: "AAAAA", organization: @org, privacy: :closed)
      team_b = create(:team, name: "bbbbbb", organization: @org, privacy: :closed)
      team_c = create(:team, name: "CcCcCc", organization: @org, privacy: :closed)
      team_b = create(:team, name: "AAABBBCCC", organization: @org, privacy: :closed)

      teams = TeamBypassActor.suggest_bypassers(@org, @org.owner, "aaaa")

      assert_equal 1, teams.size
      assert_equal team_a.id, teams[0]&.actor_id

      teams = TeamBypassActor.suggest_bypassers(@org, @org.owner, "CCCCCC")

      assert_equal 1, teams.size
      assert_equal team_c.id, teams[0]&.actor_id

      team_ids = TeamBypassActor.suggest_bypassers(@org, @org.owner, "B").map { |t| t.actor_id }

      assert_equal 2, team_ids.count
      assert team_ids.include?(team_b.id)
    end

    test "returns Teams from the organization of a user-owned repo if it exists" do
      # set up org
      @org.allow_private_repository_forking(actor: @org.admins.first)

      # set up user
      user = create(:user)
      @org.add_member(user)

      # set up org-owned repo
      private_repo = create(:private_repository, owner: @org)
      private_repo.add_member_without_validation_or_notifications(user)

      # fork repo & ensure user cannot bill to org
      repo = create(:fork_repository, forker: user, fork_repo: private_repo)

      team_a = create(:team, name: "AAAAA", organization: @org, privacy: :closed)
      team_b = create(:team, name: "bbbbbb", organization: @org, privacy: :closed)
      team_c = create(:team, name: "CcCcCc", organization: @org, privacy: :closed)
      team_b = create(:team, name: "AAABBBCCC", organization: @org, privacy: :closed)

      teams = TeamBypassActor.suggest_bypassers(repo, user, nil)

      assert_equal 4, teams.size

      teams = TeamBypassActor.suggest_bypassers(repo, user, "CCCCCC")

      assert_equal 1, teams.size
      assert_equal team_c.id, teams[0]&.actor_id
    end
  end

  context "bypass_actors_for" do
    test "returns only allowed base roles" do
      bypass_actors = RulesEngine::Suggestions.bypass_actors_for(@org, @org.owner)

      roles = bypass_actors.filter { |bypass_actor| bypass_actor[:actorType] == :RepositoryRole }

      assert_equal 3, roles.size
      role_names = roles.map { |role| role[:name] }

      assert_includes role_names, "Repository admin"
      assert_includes role_names, "Write"
      assert_includes role_names, "Maintain"
      refute_includes role_names, "Read"
      refute_includes role_names, "Triage"
    end
    test "never returns roles that aren't allowlisted" do
      roles = RulesEngine::Suggestions.bypass_actors_for(@org, @org.owner, query: "Read")
        .filter { |bypass_actor| bypass_actor[:actorType] == :RepositoryRole }
        .map { |role| role[:name] }

      refute_includes roles, "Read"

      roles = RulesEngine::Suggestions.bypass_actors_for(@org, @org.owner, query: "Triage")
        .filter { |bypass_actor| bypass_actor[:actorType] == :RepositoryRole }
        .map { |role| role[:name] }

      refute_includes roles, "Triage"
    end
    test "returns org admin as an OrganizationAdmin" do
      bypass_actors = RulesEngine::Suggestions.bypass_actors_for(@org, @org.owner)

      org_admin = bypass_actors.find { |bypass_actor| bypass_actor[:actorType] == :OrganizationAdmin }

      refute_nil org_admin
      assert_equal "Organization admin", T.must(org_admin)[:name]
    end
    test "returns deploy key" do
      bypass_actors = RulesEngine::Suggestions.bypass_actors_for(@org, @org.owner)

      deploy_key = bypass_actors.find { |bypass_actor| bypass_actor[:actorType] == :DeployKey }

      refute_nil deploy_key
      assert_nil T.must(deploy_key)[:actorId]
      assert_equal "Deploy keys", T.must(deploy_key)[:name]
    end
  end
end
