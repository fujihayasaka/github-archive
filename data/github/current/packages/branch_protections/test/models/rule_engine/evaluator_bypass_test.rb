# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/spokesd"
require "test_helpers/dependabot_github_app_helper"

class RuleEngineEvaluatorBypassTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper
  include RulesEngine::BypassTestHelper
  include GpgKeyHelper

  Spokesd.share_spokesdb(self)

  fixtures do
    @biz_owner = create(:user, plan: "business_plus")
    @business = Business.first || create(:business, owners: [@biz_owner])
    @biz_org = create(:business_plus_organization, name: "biz-org", admin: @biz_owner, business: @business)
    @another_biz_org = create(:business_plus_organization, name: "biz-org-2", admin: @biz_owner, business: @business)
    @biz_org.allow_private_repository_forking(actor: @biz_org.admin, policy: Configurable::AllowPrivateRepositoryForking::EVERYWHERE)
    @biz_org_repo = create(:private_repository, owner: @biz_org, from_example: :simple)

    @owner = create(:user, plan: "business_plus")
    @repo_admin = create(:user, plan: "business_plus")
    @repo = create(:private_repository, owner: @owner, from_example: :simple)

    signing_key = create_gpg_key
    @user = signing_key.user

    @repo.add_member @user, action: :write

    @org_admin = create(:user)
    @org = create(:business_plus_organization, name: "org1", admin: @org_admin)
    @org.allow_private_repository_forking(actor: @org.admin, policy: Configurable::AllowPrivateRepositoryForking::EVERYWHERE)

    @org_member = create(:user)
    @org.add_member(@org_member)
    @org_repo = create(:private_repository, owner: @org, from_example: :simple)
    @org_repo.add_member(@org_member, action: :write)
    @org_repo.add_member(@org_admin, action: :admin)

    @team = create(:team, organization: @org, privacy: :closed)
    @team.add_member @org_admin
    @team.add_repository @org_repo, :admin

    @bot = create(:integration, owner: @user).bot
    make_integration_installation(integration: @bot.integration, repository: @repo, permissions: { "contents" => :write })

    ca = FakeCA.new("/CN=root1")
    @cert = ca.issue("/CN=#{@user.login}/emailAddress=#{@user.emails.verified.first.email}").freeze
    GitHub.git_signing_smime_cert_store.add_cert(ca.parsed)
    example_repo_snapshot
  end

  setup do
    Failbot.expects(:report).never

    example_repo_restore

    GitHub.flipper[:rules_engine_result_validation].enable

    Spokesd.enable_spokesd

    @ref_updates = [create_ref_update(@repo)]
    @org_repo_ref_updates = [create_ref_update(@org_repo)]
  end

  test "allows bypass for bypass_actor: Team / actor: team member" do
    ruleset, ref_update = simple_ref_update_setup(@org_repo, @org_admin)

    validate_bypass_allowed(@org_repo, ref_update, @org_admin) do
      RepositoryRulesetBypassActor.new(
        repository_ruleset: ruleset,
        actor: @team
      ).save!
    end
  end

  test "allows bypass for enterprise team bypass_actor" do
    GitHub.flipper[:enterprise_teams_enabled_for_organizations].enable
    GitHub.flipper[:enterprise_rulesets].enable
    GitHub.flipper[:member_privilege_rulesets].enable

    user = create(:user)
    enterprise_team = create(:enterprise_team, business: @business)
    enterprise_team_membership = EnterpriseTeamMembership.create!(enterprise_team: enterprise_team, user: user)

    ruleset = create(:repository_ruleset, :targets_all_orgs, :targets_all_repos, source: @business, target: "repository")
    config = create(:repository_rule_configuration, rule_type: "repository_delete", repository_ruleset: ruleset)

    event = RuleEngine::Events::RepositoryOperationEvent.new(@biz_org_repo, user, { delete: nil }, persist_results: false)

    rule_suite = T.must(RuleEngine::GenericEvaluator.evaluate_rules(event).first)
    refute rule_suite.rules_fulfilled?, "Expected rules to be failing"
    refute rule_suite.action_permitted?, "Expected bypass to be denied before bypass is added"

    @biz_org_repo.enable_feature(:enterprise_rulesets_enterprise_teams)
    bypass_actor = RepositoryRulesetBypassActor.create(
      actor: enterprise_team,
      repository_ruleset: ruleset
    )

    @biz_org_repo.disable_feature(:enterprise_rulesets_enterprise_teams)
    rule_suite = T.must(RuleEngine::GenericEvaluator.evaluate_rules(event).first)
    refute rule_suite.rules_fulfilled?, "Expected rules to be failing"
    refute rule_suite.action_permitted?, "Expected bypass to be denied before FF is enabled"

    @biz_org_repo.enable_feature(:enterprise_rulesets_enterprise_teams)
    rule_suite = T.must(RuleEngine::GenericEvaluator.evaluate_rules(event).first)
    refute rule_suite.rules_fulfilled?, "Expected rules to be failing"
    assert rule_suite.action_permitted?, "Expected bypass to be pass"
  end

  test "allows bypass for bypass_actor: repo admin role / actor: repo admin role" do
    ruleset, ref_update = simple_ref_update_setup(@org_repo, @org_admin)

    validate_bypass_allowed(@org_repo, ref_update, @org_admin) do
      RepositoryRulesetBypassActor.new(
        repository_ruleset: ruleset,
        actor: RepositoryRole.find_by(name: "admin", owner: nil)
      ).save!
    end
  end

  test "denies bypass for direct commit bypass_actor: repo admin role (PR only) / actor: repo admin role" do
    ruleset, ref_update = simple_ref_update_setup(@org_repo, @org_admin)

    validate_bypass_denied(@org_repo, ref_update, @org_admin) do
      RepositoryRulesetBypassActor.new(
        repository_ruleset: ruleset,
        actor: RepositoryRole.find_by(name: "admin", owner: nil),
        bypass_mode: RepositoryRulesetBypassActor::BYPASS_MODES[:pull_request]
      ).save!
    end
  end

  test "denies bypass for bypass_actor: repo admin role / actor: write role" do
    ruleset, ref_update = simple_ref_update_setup(@org_repo, @org_member)

    validate_bypass_denied(@org_repo, ref_update, @org_member) do
      RepositoryRulesetBypassActor.new(
        repository_ruleset: ruleset,
        actor: RepositoryRole.find_by(name: "admin", owner: nil),
      ).save!
    end
  end

  test "allows bypass for bypass_actor: org admin / actor: org admin" do
    ruleset, ref_update = simple_ref_update_setup(@org_repo, @org_admin)

    validate_bypass_allowed(@org_repo, ref_update, @org_admin) do
      ruleset.bypass_mode = :org_bypass_any
      ruleset.save!
    end
  end

  test "denies bypass for direct commit bypass_actor: org admin (PR only) / actor: org admin" do
    ruleset, ref_update = simple_ref_update_setup(@org_repo, @org_admin)

    validate_bypass_denied(@org_repo, ref_update, @org_admin) do
      ruleset.bypass_mode = :org_bypass_prs_only
      ruleset.save!
    end
  end

  test "allows bypass for bypass_actor: write role / actor: write role" do
    ruleset, ref_update = simple_ref_update_setup(@org_repo, @org_member)

    validate_bypass_allowed(@org_repo, ref_update, @org_member) do
      RepositoryRulesetBypassActor.new(
        repository_ruleset: ruleset,
        actor: RepositoryRole.find_by(name: "write", owner: nil),
      ).save!
    end
  end

  test "allows bypass for bypass_actor: admin role / actor: write deploy key" do
    write_deploy_key = create :public_key, repository: @org_repo, read_only: false

    ruleset, ref_update = simple_ref_update_setup(@org_repo, @org_admin)

    validate_bypass_allowed(@org_repo, ref_update, write_deploy_key) do
      create(:repository_ruleset_bypass_actor, :repo_admin, bypass_mode: "any", repository_ruleset: ruleset)
    end
  end

  test "denies bypass for bypass_actor: admin role / actor: read deploy key" do
    read_deploy_key = create :public_key, repository: @org_repo, read_only: true

    ruleset, ref_update = simple_ref_update_setup(@org_repo, @org_admin)

    validate_bypass_denied(@org_repo, ref_update, read_deploy_key) do
      create(:repository_ruleset_bypass_actor, :repo_admin, bypass_mode: "any", repository_ruleset: ruleset)
    end
  end

  test "allows bypass by dependabot" do
    GitHub.stubs(dependency_graph_enabled?: true)
    GitHub.stubs(dependabot_enabled?: true)

    ruleset, ref_update = simple_ref_update_setup(@org_repo, @org_member)
    create(:repository_rule_configuration, repository_ruleset: ruleset)

    dependabot = create(:dependabot_integration)
    dependabot.install_on(
      @org,
      repositories: [@org_repo],
      installer: @org_admin,
      entry_point: :test_case
    )
    GitHub.stubs(dependabot_github_app: dependabot)
    assert @org.dependabot_installed?

    validate_bypass_allowed(@org_repo, ref_update, dependabot.bot) do
      RepositoryRulesetBypassActor.new(
        repository_ruleset: ruleset,
        actor: dependabot,
        bypass_mode: RepositoryRulesetBypassActor::BYPASS_MODES[:any]
      ).save!
    end
  end

  test "allows bypass for root repo admin on fork repo for push ruleset" do
    GitHub.flipper[:push_rulesets].enable

    org_repo_fork, status = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
      @org_repo.fork(forker: @org_member)
    end
    assert_equal :created, status

    push_ruleset = create(:repository_ruleset, target: "push", source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 10
    })

    push_metadata = simple_push_metadata(@org_admin, "some-long-file-name", "contents")

    validate_bypass_allowed_push(org_repo_fork, "master", push_metadata, @org_admin) do
      create(:repository_ruleset_bypass_actor, :repo_admin, bypass_mode: "any", repository_ruleset: push_ruleset)
    end
  end

  test "denies bypass for fork repo admin on fork repo for push ruleset" do
    GitHub.flipper[:push_rulesets].enable

    org_repo_fork, status = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
      @org_repo.fork(forker: @org_member)
    end
    assert_equal :created, status

    push_ruleset = create(:repository_ruleset, target: "push", source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 10
    })

    push_metadata = simple_push_metadata(@org_member, "some-long-file-name", "contents")

    validate_bypass_denied_push(org_repo_fork, "master", push_metadata, @org_member) do
      create(:repository_ruleset_bypass_actor, :repo_admin, bypass_mode: "any", repository_ruleset: push_ruleset)
    end
  end

  test "allows bypass for root org admin on cross-org fork repo for push ruleset" do
    GitHub.flipper[:push_rulesets].enable

    # Create a second organization
    org_admin_2 = create(:user)
    org_2 = create(:business_plus_organization, name: "org2", admin: org_admin_2)
    @org.add_member(org_admin_2)

    # Fork the repo to the second organization
    org_repo_fork, status = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
      @org_repo.fork(forker: org_admin_2, org: org_2)
    end
    assert_equal :created, status

    push_ruleset = create(:repository_ruleset, target: "push", source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 10
    })

    push_metadata = simple_push_metadata(@org_admin, "some-long-file-name", "contents")

    validate_bypass_allowed_push(org_repo_fork, "master", push_metadata, @org_admin) do
      push_ruleset.bypass_mode = :org_bypass_any
      push_ruleset.save!
    end
  end

  test "denies bypass for fork org admin on cross-org fork repo for push ruleset" do
    GitHub.flipper[:push_rulesets].enable

    # Create a second organization
    org_admin_2 = create(:user)
    org_2 = create(:business_plus_organization, name: "org2", admin: org_admin_2)
    @org.add_member(org_admin_2)

    # Fork the repo to the second organization
    org_repo_fork, status = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
      @org_repo.fork(forker: org_admin_2, org: org_2)
    end
    assert_equal :created, status

    push_ruleset = create(:repository_ruleset, target: "push", source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 10
    })

    push_metadata = simple_push_metadata(org_admin_2, "some-long-file-name", "contents")

    validate_bypass_denied_push(org_repo_fork, "master", push_metadata, org_admin_2) do
      push_ruleset.bypass_mode = :org_bypass_any
      push_ruleset.save!
    end
  end

  test "allows bypass by deploy keys" do
    write_deploy_key = create :public_key, repository: @org_repo, read_only: false

    ruleset, ref_update = simple_ref_update_setup(@org_repo, @org_admin)

    validate_bypass_allowed(@org_repo, ref_update, write_deploy_key) do
      ruleset.deploy_key_bypass = true
      ruleset.save!
    end
  end

  test "disallow org admin/member bypass when only deploy keys are allowed" do
    repo_admin = create(:user)
    @org_repo.add_member(repo_admin, action: :admin)

    write_deploy_key = create :public_key, repository: @org_repo, read_only: false

    ruleset, ref_update = simple_ref_update_setup(@org_repo, @org_admin)

    validate_bypass_denied(@org_repo, ref_update, @org_admin) do
      ruleset.deploy_key_bypass = true
      ruleset.save!
    end

    validate_bypass_denied(@org_repo, ref_update, repo_admin) do
      ruleset.deploy_key_bypass = true
      ruleset.save!
    end

    validate_bypass_denied(@org_repo, ref_update, @org_member) do
      ruleset.deploy_key_bypass = true
      ruleset.save!
    end
  end

  test "allow all deploy keys to bypass" do
    key = Sham.ssh_public_key
    application = create :oauth_application, user: @repo_admin
    access = create :oauth_access, user: @repo_admin, application:, scopes: %w(user)

    user_oauth_key = @repo_admin.public_keys.create_with_verification \
        key:, verifier: @repo_admin, oauth_authorization: access.authorization
    repo_oauth_key = @repo.public_keys.create_with_verification \
        key:, verifier: @repo_admin, oauth_authorization: access.authorization
    user_created_deploy_key = create :public_key, repository: @repo, read_only: false

    ruleset, ref_update = simple_ref_update_setup(@repo, @repo_admin)

    # user oauth key: denied
    validate_bypass_denied(@repo, ref_update, user_oauth_key) do
      ruleset.deploy_key_bypass = true
      ruleset.save!
    end

    ruleset.deploy_key_bypass = false
    ruleset.save!

    # repo oauth key: allowed
    validate_bypass_allowed(@repo, ref_update, repo_oauth_key) do
      ruleset.deploy_key_bypass = true
      ruleset.save!
    end

    ruleset.deploy_key_bypass = false
    ruleset.save!

    # user-created deploy key: allowed
    validate_bypass_allowed(@repo, ref_update, user_created_deploy_key) do
      ruleset.deploy_key_bypass = true
      ruleset.save!
    end
  end
end
