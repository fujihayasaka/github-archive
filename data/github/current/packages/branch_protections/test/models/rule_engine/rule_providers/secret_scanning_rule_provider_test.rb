# typed: true
# frozen_string_literal: true

require "test_helper"

class RuleEngineSecretScanningRuleProviderTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper
  include SecretScanning::Features::FeatureFlagHelper

  fixtures do
    @user = create(:user)
    @org = create(:business_organization, admin: @user)
    @reviewer = create(:user)

    @repo = create(:private_repository, owner: @org)
    @repo.add_member(@reviewer)
    @public_repo = create(:public_repository, owner: @org)
    @user_repo = create(:private_repository, owner: @user)

  end

  setup do
    GitHub.skip_secret_scanning_in_rules_engine = false

    @ref_updates = [
      create_branch_update(@repo, name: "main"),
      create_branch_update(@repo, name: "develop"),
    ]
    SecretScanning::Features::Repo::TokenScanning.new(@repo).enable(actor: @user)
    SecretScanning::Features::Repo::PushProtection.new(@repo).enable(actor: @user)
    Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
    Repository.any_instance.stubs(:advanced_security_enabled?).returns(true)
    SecurityProduct::Permissions::RepoAuthz.any_instance.stubs(:can_manage_security_products?).returns(true)

    @provider = RuleEngine::RuleProviders::SecretScanningRuleProvider.new
    @ref_update = Git::Ref::Update.new(
      repository: @repo,
      refname: "refs/origin/main",
      before_oid: GitHub::NULL_OID,
      after_oid: "a" * 40,
    )
    @rulesuite = RuleEngine::RuleSuite.new(id: 5, repository: @repo, ref_name: @ref_update.refname, before_oid: @ref_update.before_oid, after_oid: @ref_update.after_oid)
    @rule_config = RepositoryRuleConfiguration.create_provider_rule(
      provider: RuleEngine::RuleProviders::SecretScanningRuleProvider.new,
      source: @repo,
      rule_type: RuleEngine::Rules::SecretScanningRule::RULE_NAME,
      matching_ref_names: [@ref_update.refname],
      parameters: {}
    )
    @rulesuite.rule_runs = [RuleEngine::RuleRun.failure(rule_config: @rule_config, ref_update: @ref_update, message: SecretScanning::PushProtection::CliConstructor.get_short_message, evaluation_metadata: { SecretScanning::Constants::RULE_RUN_SCAN_RESULT_METADATA_KEY => make_scan_result })]

    SecretScanning::Services::DelegatedBypassService.stubs(:can_review_bypass_request?).with(@repo, @user).returns(false)
    SecretScanning::Services::DelegatedBypassService.stubs(:can_review_bypass_request?).with(@repo, @reviewer).returns(true)
  end

  context "rules_for_ref_updates" do
    test "no rules when protected branches aren't supported" do
      assert_empty @provider.rules_for_ref_updates(@user_repo, @ref_updates, @user)
    end

    test "no rules if no refs" do
      assert_empty @provider.rules_for_ref_updates(@repo, [], @user)
    end

    test "no rules if no actor" do
      assert_empty @provider.rules_for_ref_updates(@repo, @ref_updates, nil)
    end

    test "no rules if push protection isn't enabled" do
      SecretScanning::Features::User::PushProtection.any_instance.stubs(:enabled?).returns(false)
      SecretScanning::Features::Repo::PushProtection.new(@repo).disable(actor: @user)
      assert_empty @provider.rules_for_ref_updates(@repo, @ref_updates, @user)
    end

    test "no rules if user push protection is enabled but repo isn't public" do
      SecretScanning::Features::User::PushProtection.any_instance.stubs(:enabled?).returns(true)
      SecretScanning::Features::Repo::PushProtection.new(@repo).disable(actor: @user)
      assert_empty @provider.rules_for_ref_updates(@repo, @ref_updates, @user)
    end

    test "returns ref rule when repo push protection is enabled" do
      SecretScanning::Features::Repo::PushProtection.any_instance.stubs(:enabled?).returns(true)
      SecretScanning::Features::User::PushProtection.any_instance.stubs(:enabled?).returns(false)
      rules = @provider.rules_for_ref_updates(@repo, @ref_updates, @user)
      assert_equal 1, rules.size
      assert_equal RuleEngine::Rules::SecretScanningRule::RULE_NAME, rules[0]&.rule_type
      assert_equal RuleEngine::Rules::SecretScanningRule, rules[0]&.evaluator.class
    end

    test "returns ref rule when user push protection is enabled and repo is public" do
      SecretScanning::Features::Repo::PushProtection.any_instance.stubs(:enabled?).returns(false)
      SecretScanning::Features::User::PushProtection.any_instance.stubs(:enabled?).returns(true)
      rules = @provider.rules_for_ref_updates(@public_repo, @ref_updates, @user)
      assert_equal 1, rules.size
      assert_equal RuleEngine::Rules::SecretScanningRule::RULE_NAME, rules[0]&.rule_type
      assert_equal RuleEngine::Rules::SecretScanningRule, rules[0]&.evaluator.class
    end
  end

  def create_event(repo, user, rulesuite)
    RuleEngine::Events::PreReceivePushEvent.new(repo, [rulesuite.ref_update], user)
  end

  context "on_evaluation_complete" do
    test "do nothing if the RuleSuite succeeded" do
      @rulesuite.rule_runs = [RuleEngine::RuleRun.success(rule_config: @rule_config, ref_update: @ref_update)]
      @provider.on_evaluation_complete(@rulesuite, create_event(@repo, @user, @rulesuite))
      assert_nil @rulesuite.additional_cli_message
      assert_empty Failbot.reports
    end

    test "RuleSuite requires a repo" do
      rulesuite_without_repo = RuleEngine::RuleSuite.new(ref_name: @ref_update.refname, before_oid: @ref_update.before_oid, after_oid: @ref_update.after_oid)
      rulesuite_without_repo.rule_runs = [RuleEngine::RuleRun.failure(rule_config: @rule_config, ref_update: @ref_update, message: SecretScanning::PushProtection::CliConstructor.get_short_message)]
      @provider.on_evaluation_complete(rulesuite_without_repo, create_event(@repo, @user, rulesuite_without_repo))
      assert_nil @rulesuite.additional_cli_message
      assert_equal 1, Failbot.reports.size
      report = Failbot.reports.last
      assert_equal "No repository for RuleSuite", Failbot.exception_message_from_hash(report)
    end

    test "do nothing if the RuleRun's evaluation metadata doesn't have the SecretScanningRule key" do
      @rulesuite.rule_runs[0].evaluation_metadata = {}
      @provider.on_evaluation_complete(@rulesuite, create_event(@repo, @user, @rulesuite))
      assert_nil @rulesuite.additional_cli_message
      assert_empty Failbot.reports
    end

    test "constructs CLI output for found secrets w/ delegated bypass enabled" do
      SecretScanning::Services::DelegatedBypassService.stubs(:use_delegated_bypass_flow).with(@repo, @user).returns(true)
      @provider.on_evaluation_complete(@rulesuite, create_event(@repo, @user, @rulesuite))
      refute_nil @rulesuite.additional_cli_message
      expected_msg = <<-MSG

 (?) Learn how to resolve a blocked push
 #{DocsUrlConfig.url_for("code-security/working-with-push-protection-from-the-command-line-resolving-a-blocked-push")}


  —— GitHub Personal Access Token ——————————————————————
   locations:
     - commit: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
       path: foo/bar.txt:1

   (?) To push, remove secret from commit(s) or follow this URL to request an exemption.
   #{GitHub.url}/#{@repo.owner.name}/#{@repo.name}/secret_scanning/exemptions/new/c2VjcmV0X3NjYW5uaW5nLTUtMQ==


  —— Clojars Deploy Token ——————————————————————————————
   locations:
     - commit: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
       path: foo/baz.txt:1

   (?) To push, remove secret from commit(s) or follow this URL to request an exemption.
   #{GitHub.url}/#{@repo.owner.name}/#{@repo.name}/secret_scanning/exemptions/new/c2VjcmV0X3NjYW5uaW5nLTUtMg==

