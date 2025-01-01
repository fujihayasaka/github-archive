# typed: true
# frozen_string_literal: true

require "test_helper"
require "github-launch"
require "test_helpers/launch/artifacts_exchange_helper"

class CheckSuiteTest < GitHub::TestCase
  include NewsiesHelper
  include HydroTestHelpers
  include AuditLog::IntegrationTestHelpers
  include StringFromBinaryTestHelper
  include Launch::ArtifactExchangeHelper
  include BackgroundDeletesTestHelpers

  fixtures do
    @incomplete_statuses = CheckRun::statuses.keys - ["completed"]
    @non_stale_conclusions = CheckRun::conclusions.keys - ["stale"]
  end

  setup do
    GitHub.flipper[:notifyd_enable_ci_activity].disable
    GitHub.stubs(:actions_enabled?).returns(true)
    make_trusted_oauth_apps_owner
  end

  test "CheckSuite#save_and_rescue_uniqueness" do
    original_check_suite = create(:check_suite)
    dup_check_suite = build(:check_suite,
      repository: original_check_suite.repository,
      github_app: original_check_suite.github_app,
      head_sha: original_check_suite.head_sha
    )
    assert_equal original_check_suite, dup_check_suite.save_and_rescue_uniqueness
  end

  test "check suite uniqueness" do
    original_check_suite = create(:check_suite)
    dup_check_suite = build(:check_suite,
      repository: original_check_suite.repository,
      github_app: original_check_suite.github_app,
      head_sha: original_check_suite.head_sha
    )

    assert_raises(ActiveRecord::RecordNotUnique) do
      dup_check_suite.save
    end
  end

  context "validation" do
    test "requires a github_app_id_id" do
      check = CheckSuite.new
      check.valid?

      refute check.errors[:github_app_id].blank?
    end

    test "requires a repository_id" do
      check = CheckSuite.new
      check.valid?

      refute check.errors[:repository_id].blank?
    end

    test "requires a head_sha" do
      check = CheckSuite.new
      check.valid?

      refute check.errors[:head_sha].blank?
    end
  end

  context ".expired_workflow_run?" do
    test "is stale for GitHub Actions check suites older than a month" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      user = create(:user)
      repo = create(:repository, owner: user)
      check_suite = create :check_suite_for_actions_app, created_at: 2.months.ago, repository: repo
      assert check_suite.expired_workflow_run?
    end

    test "is not stale for GitHub Actions check suites created within a month" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      user = create(:user)
      repo = create(:repository, owner: user)
      check_suite = create :check_suite_for_actions_app, created_at: 2.weeks.ago, repository: repo
      refute check_suite.expired_workflow_run?
    end

    test "is not stale for non-GitHub Actions check suites" do
      user = create(:user)
      repo = create(:repository, owner: user)
      check_suite = create :check_suite, created_at: 2.months.ago, repository: repo
      refute check_suite.expired_workflow_run?
    end
  end

  context ".request" do
    test "does not create check suite if one is found for app, repo, and head_sha" do
      org          = create :organization
      repository   = create :private_repository, owner: org, name: "Hello-World", from_example: :simple
      github_app   = create :integration, default_permissions: { "checks" => :write },
                        owner: org, url: "http://super-duper.com"
      make_integration_installation integration: github_app, repository: repository

      before = repository.heads.find("master").commit.parent_oids.first
      after = repository.heads.find("master").target_oid

      push_attrs = {
        before: before,
        after: after,
        ref: "refs/heads/master",
        repository_id: repository.id,
        pusher_id: org.admins.first.id,
        pushed_at: Time.now
      }
      create :push, push_attrs

      check_suite_attrs = {
        github_app_id: github_app.id,
        head_sha: after,
        repository_id: repository.id,
      }

      CheckSuite.create!(check_suite_attrs)

      assert_difference "CheckSuite.where(repository_id: #{repository.id}).count", 0 do
        CheckSuite.request(repository: repository, head_sha: after, actor: org.admins.first)
      end
    end

    test "does not create check suite if auto trigger checks is disabled for the app" do
      org          = create :organization
      repository   = create :private_repository, owner: org, name: "Hello-World", from_example: :simple
      github_app   = create :integration, default_permissions: { "checks" => :write },
                        owner: org, url: "http://super-duper.com"
      make_integration_installation integration: github_app, repository: repository
      repository.set_auto_trigger_checks(actor: github_app.bot, app: github_app, value: "false")

      before = repository.heads.find("master").commit.parent_oids.first
      after = repository.heads.find("master").target_oid

      push_attrs = {
        before: before,
        after: after,
        ref: "refs/heads/master",
        repository_id: repository.id,
        pusher_id: org.admins.first.id,
        pushed_at: Time.now
      }
      create :push, push_attrs

      check_suite_attrs = {
        github_app_id: github_app.id,
        head_sha: after,
        repository_id: repository.id,
      }

      assert_difference "CheckSuite.where(repository_id: #{repository.id}).count", 0 do
        CheckSuite.request(repository: repository, head_sha: after, actor: org.admins.first)
      end
      refute repository.auto_trigger_checks_for?(app_id: github_app.id)
    end
  end

  context "nil creator" do
    test "returns ghost user" do
      check_suite = create(:check_suite)
      check_suite.creator.delete
      assert_equal User.ghost, check_suite.reload.creator
    end
  end

  context "#save" do
    test "scopes update queries to repository id" do
      check_suite = create(:check_suite)
      check_suite.name = "New check suite name"

      _, queries = log_queries do
        check_suite.save
      end

      refute queries.any? { |q| q.digested_sql.match?(/\AUPDATE check_suites SET (.*) WHERE check_suites.id = \?\Z/) }, "Expected no update query that's not scoped to a repo. Got:\n#{queries.map(&:digested_sql).select { |q| q.start_with?("UPDATE check_suites") }}"
      assert queries.any? { |q| q.digested_sql.match?(/\AUPDATE check_suites SET (.*) WHERE check_suites.id = \? AND check_suites.repository_id = \?\Z/) }, "Expected update query to be scoped to repo. Got:\n#{queries.map(&:digested_sql).select { |q| q.start_with?("UPDATE check_suites") }}"
    end
  end

  context "#after_save" do
    test "triggers check_suite.complete when the suite changes to being completed" do
      events = subscribe "check_suite.complete"

      check_suite = create :check_suite
      check_suite.update(status: "completed", conclusion: "success", repository_id: check_suite.repository_id)

      expected_payload = {
        check_suite_id: check_suite.id,
        repository_id: check_suite.repository_id,
        organization_id: check_suite.repository.owner.organization? ? check_suite.repository.owner_id : nil,
        business_id: check_suite.repository.organization&.business&.id
      }
      instrumentation_event = events.pop

      assert_equal "check_suite.complete", instrumentation_event.name
      assert_subset_hash expected_payload, instrumentation_event.payload
    end

    test "triggers check_suite.complete when the suite is already completed but changes conclusion" do
      check_suite = create :check_suite
      check_suite.update(status: "completed", conclusion: "neutral")

      events = subscribe "check_suite.complete"
      check_suite.update(status: "completed", conclusion: "success")

      expected_payload = {
        check_suite_id: check_suite.id,
        repository_id: check_suite.repository_id,
        organization_id: check_suite.repository.owner.organization? ? check_suite.repository.owner_id : nil,
        business_id: check_suite.repository.organization&.business&.id
      }
      instrumentation_event = events.pop

      assert_equal "check_suite.complete", instrumentation_event.name
      assert_subset_hash expected_payload, instrumentation_event.payload
    end

    test "does not trigger check_suite.complete when the suite is already completed" do
      check_suite = create :check_suite
      check_suite.update(status: "completed", conclusion: "success")

      events = subscribe "check_suite.complete"
      check_suite.update(updated_at: Time.now.utc)

      refute events.pop
    end
  end

  test "supports 4 byte emojis in branch names" do
    branch_name = "🐶-food"
    check_suite = create(:check_suite, head_branch: branch_name)

    assert_equal check_suite.reload.head_branch, branch_name
  end

  test "sets the started_at time when it is created, the duration is zero" do
    Timecop.freeze do
      check_suite = create(:check_suite)
      assert_equal Time.now.to_i, check_suite.started_at.to_i
      assert_nil check_suite.completed_at
      assert_equal 0, check_suite.duration
    end
  end

  test "filter check suites by GitHub App ID" do
    repo = create :repository
    check_suite1 = create :check_suite, repository: repo
    check_suite2 = create :check_suite, repository: repo

    check_suites = CheckSuite.where(repository_id: repo.id).for_app_id(check_suite1.github_app_id)

    assert_equal 1, check_suites.length
    assert_equal check_suite1.id, T.must(check_suites.first).id
  end

  test "filter check suites by check name" do
    repo = create :repository
    check_suite1 = create :check_suite, repository: repo
    check_run1   = create :check_run, check_suite: check_suite1, name: "apple"
    check_suite2 = create :check_suite, repository: repo
    check_run2   = create :check_run, check_suite: check_suite2, name: "banana"
    check_suite3 = create :check_suite, repository: repo
    check_run3   = create :check_run, check_suite: check_suite3, name: "apple"

    check_suites = CheckSuite.where(repository_id: repo.id).with_check_run_named("apple", repo.id)

    assert_equal 2, check_suites.length
    assert_same_elements [check_suite1.id, check_suite3.id], check_suites.map(&:id)
  end

  context "querying and updating conclusions and status" do
    test "returns the lowest hierarchical status for the suite's check runs as its `status`" do
      check_suite  = create :check_suite
      check_run1   = create(:check_run, check_suite: check_suite, status: "in_progress")
      check_run2   = create(:check_run, check_suite: check_suite, status: "completed", conclusion: "success", completed_at: Time.now.utc)

      assert_equal "in_progress", check_suite.status
    end

    test "returns the lowest hierarchical status only if there is no waiting status for the suite's check runs as its `status`" do
      check_suite  = create :check_suite
      check_run1   = create(:check_run, check_suite: check_suite, status: "in_progress")
      check_run2   = create(:check_run, check_suite: check_suite, status: "waiting")
      check_run3   = create(:check_run, check_suite: check_suite, status: "completed", conclusion: "success", completed_at: Time.now.utc)

      assert_equal "waiting", check_suite.status
    end

    test "returns 'waiting' status for whole suite, even if one of the check runs is in 'queued' state" do
      check_suite  = create :check_suite
      check_run1   = create(:check_run, check_suite: check_suite, status: "in_progress")
      check_run2   = create(:check_run, check_suite: check_suite, status: "waiting")
      check_run3   = create(:check_run, check_suite: check_suite, status: "queued")
      check_run4   = create(:check_run, check_suite: check_suite, status: "completed", conclusion: "success", completed_at: Time.now.utc)

      assert_equal "waiting", check_suite.status
    end

    test "returns 'requested' status for whole suite, even if one of the check runs is in 'waiting' state" do
      check_suite  = create :check_suite
      check_run1   = create(:check_run, check_suite: check_suite, status: "in_progress")
      check_run2   = create(:check_run, check_suite: check_suite, status: "waiting")
      check_run3   = create(:check_run, check_suite: check_suite, status: "requested")
      check_run4   = create(:check_run, check_suite: check_suite, status: "queued")
      check_run5   = create(:check_run, check_suite: check_suite, status: "completed", conclusion: "success", completed_at: Time.now.utc)

      assert_equal "requested", check_suite.status
    end

    test "returns 'requested' when there are no check runs" do
      check_suite = create :check_suite

      check_suite.set_rollup_values!
      assert_equal "requested", check_suite.status
    end

    test "returns the lowest hierarchical conclusion for the suite's concluded check runs" do
      check_suite  = create :check_suite
      check_run1   = create(:check_run, check_suite: check_suite, status: "completed", conclusion: "neutral", completed_at: Time.now.utc)
      check_run2   = create(:check_run, check_suite: check_suite, status: "completed", conclusion: "failure", completed_at: Time.now.utc)
      check_run3   = create(:check_run, check_suite: check_suite, status: "completed", conclusion: "skipped", completed_at: Time.now.utc)

      assert_equal "failure", check_suite.conclusion
      assert check_suite.completed_at
    end

    test "returns nil for conclusion when there are no concluded check runs" do
      check_suite = create :check_suite
      check_run   = create(:check_run, check_suite: check_suite, status: "in_progress")

      assert_nil check_suite.conclusion
      assert_nil check_suite.completed_at
    end

    test "does update the conclusion when there are in_progress check runs added after a conclusion already set" do
      # In the case that we create a check run with a set conclusion, that conclusion should be available via
      # the API
      check_suite  = create :check_suite
      check_run    = create(:check_run, check_suite: check_suite, status: "completed", conclusion: "neutral", completed_at: Time.now.utc)

      assert check_suite.conclusion, "Expected a conclusion for a suite with concluded runs"

      # In the case that we have added an in_progress check run, the suite should no longer have a conclusion,
      # as it's not conluded anymore.
      check_run.update(status: "in_progress", conclusion: nil, completed_at: nil)

      check_suite.set_rollup_values!
      assert_nil check_suite.conclusion
      assert_nil check_suite.completed_at
    end

    test "is calculated only when all check_runs concluded" do
      # If there are non-completed check runs, the suite should not have a status (it should be nil)
      check_suite  = create :check_suite
      create(:check_run, check_suite: check_suite, status: "completed", conclusion: "failure", completed_at: Time.now.utc)
      create(:check_run, check_suite: check_suite, status: "in_progress", conclusion: nil)

      assert_nil check_suite.conclusion
      assert_nil check_suite.completed_at
    end

    test "honors the explicit_completion flag" do
      check_suite = create :check_suite, explicit_completion: true
      assert_equal "queued", check_suite.status

      # Check suite updates to in_progress if check runs are created
      check_run1 = create(:check_run, check_suite: check_suite, status: "completed", conclusion: "failure", completed_at: Time.now.utc)
      assert_equal "in_progress", check_suite.reload.status
      refute_predicate check_suite, :conclusion

      # Double check that it does not update unless force is true
      check_suite.set_rollup_values!
      assert_equal "in_progress", check_suite.reload.status
      refute_predicate check_suite, :conclusion

      # Updates the status and conclusion if force is true
      check_suite.set_complete_explicitly!("failure")
      assert_equal "completed", check_suite.reload.status
      assert_equal "failure", check_suite.conclusion
      assert check_suite.completed_at

      # Everything works the same after reseting the check suite
      check_suite.reset
      assert_equal "queued", check_suite.reload.status
      assert_nil check_suite.completed_at

      # Double check that it does not update unless force is true
      check_suite.set_rollup_values!
      assert_equal "in_progress", check_suite.reload.status
      refute_predicate check_suite, :conclusion

      # Updates the status and conclusion if force is true
      check_suite.set_complete_explicitly!("failure")
      assert_equal "completed", check_suite.reload.status
      assert_equal "failure", check_suite.conclusion
      assert check_suite.completed_at
    end

    test "updates the workflow run execution" do
      check_suite = create(:check_suite_for_actions_app, explicit_completion: true, status: "queued")
      workflow_run_execution = check_suite.workflow_run.workflow_run_executions.last

      assert_equal check_suite.status, workflow_run_execution.status

      # This will call set_rollup_values!
      create(:check_run, check_suite: check_suite, status: "completed", conclusion: "failure", completed_at: Time.now.utc)

      assert_equal check_suite.reload.status, workflow_run_execution.reload.status
    end

    test "updates the status when the persisted value is different from rollup value" do
      check_suite = create(:check_suite, explicit_completion: true, status: "in_progress")
      create(:check_run, check_suite: check_suite, status: "completed", conclusion: "failure", completed_at: Time.now.utc)

      # Manually set status so we can update it
      check_suite.update_columns(status: "queued")

      _, queries = log_queries do
        check_suite.set_rollup_values!
      end

      assert queries.any? { |q| q.digested_sql.match?(/\AUPDATE check_suites SET check_suites.status = \?(.*)WHERE (.*)check_suites.repository_id = \?(.*)\Z/) }, "Expected update to check suite status that's scoped to a repo"
      assert_equal "in_progress", check_suite.reload.status
    end

    test "updates the status when the rolled up status isn't complete" do
      check_suite = create(:check_suite, explicit_completion: true, status: "queued")
      create(:check_run, check_suite: check_suite, status: "in_progress")

      # Manually set status so we can update it
      check_suite.update_columns(status: "queued")

      _, queries = log_queries do
        check_suite.set_rollup_values!
      end

      assert queries.any? { |q| q.digested_sql.match?(/\AUPDATE check_suites SET check_suites.status = \?(.*)WHERE (.*)check_suites.repository_id = \?(.*)\Z/) }, "Expected update to check suite status that's scoped to a repo"
      assert_equal "in_progress", check_suite.reload.status
    end

    test "does not change the status if the new rolled up status is the same as the old one" do
      check_suite = create(:check_suite, explicit_completion: true, status: "in_progress")
      create(:check_run, check_suite: check_suite, status: "completed", conclusion: "failure", completed_at: Time.now.utc)
      assert_equal "in_progress", check_suite.status

      _, queries = log_queries do
        check_suite.set_rollup_values!
      end

      refute queries.any? { |q| q.digested_sql.start_with?("UPDATE check_suites SET check_suites.status") }, "Expected no update to check suite status"
      assert_equal "in_progress", check_suite.reload.status
    end

    test "does not change the status when the rollup status is completed and the persisted value is completed" do
      check_suite = create(:check_suite, explicit_completion: true, status: "queued")
      create(:check_run, check_suite: check_suite, status: "completed", conclusion: "failure", completed_at: Time.now.utc)

      # Force a disconnect between the model value and the db
      check_suite.update_columns(status: "completed")
      check_suite.status = "queued"

      check_suite.set_rollup_values!

      assert_equal "completed", check_suite.reload.status
    end

    test "does not update the status if the new rolled up status is the same as the old one" do
      check_suite = create(:check_suite, explicit_completion: true, status: "in_progress")
      create(:check_run, check_suite: check_suite, status: "completed", conclusion: "failure", completed_at: Time.now.utc)
      assert_equal "in_progress", check_suite.status

      _, queries = log_queries do
        check_suite.set_rollup_values!
      end

      refute queries.any? { |q| q.digested_sql.start_with?("UPDATE check_suites") }, "Expected no update to check suite"
      assert_equal "in_progress", check_suite.reload.status
    end

    test "doesn't persist the information when run_callbacks is false and the conditional update feature flag is off" do
      GitHub.flipper[:check_suite_update_conclusion_with_conditional_query].disable
      check_suite = create :check_suite, explicit_completion: true

      check_suite.set_complete_explicitly!("failure", run_callbacks: false)
      assert_equal "completed", check_suite.status
      assert_equal "failure", check_suite.conclusion
      assert check_suite.completed_at
      assert check_suite.changed?
    end

    test "update_when_not_completed persists the information when the check suite isn't completed" do
      check_suite = create(:check_suite_for_actions_app, explicit_completion: true)

      _, queries = log_queries do
        check_suite.update_when_not_completed(status: "completed", conclusion: "failure", completed_at: Time.now)
      end

      update_queries = queries.map(&:digested_sql).select { |q| q.start_with?("UPDATE check_suites") }
      assert update_queries.any? { |q| q.match?(/\AUPDATE check_suites SET (.*) \? WHERE(.*)check_suites.status != ?(.*)\Z/) }, "Expected update query to be conditional to status. Got:\n#{update_queries}"

      check_suite.reload
      assert_equal "completed", check_suite.status
      assert_equal "failure", check_suite.conclusion
      refute_nil check_suite.completed_at
    end

    test "update_when_not_completed instruments complete events if the check suite isn't completed" do
      check_suite = create(:check_suite_for_actions_app, explicit_completion: true)
      events = subscribe("check_suite.complete")

      check_suite.update_when_not_completed(status: "completed", conclusion: "failure", completed_at: Time.now)

      expected_payload = {
        check_suite_id: check_suite.id,
        repository_id: check_suite.repository_id,
        organization_id: check_suite.repository.owner.organization? ? check_suite.repository.owner_id : nil,
        business_id: check_suite.repository.organization&.business&.id
      }

      instrumentation_event = events.pop
      refute_nil instrumentation_event
      assert_equal "check_suite.complete", instrumentation_event.name
      assert_subset_hash expected_payload, instrumentation_event.payload
    end

    test "update_when_not_completed instruments workflow run complete events if the check suite isn't completed" do
      check_suite = create(:check_suite_for_actions_app, explicit_completion: true)
      names = []
      payloads = []
      GlobalInstrumenter.subscribe("check_suite.notification_triggered") do |event, _start, _finish, _id, payload|
        names << event
        payloads << payload
      end

      check_suite.update_when_not_completed(status: "completed", conclusion: "failure", completed_at: Time.now)
      expected_payload = { conclusion: "failure", check_suite: check_suite }

      assert_equal "check_suite.notification_triggered", names.pop
      assert_subset_hash expected_payload, payloads.pop
    end

    test "update_when_not_completed notifies subscribers about status changed events if the check suite isn't completed" do
      check_suite = create(:check_suite_for_actions_app, explicit_completion: true)

      GlobalInstrumenter.expects(:instrument).with("prebuild_repository_check_suite.update", {
        check_suite_id: check_suite.id,
        repository_id: check_suite.repository_id,
      })
      GlobalInstrumenter.expects(:instrument).with("check_suite.status_changed", {
        check_suite_id: check_suite.id,
        repository_id: check_suite.repository_id,
        previous_status: :queued,
        current_status: :completed,
        head_sha: check_suite.head_sha,
        conclusion: "failure",
        app: check_suite.github_app,
      })

      GlobalInstrumenter.expects(:instrument).with("check_suite.notification_triggered", { check_suite: check_suite, conclusion: "failure" })
      check_suite.update_when_not_completed(status: "completed", conclusion: "failure", completed_at: Time.now)
    end

    test "update_when_not_completed instruments workflow run change events if the check suite isn't completed" do
      check_suite = create(:check_suite_for_actions_app, explicit_completion: true)
      events = subscribe("workflow_run.status_changed")

      expected_payload = {
        run_id: check_suite.workflow_run.id,
        action: :completed,
        actor_id: check_suite.creator.id,
        repository_id: check_suite.repository_id,
        primary_resource: check_suite.workflow_run.attributes
      }

      check_suite.update_when_not_completed(status: "completed", conclusion: "failure", completed_at: Time.now)

      instrumentation_event = events.pop
      refute_nil instrumentation_event
      assert_equal "workflow_run.status_changed", instrumentation_event.name
      assert_subset_hash expected_payload, instrumentation_event.payload
    end

    test "update_when_not_completed runs callbacks when the check suite isn't completed" do
      GitHub.flipper[:check_suite_update_conclusion_with_conditional_query].enable
      check_suite = create(:check_suite_for_actions_app, explicit_completion: true)

      Actions::WorkflowRun.any_instance.expects(:synchronize_search_index).once
      GitHub::WebSocket.expects(:notify_repository_channel).once

      check_suite.update_when_not_completed(status: "completed", conclusion: "failure", completed_at: Time.now)
    end

    test "update_when_not_completed updates the workflow run execution when the check suite isn't completed" do
      GitHub.flipper[:check_suite_update_conclusion_with_conditional_query].enable
      check_suite = create(:check_suite_for_actions_app, explicit_completion: true)

      check_suite.update_when_not_completed(status: "completed", conclusion: "failure", completed_at: Time.now)

      workflow_run_execution = check_suite.workflow_run.latest_workflow_run_execution.reload
      assert_equal "completed", workflow_run_execution.status
      assert_equal "failure", workflow_run_execution.conclusion
    end

    test "update_when_not_completed does not persist the information when the check suite is already completed" do
      GitHub.flipper[:check_suite_update_conclusion_with_conditional_query].enable
      check_suite = create(:check_suite, explicit_completion: true, status: "completed", conclusion: "success", completed_at: Time.now)

      GitHub::WebSocket.expects(:notify_repository_channel).never

      check_suite.update_when_not_completed(status: "completed", conclusion: "failure", completed_at: Time.now)

      check_suite.reload
      assert_equal "completed", check_suite.status
      assert_equal "success", check_suite.conclusion
    end

    test "set_complete_explicitly! does not affect non-explicit_completion check suites" do
      check_suite = create :check_suite, explicit_completion: false
      check_suite.set_complete_explicitly!("failure")
      refute_equal "failure", check_suite.conclusion
      assert_nil check_suite.completed_at
    end

    test "check run updates cannot roll back an explicitly complete check suite from complete" do
      check_suite = create :check_suite, explicit_completion: true
      assert_equal "queued", check_suite.status

      check_run  = create(:check_run, check_suite: check_suite, status: "queued")

      check_suite.set_complete_explicitly!("neutral")
      assert_equal "completed", check_suite.status
      assert_equal "neutral", check_suite.conclusion
      assert check_suite.completed_at

      check_run.update(status: "in_progress", conclusion: nil, completed_at: nil)
      check_suite.set_rollup_values!

      assert_equal "completed", check_suite.status
      assert_equal "neutral", check_suite.conclusion
      assert check_suite.completed_at

      check_run.update(status: "in_progress", conclusion: "failure", completed_at: Time.now.utc)
      check_suite.set_rollup_values!

      assert_equal "completed", check_suite.status
      assert_equal "neutral", check_suite.conclusion
      assert check_suite.completed_at
    end

    test "check runs cannot cause a explicitly completed check suite's conclusion to change after it has completed" do
      check_suite = create :check_suite, explicit_completion: true
      check_run = create(:check_run, check_suite: check_suite, status: "in_progress")
      check_suite.set_complete_explicitly!("timed_out")
      assert_equal "completed", check_suite.status
      assert_equal "timed_out", check_suite.conclusion
      assert check_suite.completed_at

      check_run.update(status: "completed", conclusion: "failure", completed_at: Time.now.utc)
      assert_equal "completed", check_suite.status
      assert_equal "timed_out", check_suite.conclusion
      assert check_suite.completed_at
    end

    test "marks a check suite with explicit_completion as completed even if there are uncompleted checks" do
      check_suite = create :check_suite, explicit_completion: true
      assert_equal "queued", check_suite.status

      check_run = create(:check_run, check_suite: check_suite, status: "in_progress")

      check_suite.set_complete_explicitly!("success")
      assert_equal "completed", check_suite.status
      assert_equal "success", check_suite.conclusion
      assert check_suite.completed_at
    end
  end

  context "#latest_check_runs" do
    test "returns the last CheckRun per name" do
      check_suite = create :check_suite

      check_run1   = create(:check_run, check_suite: check_suite, name: "a", status: "completed", conclusion: "failure", completed_at: Time.now.utc)
      check_run2_1 = create(:check_run, check_suite: check_suite, name: "b", status: "in_progress", conclusion: nil)
      sleep 1
      check_run2_2 = create(:check_run, check_suite: check_suite, name: "b", status: "in_progress", conclusion: nil)

      assert_same_elements [check_run1.id, check_run2_2.id], check_suite.latest_check_runs.collect(&:id)
    end

    test "scopes the check runs to the check suite" do
      check_suite1 = create :check_suite
      check_suite2 = create(:check_suite, repository: check_suite1.repository, head_sha: check_suite1.head_sha)

      check_run1   = create(:check_run, check_suite: check_suite1, name: "a", status: "completed", conclusion: "failure", completed_at: Time.now.utc)
      check_run2   = create(:check_run, check_suite: check_suite2, name: "b", status: "completed", conclusion: "failure", completed_at: Time.now.utc)

      assert_same_elements [check_run1.id], check_suite1.latest_check_runs.collect(&:id)
      assert_same_elements [check_run2.id], check_suite2.latest_check_runs.collect(&:id)
    end

    test "returns an empty relation when no check runs are in the check suite" do
      check_suite = create :check_suite
      assert_predicate check_suite.latest_check_runs, :none?
    end
  end

  context "#latest_waiting_check_run_ids" do
    test "returns the last waiting CheckRun per name" do
      check_suite = create :check_suite

      check_run1   = create(:check_run, check_suite: check_suite, name: "a", status: "completed", conclusion: "failure", completed_at: Time.now.utc)
      check_run2_1 = create(:check_run, check_suite: check_suite, name: "b", status: "waiting", conclusion: nil)
      check_run2_2 = create(:check_run, check_suite: check_suite, name: "b", status: "waiting", conclusion: nil)
      assert_same_elements [check_run2_2.id], check_suite.fetch_latest_waiting_check_run_ids
    end
  end

  context "#latest_check_run_ids" do
    test "returns the last CheckRun per name" do
      check_suite = create :check_suite

      check_run1   = create(:check_run, check_suite: check_suite, name: "a", status: "completed", conclusion: "failure", completed_at: Time.now.utc)
      check_run2_1 = create(:check_run, check_suite: check_suite, name: "b", status: "in_progress", conclusion: nil)
      check_run2_2 = create(:check_run, check_suite: check_suite, name: "b", status: "in_progress", conclusion: nil)

      assert_same_elements [check_run1.id, check_run2_2.id], check_suite.fetch_latest_check_run_ids
    end

    test "for Actions returns the last CheckRun per name since the last re-run" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      user = create(:user)
      repo = create(:repository, owner: user)
      check_suite = create(:check_suite_for_actions_app, repository: repo)

      Timecop.freeze do
        check_run1 = create(:check_run, check_suite: check_suite, name: "a", status: "completed", conclusion: "failure", completed_at: Time.now.utc)

        Timecop.travel(10.minutes)

        check_suite.rerequest(actor: user)

        check_run2_1 = create(:check_run, check_suite: check_suite, name: "b", status: "in_progress", conclusion: nil)
        check_run2_2 = create(:check_run, check_suite: check_suite, name: "b", status: "in_progress", conclusion: nil)

        assert_same_elements [check_run2_2.id], check_suite.fetch_latest_check_run_ids
      end
    end

    test "for Actions returns latest Checkrun within timerange" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      user = create(:user)
      repo = create(:repository, owner: user)
      check_suite = create(:check_suite_for_actions_app, repository: repo)

      Timecop.freeze do
        check_run_a_1 = create(:check_run, check_suite: check_suite, name: "a", status: "completed", conclusion: "failure", completed_at: Time.now.utc)
        check_run_b_1 = create(:check_run, check_suite: check_suite, name: "b", status: "completed", conclusion: "failure", completed_at: Time.now.utc)

        Timecop.travel(10.minutes)
        check_suite.rerequest(actor: user)
        check_run_a_2 = create(:check_run, check_suite: check_suite, name: "a", status: "completed", conclusion: "failure", completed_at: Time.now.utc)
        check_run_b_2 = create(:check_run, check_suite: check_suite, name: "b", status: "completed", conclusion: "failure", completed_at: Time.now.utc)

        Timecop.travel(10.minutes)
        check_suite.rerequest(actor: user)

        check_run_a_3 = create(:check_run, check_suite: check_suite, name: "a", status: "in_progress", conclusion: nil)
        check_run_b_3 = create(:check_run, check_suite: check_suite, name: "b", status: "in_progress", conclusion: nil)

        assert_same_elements [check_run_a_2.id, check_run_b_2.id], check_suite.fetch_latest_check_run_ids(min_start_time: 11.minutes.ago, max_start_time: 9.minutes.ago)
      end
    end
  end

  context "#request" do
    test "triggers check_suite.request instrumentation" do
      events = subscribe "check_suite.request"
      check_suite = create :check_suite
      check_suite.request

      expected_payload = {
        check_suite_id: check_suite.id,
        actor_id: nil,
        repository_id: check_suite.repository_id,
        organization_id: nil,
        business_id: nil,
        primary_resource: check_suite.attributes
      }
      instrumentation_event = events.pop

      assert_equal "check_suite.request", instrumentation_event.name
      assert_equal expected_payload, instrumentation_event.payload
    end

    test "triggers check_suite.request instrumentation with org as owner" do
      organization = create(:organization)
      repo = create(:repository, owner: organization)
      events = subscribe "check_suite.request"
      check_suite = create(:check_suite, repository: repo)
      check_suite.request
      expected_payload = {
        check_suite_id: check_suite.id,
        actor_id: nil,
        repository_id: check_suite.repository_id,
        organization_id: check_suite.repository.owner_id,
        primary_resource: check_suite.attributes,
        business_id: check_suite.repository.organization&.business&.id
      }
      instrumentation_event = events.pop

      assert_equal "check_suite.request", instrumentation_event.name
      assert_subset_hash expected_payload, instrumentation_event.payload
    end
  end

  context "#rerequest" do
    test "triggers check_suite.rerequest hook event method" do
      Timecop.freeze do
        user = create(:user)
        repo = create(:repository, owner: user)
        check_suite = create(:check_suite, repository: repo)
        events = subscribe "check_suite.rerequest"

        # This check suite does not have artifacts,
        # so rerequesting it should not generate a websocket notification
        GitHub::WebSocket.expects(:notify_repository_channel).never

        check_suite.rerequest(actor: user)

        expected_payload = {
          check_suite_id: check_suite.id,
          actor_id: user.id,
          repository_id: check_suite.repository_id,
          organization_id: nil,
          business_id: nil,
          primary_resource: check_suite.attributes
        }
        instrumentation_event = events.pop

        assert_equal "check_suite.rerequest", instrumentation_event.name
        assert_equal expected_payload, instrumentation_event.payload
      end
    end

    test "triggers check_suite.rerequest hook event method with org as owner" do
      user = create(:user)
      organization = create(:organization)
      organization.add_member(user)

      repo = create(:repository, owner: organization)
      check_suite = create(:check_suite, repository: repo)
      events = subscribe "check_suite.rerequest"
      # This check suite does not have artifacts,
      # so rerequesting it should not generate a websocket notification
      GitHub::WebSocket.expects(:notify_repository_channel).never
      check_suite.rerequest(actor: user)

      expected_payload = {
        check_suite_id: check_suite.id,
        actor_id: user.id,
        repository_id: check_suite.repository_id,
        organization_id: check_suite.repository.owner_id,
        business_id: check_suite.repository.organization&.business&.id
      }
      instrumentation_event = events.pop

      assert_equal "check_suite.rerequest", instrumentation_event.name
      assert_subset_hash expected_payload, instrumentation_event.payload
    end

    test "triggers check_run.rerequest hooks for failed check runs" do
      user = create(:user)
      repo = create(:repository, owner: user)
      check_suite = create(:check_suite, repository: repo)
      check_run_success = create(:check_run, check_suite: check_suite, name: "a", status: :completed, conclusion: :success, completed_at: Time.now)
      check_run_failed1 = create(:check_run, check_suite: check_suite, name: "b", status: :completed, conclusion: :failure, completed_at: Time.now)
      check_run_failed2 = create(:check_run, check_suite: check_suite, name: "c", status: :completed, conclusion: :failure, completed_at: Time.now)
      events = subscribe "check_run.rerequest"

      check_suite.rerequest(actor: user, only_failed_check_runs: true)

      event2 = events.pop
      event1 = events.pop

      expected_payload1 = {
        check_run_id: check_run_failed1.id,
        repository_id: check_run_failed1.repository_id,
        actor_id: user.id,
      }

      expected_payload2 = {
        check_run_id: check_run_failed2.id,
        repository_id: check_run_failed2.repository_id,
        actor_id: user.id,
      }

      assert_equal "check_run.rerequest", event1.name
      assert expected_payload1 <= event1.payload

      assert_equal "check_run.rerequest", event2.name
      assert expected_payload2 <= event2.payload

      assert_nil events.pop
    end

    test "resets the status, conclusion and execution timestamps" do
      user = create(:user)
      repo = create(:repository, owner: user)
      check_suite = create(:check_suite, repository: repo)
      check_suite.update(status: CheckRun.statuses[:completed], conclusion: CheckRun.conclusions[:success], cancelled_at: Time.zone.now)

      refute_equal check_suite.status,
        CheckRun.statuses[:queued], "Expected check_suite's original status to differ from the reset value"
      refute_nil check_suite.conclusion, "Expected check_suite's original conclusion to differ from the reset value"

      original_check_suite_status     = check_suite.status
      original_check_suite_conclusion = check_suite.conclusion

      Timecop.freeze do
        check_suite.rerequest(actor: user)
        assert_equal Time.now.to_i, check_suite.started_at.to_i
        assert_nil check_suite.completed_at
        assert_nil check_suite.cancelled_at
      end

      check_suite.reload
      new_check_suite_status = check_suite.status
      new_check_suite_conclusion = check_suite.conclusion

      refute_equal original_check_suite_status, new_check_suite_status
      refute_equal original_check_suite_conclusion, new_check_suite_conclusion
    end

    test "resets the status and conclusion of itself and the check suite when only_failed_check_suites is true and in failure state" do
      user = create(:user)
      repo = create(:repository, owner: user)
      check_suite = create(:check_suite, repository: repo)
      check_suite.update(status: CheckRun.statuses[:completed], conclusion: CheckRun.conclusions[:failure])

      refute_equal check_suite.status,
        CheckRun.statuses[:queued], "Expected check_suite's original status to differ from the reset value"
      refute_nil check_suite.conclusion, "Expected check_suite's original conclusion to differ from the reset value"

      original_check_suite_status     = check_suite.status
      original_check_suite_conclusion = check_suite.conclusion

      check_suite.rerequest(actor: user, only_failed_check_suites: true)

      check_suite.reload
      new_check_suite_status = check_suite.status
      new_check_suite_conclusion = check_suite.conclusion

      refute_equal original_check_suite_status, new_check_suite_status
      refute_equal original_check_suite_conclusion, new_check_suite_conclusion
    end

    test "does not reset the workflow_run_execution" do
      check_suite = create(:check_suite_for_actions_app)
      check_suite.update(status: CheckRun.statuses[:completed], conclusion: CheckRun.conclusions[:success])

      workflow_run_execution = check_suite.workflow_run.workflow_run_executions.last

      assert_equal workflow_run_execution.status, "completed"
      assert_equal workflow_run_execution.conclusion, "success"

      check_suite.rerequest(actor: check_suite.repository.owner)

      workflow_run_execution.reload
      assert_equal workflow_run_execution.status, "completed"
      assert_equal workflow_run_execution.conclusion, "success"
    end

    test "raises an error when only_failed_check_suites is true and check suite is completed with success state" do
      user = create(:user)
      repo = create(:repository, owner: user)
      check_suite = create(:check_suite, repository: repo)
      check_suite.update(status: CheckRun.statuses[:completed], conclusion: CheckRun.conclusions[:success])

      refute_equal check_suite.status,
        CheckRun.statuses[:queued], "Expected check_suite's original status to differ from the reset value"
      refute_nil check_suite.conclusion, "Expected check_suite's original conclusion to differ from the reset value"

      original_check_suite_status     = check_suite.status
      original_check_suite_conclusion = check_suite.conclusion

      assert_raises CheckSuite::NotRerequestableError do
        check_suite.rerequest(actor: user, only_failed_check_suites: true)
      end

      check_suite.reload
      new_check_suite_status = check_suite.status
      new_check_suite_conclusion = check_suite.conclusion

      assert_equal original_check_suite_status, new_check_suite_status
      assert_equal original_check_suite_conclusion, new_check_suite_conclusion
    end

    test "does not raise an error when only_failed_check_suites is true and non-GitHub Actions check suite is stale" do
      user = create(:user)
      repo = create(:repository, owner: user)
      check_suite = create(:check_suite, repository: repo, created_at: 2.months.ago)
      check_suite.update(status: "completed", conclusion: "failure")


      original_check_suite_status     = check_suite.status
      original_check_suite_conclusion = check_suite.conclusion

      check_suite.rerequest(actor: user, only_failed_check_suites: true)

      check_suite.reload
      new_check_suite_status = check_suite.status
      new_check_suite_conclusion = check_suite.conclusion

      refute_equal original_check_suite_status, new_check_suite_status
      refute_equal original_check_suite_conclusion, new_check_suite_conclusion
    end

    test "raises an error when only_failed_check_suites is true and GitHub Actions check suite is stale" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      user = create(:user)
      repo = create(:repository, owner: user)
      check_suite = create(:check_suite_for_actions_app, repository: repo, created_at: 2.months.ago)
      check_suite.update(status: CheckRun.statuses[:completed], conclusion: CheckRun.conclusions[:failure])

      assert_raises CheckSuite::ActionsDependency::ExpiredWorkflowRunError do
        check_suite.rerequest(actor: user, only_failed_check_suites: true)
      end
    end

    test "raises an error when only_failed_check_suites is true and check suite is in pending state" do
      user = create(:user)
      repo = create(:repository, owner: user)
      check_suite = create(:check_suite, repository: repo)
      check_suite.update(status: CheckRun.statuses[:queued], conclusion: nil)

      assert_nil check_suite.conclusion, "Expected check_suite's original conclusion to differ from the reset value"

      original_check_suite_status     = check_suite.status
      original_check_suite_conclusion = check_suite.conclusion

      assert_raises CheckSuite::AlreadyRerunningError do
        check_suite.rerequest(actor: user, only_failed_check_suites: true)
      end

      check_suite.reload
      new_check_suite_status = check_suite.status
      new_check_suite_conclusion = check_suite.conclusion

      assert_equal original_check_suite_status, new_check_suite_status
      assert_nil original_check_suite_conclusion
      assert_nil new_check_suite_conclusion
    end

    test "raises an error only_failed_check_suites is false and Actions check suite is in pending state" do
      GitHub.stubs(:actions_enabled).returns(true)
      make_trusted_oauth_apps_owner
      user = create(:user)
      repo = create(:repository, owner: user)
      check_suite = create(:check_suite_for_actions_app, repository: repo)
      check_suite.update(status: CheckRun.statuses[:queued], conclusion: nil)

      assert_nil check_suite.conclusion, "Expected check_suite's original conclusion to differ from the reset value"

      original_check_suite_status     = check_suite.status
      original_check_suite_conclusion = check_suite.conclusion

      assert_raises CheckSuite::AlreadyRerunningError do
        check_suite.rerequest(actor: user, only_failed_check_suites: true)
      end

      check_suite.reload
      new_check_suite_status = check_suite.status
      new_check_suite_conclusion = check_suite.conclusion

      assert_equal original_check_suite_status, new_check_suite_status
      assert_nil original_check_suite_conclusion
      assert_nil new_check_suite_conclusion
    end

    test "raises an error when workflow_run is missing on check_suite" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      user = create(:user)
      repo = create(:repository, owner: user)
      check_suite = create(:check_suite_for_actions_app, repository: repo)
      check_suite.update(status: CheckRun.statuses[:completed], conclusion: CheckRun.conclusions[:failure])
      check_suite.workflow_run.destroy
      check_suite.reload

      assert_raises CheckSuite::MissingWorkflowRunError do
        check_suite.rerequest(actor: user)
      end
    end

    test "does not raise an error if only_failed_check_suites is false and non-Actions check suite is in pending state" do
      user = create(:user)
      repo = create(:repository, owner: user)
      check_suite = create(:check_suite, repository: repo)
      check_suite.update(status: CheckRun.statuses[:queued], conclusion: nil)

      assert_nil check_suite.conclusion, "Expected check_suite's original conclusion to differ from the reset value"

      original_check_suite_status     = check_suite.status
      original_check_suite_conclusion = check_suite.conclusion

      assert_nothing_raised do
        check_suite.rerequest(actor: user, only_failed_check_suites: false)
      end
    end

    test "does not raise an error if only_failed_check_suites is false and non-Actions check suite has completed with all runs succesfull" do
      GitHub.flipper[:checks_rerunnable_non_actions_suite].disable
      user = create(:user)
      repo = create(:repository, owner: user)
      check_suite = create(:check_suite, repository: repo)
      check_run_success = create(:check_run, check_suite: check_suite, name: "a", status: :completed, conclusion: :success, completed_at: Time.now)

      refute check_suite.rerunnable?

      GitHub.flipper[:checks_rerunnable_non_actions_suite].enable
      check_suite.reload
      assert check_suite.rerunnable?

      assert_nothing_raised do
        check_suite.rerequest(actor: user, only_failed_check_suites: false)
      end

      new_check_suite_status = check_suite.status
      new_check_suite_conclusion = check_suite.conclusion

      assert_equal "queued", new_check_suite_status
      assert_nil new_check_suite_conclusion
    end

    test "raises an error if rerequestable=false" do
      user = create(:user)
      repo = create(:repository, owner: user)
      check_suite = create(:check_suite, repository: repo, rerequestable: false)

      assert_raises CheckSuite::NotRerequestableError do
        check_suite.rerequest(actor: user)
      end
    end

    test "raises an error if check_runs_rerunnable=false" do
      user = create(:user)
      repo = create(:repository, owner: user)
      check_suite = create(:check_suite, repository: repo, rerequestable: true, check_runs_rerunnable: false)

      assert_raises CheckSuite::NotRerequestableError do
        check_suite.rerequest(actor: user, only_failed_check_runs: true)
      end
    end

    test "raises an error if a disabled actions workflow is re-run" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      user = create(:user)
      repo = create(:repository, owner: user)
      actions_check_suite = create(:check_suite_for_actions_app, :completed, :success, repository: repo, rerequestable: true, check_runs_rerunnable: true)
      workflow = actions_check_suite.workflow_run.workflow

      workflow.update(state: "disabled_manually")

      assert_raises CheckSuite::DisabledWorkflowError do
        actions_check_suite.rerequest(actor: user, only_failed_check_runs: false)
      end
    end

    test "raises an error if logs have expired" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      user = create(:user)
      repo = create(:repository, owner: user)
      actions_check_suite = create(:check_suite_for_actions_app, :completed, :success, repository: repo, rerequestable: true, check_runs_rerunnable: true)
      actions_check_suite.update(completed_at: 2.days.ago)
      check_run = actions_check_suite.check_runs.first

      check_run.update(completed_log_url: "http://github.com/something?retention=1")
      check_run.update(completed_at: 2.days.ago)

      assert_raises CheckSuite::ExpiredLogsError do
        actions_check_suite.rerequest(actor: user, only_failed_check_runs: true)
      end
    end

    test "destroys any existing artifact in the check suite" do
      artifacts_client = mock("artifacts_client")
      artifacts_client.stubs(:delete_artifact).returns(Google::Protobuf::Empty.new)
      GitHub.stubs(:launch_artifacts_exchange_for_check_suite).returns(artifacts_client)

      user = create(:user)
      repo = create(:repository, owner: user)
      check_suite = create(:check_suite, repository: repo)
      artifact = create(:artifact, check_suite: check_suite)
      other_artifact = create(:artifact)

      GitHub::WebSocket.expects(:notify_repository_channel).once

      check_suite.rerequest(actor: user)

      refute Artifact.exists?(id: artifact.id)
      assert Artifact.exists?(id: other_artifact.id)
    end

    test "destroys any existing results backed artifact in the check suite" do
      ActionsResults::Twirp::ArtifactClient
        .any_instance
        .expects(:delete_artifact)
        .returns(TwirpResponse.new(
          status: 200,
          call_succeeded: true,
          value: MonolithTwirp::ActionsResults::Core::V1::DeleteArtifactFromMonolithResponse.new(
            ok: true
          )
        ))
        .once

      user = create(:user)
      repo = create(:repository, owner: user)
      check_suite = create(:check_suite_for_actions_app, :completed, :failure, repository: repo, rerequestable: true, check_runs_rerunnable: true)
      artifact = create(:artifact_from_results_service, check_suite: check_suite)
      other_artifact = create(:artifact)

      GitHub::WebSocket.expects(:notify_repository_channel).once

      check_suite.rerequest(actor: user)

      refute Artifact.exists?(id: artifact.id)
      assert Artifact.exists?(id: other_artifact.id)
    end

    test "destroys any existing artifact in the check suite but sets skip_file_deletion on it for a partial rerun" do
      GitHub.stubs(:actions_enabled?).returns(true)

      user = create(:user)
      repo = create(:repository, owner: user)
      check_suite = create(:check_suite_for_actions_app, :completed, :failure, repository: repo, rerequestable: true, check_runs_rerunnable: true)
      artifact = create(:artifact, check_suite: check_suite)

      artifacts_client = mock("artifacts_client")
      artifacts_client.stubs(:delete_artifact).times(0)
      GitHub.stubs(:launch_artifacts_exchange_for_check_suite).returns(artifacts_client)

      check_suite.rerequest(actor: check_suite.repository.owner, only_failed_check_runs: true)

      refute Artifact.exists?(id: artifact.id)
    end

    test "not destroys any existing results backed artifact in the check suite for a partial rerun" do
      GitHub.stubs(:actions_enabled?).returns(true)

      user = create(:user)
      repo = create(:repository, owner: user)
      check_suite = create(:check_suite_for_actions_app, :completed, :failure, repository: repo, rerequestable: true, check_runs_rerunnable: true)
      artifact = create(:artifact_from_results_service, check_suite: check_suite, source_url: "results://actions-results/run/1234/job/4321/artifact/test")

      check_suite.rerequest(actor: check_suite.repository.owner, only_failed_check_runs: true)

      assert Artifact.exists?(id: artifact.id)
    end

    test "destroying an artifact sends the hydro billing event", skip_enterprise: !GitHub.hydro_enabled? do
      artifacts_client = mock("artifacts_client")
      artifacts_client.stubs(:delete_artifact).returns(Google::Protobuf::Empty.new)
      GitHub.stubs(:launch_artifacts_exchange_for_check_suite).returns(artifacts_client)

      user = create(:user)
      repo = create(:repository, owner: user)
      check_suite = create(:check_suite, repository: repo)

      assert_hydro_messages(count: 0, schema: "github.actions.v0.ArtifactStorageEvent")

      artifact = create(:artifact, check_suite: check_suite)

      # artifact created
      assert_hydro_messages(count: 1, schema: "github.actions.v0.ArtifactStorageEvent")
      messages = hydro_events = decoded_hydro_messages.select { |msg| msg.schema == "github.actions.v0.ArtifactStorageEvent" }
      assert_equal :ADD, messages.last.data.message[:artifact_event_type]

      check_suite.rerequest(actor: user)

      # artifact destroyed
      assert_hydro_messages(count: 2, schema: "github.actions.v0.ArtifactStorageEvent")
      messages = hydro_events = decoded_hydro_messages.select { |msg| msg.schema == "github.actions.v0.ArtifactStorageEvent" }
      assert_equal :REMOVE, messages.last.data.message[:artifact_event_type]

      refute Artifact.exists?(id: artifact.id)
    end

    test "triggers check_suite.rerequest hook event method for failed check runs in Actions" do
      GitHub.stubs(:actions_enabled?).returns(true)

      user = create(:user)
      repo = create(:repository, owner: user)
      check_suite = create(:check_suite_for_actions_app, repository: repo)
      check_run_success = create(:check_run_for_actions_app, name: "success", check_suite: check_suite, status: :completed, conclusion: :success, external_id: 1)
      check_run_failure = create(:check_run_for_actions_app, name: "failure", check_suite: check_suite, status: :completed, conclusion: :failure, external_id: 2)

      events = subscribe "check_suite.rerequest"

      # This check suite does not have artifacts,
      # so rerequesting it should not generate a websocket notification
      GitHub::WebSocket.expects(:notify_repository_channel).never

      check_suite.rerequest(actor: user, only_failed_check_runs: true)

      expected_payload = {
        check_suite_id: check_suite.id,
        actor_id: user.id,
        actions_meta: {
          rerun_info: {
            job_ids: [check_run_failure.external_id.to_s],
            plan_id: check_suite.external_id
          }
        },
        repository_id: check_suite.repository_id,
        organization_id: check_suite.repository.owner.organization? ? check_suite.repository.owner_id : nil,
        business_id: check_suite.repository.organization&.business&.id
      }

      instrumentation_event = events.pop

      assert_equal "check_suite.rerequest", instrumentation_event.name
      assert_subset_hash expected_payload, instrumentation_event.payload
    end

    test "triggers check_suite.rerequest hook event method for a single check run in Actions" do
      GitHub.stubs(:actions_enabled?).returns(true)

      user = create(:user)
      repo = create(:repository, owner: user)
      check_suite = create(:check_suite_for_actions_app, repository: repo)
      check_runs = [
        create(:check_run_for_actions_app, name: "failure1", check_suite: check_suite, status: :completed, conclusion: :failure),
        create(:check_run_for_actions_app, name: "failure2", check_suite: check_suite, status: :completed, conclusion: :failure)
      ]

      events = subscribe "check_suite.rerequest"

      # This check suite does not have artifacts,
      # so rerequesting it should not generate a websocket notification
      GitHub::WebSocket.expects(:notify_repository_channel).never

      check_suite.rerequest(actor: user, only_check_run_id: check_runs.first.id)

      expected_payload = {
        check_suite_id: check_suite.id,
        actor_id: user.id,
        actions_meta: {
          rerun_info: {
            job_ids: [check_runs.first.external_id],
            plan_id: check_suite.external_id
          }
        },
        repository_id: check_suite.repository_id,
        organization_id: check_suite.repository.owner.organization? ? check_suite.repository.owner_id : nil,
        business_id: check_suite.repository.organization&.business&.id
      }

      instrumentation_event = events.pop

      assert_equal "check_suite.rerequest", instrumentation_event.name
      assert_subset_hash expected_payload, instrumentation_event.payload
    end

    test "triggers check_suite.rerequest hook event method for full rerun with debug logging enabled in Actions" do
      GitHub.stubs(:actions_enabled?).returns(true)

      user = create(:user)
      repo = create(:repository, owner: user)
      check_suite = create(:check_suite_for_actions_app, :failure, repository: repo)

      events = subscribe "check_suite.rerequest"

      # This check suite does not have artifacts,
      # so rerequesting it should not generate a websocket notification
      GitHub::WebSocket.expects(:notify_repository_channel).never

      check_suite.rerequest(actor: user, enable_debug_logging: true)

      expected_payload = {
        check_suite_id: check_suite.id,
        actor_id: user.id,
        actions_meta: {
          enable_debug_logging: true,
        },
        repository_id: check_suite.repository_id,
        organization_id: check_suite.repository.owner.organization? ? check_suite.repository.owner_id : nil,
        business_id: check_suite.repository.organization&.business&.id
      }

      instrumentation_event = events.pop

      assert_equal "check_suite.rerequest", instrumentation_event.name
      assert_subset_hash expected_payload, instrumentation_event.payload
    end


    test "triggers check_suite.rerequest hook event method for failed check runs with debug logging enabled in Actions" do
      GitHub.stubs(:actions_enabled?).returns(true)

      user = create(:user)
      repo = create(:repository, owner: user)
      check_suite = create(:check_suite_for_actions_app, repository: repo)
      check_run_success = create(:check_run_for_actions_app, name: "success", check_suite: check_suite, status: :completed, conclusion: :success, external_id: 1)
      check_run_failure = create(:check_run_for_actions_app, name: "failure", check_suite: check_suite, status: :completed, conclusion: :failure, external_id: 2)

      events = subscribe "check_suite.rerequest"

      # This check suite does not have artifacts,
      # so rerequesting it should not generate a websocket notification
      GitHub::WebSocket.expects(:notify_repository_channel).never

      check_suite.rerequest(actor: user, only_failed_check_runs: true, enable_debug_logging: true)

      expected_payload = {
        check_suite_id: check_suite.id,
        actor_id: user.id,
        actions_meta: {
          rerun_info: {
            job_ids: [check_run_failure.external_id.to_s],
            plan_id: check_suite.external_id
          },
          enable_debug_logging: true,
        },
        repository_id: check_suite.repository_id,
        organization_id: check_suite.repository.owner.organization? ? check_suite.repository.owner_id : nil,
        business_id: check_suite.repository.organization&.business&.id
      }

      instrumentation_event = events.pop

      assert_equal "check_suite.rerequest", instrumentation_event.name
      assert_subset_hash expected_payload, instrumentation_event.payload
    end

    test "triggers check_suite.rerequest hook event method for a single check run with debug logging enabled in Actions" do
      GitHub.stubs(:actions_enabled?).returns(true)

      user = create(:user)
      repo = create(:repository, owner: user)
      check_suite = create(:check_suite_for_actions_app, repository: repo)
      check_runs = [
        create(:check_run_for_actions_app, name: "failure1", check_suite: check_suite, status: :completed, conclusion: :failure),
        create(:check_run_for_actions_app, name: "failure2", check_suite: check_suite, status: :completed, conclusion: :failure)
      ]

      events = subscribe "check_suite.rerequest"

      # This check suite does not have artifacts,
      # so rerequesting it should not generate a websocket notification
      GitHub::WebSocket.expects(:notify_repository_channel).never

      check_suite.rerequest(actor: user, only_check_run_id: check_runs.first.id, enable_debug_logging: true)

      expected_payload = {
        check_suite_id: check_suite.id,
        actor_id: user.id,
        actions_meta: {
          rerun_info: {
            job_ids: [check_runs.first.external_id],
            plan_id: check_suite.external_id
          },
          enable_debug_logging: true,
        },
        repository_id: check_suite.repository_id,
        organization_id: check_suite.repository.owner.organization? ? check_suite.repository.owner_id : nil,
        business_id: check_suite.repository.organization&.business&.id
      }

      instrumentation_event = events.pop

      assert_equal "check_suite.rerequest", instrumentation_event.name
      assert_subset_hash expected_payload, instrumentation_event.payload
    end

    test "raises NotRerequestableError if the single Actions check run passed in is not the most recent" do
      GitHub.stubs(:actions_enabled?).returns(true)

      user = create(:user)
      repo = create(:repository, owner: user)
      check_suite = create(:check_suite_for_actions_app, repository: repo)
      check_run_orig = create(:check_run_for_actions_app, check_suite: check_suite, status: :completed, conclusion: :failure)

      latest_execution = check_suite.workflow_run.create_new_workflow_execution(external_id: SimpleUUID::UUID.new.to_guid, attempt: 2)
      check_run_rerun = create(:check_run_for_actions_app, :success, check_suite: check_suite, is_cloned_from_previous_run: false, job_key: check_run_orig.job_key)
      latest_execution.update!(status: "completed", conclusion: "success")

      assert_raises CheckSuite::ActionsDependency::PreviousJobAttemptError do
        check_suite.rerequest(actor: user, only_check_run_id: check_run_orig.id)
      end

      assert_nothing_raised do
        check_suite.rerequest(actor: user, only_check_run_id: check_run_rerun.id)
      end
    end
  end

  context "after repo destruction" do
    test "it removes the check suites" do
      user = create(:user)
      repo = create(:deleted_repository, owner: user)
      check_suite = create(:check_suite, repository: repo)

      assert_difference("CheckSuite.where(repository_id: #{repo.id}).count", -1) do
        perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
          repo.purge(synchronous: true)
        end
      end
    end

    test "is deleted with repository" do
      check_suite = create(:check_suite)
      other_check_suite = create(:check_suite)

      assert_destroyed_in_background_with_parent do |config|
        config.parent_record = check_suite.repository
        config.expect_destroyed = [check_suite]
        config.expect_not_destroyed = [other_check_suite]
      end
    end

    test "it removes logs & artifacts" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)

      user = create(:user)
      repo = create(:repository, owner: user)
      check_suite = create(:check_suite_for_actions_app, repository: repo)
      artifact = create(:artifact, check_suite: check_suite)

      mock_delete_build_logs(check_suite:)
      mock_delete_artifact(
        artifact_name: "",
        check_suite:,
      )

      assert_difference("CheckSuite.where(repository_id: #{repo.id}).count", -1) do
        perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
          repo.remove(user, synchronous: true)
        end
      end
    end
  end

  context "analytics" do
    test "publishes hydro event when status changes" do
      GitHub.stubs(:hydro_enabled?).returns(false)

      check_suite = create :check_suite
      check_run   = create(:check_run, check_suite: check_suite, name: "a", status: :in_progress)

      GitHub.stubs(:hydro_enabled?).returns(true)
      check_run = create(:check_run, check_suite: check_suite, name: "a", status: :completed, conclusion: :success, completed_at: Time.now)

      assert_hydro_messages(count: 1, schema: "github.v1.CheckSuiteStatusChange")
      assert_hydro_published({
        check_suite_id: check_suite.id,
        previous_status: :IN_PROGRESS,
        current_status: :COMPLETED,
        repository_id: check_suite.repository_id,
        head_sha: check_suite.head_sha,
        conclusion: check_suite.conclusion,
        app: Hydro::EntitySerializer.integration(check_suite.github_app),
      }, schema: "github.v1.CheckSuiteStatusChange")
    end

    test "does not publish hydro event when status remains the same" do
      GitHub.stubs(:hydro_enabled?).returns(false)

      check_suite = create :check_suite
      check_run   = create(:check_run, check_suite: check_suite, status: :in_progress)

      GitHub.stubs(:hydro_enabled?).returns(true)
      check_run = create(:check_run, check_suite: check_suite, status: :in_progress)

      assert_hydro_messages(count: 0, schema: "github.v1.CheckSuiteStatusChange")
    end
  end

  context "#matching_pull_requests" do
    test "returns an empty AR relation if there is no head_branch" do
      check_suite = create :check_suite

      assert_empty check_suite.matching_pull_requests
      assert_kind_of ActiveRecord::Relation, check_suite.matching_pull_requests
    end

    test "returns an empty AR relation if the there is no associated repository" do
      check_suite = create :check_suite, head_branch: "master", repository_id: 12345

      assert_empty check_suite.matching_pull_requests
      assert_kind_of ActiveRecord::Relation, check_suite.matching_pull_requests
    end

    test "returns an empty AR relation if the check suite is from a forked repo" do
      check_suite = create :check_suite, head_branch: "feature", head_repository: create(:repository)

      assert_empty check_suite.matching_pull_requests
      assert_kind_of ActiveRecord::Relation, check_suite.matching_pull_requests
    end

    test "returns an empty AR relation if PR base repository has been deleted" do
      head_repo = create(:repository, from_example: :rebase_pull_request)

      base_repo = create(:repository)
      pull = create(:pull_request, :disable_disk_access, repository: base_repo, head_repository: head_repo, head_ref: "feature")
      base_repo.update!(active: false)

      head_sha = head_repo.heads.first.target.oid
      check_suite = create(:check_suite, head_branch: "feature", repository: head_repo, head_sha: head_sha)

      assert_empty check_suite.matching_pull_requests
    end

    test "returns a collection of pull requests" do
      user = create :user, login: "octocat"
      org  = create :organization, admin: user
      repo = create :repository, owner: user, name: "Hello-World", from_example: :rebase_pull_request
      github_app = create(:integration, :with_hook, default_permissions: { "checks" => :write },
        default_events: %w(check_suite), owner: org)
      installation = make_integration_installation(integration: github_app, target: user)

      # Use existing git repo `rebase_pull_request`
      # Which lives in test/fixtures/git/examples/rebase_pull_request.git

      # Create a PR between master and [existing] contrib branches on that repo.
      pull = create(:pull_request,
        repository: repo,
        base_repository: repo,
        base_user: repo.owner,
        base_ref: "master",
        head_repository: repo,
        head_user: repo.owner,
        head_ref: "contrib",
        user: user,
      )

      after = repo.refs["contrib"].commit

      check_suite = create(:check_suite, repository: repo, head_sha: after,
        head_branch: "contrib",
        github_app: github_app)

      assert_includes check_suite.matching_pull_requests, pull
    end
  end

  # This is a private method, but we want to test it anyway as a regression test.
  context "#open_pull_requests" do
    test "memoizes based on `limit` parameter" do
      check_suite = create :check_suite

      # Only the first call for any given `limit` will run queries.
      assert_queries { check_suite.send(:open_pull_requests).load }
      assert_no_queries { check_suite.send(:open_pull_requests).load }

      assert_queries { check_suite.send(:open_pull_requests, limit: 10).load }
      assert_no_queries { check_suite.send(:open_pull_requests, limit: 10).load }

      assert_queries { check_suite.send(:open_pull_requests, limit: 20).load }
      assert_no_queries { check_suite.send(:open_pull_requests, limit: 20).load }
    end
  end

  context "notify websockets on updates" do
    test "notify if completed_log_url changes" do
      check_suite = create(:check_suite)
      GitHub::WebSocket.expects(:notify_repository_channel).once
      check_suite.update(completed_log_url: "https://example.com")
    end

    test "notify if suite completes" do
      check_suite = create(:check_suite)
      GitHub::WebSocket.expects(:notify_repository_channel).once
      check_suite.update(conclusion: "success")
    end

    test "notify if we have reset status back to pending" do
      check_suite = create(:check_suite)
      GitHub::WebSocket.expects(:notify_repository_channel).once
      check_suite.update(status: CheckRun.statuses[:pending])
    end

    test "do not notify if we have changed status to something other than pending" do
      check_suite = create(:check_suite)
      GitHub::WebSocket.expects(:notify_repository_channel).never
      check_suite.update(status: CheckRun.statuses[:completed])
    end

    test "do not notify if other field changes" do
      check_suite = create(:check_suite)
      GitHub::WebSocket.expects(:notify_repository_channel).never
      check_suite.update(hidden: true)
    end
  end

  context "calculate_hidden" do
    test "it's set to false when event = push, pull_request, pull_request_review, pull_request_target or deployment" do
      push_check_suite = create(:check_suite, event: "push")
      pull_request_check_suite = create(:check_suite, event: "pull_request")
      pull_request_review_check_suite = create(:check_suite, event: "pull_request_review")
      pull_request_target_check_suite = create(:check_suite, event: "pull_request_target")
      deployment_check_suite = create(:check_suite, event: "deployment")
      nil_event_check_suite = create(:check_suite, event: nil)

      refute_predicate push_check_suite, :hidden
      refute_predicate pull_request_check_suite, :hidden
      refute_predicate pull_request_review_check_suite, :hidden
      refute_predicate pull_request_target_check_suite, :hidden
      refute_predicate deployment_check_suite, :hidden
      refute_predicate nil_event_check_suite, :hidden
    end

    test "it's set to true when event is not push, pull_request, pull_request_review, pull_request_target or deployment" do
      issue_comment_check_suite = create(:check_suite_for_actions_app, event: "issue_comment")

      assert_predicate issue_comment_check_suite, :hidden
    end
  end

  context "#readable_by?" do
    test "resolves to true where a user can read the repository" do
      rando = create(:user)
      check_suite = create(:check_suite)

      assert check_suite.repository.readable_by?(rando)
      assert check_suite.readable_by?(rando)
    end

    test "resolves to false where a user cannot read the repository" do
      rando = create(:user)
      check_suite = create(:check_suite, repository: create(:private_repository))

      refute check_suite.repository.readable_by?(rando)
      refute check_suite.readable_by?(rando)
    end
  end

  context "#workflow_name" do
    test "returns the check suite name if present" do
      check_suite = create(:check_suite_for_actions_app, name: "CI")

      assert_equal "CI", check_suite.workflow_name
    end

    test "returns a placeholder if the check suite name is blank" do
      check_suite1 = create(:check_suite)
      check_suite2 = create(:check_suite, name: " ")

      assert_equal "(Unnamed workflow)", check_suite1.workflow_name
      assert_equal "(Unnamed workflow)", check_suite2.workflow_name
    end
  end

  context "#workflow_filename" do
    test "returns file name for check suite with workflow" do
      # yml
      check_suite1 = create(:check_suite_for_actions_app, name: "CI", workflow_file_path: ".github/workflows/main.yml")
      # yaml
      check_suite2 = create(:check_suite_for_actions_app, name: "test", workflow_file_path: ".github/workflows/test.yaml")

      assert_equal "main.yml", check_suite1.workflow_filename
      assert_equal "test.yaml", check_suite2.workflow_filename
    end

    test "does not return file name for check suite without workflow" do
      check_suite = create(:check_suite_for_actions_app, name: "CI", workflow_file_path: nil)

      assert_equal "", check_suite.workflow_filename
    end

    test "does not return file name when path doesn't have yaml extension'" do
      # some workflow parsing failures lead to workflow_file_path of "BuildFailed"
      check_suite = create(:check_suite, name: "CI", workflow_file_path: "BuildFailed")

      assert_equal "", check_suite.workflow_filename
    end
  end

  context "deleted GitHub app" do
    test "returns the GhostGitHubApp" do
      assert_equal GhostGitHubApp.instance, CheckSuite.new.github_app
    end

    test "delegates correctly" do
      assert_equal "Deleted GitHub App", CheckSuite.new.github_app_name
    end
  end

  test "DB constraints prevent creating multiple suites with the same external_id" do
    github_app = create :integration
    repo = create(:repository)
    attrs = attributes_for(:check_suite, external_id: "a").update(repository: repo, github_app: github_app)
    assert_raises(ActiveRecord::RecordNotUnique) do
      CheckSuite.find_or_create_for_integrator(attrs)
      CheckSuite.create(attrs)
    end
  end

  context "user_visible?" do
    test "explicit completion suites are always visible" do
      check_suite = create :check_suite, explicit_completion: true
      assert_predicate check_suite, :user_visible?
    end
    test "non-explicitly completed suites are visible when they have runs" do
      check_suite = create :check_suite
      refute_predicate check_suite, :user_visible?
      check_run   = create :check_run, check_suite: check_suite, name: "apple"
      assert_predicate check_suite, :user_visible?
    end
  end

  context "create workflow" do
    test "creates a workflow and a workflow_run for the Actions app" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      repository = create :repository

      workflow_file_path = ".github/workflows/main.yml"
      check_suite1 = create :check_suite_for_actions_app,
        repository: repository,
        workflow_file_path: workflow_file_path,
        name: "Node CI",
        external_id: SimpleUUID::UUID.new.to_guid,
        event: "pull_request",
        action: "open"
      workflow_run1 = check_suite1.workflow_run
      assert workflow_run1
      assert workflow_run1.workflow
      assert_equal "Node CI", workflow_run1.workflow.name
      assert_equal check_suite1.workflow_file_path, workflow_run1.workflow.path
      assert_equal check_suite1.name, workflow_run1.workflow.name
      assert_equal "active", workflow_run1.workflow.state

      assert_equal check_suite1.event, workflow_run1.event
      assert_equal check_suite1.action, workflow_run1.action
      assert_equal check_suite1.name, workflow_run1.name
      assert_equal check_suite1.head_branch, workflow_run1.head_branch
      assert_equal check_suite1.head_sha, workflow_run1.head_sha
      assert_equal check_suite1.workflow_file_path, workflow_run1.workflow_file_path
      assert_equal check_suite1.external_id, workflow_run1.external_id
      assert_equal check_suite1.repository, workflow_run1.repository

      # now we test that it does not create a new workflow when it already exists
      check_suite2 = create :check_suite_for_actions_app,
        repository: repository,
        workflow_file_path: workflow_file_path,
        name: "Another name",
        external_id: SimpleUUID::UUID.new.to_guid,
        event: "pull_request",
        action: "open"
      workflow_run2 = check_suite2.workflow_run
      assert workflow_run2
      assert_equal workflow_run2.workflow.id, workflow_run1.workflow.id
      assert_equal "Another name", workflow_run2.workflow.name
      assert_equal check_suite2.workflow_file_path, workflow_run2.workflow.path
      assert_equal check_suite2.name, workflow_run2.workflow.name
      assert_equal "active", workflow_run2.workflow.state

      assert_equal check_suite2.event, workflow_run2.event
      assert_equal check_suite2.action, workflow_run2.action
      assert_equal check_suite2.name, workflow_run2.name
      assert_equal check_suite2.head_branch, workflow_run2.head_branch
      assert_equal check_suite2.head_sha, workflow_run2.head_sha
      assert_equal check_suite2.workflow_file_path, workflow_run2.workflow_file_path
      assert_equal check_suite2.external_id, workflow_run2.external_id
      assert_equal check_suite2.repository, workflow_run2.repository
    end


    test "create workflow run for check suites with the 'startup_failure' conclusion" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      repository = create :repository

      check_suite = create :check_suite_for_actions_app, :startup_failure, workflow_file_path: ".github/workflows/node.yml", explicit_completion: true
      assert_equal check_suite.conclusion, "startup_failure"
      workflow_run = check_suite.workflow_run
      assert workflow_run
    end

    test "does not create workflow or workflow run for check suites not created by the Actions app" do
      check_suite = create :check_suite

      workflow_run = Actions::WorkflowRun.find_by(check_suite_id: check_suite.id, repository_id: check_suite.repository_id)
      refute workflow_run
    end

    # This will prevent creating workflow runs for check suites created programatically by users with the GITHUB_TOKEN
    test "does not create workflow or workflow run for check suites created with the GITHUB_TOKEN" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner
      check_suite = create :check_suite_for_actions_app, workflow_file_path: nil

      workflow_run = Actions::WorkflowRun.find_by(id: check_suite.id)
      refute workflow_run
    end

    test "creates a workflow marked as deleted when the check suite does not have a valid workflow file path" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      repository = create :repository

      workflow_file_path = "Build Failed" # See https://github.com/github/c2c-actions-experience/issues/2148
      check_suite1 = create :check_suite_for_actions_app, repository: repository, workflow_file_path: workflow_file_path, name: "Node CI"
      workflow_run1 = check_suite1.workflow_run
      assert workflow_run1
      assert workflow_run1.workflow
      assert_equal "Node CI", workflow_run1.workflow.name
      assert_equal check_suite1.workflow_file_path, workflow_run1.workflow.path
      assert_equal check_suite1.name, workflow_run1.workflow.name
      assert_equal "deleted", workflow_run1.workflow.state
    end

    test "creates a workflow with the passed in workflow_name_hint if there is one, and the event is dynamic, otherwise falls back to the check suite name" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      repository = create :repository

      workflow_name_hint = "A Workflow Name"
      path = ".github/workflows/main.yml"

      dynamic_name = create :check_suite_for_actions_app,
        repository: repository,
        workflow_file_path: path,
        name: "Dynamic With Name",
        workflow_name_hint: workflow_name_hint,
        event: "dynamic"

      dynamic_no_name = create :check_suite_for_actions_app,
        repository: repository,
        workflow_file_path: path,
        name: "Dynamic With No Name",
        event: "dynamic"

      name_not_dynamic = create :check_suite_for_actions_app,
        repository: repository,
        workflow_file_path: path,
        name: "Not Dynamic",
        workflow_name_hint: workflow_name_hint

      assert_equal workflow_name_hint, dynamic_name.workflow_run.workflow.name
      assert_equal "Dynamic With No Name", dynamic_no_name.workflow_run.workflow.name
      assert_equal "Not Dynamic", name_not_dynamic.workflow_run.workflow.name
    end

    test "rollback when a workflow run creation fails" do
      assert_no_difference -> { CheckSuite.count } do
        exception = ActiveRecord::StatementInvalid
        CheckSuite.any_instance.stubs(:create_workflow_run).raises(exception)
        assert_raises(exception) do
          create :check_suite_for_actions_app
        end
      end
    end
  end

  context "delete logs" do
    test "deletes the logs in cascade" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      repository = create(:repository)
      check_suite = create(:check_suite_for_actions_app, repository: repository)
      check_run = create(:check_run, :with_steps, check_suite: check_suite)

      check_suite.update(completed_log_url: "https://logs.github.com/some-unique-slug-run1")
      check_run.update(completed_log_url: "https://logs.github.com/some-unique-slug-run1", completed_log_lines: 1000)
      check_run.steps.first.update(completed_log_url: "https://logs.github.com/some-unique-slug-step1", completed_log_lines: 100)

      mock_delete_build_logs(check_suite:)

      events = assert_performed_audit_entries(count: 1, only: "checks.delete_logs") do
        check_suite.delete_logs(actor: repository.owner)
      end

      expected_payload = {
        action: "checks.delete_logs",
        actor: repository.owner.login,
        repo: repository.nwo,
        check_suite_id: check_suite.id,
        operation_type: "remove",
      }

      assert_subset_hash expected_payload, events.first

      check_suite.reload
      check_run.reload

      refute check_suite.completed_log_url
      refute check_run.completed_log_url
      refute check_run.completed_log_lines

      check_run.steps.each do |step|
        refute step.completed_log_url
        refute step.completed_log_lines
      end
    end

    test "does not create workflow or workflow run for check suites not created by the Actions app" do
      check_suite = create :check_suite

      workflow_run = Actions::WorkflowRun.find_by(id: check_suite.id)
      refute workflow_run
    end
  end

  context "#destroy" do
    test "deletes the logs for Actions check suites" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner
      check_suite = create(:check_suite_for_actions_app)

      mock_delete_build_logs(check_suite:)

      check_suite.destroy
    end

    test "doesn't raise an error when deleting the logs for Actions check suites" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner
      check_suite = create(:check_suite_for_actions_app)

      mock_delete_build_logs(check_suite:, returns_error: true)

      check_suite.destroy
    end

    test "does not delete the logs for a non-Actions check suite" do
      artifacts_client = mock("artifacts_client")

      check_suite = create(:check_suite)

      mock_delete_build_logs(check_suite:).never

      check_suite.destroy
    end

    test "deletes associated artifacts" do
      check_suite = create(:check_suite_for_actions_app)
      artifact = create(:artifact, check_suite: check_suite, source_url: "https://logs.github.com/some-unique-slug-step1")
      artifact_id = artifact.id

      perform_enqueued_jobs(only: DestroyDependentRecordsJob) do
        check_suite.destroy
      end

      assert_nil Artifact.find_by(id: artifact_id)
    end

    test "skips deleting logs and artifacts from file storage when attribute is set" do
      check_suite = create(:check_suite_for_actions_app)

      mock_delete_artifact(artifact_name: "", check_suite:).never
      mock_delete_build_logs(check_suite:).never

      check_suite.skip_delete_resources_from_launch = true
      check_suite.destroy
    end
  end

  context "#rerunnable" do
    test "if rerequestable=true and check_runs_rerunnable=true" do
      GitHub.stubs(:actions_enabled?).returns(true)
      GitHub.flipper[:checks_rerunnable_non_actions_suite].enable
      make_trusted_oauth_apps_owner

      actions_check_suite = create(:check_suite_for_actions_app, :success, rerequestable: true, check_runs_rerunnable: true)
      assert actions_check_suite.rerunnable?

      check_suite = create(:check_suite, :success, rerequestable: true, check_runs_rerunnable: true)
      assert check_suite.rerunnable?
    end

    test "if rerequestable=false and check_runs_rerunnable=true" do
      GitHub.stubs(:actions_enabled?).returns(true)
      GitHub.flipper[:checks_rerunnable_non_actions_suite].enable
      make_trusted_oauth_apps_owner

      actions_check_suite = create(:check_suite_for_actions_app, :success, rerequestable: false, check_runs_rerunnable: true)
      assert actions_check_suite.rerunnable?

      check_suite = create(:check_suite, :success, rerequestable: false, check_runs_rerunnable: true)
      assert check_suite.rerunnable?
    end

    test "if rerequestable=true and check_runs_rerunnable=false" do
      GitHub.stubs(:actions_enabled?).returns(true)
      GitHub.flipper[:checks_rerunnable_non_actions_suite].enable
      make_trusted_oauth_apps_owner

      actions_check_suite = create(:check_suite_for_actions_app, :success, rerequestable: true, check_runs_rerunnable: false)
      assert actions_check_suite.rerunnable?

      check_suite = create(:check_suite, :success, rerequestable: true, check_runs_rerunnable: false)
      assert check_suite.rerunnable?
    end

    test "if rerequestable=false and check_runs_rerunnable=false" do
      GitHub.stubs(:actions_enabled?).returns(true)
      GitHub.flipper[:checks_rerunnable_non_actions_suite].enable
      make_trusted_oauth_apps_owner

      actions_check_suite = create(:check_suite_for_actions_app, :success, rerequestable: false, check_runs_rerunnable: false)
      refute actions_check_suite.rerunnable?

      check_suite = create(:check_suite, :success, rerequestable: false, check_runs_rerunnable: false)
      refute check_suite.rerunnable?
    end

    test "if an actions check_suite is expired" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      check_suite = create(:check_suite_for_actions_app, :success, created_at: 2.months.ago, rerequestable: true)
      refute check_suite.rerunnable?
    end

    test "if an actions check_suite can be canceled" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      check_suite = create :check_suite_for_actions_app
      assert check_suite.workflow_run
      assert check_suite.cancelable?
      refute check_suite.completed?
      refute check_suite.rerunnable?
    end

    test "if an actions check_suite is failed" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      check_suite = create(:check_suite_for_actions_app, :failure, rerequestable: true, check_runs_rerunnable: true)
      # A failed check_suite status should not have an impact on the rerunnable state
      assert check_suite.failed?
      assert check_suite.rerunnable?
    end

    test "if the repository is archived" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      repo = create(:repository, maintained: false)
      check_suite = create(:check_suite_for_actions_app, :failure, repository: repo, rerequestable: true, check_runs_rerunnable: true)

      refute check_suite.rerunnable?
    end
  end

  context "#cancelable" do
    test "if a non-completed actions check_suite" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      check_suite = create(:check_suite_for_actions_app)
      refute check_suite.completed?
      assert check_suite.workflow_run
      assert check_suite.workflow_file_path?
      assert check_suite.cancelable?
    end

    test "if a completed actions check_suite" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      check_suite = create(:check_suite_for_actions_app, :success)
      assert check_suite.completed?
      assert check_suite.workflow_run
      assert check_suite.workflow_file_path?
      refute check_suite.cancelable?
    end

    test "if a non-actions check_suite" do
      check_suite = create(:check_suite)
      refute check_suite.completed?
      refute check_suite.workflow_run
      refute check_suite.workflow_file_path?
      refute check_suite.cancelable?
    end
  end

  context "#cancel" do
    test "adds actor to Twirp request if specified" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)

      check_suite = create :check_suite_for_actions_app
      actor = check_suite.repository.owner

      cancel_args = {
        check_suite_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: check_suite.global_relay_id),
        canceled_by_id: actor.id,
        canceled_by_name: actor.display_login,
        canceled_by_global_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: actor.global_relay_id),
        force: false
      }

      Launch::Twirp::DeployerClient.any_instance
        .expects(:rpc)
        .with(:WorkflowCancel, cancel_args)
        .returns(TwirpResponse.new(status: 200, call_succeeded: true))
        .once

      check_suite.cancel(actor: actor)
    end

    test "actor is not in Twirp request if not specified" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      check_suite = create :check_suite_for_actions_app

      cancel_args = {
        check_suite_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: check_suite.global_relay_id),
        force: false
      }

      Launch::Twirp::DeployerClient.any_instance
        .expects(:rpc)
        .with(:WorkflowCancel, cancel_args)
        .returns(TwirpResponse.new(status: 200, call_succeeded: true))
        .once

      check_suite.cancel(actor: nil)
    end

    test "uses a direct call to run-service via twirp if the feature flag is set" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)

      check_suite = create :check_suite_for_actions_app

      run_stamp_url = "https://run-stamp.example.com/0"
      check_suite.workflow_run.latest_workflow_run_execution.update!(run_stamp_url: run_stamp_url)

      # No calls to standard launch endpoint
      Launch::Twirp::DeployerClient.any_instance.expects(:rpc).with(:WorkflowCancel).never

      # Instead a call to the RunService twirp endpoint
      run_service_mock = mock
      cancel_args = {
        plan_id: check_suite.workflow_run.latest_workflow_run_execution.external_id,
        cancelled_by: check_suite.repository.owner.login,
        is_force_cancel: false
      }
      run_service_mock.expects(:cancel_plan).with(equals(cancel_args)).returns(TwirpResponse.new(status: 200, call_succeeded: true))
      ActionsRunService::Twirp::RunServiceClient.expects(:new).with(base_url: run_stamp_url).returns(run_service_mock)

      check_suite.cancel(actor: check_suite.repository.owner)
    end

    test "uses a direct call to run-service via twirp if the feature flag is set (and handles missing actor)" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)

      check_suite = create :check_suite_for_actions_app

      run_stamp_url = "https://run-stamp.example.com/0"
      check_suite.workflow_run.latest_workflow_run_execution.update!(run_stamp_url: run_stamp_url)

      # No calls to standard launch endpoint
      Launch::Twirp::DeployerClient.any_instance.expects(:rpc).with(:WorkflowCancel).never

      # Instead a call to the RunService twirp endpoint
      run_service_mock = mock
      cancel_args = {
        plan_id: check_suite.workflow_run.latest_workflow_run_execution.external_id,
        is_force_cancel: false
      }
      run_service_mock.expects(:cancel_plan).with(equals(cancel_args)).returns(TwirpResponse.new(status: 200, call_succeeded: true))
      ActionsRunService::Twirp::RunServiceClient.expects(:new).with(base_url: run_stamp_url).returns(run_service_mock)

      check_suite.cancel(actor: nil)
    end
  end

  context "#update_workflow_run_execution" do
    test "when status changes" do
      check_suite = create(:check_suite_for_actions_app)
      workflow_run_execution = check_suite.workflow_run.workflow_run_executions.last
      # queued
      assert_equal check_suite.status, workflow_run_execution.status

      # in progress
      check_suite.update(status: CheckRun.statuses[:in_progress])
      assert_equal check_suite.status, workflow_run_execution.reload.status

      # completed
      check_suite.update(status: CheckRun.statuses[:completed], conclusion: CheckRun.conclusions[:success])
      assert_equal check_suite.status, workflow_run_execution.reload.status
      assert_equal check_suite.conclusion, workflow_run_execution.conclusion
    end

    test "when check_suite fields change for rerun" do
      check_suite = create(:check_suite_for_actions_app)
      workflow_run_execution = check_suite.workflow_run.workflow_run_executions.last

      assert_equal check_suite.status, workflow_run_execution.status
      assert_nil workflow_run_execution.conclusion
      assert_equal check_suite.started_at, workflow_run_execution.started_at
      assert_nil workflow_run_execution.completed_at
      assert_nil workflow_run_execution.completed_log_url

      original_exeuction_id = workflow_run_execution.external_id
      refute_nil original_exeuction_id

      # expect these fields to change during/after rerun
      check_suite.update(
        status: CheckRun.statuses[:completed],
        conclusion: CheckRun.conclusions[:success],
        started_at: Time.now,
        completed_at: 1.hour.from_now,
        completed_log_url: "https://example.com",
        external_id: SimpleUUID::UUID.new.to_guid,
      )

      assert_equal check_suite.status, workflow_run_execution.reload.status
      assert_equal check_suite.conclusion, workflow_run_execution.conclusion
      assert_equal check_suite.started_at, workflow_run_execution.started_at
      assert_equal check_suite.completed_at, workflow_run_execution.completed_at
      assert_equal check_suite.completed_log_url, workflow_run_execution.completed_log_url

      assert_equal check_suite.external_id, workflow_run_execution.external_id
      refute_equal original_exeuction_id, workflow_run_execution.external_id
    end

    test "when status changes to in_progress" do
      events = subscribe "workflow_run.status_changed"

      check_suite = create(:check_suite_for_actions_app)
      workflow_run_execution = check_suite.workflow_run.workflow_run_executions.last

      # in progress
      check_suite.update(status: CheckRun.statuses[:in_progress])
      assert_equal check_suite.status, workflow_run_execution.reload.status
      instrumentation_event = events.pop
      assert_equal "workflow_run.status_changed", instrumentation_event.name

      expected_payload = {
        run_id: check_suite.workflow_run.id,
        action: :in_progress,
        primary_resource: check_suite.workflow_run.attributes,
        actor_id: check_suite.workflow_run.actor_id,
        repository_id: check_suite.repository_id,
        organization_id: check_suite.repository.owner.organization? ? check_suite.repository.owner_id : nil,
        business_id: check_suite.repository.organization&.business&.id
       }
      assert_equal expected_payload, instrumentation_event.payload
    end
  end

  context "annotation_count" do
    test "is zero for a check suite without annotations" do
      check_suite = create(:check_suite)

      assert_equal 0, check_suite.annotation_count
    end

    test "is the correct count for a check suite with annotations" do
      check_suite = create(:check_suite)
      create_list(:check_annotation, 4, check_run: nil, check_suite: check_suite, repository: check_suite.repository)

      assert_equal 4, check_suite.annotation_count
    end

    test "is the correct count for a check suite with check runs and annotations" do
      check_suite = create(:check_suite)
      repository = check_suite.repository
      create_list(:check_annotation, 3, check_run: nil, check_suite: check_suite, repository: repository)

      check_run1 = create(:check_run, check_suite: check_suite, repository: repository)
      create_list(:check_annotation, 5, check_run: check_run1, check_suite: nil, repository: repository)

      check_run2 = create(:check_run, check_suite: check_suite, repository: repository)
      create_list(:check_annotation, 7, check_run: check_run2, check_suite: nil, repository: repository)

      assert_equal 15, check_suite.annotation_count
    end
  end

  context "#message_id" do
    test "sets an id for to identify workflow runs in emails" do
      check_suite = create(:check_suite)
      expected_message_id = "<#{check_suite.repository.name_with_display_owner}/check-suites/#{check_suite.global_relay_id}/#{check_suite.updated_at.to_i}@#{GitHub.urls.host_name}>"
      assert_equal expected_message_id, check_suite.message_id
    end
  end

  context "#approval_notifications" do
    test "send web and email notifications for creating approval gate request" do

      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      user1 = create(:user)
      user2 = create(:user)
      org = create(:organization)
      org.add_member(user1)
      org.add_member(user2)
      repo = create(:private_repository, owner: org)
      team = org.teams.create(name: "Approvers", privacy: :closed)
      team.add_repository(repo, :admin)
      team.add_member(user1)
      team.add_member(user2)

      enable_notifications_for_user(user1)
      GitHub.newsies.get_and_update_settings(user1) do |settings|
        settings.continuous_integration_web = true
        # email notifications disabled for one user
        settings.continuous_integration_email = false
      end

      enable_notifications_for_user(user2)
      GitHub.newsies.get_and_update_settings(user2) do |settings|
        settings.continuous_integration_web = true
        #email notifications enabled for another user
        settings.continuous_integration_email = true
      end

      # WorkflowRunApprovalNotification uses the workflow_run's updated_at timestamp to generate an id
      # so we need to make sure the workflow_run doesn't get updated after the notification is sent to
      # allow us to assert for the specfic notification delivery using WorkflowRunApprovalNotification.new
      Timecop.freeze do
        check_suite_name = "Node CI"
        check_suite = create(:check_suite_for_actions_app, :failure, repository: repo, name: check_suite_name, trigger: nil, event: "pull_request", action: "open")

        env = create(:environment, repository: repo, name: "staging")
        env.add_approver(user1)
        env.add_approver(team)
        deployment = create(:deployment, repository: repo, environment: env.name)
        check_run = create(:check_run, check_suite: check_suite, name: "actions check run", deployment: deployment, status: "queued")

        Newsies::NotificationEntry.destroy_all
        Newsies::NotificationDelivery.delete_all
        ActionMailer::Base.deliveries.clear

        gate_request = perform_enqueued_jobs do # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
          GateRequest.create_or_update_gate_request(env.approval_gate, check_run, "token", nil)
        end

        assert_equal 1, Newsies::NotificationEntry.for_user(user1).count
        assert_equal 1, Newsies::NotificationEntry.for_user(user2).count

        assert_delivered_web_notification(user1, WorkflowRunApprovalNotification.new(check_suite.workflow_run), "approval_requested")
        assert_delivered_web_notification(user2, WorkflowRunApprovalNotification.new(check_suite.workflow_run), "approval_requested")

        # check email notifications
        assert_equal 1, ActionMailer::Base.deliveries.size
        recipients = ActionMailer::Base.deliveries.map { |e| e.smtp_envelope_to }.flatten
        assert_equal [user2.email], recipients
      end
    end

    test "send web and email notifications only runs you are an approver on" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      user1 = create(:user)
      user2 = create(:user)
      org = create(:organization)
      org.add_member(user1)
      org.add_member(user2)
      repo = create(:private_repository, owner: org)

      enable_notifications_for_user(user1)
      GitHub.newsies.get_and_update_settings(user1) do |settings|
        settings.continuous_integration_web = true
        settings.continuous_integration_email = true
      end

      enable_notifications_for_user(user2)
      GitHub.newsies.get_and_update_settings(user2) do |settings|
        settings.continuous_integration_web = true
        settings.continuous_integration_email = true
      end

      # WorkflowRunApprovalNotification uses the workflow_run's updated_at timestamp to generate an id
      # so we need to make sure the workflow_run doesn't get updated after the notification is sent to
      # allow us to assert for the specfic notification delivery using WorkflowRunApprovalNotification.new
      Timecop.freeze do
        check_suite_name = "Node CI"
        check_suite = create(:check_suite_for_actions_app, :failure, repository: repo, name: check_suite_name, trigger: nil, event: "pull_request", action: "open")

        env = create(:environment, repository: repo, name: "staging")
        prod_env = create(:environment, repository: repo, name: "production")
        env.add_approver(user1)
        prod_env.add_approver(user2)
        deployment = create(:deployment, repository: repo, environment: env.name)
        check_run = create(:check_run, check_suite: check_suite, name: "actions check run", deployment: deployment, status: "queued")

        prod_deployment = create(:deployment, repository: repo, environment: prod_env.name)
        prod_check_run = create(:check_run, check_suite: check_suite, name: "prod actions check run", deployment: prod_deployment, status: "queued")

        Newsies::NotificationEntry.destroy_all
        Newsies::NotificationDelivery.delete_all
        ActionMailer::Base.deliveries.clear

        gate_request = perform_enqueued_jobs do # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
          GateRequest.create_or_update_gate_request(env.approval_gate, check_run, "token", nil)
        end

        assert_equal 1, Newsies::NotificationEntry.for_user(user1).count
        assert_equal 0, Newsies::NotificationEntry.for_user(user2).count

        assert_delivered_web_notification(user1, WorkflowRunApprovalNotification.new(check_suite.workflow_run), "approval_requested")
        refute_delivered_web_notification(user2, WorkflowRunApprovalNotification.new(check_suite.workflow_run))

        # check email notifications
        assert_equal 1, ActionMailer::Base.deliveries.size
        recipients = ActionMailer::Base.deliveries.map { |e| e.smtp_envelope_to }.flatten
        assert_equal [user1.email], recipients
      end
    end
  end

  context "#mark_stale" do
    test "returns nil when the check run is not old enough to be stale" do
      check_suite = create(:check_suite)
      assert_nil check_suite.mark_stale!
    end

    context "when the check suite hasn't been updated in more than 2 weeks" do
      test "marks a check suite with no check runs as stale" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        check_suites = []

        # creates checks older than 2 weeks with incomplete statuses
        now = Time.zone.now
        @incomplete_statuses.each do |status|
          check_suite = create(
            :check_suite,
            status: status,
            created_at: now.ago(CheckSuite::DEFAULT_STALE_THRESHOLD),
            updated_at: now.ago(CheckSuite::DEFAULT_STALE_THRESHOLD),
          )
          check_suites << check_suite
        end

        check_suites.each do |check_suite|
          assert_predicate check_suite.check_runs.where(repository_id: check_suite.repository_id), :empty?

          check_suite.mark_stale!

          assert_equal "completed", check_suite.status
          assert_equal "stale", check_suite.conclusion
        end

        assert_equal check_suites.size, GitHub.dogstats.increments("checks.marked_stale").size
      end

      test "marks all the check runs as stale, which also marks the check suite as stale" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        check_suites = []

        # creates checks older than 2 weeks with incomplete statuses
        now = Time.zone.now
        @incomplete_statuses.each do |status|
          check_run = create(
            :check_run,
            status: status,
            created_at: now.ago(CheckSuite::DEFAULT_STALE_THRESHOLD),
            updated_at: now.ago(CheckSuite::DEFAULT_STALE_THRESHOLD),
          )
          check_run.check_suite.update(created_at: check_run.created_at, updated_at: check_run.updated_at)
          check_suites << check_run.check_suite
        end

        # Test that check suite completed events were never sent
        CheckSuite.any_instance.expects(:instrument).never

        # test that all the check runs were marked :stale
        check_suites.each do |check_suite|
          check_suite.mark_stale!
          check_suite.reload

          check_suite.check_runs do |check_run|
            assert_equal "completed", check_run.status
            assert_equal "stale", check_run.conclusion
          end

          assert_equal "completed", check_suite.status
          assert_equal "stale", check_suite.conclusion
        end

        assert_equal check_suites.size, GitHub.dogstats.increments("checks.marked_stale").size
      end

      test "marks old incomplete Actions check suites as stale" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        check_suite = create(:check_suite, status: "queued", explicit_completion: true)
        create(:check_run, :success, check_suite: check_suite)
        check_suite.update(created_at: Time.zone.now.ago(CheckSuite::DEFAULT_STALE_THRESHOLD), updated_at: Time.zone.now.ago(CheckSuite::DEFAULT_STALE_THRESHOLD))

        check_suite.mark_stale!

        check_suite.reload

        assert_equal "completed", check_suite.status
        assert_equal "stale", check_suite.conclusion

        assert_equal 1, GitHub.dogstats.increments("checks.marked_stale").size
      end

      test "marks old incomplete checks as stale, even if they fail AR validation" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        # creates checks older than 2 weeks with incomplete statuses
        now = Time.zone.now
        check_run = create(
          :check_run,
          status: "requested",
          created_at: now.ago(CheckSuite::DEFAULT_STALE_THRESHOLD),
          updated_at: now.ago(CheckSuite::DEFAULT_STALE_THRESHOLD),
        )
        check_run.details_url = "ftp://is-invalid"
        assert_raises ActiveRecord::RecordInvalid do
          check_run.save!
        end
        check_run.save!(validate: false, touch: false)
        check_run.check_suite.update(created_at: check_run.created_at, updated_at: check_run.updated_at)

        check_suite = check_run.check_suite
        check_suite.mark_stale!
        check_suite.reload

        check_suite.check_runs.where(repository_id: check_suite.repository_id).each do |check_run|
          assert_equal "completed", check_run.status
          assert_equal "stale", check_run.conclusion
        end

        assert_equal "completed", check_suite.status
        assert_equal "stale", check_suite.conclusion

        assert_equal 1, GitHub.dogstats.increments("checks.marked_stale").size
      end
    end
  end

  context "#copy_non_actions_check_runs_from_previous_execution" do
    test "copies check runs from the previous execution" do
      user = create(:user)
      repo = create(:repository, owner: user)

      Timecop.freeze do
        check_suite = create(:check_suite_for_actions_app, repository: repo)
        # first execution has 1 actions check run and 1 non-actions check run
        create(:check_run_for_actions_app, :success, check_suite: check_suite, name: "actions check run")
        create(:check_run, :success, check_suite: check_suite, name: "non actions check run")
        check_suite.update!(status: "completed", conclusion: "success", completed_at: Time.now)

        Timecop.travel(10.minutes)
        check_suite.rerequest(actor: user)
        workflow_run = check_suite.workflow_run
        # second execution has 1 actions check run, non-actions check run should be copied from the first execution
        execution = workflow_run.create_new_workflow_execution(external_id: SimpleUUID::UUID.new.to_guid, attempt: 2)
        create(:check_run_for_actions_app, :success, check_suite: check_suite, name: "actions check run")

        check_suite.update!(status: "completed", conclusion: "success", completed_at: Time.now)

        latest_check_runs = workflow_run.latest_check_runs(execution: execution)
        assert_equal 2, latest_check_runs.size
        assert latest_check_runs.any? { |check_run| check_run.name == "non actions check run" }
      end
    end

    test "does not copy check runs from the previous execution if created during current execution" do
      user = create(:user)
      repo = create(:repository, owner: user)

      Timecop.freeze do
        check_suite = create(:check_suite_for_actions_app, repository: repo)
        # first execution has 1 actions check run and 1 non-actions check run
        create(:check_run_for_actions_app, :success, check_suite: check_suite, name: "actions check run")
        create(:check_run, :success, check_suite: check_suite, name: "non actions check run")
        check_suite.update!(status: "completed", conclusion: "success", completed_at: Time.now)

        Timecop.travel(10.minutes)
        check_suite.rerequest(actor: user)

        workflow_run = check_suite.workflow_run
        # second execution has 1 actions check run and 1 non-actions check run
        execution = workflow_run.create_new_workflow_execution(external_id: SimpleUUID::UUID.new.to_guid, attempt: 2)

        # create non-actions check run while actions check run is still running
        actions_check_run = create(:check_run_for_actions_app, check_suite: check_suite, name: "actions check run")
        create(:check_run, :success, check_suite: check_suite, name: "non actions check run")

        latest_check_runs = workflow_run.latest_check_runs(execution: execution)
        assert_equal 2, latest_check_runs.size
        assert latest_check_runs.any? { |check_run| check_run.name == "non actions check run" }

        actions_check_run.update!(status: "completed", conclusion: "success", completed_at: Time.now)
        # check run completion will also set check_suite to completed through update_suite_rollups
        latest_check_runs = workflow_run.latest_check_runs(execution: execution)
        assert_equal 2, latest_check_runs.size
        assert latest_check_runs.any? { |check_run| check_run.name == "non actions check run" }
      end
    end
  end

  [:head_branch, :name, :workflow_file_path].each do |field|
    test "supports emoji for #{field}" do
      check_suite = create(:check_suite, field => "we ❤️ emojis")

      assert_multibyte_tracked_changes(check_suite, field)
    end
  end

  context "#head_repository_and_branch_name" do
    test "returns the repository and branch name" do
      repo = create :repository
      head = create :repository
      check_suite  = create(:check_suite, repository: repo, head_repository: head, head_branch: "test-branch")

      assert_equal "#{head.owner.display_login}:test-branch", check_suite.head_repository_and_branch_name
    end

    test "returns head branch name for deleted head_repository owner" do
      head_owner = create :user
      repo = create :repository
      head = create(:repository, owner: head_owner)
      check_suite  = create(:check_suite, repository: repo, head_repository: head, head_branch: "test-branch")
      head_owner.destroy!
      check_suite.reload

      assert_equal "test-branch", check_suite.head_repository_and_branch_name
    end
  end
