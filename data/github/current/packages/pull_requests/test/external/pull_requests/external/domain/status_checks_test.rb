# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module External
    module Domain
      class StatusChecksTest < GitHub::TestCase
        extend T::Sig

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

              domain = PullRequests::External::Domain::StatusChecks.new(:test)
              canonical_checks = domain.for_pull_request(@pull)

              assert_equal 1, canonical_checks.size
              check = T.must(canonical_checks.first)
              assert_equal "some-test", check.context
              refute_predicate check, :required?
            end

            test "finds check runs on head commit" do
              create_check_run(context: "some-test", sha: @pull.head_sha)

              domain = PullRequests::External::Domain::StatusChecks.new(:test)
              canonical_checks = domain.for_pull_request(@pull)

              assert_equal 1, canonical_checks.size
              check = T.must(canonical_checks.first)
              assert_equal "some-test", check.context
              refute_predicate check, :required?
            end

            test "finds statuses on merge commit" do
              @pull.create_merge_commit
              create_status(context: "some-test", sha: @pull.merge_commit_sha)

              domain = PullRequests::External::Domain::StatusChecks.new(:test)
              canonical_checks = domain.for_pull_request(@pull)

              assert_equal 1, canonical_checks.size
              check = T.must(canonical_checks.first)
              assert_equal "some-test", check.context
              refute_predicate check, :required?
            end

            test "finds check runs on merge commit" do
              @pull.create_merge_commit
              create_check_run(context: "some-test", sha: @pull.merge_commit_sha)

              domain = PullRequests::External::Domain::StatusChecks.new(:test)
              canonical_checks = domain.for_pull_request(@pull)

              assert_equal 1, canonical_checks.size
              check = T.must(canonical_checks.first)
              assert_equal "some-test", check.context
              refute_predicate check, :required?
            end
          end

          context "for a PR with required checks" do
            test "reports expected checks" do
              require_checks(["important-tests"])

              domain = PullRequests::External::Domain::StatusChecks.new(:test)
              canonical_checks = domain.for_pull_request(@pull)

              assert_equal 1, canonical_checks.size
              check = T.must(canonical_checks.first)
              assert_equal "important-tests", check.context
              assert_equal "expected",  check.state
              assert_predicate check, :required?
            end

            test "does not report expected checks if there is a matching status" do
              require_checks(["important-tests"])
              create_status(
                context: "important-tests",
                sha: @pull.head_sha,
                state: "success",
              )

              domain = PullRequests::External::Domain::StatusChecks.new(:test)
              canonical_checks = domain.for_pull_request(@pull)

              assert_equal 1, canonical_checks.size
              check = T.must(canonical_checks.first)
              assert_equal "important-tests", check.context
              assert_equal "success",  check.state
              assert_predicate check, :required?
            end

            test "does not report expected checks if there is a matching check run" do
              require_checks(["important-tests"])
              create_check_run(
                context: "important-tests",
                sha: @pull.head_sha,
                conclusion: :success,
              )

              domain = PullRequests::External::Domain::StatusChecks.new(:test)
              canonical_checks = domain.for_pull_request(@pull)

              assert_equal 1, canonical_checks.size
              check = T.must(canonical_checks.first)
              assert_equal "important-tests", check.context
              assert_equal "success",  check.state
              assert_predicate check, :required?
            end

            test "invokes the rule engine to disambiguate between required checks" do
              require_checks(%w[test-1 test-2])
              @pull.create_merge_commit
              create_status(
                context: "test-1",
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
                context: "test-2",
                sha: @pull.head_sha,
                state: "failure",
              )

              domain = PullRequests::External::Domain::StatusChecks.new(:test)
              canonical_checks = domain.for_pull_request(@pull)

              # NOTE: We're not making any particular assertions here about _which_
              #  statuses the `RuleEngine` picked, only that we didn't end up with
              #  any duplicates.
              assert_equal 2, canonical_checks.size
              assert_same_elements %w[test-1 test-2], canonical_checks.map(&:context)
              assert_equal [true, true], canonical_checks.map(&:required?)
            end
          end

          test "disambiguates non-required checks in favour of the merge commit" do
            @pull.create_merge_commit
            create_status(
              context: "test-1",
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
              context: "test-2",
              sha: @pull.head_sha,
              state: "failure",
            )

            domain = PullRequests::External::Domain::StatusChecks.new(:test)
            canonical_checks = domain.for_pull_request(@pull)

            assert_same_elements(
              [{ "test-1" => "failure" }, { "test-2" => "success" }],
              canonical_checks.map { { _1.context => _1.state } },
            )
          end
        end

        private

        sig { params(context: String, sha: String, conclusion: Symbol).returns(CheckRun) }
        def create_check_run(context:, sha:, conclusion: :success)
          check_suite = create(
            :check_suite,
            repository: @repo,
            github_app: @integration,
            head_sha: sha,
          )
          create(
            :check_run, :completed,
            repository: @repo,
            creator: @integration.bot,
            display_name: context,
            check_suite:,
            conclusion:,
          )
        end

        sig { params(context: String, sha: String, state: String).returns(Status) }
        def create_status(context:, sha:, state: "success")
          create(:status, repository: @repo, creator: @owner, context:, sha:, state:)
        end

        sig { params(contexts: T::Array[String]).void }
        def require_checks(contexts)
          protected_branch = create(
            :protected_branch,
            repository: @repo,
            required_status_checks_enforcement_level: :non_admins,
            name: @pull.base_ref,
          )
          contexts.each do |context|
            protected_branch.required_status_checks.create!(context:)
          end
        end
      end
    end
  end
end
