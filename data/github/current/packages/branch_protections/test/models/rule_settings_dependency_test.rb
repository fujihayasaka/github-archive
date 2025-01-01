# typed: true
# frozen_string_literal: true

require "test_helper"

class RuleEngineRuleSettingsDependencyTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper
  include Exemptions::Evaluators

  fixtures do
    @enterprise = create(:business)
    @org_admin = create(:user)
    @org = create(:business_plus_org, admin: @org_admin, business: @enterprise)
    @org2 = create(:business_plus_org, admin: @org_admin, business: @enterprise)
    @repo = create(:repository, owner: @org)
    @repo2 = create(:repository, owner: @org2)
    @priv_repo = create(:private_repository, owner: @org, from_example: :simple)
    @collaborator = create(:user)
    @member = create(:user)
    @org.add_member(@collaborator)
    @org.add_member(@member)
    create(:collaborator, collaborator: @collaborator, repository: @priv_repo, action: :write)
    create(:collaborator, collaborator: @member, repository: @priv_repo, action: :write)
    @org_team = create(:team, organization: @org, privacy: :closed)
    @org_team.add_member @collaborator
    @org_team.add_member @member
  end

  setup do
    # create a repo operation failure and bypass request
    enable_feature_flag(:member_privilege_rulesets)
    enable_feature_flag(:repo_policy_bypass)
    ruleset = create(:repository_ruleset, :targets_all_repos, source: @org, target: "repository")
    config = create(:repository_rule_configuration, rule_type: "repository_delete", repository_ruleset: ruleset)
    event = RuleEngine::Events::RepositoryOperationEvent.new(@priv_repo, @member, { delete: nil }, persist_results: true)
    results = RuleEngine::GenericEvaluator.evaluate_rules(event)
    @policy_suite = T.must(results.first)
    @policy_request = RepositoryPolicyRulesetBypass.create_request!(@policy_suite, @member, "please let me delete this repo")
  end

  test "returns applicable rulesets for a ref" do
    inherited_ruleset = create(:repository_ruleset, :targets_all_repos, :targets_default_branch, name: "ruleset-1", source: @org)
    default_ruleset = create(:repository_ruleset, :example_ruleset, name: "ruleset-1", source: @repo)
    disabled_ruleset = create(:repository_ruleset, :example_ruleset, name: "ruleset-2", enforcement: :disabled, source: @repo)
    non_default_ruleset = create(:repository_ruleset, name: "ruleset-3", source: @repo)
    create(:repository_rule_condition, :targets_branch, repository_ruleset: non_default_ruleset)

    assert_same_elements [inherited_ruleset, default_ruleset], @repo.rulesets_for_ref("refs/heads/#{@repo.default_branch}")
    assert_same_elements [non_default_ruleset], @repo.rulesets_for_ref("refs/heads/develop")
  end

  context "fetch_rule_suites" do
    test "returns rule suite for repo" do
      ruleset = create(:repository_ruleset, :example_ruleset, source: @repo)
      ref_update = create_branch_update(@repo)
      run = RuleEngine::RuleRun.success(rule_config: ruleset.rule_configurations.first, ref_update: ref_update)
      suite = RuleEngine::RuleSuite.for_ref_update(ref_update: ref_update, rule_runs: [run], actor: @org_admin)
      suite.save

      suites, _ = @repo.fetch_rule_suites
      assert_equal 1, suites.size
      assert_equal suite.id, suites.first.id
    end

    test "does not return rule suite for a different repo" do
      ruleset = create(:repository_ruleset, :example_ruleset, source: @org)
      another_repo = create(:repository, owner: @org)

      ref_update = create_branch_update(another_repo)
      run = RuleEngine::RuleRun.success(rule_config: ruleset.rule_configurations.first, ref_update: ref_update)
      suite = RuleEngine::RuleSuite.for_ref_update(ref_update: ref_update, rule_runs: [run], actor: @org_admin)
      suite.save

      suites, _ = @repo.fetch_rule_suites
      assert_equal 0, suites.size
    end

    test "returns rule suite for repos within an org" do
      ruleset = create(:repository_ruleset, :example_ruleset, source: @org)
      ref_update = create_branch_update(@repo)
      run = RuleEngine::RuleRun.success(rule_config: ruleset.rule_configurations.first, ref_update: ref_update)
      suite = RuleEngine::RuleSuite.for_ref_update(ref_update: ref_update, rule_runs: [run], actor: @org_admin)
      suite.save

      suites, _ = @org.fetch_rule_suites
      assert_same_elements [@policy_suite, suite], suites
    end

    test "filter by ruleset" do
      ruleset1 = create(:repository_ruleset, :example_ruleset, source: @repo)
      ref_update1 = create_branch_update(@repo)
      run1 = RuleEngine::RuleRun.success(rule_config: ruleset1.rule_configurations.first, ref_update: ref_update1)
      suite1 = RuleEngine::RuleSuite.for_ref_update(ref_update: ref_update1, rule_runs: [run1], actor: @org_admin)
      suite1.save

      ruleset2 = create(:repository_ruleset, :example_ruleset, source: @repo)
      ref_update2 = create_branch_update(@repo)
      run2 = RuleEngine::RuleRun.success(rule_config: ruleset2.rule_configurations.first, ref_update: ref_update2)
      suite2 = RuleEngine::RuleSuite.for_ref_update(ref_update: ref_update2, rule_runs: [run2], actor: @org_admin)
      suite2.save

      suites, _ = @repo.fetch_rule_suites(ruleset: ruleset1)
      assert_equal 1, suites.size
      assert_equal suite1.id, suites.first.id
    end

    test "filter by unqualified ref" do
      rule_suites = setup_rule_suites

      suites, _ = @repo.fetch_rule_suites(ref: "dev")
      assert_equal 2, suites.size
      assert_same_elements [rule_suites[:branch_suite2].id, rule_suites[:tag_suite2].id], suites.map(&:id)
    end

    test "filter by qualified head ref" do
      rule_suites = setup_rule_suites

      suites, _ = @repo.fetch_rule_suites(ref: "refs/heads/dev")
      assert_equal 1, suites.size
      assert_equal rule_suites[:branch_suite2].id, suites.first.id
    end

    test "filter by qualified tag ref" do
      rule_suites = setup_rule_suites

      suites, _ = @repo.fetch_rule_suites(ref: "refs/tags/dev")
      assert_equal 1, suites.size
      assert_equal rule_suites[:tag_suite2].id, suites.first.id
    end

    test "filter by organization" do
      ruleset = create(:repository_ruleset, :example_ruleset, :targets_all_orgs, :targets_all_repos, source: @enterprise)
      ref_update1 = create_branch_update(@repo, name: "main")
      run1 = RuleEngine::RuleRun.success(rule_config: ruleset.rule_configurations.first, ref_update: ref_update1)
      suite1 = RuleEngine::RuleSuite.for_ref_update(ref_update: ref_update1, rule_runs: [run1], actor: @org_admin)
      suite1.save

      ref_update2 = create_branch_update(@repo2, name: "main")
      run2 = RuleEngine::RuleRun.success(rule_config: ruleset.rule_configurations.first, ref_update: ref_update2)
      suite2 = RuleEngine::RuleSuite.for_ref_update(ref_update: ref_update2, rule_runs: [run2], actor: @org_admin)
      suite2.save

      suites, _ = @enterprise.fetch_rule_suites(organization: @repo.owner)
      assert_equal 1, suites.size
      assert_equal suite1.id, suites.first.id
    end

    test "filter by actor" do
      ruleset = create(:repository_ruleset, :example_ruleset, source: @repo)
      ref_update1 = create_branch_update(@repo, name: "main")
      run1 = RuleEngine::RuleRun.success(rule_config: ruleset.rule_configurations.first, ref_update: ref_update1)
      suite1 = RuleEngine::RuleSuite.for_ref_update(ref_update: ref_update1, rule_runs: [run1], actor: @org_admin)
      suite1.save

      other_user = create(:user)
      @org.add_member(other_user)
      ref_update2 = create_branch_update(@repo, name: "develop")
      run2 = RuleEngine::RuleRun.success(rule_config: ruleset.rule_configurations.first, ref_update: ref_update2)
      suite2 = RuleEngine::RuleSuite.for_ref_update(ref_update: ref_update2, rule_runs: [run2], actor: other_user)
      suite2.save

      suites, _ = @repo.fetch_rule_suites(actor: other_user)
      assert_equal 1, suites.size
      assert_equal suite2.id, suites.first.id
    end

    test "includes rule suites for repos moved out of orgs" do
      ruleset = create(:repository_ruleset, :example_ruleset, source: @org)

      repo_not_owned_by_org = create(:repository, owner: @org)

      ref_update = create_branch_update(repo_not_owned_by_org, name: "main")
      run = RuleEngine::RuleRun.success(rule_config: ruleset.rule_configurations.first, ref_update: ref_update)
      suite = RuleEngine::RuleSuite.for_ref_update(ref_update: ref_update, rule_runs: [run], actor: @org_admin)
      suite.save

      # Simulate a repo that was moved out of the org
      repo_not_owned_by_org.owner = @org_admin
      repo_not_owned_by_org.save

      suites, _ = @org.fetch_rule_suites
      assert_same_elements [@policy_suite, suite], suites
    end

    test "paging works correctly" do
      (1..11).each do |i|
        ruleset = create(:repository_ruleset, :example_ruleset, source: @repo)
        ref_update = create_branch_update(@repo, name: "branch-#{i}")
        run = RuleEngine::RuleRun.success(rule_config: ruleset.rule_configurations.first, ref_update: ref_update)
        suite = RuleEngine::RuleSuite.for_ref_update(ref_update: ref_update, rule_runs: [run], actor: @org_admin)
        suite.save
      end

      # Page size 5

      suites, has_more = @repo.fetch_rule_suites(page_size: 5, page: 1)
      assert_equal 5, suites.size
      assert_equal "refs/heads/branch-11", suites.first.ref_name
      assert_equal "refs/heads/branch-7", suites.last.ref_name
      assert has_more

      suites, has_more = @repo.fetch_rule_suites(page_size: 5, page: 2)
      assert_equal 5, suites.size
      assert_equal "refs/heads/branch-6", suites.first.ref_name
      assert_equal "refs/heads/branch-2", suites.last.ref_name
      assert has_more

      suites, has_more = @repo.fetch_rule_suites(page_size: 5, page: 3)
      assert_equal 1, suites.size
      assert_equal "refs/heads/branch-1", suites.first.ref_name
      refute has_more

      # Page size 10

      suites, has_more = @repo.fetch_rule_suites(page_size: 10, page: 1)
      assert_equal 10, suites.size
      assert_equal "refs/heads/branch-11", suites.first.ref_name
      assert_equal "refs/heads/branch-2", suites.last.ref_name
      assert has_more

      suites, has_more = @repo.fetch_rule_suites(page_size: 10, page: 2)
      assert_equal 1, suites.size
      assert_equal "refs/heads/branch-1", suites.first.ref_name
      refute has_more

      suites, has_more = @repo.fetch_rule_suites(page_size: 10, page: 3)
      assert_equal 0, suites.size
      refute has_more
    end
  end

  context "fetch_bypass_requests" do
    test "returns all bypass requests for the repository" do
      request, _ = create_exemption_request(@priv_repo, @priv_repo, @org_admin)

      exemption_requests, _ = @priv_repo.fetch_bypass_requests
      assert_same_elements [request, @policy_request], exemption_requests
    end

    test "filter by approvers" do
      create_exemption_request(@priv_repo, @priv_repo, @org_admin, reviewer: @collaborator)

      exemption_requests, _ = @priv_repo.fetch_bypass_requests(approver: @collaborator)
      assert_equal 1, exemption_requests.size

      exemption_requests, _ = @priv_repo.fetch_bypass_requests(approver: @member)
      assert_equal 0, exemption_requests.size

    end

    test "filter by requesters" do
      create_exemption_request(@priv_repo, @priv_repo, @org_admin)
      0..2.times { create_exemption_request(@priv_repo, @priv_repo, @collaborator) }

      exemption_requests, _ = @priv_repo.fetch_bypass_requests(requester: @collaborator)
      assert_equal 2, exemption_requests.size

      exemption_requests, _ = @priv_repo.fetch_bypass_requests(requester: @org_admin)
      assert_equal 1, exemption_requests.size
    end

    test "filter by time period" do
      # right before the 1 week mark
      request, _response = create_exemption_request(@priv_repo, @priv_repo, @org_admin, created_at: 1.week.ago - 1.hour)

      exemption_requests, _ = @priv_repo.fetch_bypass_requests(time_period: "week")
      assert_same_elements [@policy_request], exemption_requests

      exemption_requests, _ = @priv_repo.fetch_bypass_requests(time_period: "month")
      assert_same_elements [request, @policy_request], exemption_requests
    end

    test "filter by status" do
      # our time filters are a bit strange
      open_request, _ = create_exemption_request(@priv_repo, @priv_repo, @org_admin)
      one_week_request, _ = create_exemption_request(@priv_repo, @priv_repo, @org_admin, created_at: 1.week.ago + 1.hour, expires_at: Time.now - 1.hour)
      one_month_request, _ = create_exemption_request(@priv_repo, @priv_repo, @org_admin, created_at: 1.month.ago + 1.hour, expires_at: Time.now - 1.hour)
      rejected_request, _ = create_exemption_request(@priv_repo, @priv_repo, @org_admin, reviewer: @collaborator, response_status: :rejected)

      exemption_requests, _ = @priv_repo.fetch_bypass_requests(request_status: "expired", time_period: "week")
      assert_same_elements [one_week_request], exemption_requests

      exemption_requests, _ = @priv_repo.fetch_bypass_requests(request_status: "expired", time_period: "month")
      assert_same_elements [one_week_request, one_month_request], exemption_requests

      exemption_requests, _ = @priv_repo.fetch_bypass_requests(request_status: "denied")
      assert_same_elements [rejected_request], exemption_requests

      exemption_requests, _ = @priv_repo.fetch_bypass_requests(request_status: "open")
      assert_same_elements [open_request, @policy_request], exemption_requests
    end

    test "paging works correctly" do
      0..11.times { create_exemption_request(@priv_repo, @priv_repo, @org_admin) }

      # page size 5
      exemption_requests, has_more = @priv_repo.fetch_bypass_requests(page_size: 5, page: 1)
      assert_equal 5, exemption_requests.size
      assert has_more

      exemption_requests, has_more = @priv_repo.fetch_bypass_requests(page_size: 5, page: 2)
      assert_equal 5, exemption_requests.size
      assert has_more

      exemption_requests, has_more = @priv_repo.fetch_bypass_requests(page_size: 5, page: 3)
      assert_equal 2, exemption_requests.size
      refute has_more

      # Page size 10

      exemption_requests, has_more = @priv_repo.fetch_bypass_requests(page_size: 10, page: 1)
      assert_equal 10, exemption_requests.size
      assert has_more

      exemption_requests, has_more = @priv_repo.fetch_bypass_requests(page_size: 10, page: 2)
      assert_equal 2, exemption_requests.size
      refute has_more

      exemption_requests, has_more = @priv_repo.fetch_bypass_requests(page_size: 10, page: 3)
      assert_equal 0, exemption_requests.size
      refute has_more

    end

    context "organization specific fetch_bypass_requests" do
      test "returns all bypass requests for organization level rulesets" do
        request, response = create_exemption_request(@org, @priv_repo, @org_admin)
        create_exemption_request(@priv_repo, @priv_repo, @org_admin)

        exemption_requests, _ = @org.fetch_bypass_requests(repository: @priv_repo)
        assert_same_elements [request, @policy_request], exemption_requests
      end

      test "filter by repository" do
        request, _ = create_exemption_request(@org, @priv_repo, @org_admin)
        empty_priv_repo = create(:private_repository, owner: @org, from_example: :simple)

        exemption_requests, _ = @org.fetch_bypass_requests(repository: @priv_repo)
        assert_same_elements [request, @policy_request], exemption_requests

        exemption_requests, _ = @org.fetch_bypass_requests(repository: empty_priv_repo)
        assert_equal 0, exemption_requests.size
      end

      test "marks requests associated with deleted or missing repositories as deleted" do
        request, _ = create_exemption_request(@org, @priv_repo, @org_admin)

        deleted_repo = create(:private_repository, owner: @org, from_example: :simple)
        deleted_repo_request, _ = create_exemption_request(@org, deleted_repo, @org_admin)

        missing_repo = create(:private_repository, owner: @org, from_example: :simple)
        missing_repo_request, _ = create_exemption_request(@org, missing_repo, @org_admin)

        deleted_repo.deleted_at = Time.now
        deleted_repo.active = false
        deleted_repo.save!
        missing_repo.destroy!

        exemption_requests, _ = @org.fetch_bypass_requests
        assert_same_elements [request, @policy_request, deleted_repo_request, missing_repo_request], exemption_requests

        exemption_request_lookup = exemption_requests.each_with_object({}) do |request, hash|
          hash[request.id] = request
        end

        assert_equal "pending", exemption_request_lookup[request.id].status
        assert_equal "pending", exemption_request_lookup[@policy_request.id].status
        assert_equal "deleted", exemption_request_lookup[deleted_repo_request.id].status
        assert_equal "deleted", exemption_request_lookup[missing_repo_request.id].status
      end
    end
  end

  context "blocks_repository_rename?" do
    test "should return false on a default org ruleset" do
      repository_ruleset = create(:repository_ruleset, :example_ruleset, name: "ruleset-1", source: @org)
      create(:repository_rule_condition, :targets_all_repos, repository_ruleset:)

      refute @repo.blocks_repository_rename?(@org_admin)
    end

    test "should return false on a non-org ruleset" do
      different_repo = create(:repository, owner: @org_admin)
      repository_ruleset = create(:repository_ruleset, name: "rename-ruleset-1", source: different_repo)
      create(:repository_rule_condition, :targets_branch, repository_ruleset:)

      refute different_repo.blocks_repository_rename?(@org_admin)
    end

    test "should return false on a repo targeted by id" do
      repository_ruleset = create(:repository_ruleset, name: "rename-ruleset-1", source: @org)
      create(:repository_rule_condition, :targets_repo_by_id, repository_ruleset:, target_repository: @repo)

      refute @repo.blocks_repository_rename?(@org_admin)
    end

    test "should return true for a protected repo targeted by name" do
      repository_ruleset = create(:repository_ruleset, name: "rename-ruleset-1", source: @org)
      create(:repository_rule_condition, :targets_all_repos_protected, repository_ruleset:)

      assert @repo.blocks_repository_rename?(@org_admin)
    end

    test "should return false for a protected repo targeted by name if able to bypass" do
      repository_ruleset = create(:repository_ruleset, :org_admin_bypass_any, name: "rename-ruleset-1", source: @org)
      create(:repository_rule_condition, :targets_all_repos_protected, repository_ruleset:)

      refute @repo.blocks_repository_rename?(@org_admin)
    end
  end

  context "filtered_inherited_rulesets" do
    [true, false].each do |enabled_only|
      test "should only return applicable enabled enterprise rulesets for repository (enabled_only: #{enabled_only ? "yes" : "no"})" do
        enable_feature_flag(:enterprise_rulesets)
        enable_feature_flag(:enterprise_ref_rulesets)
        enable_feature_flag(:enterprise_custom_properties)

        enterprise_ruleset = create(:repository_ruleset, :targets_all_orgs, :targets_all_repos, source: @enterprise)
        disabled_enterprise_ruleset = create(:repository_ruleset, :targets_all_orgs, :targets_all_repos, source: @enterprise, enforcement: :disabled)
        evaluate_enterprise_ruleset = create(:repository_ruleset, :targets_all_orgs, :targets_all_repos, source: @enterprise, enforcement: :evaluate)
        non_matching_enterprise_ruleset = create(:repository_ruleset, :targets_all_orgs, source: @enterprise)
        create(:repository_rule_condition, target: "repository_property", parameters: {
          include: [
            { name: "visibility", property_values: ["internal"], source: "system" }
          ],
          exclude: []
        }, repository_ruleset: non_matching_enterprise_ruleset)

        org_ruleset = create(:repository_ruleset, :targets_all_repos, source: @org)
        repository_ruleset = create(:repository_ruleset, :example_ruleset, source: @repo)
        disabled_repository_ruleset = create(:repository_ruleset, :example_ruleset, source: @repo)

        expected_enterprise_ruleset_ids = if enabled_only
          [enterprise_ruleset.id, non_matching_enterprise_ruleset.id]
        else
          [enterprise_ruleset.id, disabled_enterprise_ruleset.id, evaluate_enterprise_ruleset.id, non_matching_enterprise_ruleset.id]
        end

        assert_same_elements [enterprise_ruleset.id, org_ruleset.id, repository_ruleset.id, disabled_repository_ruleset.id], @repo.filtered_inherited_rulesets(enabled_only:).map(&:id)
        assert_same_elements [enterprise_ruleset.id, non_matching_enterprise_ruleset.id, org_ruleset.id], @org.filtered_inherited_rulesets(enabled_only:).map(&:id)
        assert_same_elements expected_enterprise_ruleset_ids, @enterprise.filtered_inherited_rulesets(enabled_only:).map(&:id)
      end
    end

    test "enterprise rulesets should check both org and repo conditions for repo matching" do
      enable_feature_flag(:enterprise_rulesets)
      enable_feature_flag(:enterprise_ref_rulesets)

      enterprise_ruleset = create(:repository_ruleset, :targets_org, :targets_all_repos, :targets_default_branch, target: "branch", org: @org2, source: @enterprise)

      assert_same_elements [], @repo.filtered_inherited_rulesets(enabled_only: true).map(&:id)
      assert_same_elements [enterprise_ruleset.id], @repo2.filtered_inherited_rulesets(enabled_only: true).map(&:id)
    end
  end

  private

  def create_exemption_request(ruleset_source, repo, requester, reviewer: nil, response_status: :approved, created_at: Time.now, expires_at: 1.week.from_now)
    push_ruleset = create(:repository_ruleset, target: "push", source: ruleset_source)
    rule_config = create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 10
    })
    create(:repository_ruleset_bypass_actor, actor: @org_team, bypass_mode: "any", repository_ruleset: push_ruleset)

    ref_update = create_branch_update(repo)
    run = RuleEngine::RuleRun.failure(rule_config:, ref_update:, message: "failed")
    suite = RuleEngine::RuleSuite.for_ref_update(ref_update: ref_update, rule_runs: [run], actor: requester)
    suite.save!

    request = Exemptions::ExemptionRequest.create!(
      resource_owner: suite,
      requester:,
      resource_identifier: suite.after_oid,
      repository: suite.repository,
      request_type: "push_ruleset_bypass",
      created_at:,
      expires_at:
    )

    if reviewer
      response = Exemptions::ExemptionResponse.create!(
        exemption_request: request,
        reviewer:,
        status: response_status,
      )
    end

    [request, response]
  end

  def setup_rule_suites
    branch_ruleset = create(:repository_ruleset, :example_ruleset, source: @repo)
    tag_ruleset = create(:repository_ruleset, :tag_ruleset, source: @repo)

    branch_update1 = create_branch_update(@repo, name: "main")
    branch_run1 = RuleEngine::RuleRun.success(rule_config: branch_ruleset.rule_configurations.first, ref_update: branch_update1)
    branch_suite1 = RuleEngine::RuleSuite.for_ref_update(ref_update: branch_update1, rule_runs: [branch_run1], actor: @org_admin)
    branch_suite1.save

    branch_update2 = create_branch_update(@repo, name: "dev")
    branch_run2 = RuleEngine::RuleRun.success(rule_config: branch_ruleset.rule_configurations.first, ref_update: branch_update2)
    branch_suite2 = RuleEngine::RuleSuite.for_ref_update(ref_update: branch_update2, rule_runs: [branch_run2], actor: @org_admin)
    branch_suite2.save

    tag_update1 = create_tag_update(@repo, name: "1.0.0")
    tag_run1 = RuleEngine::RuleRun.success(rule_config: tag_ruleset.rule_configurations.first, ref_update: tag_update1)
    tag_suite1 = RuleEngine::RuleSuite.for_ref_update(ref_update: tag_update1, rule_runs: [tag_run1], actor: @org_admin)
    tag_suite1.save

    tag_update2 = create_tag_update(@repo, name: "dev")
    tag_run2 = RuleEngine::RuleRun.success(rule_config: tag_ruleset.rule_configurations.first, ref_update: tag_update2)
    tag_suite2 = RuleEngine::RuleSuite.for_ref_update(ref_update: tag_update2, rule_runs: [tag_run2], actor: @org_admin)
    tag_suite2.save

    {
      branch_suite1: branch_suite1,
      branch_suite2: branch_suite2,
      tag_suite1: tag_suite1,
      tag_suite2: tag_suite2,
    }
  end
end
