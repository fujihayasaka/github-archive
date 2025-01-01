# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module External
    module Domain
      class StatusChecksTest < GitHub::TestCase
        fixtures do
          @owner = create(:user)
          @repo = create(:repository, owner: @owner, from_example: :simple)
          @pull = create(
            :pull_request,
            repository: @repo,
            user: @owner,
            head_ref: "cr-line-endings",
            base_ref: "master",
          )

          @integration = create(:integration)

          example_repo_snapshot
        end

        setup do
          example_repo_restore
        end

        context "#canonical_checks" do
          context "for a vanilla PR with no rules" do
            test "finds statuses on head commit" do
              create_status(context: "some-test", sha: @pull.head_sha)

              domain = PullRequests::External::Domain::StatusChecks.new
              canonical_checks = domain.for_pull_request(@pull)

              assert_equal 1, canonical_checks.size
              check = T.must(canonical_checks.first)
              assert_equal "some-test", check.context
              refute_predicate check, :required?
              assert_equal StatusChecks::RuleEvaluationResult::NotRequired,
                check.rule_evaluation_result
            end

            test "finds check runs on head commit" do
              create_check_run(context: "some-test", sha: @pull.head_sha)

              domain = PullRequests::External::Domain::StatusChecks.new
              canonical_checks = domain.for_pull_request(@pull)

              assert_equal 1, canonical_checks.size
              check = T.must(canonical_checks.first)
              assert_equal "some-test", check.context
              refute_predicate check, :required?
              assert_equal StatusChecks::RuleEvaluationResult::NotRequired,
                check.rule_evaluation_result
            end

            test "finds statuses on merge commit" do
              @pull.create_merge_commit
              create_status(context: "some-test", sha: @pull.merge_commit_sha)

              domain = PullRequests::External::Domain::StatusChecks.new
              canonical_checks = domain.for_pull_request(@pull)

              assert_equal 1, canonical_checks.size
              check = T.must(canonical_checks.first)
              assert_equal "some-test", check.context
              refute_predicate check, :required?
              assert_equal StatusChecks::RuleEvaluationResult::NotRequired,
                check.rule_evaluation_result
            end

            test "finds check runs on merge commit" do
              @pull.create_merge_commit
              create_check_run(context: "some-test", sha: @pull.merge_commit_sha)

              domain = PullRequests::External::Domain::StatusChecks.new
              canonical_checks = domain.for_pull_request(@pull)

              assert_equal 1, canonical_checks.size
              check = T.must(canonical_checks.first)
              assert_equal "some-test", check.context
              refute_predicate check, :required?
              assert_equal StatusChecks::RuleEvaluationResult::NotRequired,
                check.rule_evaluation_result
            end
          end

          context "for a PR with required checks" do
            test "reports expected checks" do
              create_protected_branch_with_required_checks([
                { context: "important-tests" },
              ])

              domain = PullRequests::External::Domain::StatusChecks.new
              canonical_checks = domain.for_pull_request(@pull)

              assert_equal 1, canonical_checks.size
              check = T.must(canonical_checks.first)
              assert_equal "important-tests", check.context
              assert_equal "expected",  check.state
              assert_predicate check, :required?
              assert_equal StatusChecks::RuleEvaluationResult::Missing,
                check.rule_evaluation_result
            end

            test "does not report expected checks if there is a matching status" do
              create_protected_branch_with_required_checks([
                { context: "important-tests" },
              ])
              create_status(
                context: "important-tests",
                sha: @pull.head_sha,
                state: "success",
              )

              domain = PullRequests::External::Domain::StatusChecks.new
              canonical_checks = domain.for_pull_request(@pull)

              assert_equal 1, canonical_checks.size
              check = T.must(canonical_checks.first)
              assert_equal "important-tests", check.context
              assert_equal "success",  check.state
              assert_predicate check, :required?
              assert_equal StatusChecks::RuleEvaluationResult::Success,
                check.rule_evaluation_result
            end

            test "does not report expected checks if there is a matching check run" do
              create_protected_branch_with_required_checks([
                { context: "important-tests" },
              ])
              create_check_run(
                context: "important-tests",
                sha: @pull.head_sha,
                conclusion: :success,
              )

              domain = PullRequests::External::Domain::StatusChecks.new
              canonical_checks = domain.for_pull_request(@pull)

              assert_equal 1, canonical_checks.size
              check = T.must(canonical_checks.first)
              assert_equal "important-tests", check.context
              assert_equal "success",  check.state
              assert_predicate check, :required?
              assert_equal StatusChecks::RuleEvaluationResult::Success,
                check.rule_evaluation_result
            end

            test "associates the relevant rule engine result with every matching status" do
              create_protected_branch_with_required_checks([
                { context: "test-1" },
                { context: "test-2" },
              ])
              @pull.create_merge_commit
              create_status(
                context: "TEST-1",
                sha: @pull.merge_commit_sha,
                state: "failure",
              )
              create_status(
                context: "test-2",
                sha: @pull.merge_commit_sha,
                state: "success",
              )
              create_status(
                context: "test-1",
                sha: @pull.head_sha,
                state: "success",
              )
              create_status(
                context: "TEST-2",
                sha: @pull.head_sha,
                state: "failure",
              )

              domain = PullRequests::External::Domain::StatusChecks.new
              canonical_checks = domain.for_pull_request(@pull)
              canonical_checks_by_context = canonical_checks.group_by { _1.context.downcase }

              assert_equal 4, canonical_checks.size

              test1_checks = canonical_checks_by_context.fetch("test-1", [])
              assert_equal 2, test1_checks.size
              assert_equal [true, true], test1_checks.map(&:required?)
              assert_equal %w[failure success], test1_checks.map(&:state).sort
              assert_equal [StatusChecks::RuleEvaluationResult::Unsuccessful],
                test1_checks.map(&:rule_evaluation_result).uniq,
                "Expected the rule engine to prefer the merge commit result"

              test2_checks = canonical_checks_by_context.fetch("test-2", [])
              assert_equal 2, test2_checks.size
              assert_equal [true, true], test2_checks.map(&:required?)
              assert_equal %w[failure success], test2_checks.map(&:state).sort
              assert_equal [StatusChecks::RuleEvaluationResult::Success],
                test2_checks.map(&:rule_evaluation_result).uniq,
                "Expected the rule engine to prefer the merge commit result"
            end
          end

          test "returns multiple results for the same context when they are reported against different commits" do
            @pull.create_merge_commit
            create_status(
              context: "test-1",
              sha: @pull.merge_commit_sha,
              state: "failure",
            )
            create_status(
              context: "test-1",
              sha: @pull.head_sha,
              state: "success",
            )

            domain = PullRequests::External::Domain::StatusChecks.new
            canonical_checks = domain.for_pull_request(@pull)

            assert_same_elements(
              [{ "test-1" => "failure" }, { "test-1" => "success" }],
              canonical_checks.map { { _1.context => _1.state } },
            )
          end

          test "correctly combines results when two rulesets have different requirements" do
            # A check run from @integration _will_ satisfy this rule.
            create_repo_ruleset_with_required_checks([
              { context: "test" },
            ])
            # A check run from @integration _will not_ satisfy this rule.
            other_integration = create(:integration)
            create_protected_branch_with_required_checks([
              { context: "test", integration_id: other_integration.id },
            ])
            create_check_run(
              context: "test",
              sha: @pull.head_sha,
              creator: @integration.bot,
            )

            domain = PullRequests::External::Domain::StatusChecks.new
            canonical_checks = domain.for_pull_request(@pull)

            assert_equal 1, canonical_checks.size
            check = T.must(canonical_checks.first)
            assert_equal "test", check.context
            assert_equal "success",  check.state
            assert_predicate check, :required?

            # With two rules (one satisfied, one unsatisfied) we expect the
            # unsatisfied result to be reported.
            assert_equal StatusChecks::RuleEvaluationResult::InvalidIntegration,
              check.rule_evaluation_result
          end

          test "only returns one expected check when two rules require exactly the same thing" do
            create_repo_ruleset_with_required_checks([
              { context: "test" },
            ])
            create_protected_branch_with_required_checks([
              { context: "test" },
            ])

            domain = PullRequests::External::Domain::StatusChecks.new
            canonical_checks = domain.for_pull_request(@pull)

            assert_equal 1, canonical_checks.size
            check = T.must(canonical_checks.first)
            assert_equal "test", check.context
            assert_equal "expected", check.state
            assert_predicate check, :required?
            assert_equal StatusChecks::RuleEvaluationResult::Missing,
              check.rule_evaluation_result
          end

          test "returns two expected check when two rules require the same context from different integrations" do
            create_repo_ruleset_with_required_checks([
              { context: "test" },
            ])
            create_protected_branch_with_required_checks([
              { context: "test", integration_id: @integration.id },
            ])

            domain = PullRequests::External::Domain::StatusChecks.new
            canonical_checks = domain.for_pull_request(@pull)

            assert_equal 2, canonical_checks.size
            assert_equal %w[test test], canonical_checks.map(&:context)
            assert_equal %w[expected expected], canonical_checks.map(&:state)
            assert_equal [true, true], canonical_checks.map(&:required?)
            assert_same_elements(
              [@integration.id, nil],
              canonical_checks.map(&:integration_id)
            )
            assert_equal(
              [StatusChecks::RuleEvaluationResult::Missing, StatusChecks::RuleEvaluationResult::Missing],
              canonical_checks.map(&:rule_evaluation_result)
            )
          end
        end

        private

        sig { params(context: String, sha: String, conclusion: Symbol, creator: T.nilable(Bot)).returns(CheckRun) }
        def create_check_run(context:, sha:, conclusion: :success, creator: nil)
          check_suite = create(
            :check_suite,
            repository: @repo,
            github_app: @integration,
            head_sha: sha,
          )
          create(
            :check_run, :completed,
            repository: @repo,
            creator: creator || @integration.bot,
            display_name: context,
            check_suite:,
            conclusion:,
          )
        end

        sig { params(context: String, sha: String, state: String).returns(Status) }
        def create_status(context:, sha:, state: "success")
          create(:status, repository: @repo, creator: @owner, context:, sha:, state:)
        end

        sig { params(required_status_checks: T::Array[T::Hash[Symbol, T.any(String, Integer)]]).void }
        def create_protected_branch_with_required_checks(required_status_checks)
          protected_branch = create(
            :protected_branch,
            repository: @repo,
            required_status_checks_enforcement_level: :non_admins,
            name: @pull.base_ref,
          )
          required_status_checks.each do |attributes|
            protected_branch.required_status_checks.create!(**attributes)
          end
        end

        sig do
          params(
            required_status_checks: T::Array[T::Hash[Symbol, T.any(String, Integer)]],
          ).void
        end
        def create_repo_ruleset_with_required_checks(required_status_checks)
          create(
            :repository_ruleset,
            :targets_default_branch,
            source: @repo,
            rule_configurations: [
              build(
                :repository_rule_configuration,
                rule_type: "required_status_checks",
                parameters: {
                  strict_required_status_checks_policy: true,
                  required_status_checks:,
                },
              ),
            ],
          )
        end
      end
    end
  end
end
