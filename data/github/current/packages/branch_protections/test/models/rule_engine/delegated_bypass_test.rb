# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/spokesd"

class DelegatedBypassTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper
  include RulesEngine::BypassTestHelper

  Spokesd.share_spokesdb(self)

  fixtures do
    @owner = create(:user, plan: "business_plus")
    @repo = create(:private_repository, owner: @owner, from_example: :simple)

    @enterprise_admin = create(:user)
    @enterprise = create(:business, owners: [@enterprise_admin])
    @org_admin = create(:user)
    @org = create(:business_plus_organization, name: "org1", admin: @org_admin, business: @enterprise)
    @org.allow_private_repository_forking(actor: @org.admin, policy: Configurable::AllowPrivateRepositoryForking::EVERYWHERE)

    @org_member = create(:user)
    @org.add_member(@org_member)

    @org_member2 = create(:user)
    @org.add_member(@org_member2)

    @org_repo = create(:private_repository, owner: @org, from_example: :simple)
    @org_repo.add_member(@org_member, action: :write)
    @org_repo.add_member(@org_member2, action: :write)
    @org_repo.add_member(@org_admin, action: :admin)

    @team = create(:team, organization: @org, privacy: :closed)
    @team.add_member @org_admin
    @team.add_repository @org_repo, :admin

    @org_member_team = create(:team, organization: @org, privacy: :closed)
    @org_member_team.add_member @org_member
    @org_member_team.add_repository @org_repo, :admin

    @org_member2_team = create(:team, organization: @org, privacy: :closed)
    @org_member2_team.add_member @org_member2
    @org_member2_team.add_repository @org_repo, :admin

    example_repo_snapshot
  end

  setup do
    Failbot.expects(:report).never

    GitHub.flipper[:push_rulesets].enable
    GitHub.flipper[:push_ruleset_delegated_bypass].enable

    example_repo_restore

    Spokesd.enable_spokesd
  end

  test "denies bypass, produces URL for delegatable rulesets" do
    push_ruleset = create(:repository_ruleset, :org_admin_bypass_any, target: "push", source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 10
    })

    push_metadata = simple_push_metadata(@org_admin, "some-long-file-name", "contents")

    rule_suite = RuleEngine::Evaluator.evaluate_pre_commit_rules(@org_repo, @org_repo.heads["master"].target_oid, @org_member, push_metadata, target_ref_name: "master")

    refute rule_suite.action_permitted?
    assert rule_suite.additional_cli_message
  end

  test "denies bypass, does not produce URL for non-delegatable rulesets" do
    push_ruleset = create(:repository_ruleset, target: "push", source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 10
    })

    push_metadata = simple_push_metadata(@org_admin, "some-long-file-name", "contents")

    rule_suite = RuleEngine::Evaluator.evaluate_pre_commit_rules(@org_repo, @org_repo.heads["master"].target_oid, @org_member, push_metadata, target_ref_name: "master")

    refute rule_suite.action_permitted?
    refute rule_suite.additional_cli_message
  end

  test "allows bypass if delegation request is approved" do
    push_ruleset = create(:repository_ruleset, :org_admin_bypass_any, target: "push", source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 10
    })

    push_metadata = simple_push_metadata(@org_member, "some-long-file-name", "contents")

    validate_bypass_allowed_push(@org_repo, "master", push_metadata, @org_member, write_operation: true) do |rule_suite|
      request = Exemptions::ExemptionRequest.create!(
        resource_owner: rule_suite,
        requester: @org_member,
        resource_identifier: rule_suite.after_oid,
        repository: rule_suite.repository,
        request_type: "push_ruleset_bypass")
      Exemptions::ExemptionResponse.create!(
        reviewer: @org_admin,
        status: :approved,
        exemption_request: request
      )
    end
  end

  test "allows bypass if delegation request is approved (enterprise ruleset and admin)" do
    GitHub.flipper[:enterprise_rulesets].enable
    GitHub.flipper[:enterprise_code_rulesets].enable

    push_ruleset = create(:repository_ruleset, :org_admin_bypass_any, :targets_all_orgs, :targets_all_repos, :enterprise_owner_bypass, target: "push", source: @enterprise)
    create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 10
    })

    push_metadata = simple_push_metadata(@org_member, "some-long-file-name", "contents")

    validate_bypass_allowed_push(@org_repo, "master", push_metadata, @org_member, write_operation: true) do |rule_suite|
      request = Exemptions::ExemptionRequest.create!(
        resource_owner: rule_suite,
        requester: @org_member,
        resource_identifier: rule_suite.after_oid,
        repository: rule_suite.repository,
        request_type: "push_ruleset_bypass")
      Exemptions::ExemptionResponse.create!(
        reviewer: @enterprise_admin,
        status: :approved,
        exemption_request: request
      )
    end
  end

  test "allows bypass if delegation request is approved (forked repo)" do
    org_repo_fork, status = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
      @org_repo.fork(forker: @org_member)
    end
    assert_equal :created, status

    push_ruleset = create(:repository_ruleset, :org_admin_bypass_any, target: "push", source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 10
    })

    push_metadata = simple_push_metadata(@org_member, "some-long-file-name", "contents")

    validate_bypass_allowed_push(org_repo_fork, "master", push_metadata, @org_member, write_operation: true) do |rule_suite|
      request = Exemptions::ExemptionRequest.create!(
        resource_owner: rule_suite,
        requester: @org_member,
        resource_identifier: rule_suite.after_oid,
        repository: @org_repo, # This is the network root
        request_type: "push_ruleset_bypass")
      Exemptions::ExemptionResponse.create!(
        reviewer: @org_admin,
        status: :approved,
        exemption_request: request
      )
    end
  end

  test "denies bypass if delegation request is still pending" do
    push_ruleset = create(:repository_ruleset, :org_admin_bypass_any, target: "push", source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 10
    })

    push_metadata = simple_push_metadata(@org_member, "some-long-file-name", "contents")

    validate_bypass_denied_push(@org_repo, "master", push_metadata, @org_member, write_operation: true) do |rule_suite|
      Exemptions::ExemptionRequest.create!(
        resource_owner: rule_suite,
        requester: @org_member,
        resource_identifier: rule_suite.after_oid,
        repository: rule_suite.repository,
        request_type: "push_ruleset_bypass")
    end
  end

  test "denies bypass if delegation request is approved by someone who is removed from the bypassers list" do
    push_ruleset = create(:repository_ruleset, :org_admin_bypass_any, target: "push", source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 10
    })
    member2_bypass = create(:repository_ruleset_bypass_actor, actor: @org_member2_team, bypass_mode: "any", repository_ruleset: push_ruleset)

    push_metadata = simple_push_metadata(@org_member, "some-long-file-name", "contents")

    validate_bypass_denied_push(@org_repo, "master", push_metadata, @org_member, write_operation: true) do |rule_suite|
      request = Exemptions::ExemptionRequest.create!(
        resource_owner: rule_suite,
        requester: @org_member,
        resource_identifier: rule_suite.after_oid,
        repository: rule_suite.repository,
        request_type: "push_ruleset_bypass")
      Exemptions::ExemptionResponse.create!(
        reviewer: @org_member2,
        status: :approved,
        exemption_request: request
      )
      member2_bypass.destroy
    end
  end

  test "denies bypass if delegation request is only approved by 1 of 2 required reviewers" do
    push_ruleset = create(:repository_ruleset, :org_admin_bypass_any, target: "push", source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 10
    })

    push_ruleset2 = create(:repository_ruleset, :org_admin_bypass_any, target: "push", source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: push_ruleset2, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 8
    })
    create(:repository_ruleset_bypass_actor, actor: @org_member2_team, bypass_mode: "any", repository_ruleset: push_ruleset2)

    push_metadata = simple_push_metadata(@org_member, "some-long-file-name", "contents")

    validate_bypass_denied_push(@org_repo, "master", push_metadata, @org_member, write_operation: true) do |rule_suite|
      request = Exemptions::ExemptionRequest.create!(
        resource_owner: rule_suite,
        requester: @org_member,
        resource_identifier: rule_suite.after_oid,
        repository: rule_suite.repository,
        request_type: "push_ruleset_bypass")
      Exemptions::ExemptionResponse.create!(
        reviewer: @org_member2,
        status: :approved,
        exemption_request: request
      )
    end
  end

  test "allows bypass if delegation request is approved by multiple reviewers" do
    push_ruleset = create(:repository_ruleset, :org_admin_bypass_any, target: "push", source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 10
    })

    push_ruleset2 = create(:repository_ruleset, :org_admin_bypass_any, target: "push", source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: push_ruleset2, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 8
    })
    create(:repository_ruleset_bypass_actor, actor: @org_member2_team, bypass_mode: "any", repository_ruleset: push_ruleset2)

    push_metadata = simple_push_metadata(@org_member, "some-long-file-name", "contents")

    validate_bypass_allowed_push(@org_repo, "master", push_metadata, @org_member, write_operation: true) do |rule_suite|
      request = Exemptions::ExemptionRequest.create!(
        resource_owner: rule_suite,
        requester: @org_member,
        resource_identifier: rule_suite.after_oid,
        repository: rule_suite.repository,
        request_type: "push_ruleset_bypass")
      Exemptions::ExemptionResponse.create!(
        reviewer: @org_member2,
        status: :approved,
        exemption_request: request
      )
      Exemptions::ExemptionResponse.create!(
        reviewer: @org_admin,
        status: :approved,
        exemption_request: request
      )
    end
  end

  test "denies bypass if a new rule is added after a delegation request is approved" do
    push_ruleset = create(:repository_ruleset, :org_admin_bypass_any, target: "push", source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 10
    })

    push_metadata = simple_push_metadata(@org_member, "some-long-file-name.exe", "contents")

    validate_bypass_denied_push(@org_repo, "master", push_metadata, @org_member, write_operation: true) do |rule_suite|
      request = Exemptions::ExemptionRequest.create!(
        resource_owner: rule_suite,
        requester: @org_member,
        resource_identifier: rule_suite.after_oid,
        repository: rule_suite.repository,
        request_type: "push_ruleset_bypass")
      Exemptions::ExemptionResponse.create!(
        reviewer: @org_admin,
        status: :approved,
        exemption_request: request
      )
      create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "file_extension_restriction", parameters: {
        restricted_file_extensions: ["*.exe"]
      })
    end
  end

  test "denies bypass if a rule is modified after a delegation request is approved" do
    GitHub.flipper[:rules_history].enable
    push_ruleset = create(:repository_ruleset, :org_admin_bypass_any, target: "push", source: @org_repo)
    max_file_path_length_rule = create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 10
    })
    push_ruleset.rule_configurations = [max_file_path_length_rule]
    push_ruleset.save

    push_metadata = simple_push_metadata(@org_member, "some-long-file-name.exe", "contents")

    validate_bypass_denied_push(@org_repo, "master", push_metadata, @org_member, write_operation: true) do |rule_suite|
      request = Exemptions::ExemptionRequest.create!(
        resource_owner: rule_suite,
        requester: @org_member,
        resource_identifier: rule_suite.after_oid,
        repository: rule_suite.repository,
        request_type: "push_ruleset_bypass")
      Exemptions::ExemptionResponse.create!(
        reviewer: @org_admin,
        status: :approved,
        exemption_request: request
      )
      max_file_path_length_rule.parameters = {
        max_file_path_length: 9
      }
      max_file_path_length_rule.save
      push_ruleset.rule_configurations = [max_file_path_length_rule]
      push_ruleset.save
    end
  end
end
