# typed: true
# frozen_string_literal: true

require "test_helper"

class RuleEngineRuleSettingsDependencyTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper

  fixtures do
    @org_admin = create(:user)
    @org = create(:business_plus_org, admin: @org_admin)
    @repo = create(:repository, owner: @org)
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

    @fetch_suites_org = create(:business_plus_org, admin: @org_admin)
    @fetch_suites_repo = create(:repository, owner: @fetch_suites_org)
    @insights_cases = generate_insights_cases
  end

  setup do
    GitHub.flipper[:push_rulesets].enable
    GitHub.flipper[:push_ruleset_delegated_bypass].enable
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
      assert_equal 1, suites.size
      assert_equal suite.id, suites.first.id
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
      skip "re-enable this test when we store the organization ID on RuleSuites"

      ruleset = create(:repository_ruleset, :example_ruleset, source: @org)

      # Simulate a repo that was moved out of the org
      repo_not_owned_by_org = create(:repository)

      ref_update = create_branch_update(repo_not_owned_by_org, name: "main")
      run = RuleEngine::RuleRun.success(rule_config: ruleset.rule_configurations.first, ref_update: ref_update)
      suite = RuleEngine::RuleSuite.for_ref_update(ref_update: ref_update, rule_runs: [run], actor: @org_admin)
      suite.save

      suites, _ = @org.fetch_rule_suites
      assert_equal 1, suites.size
      assert_equal suite.id, suites.first.id
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

    %w[pass fail bypass all].each do |rule_status|
      %w[all active evaluate].each do |evaluate_status|
        test "matrix test: rule_status:#{rule_status}, evaluate_status:#{evaluate_status}" do
          expected, unexpected = insights_case_generator(rule_status:, evaluate_status:)

          suites, _ = @fetch_suites_repo.fetch_rule_suites(rule_status:, evaluate_status:, page_size: expected.size + unexpected.size)

          extras = unexpected.filter { |suite, _| suites.include?(suite) }
          missing = expected.reject { |suite, _| suites.include?(suite) }
          message = ""
          if extras.any?
            message += "\nQuery matched suites that were unexpected (looking for #{rule_status}-#{evaluate_status})\n"
            message += extras.map do |suite, matches|
              "  - Suite ##{suite.id} should only match #{matches}"
            end.join("\n")
          end
          if missing.any?
            message += "\nQuery did not match suites that were expected (looking for #{rule_status}-#{evaluate_status})\n"
            message += missing.map do |suite, matches|
              "  - Suite ##{suite.id} should match #{matches}"
            end.join("\n")
          end

          assert_equal expected.size, suites.size, message
          assert_same_elements expected.keys.map(&:id), suites.map(&:id), message
        end
      end
    end
  end

  sig { returns(T::Hash[RuleEngine::RuleSuite, T::Array[String]]) }
  def generate_insights_cases
    {
      create_rule_suite(runs: [{ result: "allowed", source: @fetch_suites_repo, evaluate_mode: false, can_bypass: false }]) => %w[pass-active pass-all].freeze,
      create_rule_suite(runs: [{ result: "allowed", source: @fetch_suites_org, evaluate_mode: false, can_bypass: false }]) => %w[pass-active pass-all].freeze,
      create_rule_suite(runs: [
        { result: "allowed", source: @fetch_suites_org, evaluate_mode: false, can_bypass: false },
        { result: "failed", source: @fetch_suites_org, evaluate_mode: true, can_bypass: false },
      ]) => %w[pass-active pass-all].freeze,
      create_rule_suite(runs: [
        { result: "allowed", source: @fetch_suites_repo, evaluate_mode: false, can_bypass: false },
        { result: "failed", source: @fetch_suites_org, evaluate_mode: true, can_bypass: false },
      ]) => %w[pass-active pass-all].freeze,
      create_rule_suite(runs: [
        { result: "allowed", source: @fetch_suites_org, evaluate_mode: false, can_bypass: false },
        { result: "allowed", source: @fetch_suites_org, evaluate_mode: true, can_bypass: false }
      ]) => %w[ pass-active pass-all].freeze,
      create_rule_suite(runs: [
        { result: "allowed", source: @fetch_suites_repo, evaluate_mode: false, can_bypass: false },
        { result: "allowed", source: @fetch_suites_repo, evaluate_mode: true, can_bypass: false }
      ]) => %w[pass-active pass-evaluate pass-all].freeze,
      create_rule_suite(runs: [
        { result: "allowed", source: @fetch_suites_repo, evaluate_mode: true, can_bypass: false },
        { result: "allowed", source: @fetch_suites_org, evaluate_mode: true, can_bypass: false }
      ]) => %w[pass-evaluate pass-all].freeze,
      create_rule_suite(runs: [{ result: "allowed", source: @fetch_suites_repo, evaluate_mode: true, can_bypass: false }]) => %w[pass-evaluate pass-all].freeze,
      create_rule_suite(runs: [
        { result: "allowed", source: @fetch_suites_repo, evaluate_mode: true, can_bypass: false },
        { result: "failed", source: @fetch_suites_org, evaluate_mode: true, can_bypass: false },
      ]) => %w[pass-evaluate pass-all].freeze,
      create_rule_suite(runs: [{ result: "failed", source: @fetch_suites_repo, evaluate_mode: false, can_bypass: false }]) => %w[fail-active fail-all].freeze,
      create_rule_suite(runs: [{ result: "failed", source: @fetch_suites_org, evaluate_mode: false, can_bypass: false }]) => %w[fail-active fail-all].freeze,
      create_rule_suite(runs: [{ result: "failed", source: @fetch_suites_repo, evaluate_mode: true, can_bypass: false }]) => %w[fail-evaluate fail-all].freeze,
      create_rule_suite(runs: [
        { result: "failed", source: @fetch_suites_repo, evaluate_mode: true, can_bypass: false },
        { result: "failed", source: @fetch_suites_org, evaluate_mode: true, can_bypass: false },
      ]) => %w[fail-evaluate fail-all].freeze,
      create_rule_suite(runs: [{ result: "failed", source: @fetch_suites_repo, evaluate_mode: false, can_bypass: true }]) => %w[bypass-active bypass-all].freeze,
      create_rule_suite(runs: [{ result: "failed", source: @fetch_suites_org, evaluate_mode: false, can_bypass: true }]) => %w[bypass-active bypass-all].freeze,
      create_rule_suite(runs: [{ result: "failed", source: @fetch_suites_repo, evaluate_mode: true, can_bypass: true }]) => %w[bypass-evaluate bypass-all].freeze,
      create_rule_suite(runs: [
        { result: "failed", source: @fetch_suites_repo, evaluate_mode: true, can_bypass: true },
        { result: "failed", source: @fetch_suites_org, evaluate_mode: true, can_bypass: true },
      ]) => %w[bypass-evaluate bypass-all].freeze,
      create_rule_suite(runs: [
        { result: "failed", source: @fetch_suites_repo, evaluate_mode: false, can_bypass: false },
        { result: "failed", source: @fetch_suites_repo, evaluate_mode: true, can_bypass: true },
      ]) => %w[bypass-evaluate fail-active fail-all].freeze,
      create_rule_suite(runs: [
        { result: "failed", source: @fetch_suites_repo, evaluate_mode: false, can_bypass: true },
        { result: "failed", source: @fetch_suites_repo, evaluate_mode: true, can_bypass: true },
      ]) => %w[bypass-active bypass-evaluate bypass-all].freeze,
      create_rule_suite(runs: [{ result: "allowed", source: @fetch_suites_org, evaluate_mode: true, can_bypass: false }]) => [].freeze,
      create_rule_suite(runs: [{ result: "failed", source: @fetch_suites_org, evaluate_mode: true, can_bypass: true }]) => [].freeze,
    }.freeze
  end

  sig do
    params(rule_status: String, evaluate_status: String)
    .returns([T::Hash[RuleEngine::RuleSuite, T::Array[String]], T::Hash[RuleEngine::RuleSuite, T::Array[String]]])
  end
  def insights_case_generator(rule_status:, evaluate_status:)
    expected = @insights_cases.filter do |_, matches|
      next true if matches.include?("#{rule_status}-#{evaluate_status}")
      next true if rule_status == "all" && matches.any? { |match| match.ends_with?("-#{evaluate_status}") }
      false
    end
    unexpected = @insights_cases.reject { |case_match| expected.include?(case_match) }

    [expected, unexpected]
  end

  sig do
    params(
      runs: T::Array[{
        source: RuleEngine::Types::RuleSource,
        result: String,
        evaluate_mode: T::Boolean,
        can_bypass: T::Boolean,
      }],
    ).returns(RuleEngine::RuleSuite)
  end
  def create_rule_suite(runs:)
    ref_update = create_branch_update(@fetch_suites_repo)

    rule_runs = runs.map do |run|
      ruleset = create(:repository_ruleset, :example_ruleset, source: run[:source])
      ruleset.update!(enforcement: :evaluate) if run[:evaluate_mode]

      run = if run[:result] == "allowed"
        RuleEngine::RuleRun.success(rule_config: ruleset.rule_configurations.first, ref_update: ref_update)
      else
        RuleEngine::RuleRun.failure(rule_config: ruleset.rule_configurations.first, ref_update: ref_update, message: "fail")
      end
    end

    suite = RuleEngine::RuleSuite.for_ref_update(ref_update: ref_update, rule_runs:, actor: @org_admin)
    suite.result = :bypassed if runs.any? { !_1[:evaluate_mode] } && runs.filter { !_1[:evaluate_mode] }.all? { _1[:can_bypass] }
    suite.save

    suite.source_results.each do |source_result|
      filtered_runs = runs.filter { |run| source_result.source == run[:source] }
      source_result.result = :bypassed if filtered_runs.any? { !_1[:evaluate_mode] } && filtered_runs.filter { !_1[:evaluate_mode] }.all? { _1[:can_bypass] }
      source_result.evaluate_result = :bypassed if filtered_runs.any? { _1[:evaluate_mode] } && filtered_runs.filter { _1[:evaluate_mode] }.all? { _1[:can_bypass] }
      source_result.save
    end

    suite
  end

  context "fetch_bypass_requests" do
    test "returns all bypass requests for the repository" do
      request, _ = create_exemption_request(@priv_repo, @priv_repo, @org_admin)

      exemption_requests, _ = @priv_repo.fetch_bypass_requests(repository_id: @priv_repo.id)
      assert_equal 1, exemption_requests.size
    end

    test "filter by approvers" do
      create_exemption_request(@priv_repo, @priv_repo, @org_admin, reviewer: @collaborator)

      exemption_requests, _ = @priv_repo.fetch_bypass_requests(repository_id: @priv_repo.id, approver: @collaborator)
      assert_equal 1, exemption_requests.size

      exemption_requests, _ = @priv_repo.fetch_bypass_requests(repository_id: @priv_repo.id, approver: @member)
      assert_equal 0, exemption_requests.size

    end

    test "filter by requesters" do
      create_exemption_request(@priv_repo, @priv_repo, @org_admin)
      0..2.times { create_exemption_request(@priv_repo, @priv_repo, @collaborator) }

      exemption_requests, _ = @priv_repo.fetch_bypass_requests(repository_id: @priv_repo.id, requester: @collaborator)
      assert_equal 2, exemption_requests.size

      exemption_requests, _ = @priv_repo.fetch_bypass_requests(repository_id: @priv_repo.id, requester: @org_admin)
      assert_equal 1, exemption_requests.size
    end

    test "filter by time period" do
      # right before the 1 week mark
      create_exemption_request(@priv_repo, @priv_repo, @org_admin, created_at: 1.week.ago - 1.hour)

      exemption_requests, _ = @priv_repo.fetch_bypass_requests(repository_id: @priv_repo.id, time_period: "week")
      assert_equal 0, exemption_requests.size

      exemption_requests, _ = @priv_repo.fetch_bypass_requests(repository_id: @priv_repo.id, time_period: "month")
      assert_equal 1, exemption_requests.size
    end

    test "filter by status" do
      # our time filters are a bit strange
      create_exemption_request(@priv_repo, @priv_repo, @org_admin)
      create_exemption_request(@priv_repo, @priv_repo, @org_admin, created_at: 1.week.ago + 1.hour, expires_at: Time.now - 1.hour)
      create_exemption_request(@priv_repo, @priv_repo, @org_admin, created_at: 1.month.ago + 1.hour, expires_at: Time.now - 1.hour)
      create_exemption_request(@priv_repo, @priv_repo, @org_admin, reviewer: @collaborator, response_status: :rejected)

      status = "expired"
      exemption_requests, _ = @priv_repo.fetch_bypass_requests(repository_id: @priv_repo.id, request_status: status, time_period: "week")
      assert_equal 1, exemption_requests.size

      status = "expired"
      exemption_requests, _ = @priv_repo.fetch_bypass_requests(repository_id: @priv_repo.id, request_status: status, time_period: "month")
      assert_equal 2, exemption_requests.size

      status = "denied"
      exemption_requests, _ = @priv_repo.fetch_bypass_requests(repository_id: @priv_repo.id, request_status: status)
      assert_equal 1, exemption_requests.size

      status = "open"
      exemption_requests, _ = @priv_repo.fetch_bypass_requests(repository_id: @priv_repo.id, request_status: status)
      assert_equal 1, exemption_requests.size
    end

    test "paging works correctly" do
      0..11.times { create_exemption_request(@priv_repo, @priv_repo, @org_admin) }

      # page size 5
      exemption_requests, has_more = @priv_repo.fetch_bypass_requests(repository_id: @priv_repo.id, page_size: 5, page: 1)
      assert_equal 5, exemption_requests.size
      assert has_more

      exemption_requests, has_more = @priv_repo.fetch_bypass_requests(repository_id: @priv_repo.id, page_size: 5, page: 2)
      assert_equal 5, exemption_requests.size
      assert has_more

      exemption_requests, has_more = @priv_repo.fetch_bypass_requests(repository_id: @priv_repo.id, page_size: 5, page: 3)
      assert_equal 1, exemption_requests.size
      refute has_more

      # Page size 10

      exemption_requests, has_more = @priv_repo.fetch_bypass_requests(repository_id: @priv_repo.id, page_size: 10, page: 1)
      assert_equal 10, exemption_requests.size
      assert has_more

      exemption_requests, has_more = @priv_repo.fetch_bypass_requests(repository_id: @priv_repo.id, page_size: 10, page: 2)
      assert_equal 1, exemption_requests.size
      refute has_more

      exemption_requests, has_more = @priv_repo.fetch_bypass_requests(repository_id: @priv_repo.id, page_size: 10, page: 3)
      assert_equal 0, exemption_requests.size
      refute has_more

    end

    context "organization specific fetch_bypass_requests" do
      test "returns all bypass requests for organization level rulesets" do
        create_exemption_request(@org, @priv_repo, @org_admin)
        create_exemption_request(@priv_repo, @priv_repo, @org_admin)

        exemption_requests, _ = @org.fetch_bypass_requests(repository_id: @priv_repo.id)
        assert_equal 1, exemption_requests.size
      end

      test "filter by repository" do
        request, _ = create_exemption_request(@org, @priv_repo, @org_admin)
        empty_priv_repo = create(:private_repository, owner: @org, from_example: :simple)

        exemption_requests, _ = @org.fetch_bypass_requests(repository_id: @priv_repo.id)
        assert_equal 1, exemption_requests.size

        exemption_requests, _ = @org.fetch_bypass_requests(repository_id: empty_priv_repo.id)
        assert_equal 0, exemption_requests.size
      end
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
