# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryRulesetBypassTest < GitHub::TestCase
  include RepositoriesTestHelper
  include RulesEngine::RefUpdateTestHelper

  MODE_ANY = RepositoryRulesetBypassActor::BYPASS_MODES[:any]
  private_constant :MODE_ANY
  MODE_PULL_REQUEST = RepositoryRulesetBypassActor::BYPASS_MODES[:pull_request]
  private_constant :MODE_PULL_REQUEST

  fixtures do
    @org_admin = create(:user)
    @org = create(:business_plus_organization, admin: @org_admin)

    @repo = create(:repository, owner: @org, from_example: :simple)

    @repo_admin = create(:user)
    @repo.add_member @repo_admin, action: :admin

    @repo_maintainer = create(:user)
    @repo.add_member @repo_maintainer, action: :maintain

    @repo_writer = create(:user)
    @repo.add_member @repo_writer, action: :write

    @repo_reader = create(:user)
    @repo.add_member @repo_reader, action: :read

    @team = create(:team, organization: @org, privacy: :closed)
    @team.add_repository @repo, :read

    @team_member = create(:user)
    @team.add_member @team_member

    permissions = { "metadata" => :read, "contents" => :write }

    @app = create(:integration, default_permissions: permissions)
    @bot = create(:bot, integration: @app)
    make_integration_installation(integration: @bot.integration, repository: @repo)
  end

  setup do
    # Enables the max_file_path_length rule
    GitHub.flipper[:push_rulesets].enable
  end

  context "User inherits different bypass modes from multiple scopes" do
    test "org admins have no explicit bypass mode, but repo admins can bypsss" do
      ruleset = create(:repository_ruleset, :targets_default_branch, source: @repo, bypass_mode: :no_org_bypass)
      rule_config = create(:repository_rule_configuration,
        :pull_request, required_approving_review_count: 1,
        repository_ruleset: ruleset)
      create(:repository_ruleset_bypass_actor, :repo_admin, bypass_mode: MODE_ANY, repository_ruleset: ruleset)

      merge_commit = @repo.commits.create_merge_commit(@org_admin, "master", "cr-line-endings").first
      ref_update = create_branch_update(@repo, name: "master",
        before_oid: merge_commit.parent_oids.first, after_oid: merge_commit.oid)

      # Even though :no_org_bypass is set, org admins are also repo admins, so they have 'any' permission.
      [@org_admin, @repo_admin].each do |user|
        decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, user)
        refute_predicate decision, :rules_fulfilled?
        assert decision.can_bypass_rule_type?(:pull_request)
      end

      [@repo_maintainer, @repo_writer, @team_member, @bot, @repo_reader].each do |user|
        decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, user)
        refute_predicate decision, :rules_fulfilled?
        refute decision.can_bypass_rule_type?(:pull_request)
      end
    end

    test "'PR-required' permission at one scope will not block 'any' permission from a different scope" do
      ruleset = create(:repository_ruleset, :targets_default_branch, source: @repo, bypass_mode: :org_bypass_prs_only)
      rule_config = create(:repository_rule_configuration,
        :pull_request, required_approving_review_count: 1,
        repository_ruleset: ruleset)
      create(:repository_ruleset_bypass_actor, :repo_maintain, bypass_mode: MODE_PULL_REQUEST, repository_ruleset: ruleset)
      create(:repository_ruleset_bypass_actor, :repo_write, bypass_mode: MODE_ANY, repository_ruleset: ruleset)

      merge_commit = @repo.commits.create_merge_commit(@org_admin, "master", "cr-line-endings").first
      ref_update = create_branch_update(@repo, name: "master",
        before_oid: merge_commit.parent_oids.first, after_oid: merge_commit.oid)

      # Even though org-admin and repo-maintainer modes require a PR, everyone with write permission also has mode 'any'.
      # Admins and maintainers will have both 'PR' and 'any' bypass modes, and will be able to bypass even with no PR.
      # Even though :no_org_bypass is set, org admins are also repo admins, so they have 'any' permission.
      [@org_admin, @repo_admin, @repo_maintainer, @repo_writer].each do |user|
        decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, user)
        refute_predicate decision, :rules_fulfilled?
        assert decision.can_bypass_rule_type?(:pull_request)
      end

      [@team_member, @bot, @repo_reader].each do |user|
        decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, user)
        refute_predicate decision, :rules_fulfilled?
        refute decision.can_bypass_rule_type?(:pull_request)
      end
    end
  end

  context "Test ruleset column for org admin bypass mode" do
    test "Org admins not allowed to bypass" do
      ruleset = create(:repository_ruleset, :targets_default_branch, source: @repo, bypass_mode: :no_org_bypass)
      rule_config = create(:repository_rule_configuration,
        :pull_request, required_approving_review_count: 1,
        repository_ruleset: ruleset)

      merge_commit = @repo.commits.create_merge_commit(@org_admin, "master", "cr-line-endings").first
      ref_update = create_branch_update(@repo, name: "master",
        before_oid: merge_commit.parent_oids.first, after_oid: merge_commit.oid)

      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @org_admin)
      refute_predicate decision, :rules_fulfilled?

      # Bypass denied via push
      refute decision.can_bypass_rule_type?(:pull_request)

      pull = PullRequest.create_for!(@repo, user: @org_admin,
        base: "master", head: "cr-line-endings", title: "convert to CR line ending")
      pr_ref_update = Git::Branch::Update.new(repository: @repo, refname: "refs/heads/#{pull.base_ref_name}",
          before_oid:  merge_commit.parent_oids.first, after_oid: merge_commit.oid,
          pull_request: pull)

      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, pr_ref_update, @org_admin)
      refute_predicate decision, :rules_fulfilled?

      # Bypass denied via PR
      refute decision.can_bypass_rule_type?(:pull_request)
    end

    test "Org admins allowed to bypass only via PR" do
      ruleset = create(:repository_ruleset, :targets_default_branch, source: @repo, bypass_mode: :org_bypass_prs_only)
      rule_config = create(:repository_rule_configuration,
        :pull_request, required_approving_review_count: 1,
        repository_ruleset: ruleset)

      merge_commit = @repo.commits.create_merge_commit(@org_admin, "master", "cr-line-endings").first
      ref_update = create_branch_update(@repo, name: "master",
        before_oid: merge_commit.parent_oids.first, after_oid: merge_commit.oid)

      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @org_admin)
      refute_predicate decision, :rules_fulfilled?

      # Bypass denied via push
      refute decision.can_bypass_rule_type?(:pull_request)

      pull = PullRequest.create_for!(@repo, user: @org_admin,
        base: "master", head: "cr-line-endings", title: "convert to CR line ending")
      pr_ref_update = Git::Branch::Update.new(repository: @repo, refname: "refs/heads/#{pull.base_ref_name}",
          before_oid:  merge_commit.parent_oids.first, after_oid: merge_commit.oid,
          pull_request: pull)

      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, pr_ref_update, @org_admin)
      refute_predicate decision, :rules_fulfilled?

      # Bypass allowed via PR
      assert decision.can_bypass_rule_type?(:pull_request)
    end

    test "Org admins allowed to bypass via PR or push" do
      ruleset = create(:repository_ruleset, :targets_default_branch, source: @repo, bypass_mode: :org_bypass_any)
      rule_config = create(:repository_rule_configuration,
        :pull_request, required_approving_review_count: 1,
        repository_ruleset: ruleset)

      merge_commit = @repo.commits.create_merge_commit(@org_admin, "master", "cr-line-endings").first
      ref_update = create_branch_update(@repo, name: "master",
        before_oid: merge_commit.parent_oids.first, after_oid: merge_commit.oid)

      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @org_admin)
      refute_predicate decision, :rules_fulfilled?

      # Bypass allowed via push
      assert decision.can_bypass_rule_type?(:pull_request)

      pull = PullRequest.create_for!(@repo, user: @org_admin,
        base: "master", head: "cr-line-endings", title: "convert to CR line ending")
      pr_ref_update = Git::Branch::Update.new(repository: @repo, refname: "refs/heads/#{pull.base_ref_name}",
          before_oid:  merge_commit.parent_oids.first, after_oid: merge_commit.oid,
          pull_request: pull)

      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, pr_ref_update, @org_admin)
      refute_predicate decision, :rules_fulfilled?

      # Bypass allowed via PR
      assert decision.can_bypass_rule_type?(:pull_request)
    end
  end

  context "Bypass is not allowed" do
    test "and user pushes directly" do
      ruleset = create(:repository_ruleset, :targets_default_branch, source: @repo, bypass_mode: :no_org_bypass)
      rule_config = create(:repository_rule_configuration,
        :pull_request, required_approving_review_count: 1,
        repository_ruleset: ruleset)

      merge_commit = @repo.commits.create_merge_commit(@org_admin, "master", "cr-line-endings").first
      ref_update = create_branch_update(@repo, name: "master",
        before_oid: merge_commit.parent_oids.first, after_oid: merge_commit.oid)

      [@org_admin, @repo_admin, @repo_maintainer, @repo_writer, @team_member, @bot, @repo_reader].each do |user|
        decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, user)
        refute_predicate decision, :rules_fulfilled?
        refute decision.can_bypass_rule_type?(:pull_request)
      end
    end

    test "and PR is used" do
      ruleset = create(:repository_ruleset, :targets_default_branch, source: @repo, bypass_mode: :no_org_bypass)
      rule_config = create(:repository_rule_configuration,
        :pull_request, required_approving_review_count: 1,
        repository_ruleset: ruleset)

      pull = PullRequest.create_for!(@repo, user: @org_admin,
        base: "master", head: "cr-line-endings", title: "convert to CR line ending")
      merge_commit = @repo.commits.create_merge_commit(@org_admin, "master", "cr-line-endings").first
      ref_update = Git::Branch::Update.new(repository: @repo, refname: "refs/heads/#{pull.base_ref_name}",
          before_oid:  merge_commit.parent_oids.first, after_oid: merge_commit.oid,
          pull_request: pull)

      [@org_admin, @repo_admin, @repo_maintainer, @repo_writer, @team_member, @bot, @repo_reader].each do |user|
        decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, user)
        refute_predicate decision, :rules_fulfilled?
        refute decision.can_bypass_rule_type?(:pull_request)
      end
    end
  end

  context "Bypass is allowed via any means" do
    test "and user pushes directly" do
      ruleset = create(:repository_ruleset, :targets_default_branch, source: @repo, bypass_mode: :org_bypass_any)
      rule_config = create(:repository_rule_configuration,
        :pull_request, required_approving_review_count: 1,
        repository_ruleset: ruleset)
      create(:repository_ruleset_bypass_actor, :repo_write, bypass_mode: MODE_ANY, repository_ruleset: ruleset)
      create(:repository_ruleset_bypass_actor, actor_type: "Team", actor_id: @team.id, bypass_mode: MODE_ANY, repository_ruleset: ruleset)
      create(:repository_ruleset_bypass_actor, actor_type: "Integration", actor_id: @app.id, bypass_mode: MODE_ANY, repository_ruleset: ruleset)

      merge_commit = @repo.commits.create_merge_commit(@org_admin, "master", "cr-line-endings").first
      ref_update = create_branch_update(@repo, name: "master",
        before_oid: merge_commit.parent_oids.first, after_oid: merge_commit.oid)

      [@org_admin, @repo_admin, @repo_maintainer, @repo_writer, @team_member, @bot].each do |user|
        decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, user)
        refute_predicate decision, :rules_fulfilled?
        assert decision.can_bypass_rule_type?(:pull_request)
      end

      [@repo_reader].each do |user|
        decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, user)
        refute_predicate decision, :rules_fulfilled?
        refute decision.can_bypass_rule_type?(:pull_request)
      end
    end

    test "and PR is used" do
      ruleset = create(:repository_ruleset, :targets_default_branch, source: @repo, bypass_mode: :org_bypass_any)
      rule_config = create(:repository_rule_configuration,
        :pull_request, required_approving_review_count: 1,
        repository_ruleset: ruleset)
      create(:repository_ruleset_bypass_actor, :repo_write, bypass_mode: MODE_ANY, repository_ruleset: ruleset)
      create(:repository_ruleset_bypass_actor, actor_type: "Team", actor_id: @team.id, bypass_mode: MODE_ANY, repository_ruleset: ruleset)
      create(:repository_ruleset_bypass_actor, actor_type: "Integration", actor_id: @app.id, bypass_mode: MODE_ANY, repository_ruleset: ruleset)

      pull = PullRequest.create_for!(@repo, user: @org_admin,
        base: "master", head: "cr-line-endings", title: "convert to CR line ending")
      merge_commit = @repo.commits.create_merge_commit(@org_admin, "master", "cr-line-endings").first
      ref_update = Git::Branch::Update.new(repository: @repo, refname: "refs/heads/#{pull.base_ref_name}",
          before_oid:  merge_commit.parent_oids.first, after_oid: merge_commit.oid,
          pull_request: pull)

      [@org_admin, @repo_admin, @repo_maintainer, @repo_writer, @team_member, @bot].each do |user|
        decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, user)
        refute_predicate decision, :rules_fulfilled?
        assert decision.can_bypass_rule_type?(:pull_request)
      end

      [@repo_reader].each do |user|
        decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, user)
        refute_predicate decision, :rules_fulfilled?
        refute decision.can_bypass_rule_type?(:pull_request)
      end
    end
  end

  context "Bypass is only allowed via PR" do
    test "but user attempts to push directly" do
      ruleset = create(:repository_ruleset, :targets_default_branch, source: @repo, bypass_mode: :org_bypass_prs_only)
      rule_config = create(:repository_rule_configuration,
        :pull_request, required_approving_review_count: 1,
        repository_ruleset: ruleset)
      create(:repository_ruleset_bypass_actor, :repo_write, bypass_mode: MODE_PULL_REQUEST, repository_ruleset: ruleset)
      create(:repository_ruleset_bypass_actor, actor_type: "Team", actor_id: @team.id, bypass_mode: MODE_PULL_REQUEST, repository_ruleset: ruleset)
      create(:repository_ruleset_bypass_actor, actor_type: "Integration", actor_id: @app.id, bypass_mode: MODE_PULL_REQUEST, repository_ruleset: ruleset)

      merge_commit = @repo.commits.create_merge_commit(@org_admin, "master", "cr-line-endings").first
      ref_update = create_branch_update(@repo, name: "master",
        before_oid: merge_commit.parent_oids.first, after_oid: merge_commit.oid)

      [@org_admin, @repo_admin, @repo_maintainer, @repo_writer, @team_member, @bot, @repo_reader].each do |user|
        decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, user)
        refute_predicate decision, :rules_fulfilled?
        refute decision.can_bypass_rule_type?(:pull_request)
      end
    end

    test "and PR is used" do
      ruleset = create(:repository_ruleset, :targets_default_branch, source: @repo, bypass_mode: :org_bypass_prs_only)
      rule_config = create(:repository_rule_configuration,
        :pull_request, required_approving_review_count: 1,
        repository_ruleset: ruleset)
      create(:repository_ruleset_bypass_actor, :repo_write, bypass_mode: MODE_PULL_REQUEST, repository_ruleset: ruleset)
      create(:repository_ruleset_bypass_actor, actor_type: "Team", actor_id: @team.id, bypass_mode: MODE_PULL_REQUEST, repository_ruleset: ruleset)
      create(:repository_ruleset_bypass_actor, actor_type: "Integration", actor_id: @app.id, bypass_mode: MODE_PULL_REQUEST, repository_ruleset: ruleset)

      pull = PullRequest.create_for!(@repo, user: @org_admin,
        base: "master", head: "cr-line-endings", title: "convert to CR line ending")
      merge_commit = @repo.commits.create_merge_commit(@org_admin, "master", "cr-line-endings").first
      ref_update = Git::Branch::Update.new(repository: @repo, refname: "refs/heads/#{pull.base_ref_name}",
          before_oid:  merge_commit.parent_oids.first, after_oid: merge_commit.oid,
          pull_request: pull)

      [@org_admin, @repo_admin, @repo_maintainer, @repo_writer, @team_member, @bot].each do |user|
        decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, user)
        refute_predicate decision, :rules_fulfilled?
        assert decision.can_bypass_rule_type?(:pull_request)
      end

      [@repo_reader].each do |user|
        decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, user)
        refute_predicate decision, :rules_fulfilled?
        refute decision.can_bypass_rule_type?(:pull_request)
      end
    end
  end
end