end

class CheckSuiteFindOrCreateForIntegratorTest < GitHub::TestCase
  include GitHub::LoggerHelper

  setup do
    # actions is currently the only app with multiple_check_suites_per_sha_enabled
    @actions_app = create :integration
    GitHub.stubs(:launch_github_app).returns(@actions_app)
    @repo = create(:repository)
  end

  test "if external_id is present, will return an existing suite for the same repo with the same id" do
    attrs = attributes_for(:check_suite, external_id: "a").update(repository: @repo, github_app: @actions_app)
    first = CheckSuite.find_or_create_for_integrator(attrs)
    second = CheckSuite.find_or_create_for_integrator(attrs)
    assert_predicate second, :existing?
    assert_predicate second, :success?
    assert_equal first.record.id, second.record.id
  end

  test "allows multiple check suites for different repos with the same external_id" do
    repo_two = create(:repository)

    attrs = attributes_for(:check_suite, external_id: "a").update(github_app: @actions_app)

    first = CheckSuite.find_or_create_for_integrator(attrs.update(repository: @repo))
    second = CheckSuite.find_or_create_for_integrator(attrs.update(repository: repo_two))

    assert_empty first.errors
    assert_empty second.errors
    refute_predicate second, :existing?
    refute_equal first.record.id, second.record.id
  end

  test "for apps without multiple_check_suites_per_sha_enabled, cannot create multiple checks for a sha" do
    app = create :integration
    attrs = attributes_for(:check_suite).update(repository: @repo, github_app: app)

    first = CheckSuite.find_or_create_for_integrator(attrs)
    assert_predicate first, :success?

    second = CheckSuite.find_or_create_for_integrator(attrs)
    assert_predicate second, :duplicate_for_sha?
    refute_predicate second, :success?
  end

  test "for apps with multiple_check_suites_per_sha_enabled, does not rescue on uniqueness key" do
    Actions::Workflow.stubs(:create_or_update_workflow).raises(ActiveRecord::RecordNotUnique)

    attrs = attributes_for(:check_suite_for_actions_app).update(repository: @repo, github_app: @actions_app)

    expected_log = {
      "Body" => "Failed to save check suite",
      "code.namespace" => "CheckSuite",
      "code.function" => "find_or_create_for_integrator",
    }

    results = T.let(nil, T.nilable(CheckSuite))
    assert_logged(**expected_log) do
      results = CheckSuite.find_or_create_for_integrator(attrs)
    end

    refute_predicate results, :success?
    assert_predicate results, :conflict?
  end

  test "does not prevent multiple check suites for an app on a repo without external_id" do
    app = create :integration
    attrs = attributes_for(:check_suite).update(repository: @repo, github_app: app)

    %w[aabb bbcc ccdd].each do |sha|
      result = CheckSuite.find_or_create_for_integrator(attrs.update(head_sha: sha))
      assert_predicate result, :success?
      assert_equal sha, result.record.head_sha
    end
  end

  test "allows multiple check suites for same repos with the same external_id, for different apps" do
    github_app_two = create :integration

    attrs = attributes_for(:check_suite, external_id: "a").update(repository: @repo)

    first = CheckSuite.find_or_create_for_integrator(attrs.update(github_app: @actions_app))
    second = CheckSuite.find_or_create_for_integrator(attrs.update(github_app: github_app_two))

    assert_empty first.errors
    assert_empty second.errors
    refute_equal first.record.id, second.record.id
  end

  test "does not upsert a record with the same external_id" do
    attrs = attributes_for(:check_suite, external_id: "a").update(repository: @repo, github_app: @actions_app)
    first = CheckSuite.find_or_create_for_integrator(attrs)
    second = CheckSuite.find_or_create_for_integrator(attrs.update(head_sha: "other-sha"))
    assert_equal first.record.head_sha, second.record.head_sha
  end

  context "#duration" do
    test "works if started_at and completed_at are not defined" do
      Timecop.freeze do
        check_suite = create(:check_suite)
        check_suite.update(started_at: nil, completed_at: nil, created_at: check_suite.updated_at - 1.hour)
        assert_equal 1.hour.to_i, check_suite.duration
      end
    end

    test "works if started_at is defined but completed_at not" do
      Timecop.freeze do
        check_suite = create(:check_suite)
        check_suite.update(started_at: Time.now, completed_at: nil)
        assert_equal 0, check_suite.duration
      end
    end

    test "works if started_at and completed_at are defined" do
      Timecop.freeze do
        check_suite = create(:check_suite)
        check_suite.update(started_at: Time.now, completed_at: 1.hour.from_now)
        assert_equal 1.hour.to_i, check_suite.duration
      end
    end
  end

  context"#gate_approval_logs" do
    test "returns gate approval logs in the creation order" do
      org = create(:organization)
      repo = create(:private_repository, owner: org)
      check_suite = create(:check_suite, :success)

      gate_approval_log1 = create(:gate_approval_log, repository: repo, check_suite: check_suite)
      gate_approval_log2 = create(:gate_approval_log, repository: repo, check_suite: check_suite)
      gate_approval_log3 = create(:gate_approval_log, repository: repo, check_suite: check_suite)

      assert_equal check_suite.gate_approval_logs, [gate_approval_log3, gate_approval_log2, gate_approval_log1]
    end
  end

  context "#has_reruns" do
    test "returns false if started_at is nil" do
      check_suite = create(:check_suite)
      check_suite.update(started_at: nil)
      refute check_suite.has_reruns
    end

    test "return false if started_at is equal to created_at" do
      check_suite = create(:check_suite)
      assert_equal check_suite.started_at, check_suite.created_at
      refute check_suite.has_reruns
    end

    test "return true when started_at is greater than created_at" do
      check_suite = create(:check_suite)
      check_suite.update(started_at: 1.minute.from_now)
      assert check_suite.has_reruns
    end

    test "head_branch returns the stripped version by default" do
      check_suite1 = create(:check_suite, head_branch: "main")
      assert_equal "main", check_suite1.head_branch

      check_suite2 = create(:check_suite, head_branch: "refs/heads/main")
      assert_equal "main", check_suite2.head_branch
      assert_equal "refs/heads/main", check_suite2.head_branch(fully_qualified: true)
    end
  end
end