MSG
      assert_equal expected_msg, @rulesuite.additional_cli_message
    end

    test "constructs CLI output for found secrets" do
      @provider.on_evaluation_complete(@rulesuite, create_event(@repo, @user, @rulesuite))
      refute_nil @rulesuite.additional_cli_message
      expected_msg = <<-MSG

 (?) Learn how to resolve a blocked push
 #{DocsUrlConfig.url_for("code-security/working-with-push-protection-from-the-command-line-resolving-a-blocked-push")}


  —— GitHub Personal Access Token ——————————————————————
   locations:
     - commit: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
       path: foo/bar.txt:1

   (?) To push, remove secret from commit(s) or follow this URL to allow the secret.
   #{GitHub.url}/#{@repo.owner.name}/#{@repo.name}/security/secret-scanning/unblock-secret/1


  —— Clojars Deploy Token ——————————————————————————————
   locations:
     - commit: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
       path: foo/baz.txt:1

   (?) To push, remove secret from commit(s) or follow this URL to allow the secret.
   #{GitHub.url}/#{@repo.owner.name}/#{@repo.name}/security/secret-scanning/unblock-secret/2

MSG

      assert_equal expected_msg, @rulesuite.additional_cli_message
    end

    test "for repos w/ delegated bypass enabled, when a bypass reviewer pushes, constructs CLI output w/ self approval flow" do
      SecretScanning::Features::Repo::DelegatedBypass.new(@repo).enable(actor: @user)
      @provider.on_evaluation_complete(@rulesuite, create_event(@repo, @reviewer, @rulesuite))
      refute_nil @rulesuite.additional_cli_message
      expected_msg = <<-MSG

 (?) Learn how to resolve a blocked push
 #{DocsUrlConfig.url_for("code-security/working-with-push-protection-from-the-command-line-resolving-a-blocked-push")}


  —— GitHub Personal Access Token ——————————————————————
   locations:
     - commit: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
       path: foo/bar.txt:1

   (?) To push, remove secret from commit(s) or follow this URL to allow the secret.
   #{GitHub.url}/#{@repo.owner.name}/#{@repo.name}/security/secret-scanning/unblock-secret/1


  —— Clojars Deploy Token ——————————————————————————————
   locations:
     - commit: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
       path: foo/baz.txt:1

   (?) To push, remove secret from commit(s) or follow this URL to allow the secret.
   #{GitHub.url}/#{@repo.owner.name}/#{@repo.name}/security/secret-scanning/unblock-secret/2

