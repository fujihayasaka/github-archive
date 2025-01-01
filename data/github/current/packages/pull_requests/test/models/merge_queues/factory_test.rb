# typed: true
# frozen_string_literal: true

require "test_helper"

module MergeQueues
  class FactoryTest < GitHub::TestCase
    test "it returns an empty collection if nothing exists" do
      queue = create(:merge_queue)
      entries = build_entry_list(queue)
      assert entries.empty?
    end

    test "it returns a sorted list putting jumped at the top" do

      queue = create(:merge_queue)
      entry_1 = create(:merge_queue_entry, queue: queue)
      entry_2 = create(:merge_queue_entry, queue: queue, jump_queue: true)
      entry_3 = create(:merge_queue_entry, queue: queue, jump_queue: true)
      entry_4 = create(:merge_queue_entry, queue: queue)

      pr_1 = entry_1.pull_request
      entry_1.update(
        head_ref: pr_1.head_ref,
        head_sha: pr_1.head_sha,
        base_sha: pr_1.base_sha,
      )

      pr_2 = entry_2.pull_request
      entry_2.update(
        head_ref: pr_2.head_ref,
        head_sha: pr_2.head_sha,
        base_sha: pr_2.base_sha,
      )

      pr_3 = entry_3.pull_request
      entry_3.update(
        head_ref: pr_3.head_ref,
        head_sha: pr_3.head_sha,
        base_sha: pr_3.base_sha,
      )

      pr_4 = entry_4.pull_request
      entry_4.update(
        head_ref: pr_4.head_ref,
        head_sha: pr_4.head_sha,
        base_sha: pr_4.base_sha,
      )

      entries = build_entry_list(queue)

      assert_equal [entry_2.id, entry_3.id, entry_1.id, entry_4.id], entries.map(&:merge_queue_entry_id)
    end

    test "generates an entry without changing the state when it is not pending" do
      head_sha = "a" * 40
      base_sha = "b" * 40
      head_ref = "merge-queue/example"
      attempts = 1

      mqe = create(
        :merge_queue_entry,
        state: Entry::State::Unmergeable::VALUE,
        dequeue_reason: Entry::RemovalReason::FailedChecks.to_i,
        head_sha:,
        base_sha:,
        head_ref:,
        attempts:
      )

      entries = build_entry_list(mqe.queue)

      assert_equal 1, entries.count

      entry = T.must(entries.first)

      assert_equal mqe.id, entry.merge_queue_entry_id
      assert_equal head_sha, entry.head_sha
      assert_equal base_sha, entry.base_sha
      assert entry.state.is_a?(Entry::State::Unmergeable)
      assert_equal Entry::RemovalReason::FailedChecks, entry.removal_reason
      assert_equal attempts, entry.attempts
      assert_equal head_ref, entry.head_ref
    end

    test "generates a list of requested checks" do
      checks_requested_at = Time.current

      setup_world!(entry_state: Entry::State::AwaitingChecks.new(
        checks_requested_at:,
      ))

      @queue_entry.update(attempts: 1)

      check_suite = create(:check_suite, repository: @repo, head_sha: @pr.head_sha)

      create(:check_run, :failure,
        check_suite: check_suite,
        display_name: "required-run",
      )

      entries = build_entry_list(@queue)
      assert_equal 1, entries.to_a.length

      entry = T.must(entries.first)

      fail unless entry.state.is_a?(Entry::State::AwaitingChecks)

      # requested checks
      assert_equal 2, entry.requested_checks.length

      requested_check = T.must(entry.requested_checks.find { |c| c.name == "required-run" })

      assert_equal 1, requested_check.attempts
      assert_equal @queue.check_run_retries_limit, requested_check.max_attempts
      assert_equal true, requested_check.supports_retry
      assert_in_delta checks_requested_at.to_time, requested_check.requested_at, 1
      assert_equal 60.minutes, requested_check.timeout_after
      assert_equal MergeQueues::Entry::RequestedCheck::State::Failed, requested_check.state

      requested_ruleset_check = T.must(entry.requested_checks.find { |c| c.name == "org ruleset workflow (enabled)" })

      assert_equal 1, requested_ruleset_check.attempts
      assert_equal @queue.check_run_retries_limit, requested_ruleset_check.max_attempts
      assert_equal false, requested_ruleset_check.supports_retry
      assert_in_delta checks_requested_at.to_time, requested_ruleset_check.requested_at, 1
      assert_equal 60.minutes, requested_ruleset_check.timeout_after
      assert_equal MergeQueues::Entry::RequestedCheck::State::Success, requested_ruleset_check.state

      requested_evaluate_ruleset_check = entry.requested_checks.find { |c| c.name == "org ruleset workflow (evaluate)" }
      assert_nil requested_evaluate_ruleset_check
    end

    test "treats the `waiting` state as `queued`" do
      setup_world!
      @queue_entry.update(state: Entry::State::Waiting::VALUE)

      entries = build_entry_list(@queue)

      assert_equal [Entry::State::Queued], entries.map { _1.state.class }
    end

    test "loads data efficiently" do
      user = create(:user)
      queue = create(:merge_queue, check_run_retries_limit: 0)
      repository = queue.repository
      queue.protected_branch.update_required_status_checks(
        contexts: %w[test1 test2 lint],
      )

      queries_by_entry_count = ["a" * 40, "b" * 40, "c" * 40].each_with_object({}) do |head_sha, queries_by_entry_count|
        create(
          :merge_queue_entry,
          queue:,
          state: Entry::State::AwaitingChecks::VALUE,
          checks_requested_at: 5.minutes.ago,
          head_sha:,
        )
        create(
          :status,
          repository:,
          creator: user,
          sha: head_sha,
          commit_oid: head_sha,
          tree_oid: "0" * 40,
          context: "test1",
        )
        check_suite = create(:check_suite, repository:, creator: user, head_sha:)
        create(:check_run, :success, check_suite:, name: "test2")

        factory = Factory.new(repository, MergeQueue.find(queue.id))
        _, queries = log_cleaned_queries do
          factory.to_entry_list
          Command.new(
            queue,
            repository,
            factory.merge_queue_entry_models,
            factory.check_models,
          )
        end

        queries_by_entry_count[MergeQueueEntry.count] = queries.map(&:digested_sql)
      end

      # FIXME: Really, what we want here is to assert that there are _no_
      #  additional queries with each added entry, but there is a bug in
      #  `CheckRun.latest_for_sha_and_repository` that currently makes this
      #  impossible.
      #
      #  See: https://github.com/github/c2c-actions-checks/issues/1389
      maximum_allowed_delta = 3
      delta_1_to_2 = queries_by_entry_count[2].count - queries_by_entry_count[1].count
      delta_2_to_3 = queries_by_entry_count[3].count - queries_by_entry_count[2].count

      assert(
        delta_1_to_2 == delta_2_to_3 && delta_1_to_2 <= maximum_allowed_delta,
        "Expected the number of queries to grow by no more than "\
        "#{maximum_allowed_delta} with each additional entry, "\
        "but it did not:\n\n"\
          " - 1 entry    =>  #{queries_by_entry_count[1].count} queries\n"\
          " - 2 entries  =>  #{queries_by_entry_count[2].count} queries (+ #{delta_1_to_2})\n"\
          " - 3 entries  =>  #{queries_by_entry_count[3].count} queries (+ #{delta_2_to_3})\n\n"\
          "The diff between the executed queries for 2 entries (expected) and "\
          "the executed queries for 3 entries (actual) was:\n\n"\
          "#{diff(queries_by_entry_count[2], queries_by_entry_count[3])}"
      )
    end

    def create_workflow_file(repo, branch, path)
      repo.heads.find_or_build(branch).append_commit({ message: "add workflow", committer: repo.owner }, repo.owner) do |files|
        files.add(path, "some content")
      end
    end

    def make_ruleset_workflow(source_repo, target_repo, pr, queue, path, ruleset_enforcement)
      org = source_repo.owner
      ruleset_workflow_path = path
      ruleset_workflow_ref = "refs/heads/master"
      ruleset_workflow_name = "org ruleset workflow (#{ruleset_enforcement})"
      required_path_for_cs = "required/#{source_repo.id}/#{ruleset_workflow_path}"
      create_workflow_file(source_repo, ruleset_workflow_ref, ruleset_workflow_path)

      imposed_workflow = Actions::Workflow.new(name: ruleset_workflow_name, path: ruleset_workflow_path, imposer_repository_id: source_repo.id, repository_id: target_repo.id)
      imposed_workflow.enable(target_repo)
      imposed_workflow.present_in_default_branch = true
      imposed_workflow.save

      required_workflow = Actions::Workflow.new(name: ruleset_workflow_name, path: ruleset_workflow_path, repository_id: source_repo.id)
      required_workflow.enable(source_repo)
      required_workflow.present_in_default_branch = true
      required_workflow.save

      #check suite needs an app integration
      github_app  = create :integration, default_permissions: { "checks" => :write }, owner: org, url: "http://super-duper.com"
      make_integration_installation integration: github_app, repository: target_repo

      check_suite_attrs = {
        github_app_id: github_app.id,
        head_sha: pr.head_sha,
        repository_id: target_repo.id,
        workflow_file_path: required_path_for_cs,
      }

      suite = CheckSuite.create!(check_suite_attrs)
      suite.conclusion = "success"
      suite.status = "completed"
      suite.save

      run = Actions::WorkflowRun.new(workflow: imposed_workflow, actor: org, repository: target_repo, check_suite: suite, name: imposed_workflow.name, workflow_file_checkout_sha: target_repo.heads[ruleset_workflow_ref].sha,
                                      head_branch: queue.branch, head_sha: pr.head_sha, workflow_file_path: ruleset_workflow_path, imposer_repository_id: source_repo.id,
                                      workflow_file_ref: ruleset_workflow_ref)
      run.save

      ruleset = create :repository_ruleset, :targets_all_repos, source: org, enforcement: ruleset_enforcement
      create(:repository_rule_condition, :targets_branch, branch_name: "refs/heads/#{queue.branch}", repository_ruleset: ruleset)

      config = create(:repository_rule_configuration, rule_type: "workflows", repository_ruleset: ruleset, parameters: {
        workflows: [{
          repository_id:  source_repo.id,
          path: ruleset_workflow_path,
          ref: ruleset_workflow_ref
        }]
      })
    end

    sig { params(required_status_checks: T::Array[String], entry_state: T.nilable(Entry::State)).void }
    def setup_world!(required_status_checks: %w[required-run], entry_state: nil)
      entry_state ||= Entry::State::AwaitingChecks.new(
        checks_requested_at: 5.minutes.ago,
      )

      @org = create(:organization, plan: "business_plus")
      @repo = create :repository, owner: @org, name: "imposee", from_example: :simple
      @workflow_repo = create :repository, owner: @org, name: "imposer"


      @queue = create(:merge_queue, check_run_retries_limit: 0, repository: @repo)
      @queue_entry = create(
        :merge_queue_entry,
        queue: @queue,
        state: entry_state.serialize,
        checks_requested_at: entry_state.try(:checks_requested_at),
      )

      @queue_branch = @repo.heads.find(@queue.branch)
      @before = @queue_branch.target_oid

      @pr = @queue_entry.pull_request

      make_ruleset_workflow(@workflow_repo, @repo, @pr, @queue, ".github/workflows/evalute.yml", "evaluate")
      make_ruleset_workflow(@workflow_repo, @repo, @pr, @queue, ".github/workflows/required.yml", "enabled")

      @queue_entry.update(
        head_ref: @pr.head_ref,
        head_sha: @pr.head_sha,
        base_sha: @pr.base_sha,
      )

      @protected_branch = @queue.protected_branch
      @protected_branch.update_required_status_checks(contexts: required_status_checks)
      @protected_branch.save!

      # Ensure memoization is cleared, e.g. for `branch_rule_evaluator`
      @queue = MergeQueue.find(@queue.id)
    end

    sig { params(queue: MergeQueue).returns(EntryList) }
    def build_entry_list(queue)
      Factory.new(
        T.must(queue.repository),
        queue,
      ).to_entry_list
    end
  end
end
