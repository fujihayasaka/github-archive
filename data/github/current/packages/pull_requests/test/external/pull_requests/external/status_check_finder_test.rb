# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module External
    class StatusCheckFinderTest < GitHub::TestCase
      test "can represent all possible rule engine results" do
        RuleEngine::StatusCheckEvaluator::StatusCheckResult::CODES.each do |code|
          assert_nothing_raised do
            Domain::StatusChecks::RuleEvaluationResult.deserialize(code)
          end
        end
      end

      context ".batch_load" do
        test "loads pull request checks data efficiently" do
          user = create(:user)
          repository = create(
            :repository,
            from_example: :pull_request_bases,
            owner: user,
          )
          protected_branch = create(
            :protected_branch,
            repository:,
            required_status_checks_enforcement_level: :non_admins,
            name: "simple2/0",
          )
          protected_branch.required_status_checks.create!(context: "required1")
          protected_branch.required_status_checks.create!(context: "required2")
          repository_ruleset = create(
            :repository_ruleset, :targets_all_branches,
            source: repository,
          )
          create(
            :repository_rule_configuration, :required_status_checks,
            repository_ruleset:,
            contexts: %w[required3 required4],
          )

          pull_requests = []
          queries_by_record_count = {}

          [
            { base_ref: "simple2/0", head_ref: "simple2/A" },
            { base_ref: "simple2/0", head_ref: "simple2/B" },
            { base_ref: "simple2/0", head_ref: "simple2/C" },
          ].each.with_index do |pull_attrs, index|
            pull = create(:pull_request, repository:, user:, **pull_attrs)
            pull.create_merge_commit
            create(
              :status,
              repository:,
              creator: user,
              sha: pull.head_sha,
              context: "required1",
              state: "success",
            )
            create(
              :status,
              repository:,
              creator: user,
              sha: pull.merge_commit_sha,
              context: "optional1",
              state: "success",
            )
            check_suite = create(
              :check_suite,
              repository:,
              head_sha: pull.head_sha,
            )
            create(
              :check_run, :completed,
              repository:,
              check_suite:,
              display_name: "required2",
              conclusion: :success,
            )
            check_suite = create(
              :check_suite,
              repository:,
              head_sha: pull.merge_commit_sha,
            )
            create(
              :check_run, :completed,
              repository:,
              check_suite:,
              display_name: "optional2",
              conclusion: :success,
            )

            pull_requests << pull

            pull_requests.each(&:reload)
            _, queries = log_cleaned_queries do
              StatusCheckFinder.batch_load(pull_requests)
            end

            queries_by_record_count[index + 1] = queries.map(&:digested_sql)
          end

          delta_1_to_2 = queries_by_record_count[2].count - queries_by_record_count[1].count
          delta_2_to_3 = queries_by_record_count[3].count - queries_by_record_count[2].count

          assert(
            delta_1_to_2 == delta_2_to_3 && delta_1_to_2 == 0,
            "Expected the number of queries to remain constant "\
            "as the number of PRs and checks increases, "\
            "but it did not:\n\n"\
            " - 1 entry    =>  #{queries_by_record_count[1].count} queries\n"\
            " - 2 entries  =>  #{queries_by_record_count[2].count} queries (+ #{delta_1_to_2})\n"\
            " - 3 entries  =>  #{queries_by_record_count[3].count} queries (+ #{delta_2_to_3})\n\n"\
            "The diff between the executed queries for 2 entries (expected) and "\
            "the executed queries for 3 entries (actual) was:\n\n"\
            "#{diff(queries_by_record_count[2], queries_by_record_count[3])}"
          )
        end
      end
    end
  end
end