MSG
      assert_equal expected_msg, @rulesuite.additional_cli_message
    end
  end

  context "construct_secret_to_bypass_url_mapping" do
    test "constructs delegated bypass urls" do
      construct_secret_to_bypass_url_mapping_helper(use_delegated_bypass: true, use_http_scheme: false)
    end

    test "constructs delegated bypass urls with http when GitHub.scheme returns http" do
      construct_secret_to_bypass_url_mapping_helper(use_delegated_bypass: true, use_http_scheme: true)
    end

    test "constructs self bypass urls" do
      construct_secret_to_bypass_url_mapping_helper(use_delegated_bypass: false, use_http_scheme: false)
    end

    test "constructs self bypass urls with http when GitHub.scheme returns http" do
      construct_secret_to_bypass_url_mapping_helper(use_delegated_bypass: false, use_http_scheme: true)
    end

    test "constructs delegated bypass urls on multitenant enterprise" do
      user = create(:paid_user)
      org = create(:organization, login: "octo-org")
      business = create(:business, name: "test-business", organizations: [org], owners: [user])
      repo = create(:public_repository, owner: user)
      @rulesuite.repository = repo
      on_multi_tenant_enterprise(tenant: business) do
        # Delegated bypass
        url_mapping = @provider.construct_secret_to_bypass_url_mapping(@rulesuite, repo, user, make_scan_result, true)
        assert_same_hash(url_mapping, {
          "1" => "https://#{business.name}.github.com/#{user.name}/#{repo.name}/secret_scanning/exemptions/new/c2VjcmV0X3NjYW5uaW5nLTUtMQ==",
          "2" => "https://#{business.name}.github.com/#{user.name}/#{repo.name}/secret_scanning/exemptions/new/c2VjcmV0X3NjYW5uaW5nLTUtMg==",
        })
        # Self bypass
        url_mapping = @provider.construct_secret_to_bypass_url_mapping(@rulesuite, repo, user, make_scan_result, false)
        assert_same_hash(url_mapping, {
          "1" => "https://#{business.name}.github.com/#{user.name}/#{repo.name}/security/secret-scanning/unblock-secret/1",
          "2" => "https://#{business.name}.github.com/#{user.name}/#{repo.name}/security/secret-scanning/unblock-secret/2",
        })
      end
    end
  end

  def construct_secret_to_bypass_url_mapping_helper(use_delegated_bypass:, use_http_scheme:)
    if use_http_scheme
      GitHub.stubs(:scheme).returns("http")
    end
    url_mapping = @provider.construct_secret_to_bypass_url_mapping(@rulesuite, @repo, @user, make_scan_result, use_delegated_bypass)
    if use_delegated_bypass
      assert_same_hash(url_mapping, {
        "1" => "#{GitHub.scheme}://#{GitHub.host_domain}/#{@repo.owner.name}/#{@repo.name}/secret_scanning/exemptions/new/c2VjcmV0X3NjYW5uaW5nLTUtMQ==",
        "2" => "#{GitHub.scheme}://#{GitHub.host_domain}/#{@repo.owner.name}/#{@repo.name}/secret_scanning/exemptions/new/c2VjcmV0X3NjYW5uaW5nLTUtMg==",
      })
    else
      assert_same_hash(url_mapping, {
        "1" => "#{GitHub.scheme}://#{GitHub.host_domain}/#{@repo.owner.name}/#{@repo.name}/security/secret-scanning/unblock-secret/1",
        "2" => "#{GitHub.scheme}://#{GitHub.host_domain}/#{@repo.owner.name}/#{@repo.name}/security/secret-scanning/unblock-secret/2",
      })
    end

  end

  def make_scan_result
    SecretScanning::Models::SynchronousScanResult.new(
      completed: true,
      secrets: [
        SecretScanning::Models::Secret.new(
          type: "GITHUB_TOKEN_V2",
          fingerprint: "abcd1234",
          token_metadata: SecretScanning::Models::TokenMetadata.new(
            token_type: "GITHUB_TOKEN_V2",
            label: "GitHub Personal Access Token",
            slug: "github_token_v2",
            provider: "GitHub",
          ),
          bypass_placeholder_ksuid: "1",
          locations: [
            SecretScanning::Models::Location.new(
              commit_oid: @ref_update.after_oid,
              path: "foo/bar.txt",
              start_line: 1,
            )
          ]
        ),
        SecretScanning::Models::Secret.new(
          type: "CLOJARS_DEPLOY_TOKEN",
          fingerprint: "xyz987",
          token_metadata: SecretScanning::Models::TokenMetadata.new(
            token_type: "CLOJARS_DEPLOY_TOKEN",
            label: "Clojars Deploy Token",
            slug: "clojars",
            provider: "Clojars",
          ),
          bypass_placeholder_ksuid: "2",
          locations: [
            SecretScanning::Models::Location.new(
              commit_oid: @ref_update.after_oid,
              path: "foo/baz.txt",
              start_line: 1,
            )
          ]
        )
      ]
    )
  end

end
