# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-actionsresults-core"
require "test_helpers/launch/exchange_url_helper"

class CheckRunTest < GitHub::TestCase
  include HydroTestHelpers
  include PushTestHelper
  include StringFromBinaryTestHelper
  include GitHub::DatabaseQueryWarningsTestHelpers
  include Launch::ArtifactExchangeUrlHelper

  fixtures do
    @github_app = create(:integration, default_permissions: { "checks" => :write }, url: "http://super-duper.com")
    @user = create(:user, login: "octocat")
    @repo = create :repository, owner: @user, name: "hello-world", from_example: :rebase_pull_request
    make_integration_installation(integration: @github_app, repository: @repo)
    @fork_user = create(:user)
    @fork = create(:fork_repository, forker: @fork_user, fork_repo: @repo, from_example: :rebase_pull_request)

    # Create a PR between master and [existing] contrib branches on that repo.
    @issue = create(:issue, user: @user, repository: @repo)
    # Make a new commit on contrib branch,
    # so that there is a diff to compare after a Push of that commit
    @before = @repo.heads.find("contrib").target_oid
    metadata = { message: "blah", committer: @user }
    commit = @repo.heads.find("contrib").append_commit(metadata, @user) do |files|
      files.add("foo", "dsfdsfsdfsd")
    end
    @head_sha = commit.oid

    @pull = create(:pull_request,
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      base_ref: "master",
      head_repository: @repo,
      head_user: @repo.owner,
      head_ref: "contrib",
      issue: @issue,
      user: @issue.user,
    )

    # Create a Push for the fresh commit(s) on the feature branch.
    perform_enqueued_jobs(only: [CreateCheckSuitesJob]) do
      trigger_push_event(
        @repo.shard_path,
        @user.login,
        [["refs/heads/contrib", @before, @head_sha]],
        Time.now,
        perform_hydro_push_jobs: [HydroRepositoriesOnPushJob]
      )
    end
    @push = T.must(push_accessor.freeze.by_repo_id_and_after(repository_id: @repo.id, after: @head_sha)).freeze

    make_trusted_oauth_apps_owner
    @code_scanning_app = create(:code_scanning_integration)

    pages_integration = create :github_pages_integration
    GitHub.stubs(:pages_github_app).returns(pages_integration)

    @check_suite = CheckSuite.where(push_id: @push.id).last
    @run         = create :check_run, check_suite: @check_suite, name: "coverage"

    @gated_check_run = create :check_run
    @gated_deployment = @gated_check_run.create_deployment("staging")
    @environment = create :environment, :with_approval_gate, repository: @gated_check_run.repository
    @gate_request = GateRequest.create_or_update_gate_request(
      @environment.approval_gate,
      @gated_check_run,
      "dummy token", # token
      :closed, # gate state
      false, # concluded
      nil # expires_at
    )
    @workflow_run_backend_id = "eaabb1cc-1e70-4c57-8307-fb1207223ec3"
    @workflow_job_run_backend_id = "a5317d85-aec2-4e03-a018-e723e2713cf5"
    @completed_log_url_from_results = "results://actions-results/run/eaabb1cc-1e70-4c57-8307-fb1207223ec3/job/a5317d85-aec2-4e03-a018-e723e2713cf5"
    @results_log_url_payload = MonolithTwirp::ActionsResults::Core::V1::GetCompletedJobLogResponse.new(
      log_url: @completed_log_url_from_results
    ).freeze
    @authenticated_url = "https://logs.github.com/some-unique-slug-job1?token=1234"
  end

  setup do
    # Ensure Actions is considered enabled, even for Enterprise
    GitHub.stubs(:actions_enabled?).returns(true)
  end

  context "nil creator" do
    test "returns ghost user" do
      @run.creator.delete
      assert_equal User.ghost, @run.reload.creator
    end
  end

  context "images" do
    test "images are converted to hash from HashWithIndifferentAccess before validation" do
      run = CheckRun.new(details_url: "http://foo.com", check_suite: @check_suite, repository: @repo)
      run.images = [{ alt: "foo", image_url: "https://github.com" }.with_indifferent_access]
      run.valid?

      assert_equal 1, run["images"].length
      assert_kind_of Hash, run["images"].first
      assert run["images"].all? { |image| image.all? { |k, _| k.is_a?(Symbol) } }, "keys were not all symbols"
    end

    test "images are converted to hash from string keys before validation" do
      run = CheckRun.new(details_url: "http://foo.com", check_suite: @check_suite, repository: @repo)
      run.images = [{ "alt" => "foo", "image_url" => "https://github.com" }]
      run.valid?

      assert_equal 1, run["images"].length
      assert_kind_of Hash, run["images"].first
      assert run["images"].all? { |image| image.all? { |k, _| k.is_a?(Symbol) } }, "keys were not all symbols"
    end

    test "images can handle symbol keys" do
      run = CheckRun.new(details_url: "http://foo.com", check_suite: @check_suite, repository: @repo)
      run.images = [{ alt: "foo", image_url: "https://github.com" }]
      run.valid?

      assert_equal 1, run["images"].length
      assert_kind_of Hash, run["images"].first
      assert run["images"].all? { |image| image.all? { |k, _| k.is_a?(Symbol) } }, "keys were not all symbols"
    end
  end

  context "validation" do
    test "requires a status" do
      run = CheckRun.new(status: nil, repository: @repo)
      run.valid?

      refute run.errors[:status].blank?
    end

    test "details_url must be http(s)" do
      valid_run_1 = CheckRun.create(name: "ci", details_url: "http://foo.com", check_suite: @check_suite, repository: @repo)
      valid_run_2 = CheckRun.create(name: "ci", details_url: "https://foo.com", check_suite: @check_suite, repository: @repo)
      invalid_run = CheckRun.create(name: "ci", details_url: "javascript://alert(1)", check_suite: @check_suite, repository: @repo)

      assert valid_run_1.errors[:details_url].blank?
      assert valid_run_2.errors[:details_url].blank?
      refute invalid_run.errors[:details_url].blank?
    end

    test "requires conclusion, if completed_at is set" do
      run = CheckRun.new(conclusion: nil, repository: @repo)
      assert run.valid?
      assert run.errors[:conclusion].blank?

      run = CheckRun.new(completed_at: Time.now.utc, conclusion: nil, repository: @repo)
      refute_predicate run, :valid?
      refute run.errors[:conclusion].blank?
    end

    test "requires conclusion if status is completed" do
      run = CheckRun.new(status: "completed", conclusion: nil, name: "foo", repository: @repo)
      refute_predicate run, :valid?
      refute run.errors[:conclusion].blank?
    end

    test "limits actions to a maxiumum quantity" do
      actions_attrs = Array.new(CheckRun::MAX_ACTIONS_QUANTITY + 1) do
        { label: "Fix",
          identifier: "fix_errors",
          description: "Fix errors" }
      end

      run = CheckRun.new(actions: actions_attrs, repository: @repo)
      refute_predicate run, :valid?
      refute_predicate run.errors[:actions], :blank?
    end

    test "actions are only valid when they are a CheckRunAction" do
      actions_attrs = [
        ActiveSupport::HashWithIndifferentAccess.new(
          label: "Fix",
          identifier: "fix_errors",
          description: "Fix errors",
        ),
      ]

      Failbot.expects(:report)
        .with(
          ArgumentError.new("CheckRunAction was a ActiveSupport::HashWithIndifferentAccess instead of a CheckRunAction"),
          "gh.check_run.id": nil,
        )
      run = CheckRun.new(repository: @repo)
      run.stubs(:actions).returns(actions_attrs)
      refute_predicate run, :valid?
    end

    test "images array size too big" do
      # (126 + 1) .... size of the image + comma (last one has no comma, but has a bracket)
      # 127 * 473 + 1 .... + 1 for the first bracket
      # = 65660 bytes, just under our 60KB limit
      images = []
      517.times do
        images << { alt: "80% coverage", image_url: "http://example.com/graph.png", caption: "The coverage decreased by 1%, and is now at 80%." }
      end

      images_check_run = CheckRun.new(images: images, repository: @repo)
      refute images_check_run.valid?

      refute_predicate images_check_run.errors[:images], :blank?
      assert_equal "array was larger than 65535 bytes", images_check_run.errors[:images].to_sentence
    end

    test "requires all images to have urls" do
      blank_url_run = CheckRun.new(repository: @repo)
      blank_url_run.images = [
        { image_url: "https://github.com" },
        { image_url: "" },
      ]
      blank_url_run.valid?

      refute_predicate blank_url_run.errors[:images], :blank?

      nil_url_run = CheckRun.new(repository: @repo)
      nil_url_run.images = [
        { image_url: "https://github.com" },
        { image_url: nil },
      ]
      nil_url_run.valid?

      refute_predicate nil_url_run.errors[:images], :blank?

      no_url_run = CheckRun.new(repository: @repo)
      no_url_run.images = [
        { image_url: "https://github.com" },
        {},
      ]
      refute_predicate no_url_run, :valid?

      refute_predicate no_url_run.errors[:images], :blank?
    end
  end

  test "copies `repository_id` from the `check_suite`" do
    suite = create :check_suite, repository: @repo
    run   = create :check_run, check_suite: @check_suite

    refute_nil run.repository_id
    assert_equal suite.repository_id, run.repository_id
  end

  test "finds runs for a single SHA in a repository" do
    run1 = @run
    run2 = create :check_run, check_suite: @check_suite

    runs = CheckRun.for_sha_and_repository_id(@check_suite.head_sha, @check_suite.repository_id)
    assert_equal 2, runs.length
    assert_same_elements [run1.id, run2.id], runs.map(&:id)
  end

  test "finds runs for multiple SHAs in a repository" do
    suite1 = @check_suite
    suite2 = create :check_suite, repository: @repo, github_app: @github_app, head_sha: @before

    run1   = @run
    run2   = create :check_run, check_suite: @check_suite
    run3   = create :check_run, check_suite: suite2, name: "coverage"

    runs = CheckRun.for_sha_and_repository_id([suite1.head_sha, suite2.head_sha], @check_suite.repository_id)
    assert_equal 3, runs.length
    assert_same_elements [run1.id, run2.id, run3.id], runs.map(&:id)
  end

  test "finds runs for SHA, repository ID and app ID" do
    sha = @check_suite.head_sha
    repo_id = @check_suite.repository_id
    check_run_id = @run.id
    app_id = @check_suite.github_app_id

    result = CheckRun
      .order("id DESC")
      .for_sha_and_repository_id(sha, repo_id)
      .for_app_id(app_id, repo_id)
      .first

    assert_equal T.must(result).id, @run.id
  end

  test "filters runs for an app ID" do
    check_suite1 = @check_suite
    run1         = @run
    check_suite2 = create :check_suite
    run2         = create :check_run, check_suite: check_suite2

    runs = CheckRun.for_app_id(check_suite1.github_app_id, @repo.id)
    assert_equal 1, runs.length
    assert_same_elements [run1.id], runs.map(&:id)
  end

  context "#before_create" do
    test "strips out extra whitespace from the name" do
      check_run = create(:check_run, check_suite: @check_suite, status: :in_progress, name: "  LOOK AT MY GOERGEOUS NAME  ")
      assert_equal "LOOK AT MY GOERGEOUS NAME", check_run.name
    end
  end

  context "#after_commit" do
    test "triggers setting the status of the check suite" do
      check_suite = create :check_suite
      assert check_suite.queued?

      create :check_run, check_suite: check_suite, status: :in_progress

      assert check_suite.reload.in_progress?
    end

    test "triggers setting the conclusion of the check suite" do
      check_suite  = create :check_suite
      assert_nil check_suite.conclusion

      check_run1   = create(:check_run, check_suite: check_suite, name: "a", status: "completed", conclusion: :failure, completed_at: Time.now.utc)
      assert check_suite.reload.failure?

      # Adding an in_progress check run changes the failure status (because it changes the entire CheckSuite status)
      check_run2   = create(:check_run, check_suite: check_suite, name: "b", status: "in_progress", conclusion: nil)
      refute_predicate check_suite.reload, :failure?
    end

    test "triggers check_run.create after create" do
      events = subscribe "check_run.create"
      check  = create :check_run

      expected_payload = {
        check_run_id: check.id,
      }
      instrumentation_event = events.pop

      assert_equal "check_run.create", instrumentation_event.name
      assert expected_payload <= instrumentation_event.payload
    end

    test "triggers websocket message" do
      channel = GitHub::WebSocket::Channels.commit(@check_suite.repository, @check_suite.head_sha)

      GitHub::WebSocket.stubs(:notify_repository_channel)
      GitHub::WebSocket.expects(:notify_repository_channel)
        .with(@check_suite.repository, channel, has_key(:reason) & has_key(:timestamp))
        .returns([]).once
      create(:check_run,
        name: "live-coverage",
        check_suite: @check_suite,
        status: "in_progress")
    end

    test "triggers websocket message to workflow_job_channel" do
      GitHub.stubs(:actions_enabled?).returns(true)
      check_suite = create(:check_suite_for_actions_app,
        repository: @repo,
        head_repository: @repo
      )
      channel = GitHub::WebSocket::Channels.workflow_job_run(check_suite.workflow_run.id, "parent-job-id")
      GitHub::WebSocket.stubs(:notify_repository_channel)
      GitHub::WebSocket.expects(:notify_repository_channel)
        .with(check_suite.repository, channel, has_key(:reason) & has_key(:timestamp))
        .returns([]).once
      create(:check_run, check_suite: check_suite, parent_job_id: "parent-job-id")
    end

    test "the complete event is only fired when the conclusion is set" do
      events = subscribe "check_run.complete"

      # create a completed check-run. This fires a "complete" event
      run = create(:completed_check_run, check_suite: @check_suite, completed_at: Time.now.utc - 1.minute)
      # update any field other than the conclusion. This shouldn't fire a "complete" event
      run.completed_at = Time.now.utc
      # even if the conclusion is set to the same value, it shouldn't fire a "complete" event
      run.conclusion = :success
      run.save

      assert_equal 1, events.size
    end

    context "#save" do
      test "scopes update queries to repository id" do
        check_run = create(:check_run)
        check_run.name = "New check run name"

        _, queries = log_queries do
          check_run.save
        end

        refute queries.any? { |q| q.digested_sql.match?(/\AUPDATE check_runs SET (.*) WHERE check_runs.id = \?\Z/) }, "Expected no update query that's not scoped to a repo. Got:\n#{queries.map(&:digested_sql).select { |q| q.start_with?("UPDATE check_runs") }}"
        assert queries.any? { |q| q.digested_sql.match?(/\AUPDATE check_runs SET (.*) WHERE check_runs.id = \? AND check_runs.repository_id = \?\Z/) }, "Expected update query to be scoped to repo. Got:\n#{queries.map(&:digested_sql).select { |q| q.start_with?("UPDATE check_runs") }}"
      end
    end

    context "on create" do
      {
        queued:      "queued",
        in_progress: "in_progress",
        completed:   "completed",
      }.each do |status_persisted, expected_event_action|
        test "when status is '#{status_persisted}', emits a 'workflow_job.#{expected_event_action}' event" do
          workflow_job_attrs = ActiveSupport::HashWithIndifferentAccess.new(
            id: 12345,
            runner_id: 123,
            runner_name: "runner"
          )

          check_run = build(
            :check_run,
            status: status_persisted,
            conclusion: status_persisted == :completed ? :success : nil
          )
          mock_workflow_job_run = Object.new
          mock_workflow_job_run.stubs(id: 12345, channel: "ch", cloned_from_previous_run?: false, runner_id: 123, runner_name: "runner", attributes: workflow_job_attrs)
          check_run.stubs(workflow_job_run: mock_workflow_job_run)
          events = subscribe /workflow_job\./

          assert_difference -> { events.size }, 1 do
            check_run.save!
          end

          instrumentation_event = events.last
          expected_payload = {
            check_run_id: check_run.id,
            action: expected_event_action,
            job_id: 12345,
            repository_id: check_run.repository_id,
            actor_id: check_run.check_suite.creator.id,
          }
          refute_nil instrumentation_event
          assert_equal "workflow_job.#{expected_event_action}", instrumentation_event.name
          assert expected_payload <= instrumentation_event.payload
          assert_nil instrumentation_event.payload[:organization_id]
          assert_nil instrumentation_event.payload[:business_id]
        end
      end
    end

    context "on update" do
      test "when status changed to 'queued', emits a 'queued' event" do

        workflow_job_attrs = ActiveSupport::HashWithIndifferentAccess.new(
            id: 12345,
            runner_id: 123,
            runner_name: "runner"
          )

        check_run = create(:check_run, status: :requested)
        mock_workflow_job_run = Object.new
        mock_workflow_job_run.stubs(id: 12345, channel: "ch", cloned_from_previous_run?: false, runner_id: 123, runner_name: "runner", attributes: workflow_job_attrs)

        check_run.stubs(workflow_job_run: mock_workflow_job_run)
        events = subscribe /workflow_job\./

        assert_difference -> { events.size }, 1 do
          check_run.update!(status: :queued)
        end

        instrumentation_event = events.last
        expected_payload = {
          check_run_id: check_run.id,
          action: "queued",
          job_id: 12345,
          repository_id: check_run.repository_id,
          actor_id: check_run.check_suite.creator.id,
        }
        refute_nil instrumentation_event
        assert_equal "workflow_job.queued", instrumentation_event.name
        assert expected_payload <= instrumentation_event.payload
        assert_nil instrumentation_event.payload[:organization_id]
        assert_nil instrumentation_event.payload[:business_id]
      end

      test "when status changed and primary data used" do
        workflow_job_attrs =
          ActiveSupport::HashWithIndifferentAccess.new(
            check_run_id: 75,
            label_data: ["self-hosted"],
            runner_id: 123,
            runner_name: "runner",
            runner_group_id: 1,
            runner_group_name: "Default",
            id: 12345,
            workflow_run_id: 12,
            repository_id: 3,
            parent_job_id: "printText",
            job_key: "printText.__default",
            created_at: "2023-02-16T05:35:50.945Z",
            updated_at: "2023-02-16T05:35:55.014Z",
            workflow_run_execution_id: 12,
            original_workflow_run_execution_id: 12
          )

        check_run = create(:check_run, status: :requested)
        mock_workflow_job_run = Object.new
        mock_workflow_job_run.stubs(id: 12345, channel: "ch", cloned_from_previous_run?: false, runner_id: 123, runner_name: "runner", attributes: workflow_job_attrs)
        check_run.stubs(workflow_job_run: mock_workflow_job_run)
        events = subscribe /workflow_job\./
        assert_difference -> { events.size }, 1 do
          check_run.update!(status: :queued)
        end
        instrumentation_event = events.last
        expected_payload = {
          check_run_id: check_run.id,
          action: "queued",
          job_id: 12345,
          repository_id: check_run.repository_id,
          actor_id: check_run.check_suite.creator.id,
        }
        refute_nil instrumentation_event
        assert expected_payload <= instrumentation_event.payload
        assert_nil instrumentation_event.payload[:organization_id]
      end

      test "primary attributes are included when webhook event is instrumented" do
        workflow_job_attrs =
          ActiveSupport::HashWithIndifferentAccess.new(
            check_run_id: 75,
            label_data: ["self-hosted"],
            runner_id: 123,
            runner_name: "runner",
            runner_group_id: 1,
            runner_group_name: "Default",
            id: 12345,
            workflow_run_id: 12,
            repository_id: 3,
            parent_job_id: "printText",
            job_key: "printText.__default",
            created_at: "2023-02-16T05:35:50.945Z",
            updated_at: "2023-02-16T05:35:55.014Z",
            workflow_run_execution_id: 12,
            original_workflow_run_execution_id: 12
          )
        organization = create(:organization)
        owner_repo = create(:repository, owner: organization)
        suite = create :check_suite, repository: owner_repo
        check_run = create :check_run, status: :requested, check_suite: suite
        mock_workflow_job_run = Object.new
        mock_workflow_job_run.stubs(id: 12345, channel: "ch", cloned_from_previous_run?: false, runner_id: 123, runner_name: "runner", attributes: workflow_job_attrs)
        check_run.stubs(workflow_job_run: mock_workflow_job_run)
        events = subscribe /workflow_job\./

        assert_difference -> { events.size }, 1 do
          check_run.update!(status: :queued)
        end

        instrumentation_event = events.last
        expected_payload = {
          check_run_id: check_run.id,
          action: "queued",
          job_id: 12345,
          repository_id: check_run.repository_id,
          actor_id: check_run.check_suite.creator.id,
          organization_id: check_run.check_suite.repository.organization.id,
          business_id: check_run.check_suite.repository.organization&.business&.id
        }

        refute_nil instrumentation_event
        refute_nil instrumentation_event.payload[:primary_resource]
        assert expected_payload <= instrumentation_event.payload
      end

      test "when status did not change, emits no 'workflow_job' events" do
        workflow_job_attrs = ActiveSupport::HashWithIndifferentAccess.new(
          id: 12345,
          runner_id: 123,
          runner_name: "runner"
        )
        check_run = create(:check_run, status: :requested)
        mock_workflow_job_run = Object.new
        mock_workflow_job_run.stubs(id: 12345, channel: "ch", cloned_from_previous_run?: false, runner_id: 123, runner_name: "runner", attributes: workflow_job_attrs)
        check_run.stubs(workflow_job_run: mock_workflow_job_run)
        events = subscribe /workflow_job\./

        assert_no_changes -> { events.size } do
          check_run.update!(title: "hello world")
        end
      end

      test "when status changed to an irrelevant status, emits no 'workflow_job' events" do
        workflow_job_attrs = ActiveSupport::HashWithIndifferentAccess.new(
          id: 12345,
          runner_id: 123,
          runner_name: "runner"
        )
        check_run = create(:check_run, status: :requested)
        mock_workflow_job_run = Object.new
        mock_workflow_job_run.stubs(id: 12345, channel: "ch", cloned_from_previous_run?: false, runner_id: 123, runner_name: "runner", attributes: workflow_job_attrs)
        check_run.stubs(workflow_job_run: mock_workflow_job_run)
        events = subscribe /workflow_job\./

        assert_no_changes -> { events.size } do
          check_run.update!(status: :pending)
        end
      end
    end
  end

  context "failed scope" do
    test "includes completed check runs that failed, agreeing with #failed?" do
      successful_run = create(:check_run, :success)
      refute_predicate successful_run, :failed?

      failed_run = create(:check_run, :failure)
      assert_predicate failed_run, :failed?

      cancelled_run = create(:check_run, :cancelled)
      assert_predicate cancelled_run, :failed?

      queued_run = create(:check_run)
      refute_predicate queued_run, :failed?

      result = CheckRun.failed.where(id: [successful_run, failed_run, cancelled_run, queued_run])

      refute_includes result, successful_run
      assert_includes result, failed_run
      assert_includes result, cancelled_run
      refute_includes result, queued_run
    end
  end

  context "#permalink" do
    test "returns an absolute for the individual check run" do
      assert_equal "/octocat/hello-world/runs/#{@run.id}", @run.permalink
    end

    test "returns a relative link to the individual check run in the context of a pull request" do
      assert_equal "/octocat/hello-world/pull/#{@pull.number}/checks?check_run_id=#{@run.id}", @run.permalink(pull: @pull)
    end

    test "returns different URLs depending on the check_suite_focus argument" do
      assert_equal "/octocat/hello-world/runs/#{@run.id}", @run.permalink
      assert_equal "/octocat/hello-world/runs/#{@run.id}?check_suite_focus=true", @run.permalink(check_suite_focus: true)
    end

    test "returns a permalink to the Actions UI with a pr number even when in the context of a PR" do
      @run.stubs(:is_actions_check_run?).returns(true)
      expected = "/octocat/hello-world/runs/#{@run.id}?check_suite_focus=true"
      expected_with_pr = "/octocat/hello-world/runs/#{@run.id}?check_suite_focus=true&pr=1"
      assert_equal expected, @run.permalink
      assert_equal expected_with_pr, @run.permalink(pull: @pull)
    end

    test "returns actions permalink with check_run id without pr number" do
      GitHub.stubs(:actions_enabled?).returns(true)

      actions_check_run = create :check_run_for_actions_app
      expected = "/#{actions_check_run.repository.nwo}/actions/runs/#{actions_check_run.check_suite.workflow_run.id}/job/#{actions_check_run.id}"
      assert_equal expected, actions_check_run.permalink
    end

    test "returns actions permalink with check_run id" do
      GitHub.stubs(:actions_enabled?).returns(true)

      actions_check_run = create :check_run_for_actions_app
      expected = "/#{actions_check_run.repository.nwo}/actions/runs/#{actions_check_run.check_suite.workflow_run.id}/job/#{actions_check_run.id}?pr=1"
      assert_equal expected, actions_check_run.permalink(pull: @pull)
    end
  end

  context "#rerequest" do
    test "triggers check_run.rerequest hook event method" do
      check_run = create :check_run
      events = subscribe "check_run.rerequest"
      check_run.rerequest(actor: @user)

      expected_payload = {
        check_run_id: check_run.id,
        repository_id: check_run.repository_id,
        organization_id: check_run.check_suite.repository.owner.organization? ? check_run.check_suite.repository.owner_id : nil,
        actor_id: @user.id,
        business_id: check_run.check_suite.repository.organization&.business&.id
      }
      instrumentation_event = events.pop

      assert_equal "check_run.rerequest", instrumentation_event.name
      assert expected_payload <= instrumentation_event.payload
    end

    test "resets the status and conclusion of the check suite, and does not update the check run itself" do
      check_run = create(:check_run, status: "completed", conclusion: "success", completed_at: Time.now.utc)
      check_suite = check_run.check_suite

      original_check_run_status       = check_run.status
      original_check_run_conclusion   = check_run.conclusion
      original_check_suite_status     = check_suite.status
      original_check_suite_conclusion = check_suite.conclusion
      refute_nil original_check_suite_status, "Expected a rollup status to be set for the check suite"
      refute_nil original_check_suite_conclusion, "Expected a rollup conclusion to be set for the check suite"

      check_run.rerequest(actor: @user)

      check_run.reload
      check_suite.reload

      assert_equal original_check_run_status, check_run.status
      assert_equal original_check_run_conclusion, check_run.conclusion

      new_check_suite_status = check_suite.status
      new_check_suite_conclusion = check_suite.conclusion
      refute_equal original_check_suite_status, new_check_suite_status
      refute_equal original_check_suite_conclusion, new_check_suite_conclusion
    end
  end

  context "#concluded?" do
    test "returns true if the CheckRun has a conclusion" do
      check_run = CheckRun.new(conclusion: :success, repository: @repo)
      assert check_run.concluded?
    end

    test "returns false if the CheckRun does not have a conclusion" do
      check_run = CheckRun.new(conclusion: nil, repository: @repo)
      refute check_run.concluded?
    end
  end

  context ".recent_check_names_and_integrations" do
    test "returns a hash of unique check names and their associated integrations with runs within cutoff date" do
      Timecop.freeze(Time.now) do
        create :check_run, check_suite: @check_suite, name: "just-now", status: :completed, conclusion: :success, completed_at: 1.second.ago
        create :check_run, check_suite: @check_suite, name: "yesterday", status: :completed, conclusion: :success, completed_at: 1.day.ago + 1.second
        create :check_run, check_suite: @check_suite, name: "yesterday", status: :completed, conclusion: :success, completed_at: 1.day.ago + 1.minute # duplicate is removed

        create :check_run, check_suite: @check_suite, name: "too-long-ago", status: :completed, conclusion: :success, completed_at: 2.days.ago # missed cutoff

        result = CheckRun.recent_check_names_and_integrations(repo: @repo, start: 1.day.ago, limit: 100)
        assert_equal({ "just-now" => Set[@check_suite.github_app], "yesterday" => Set[@check_suite.github_app] }, result)
      end
    end


    test "returns names in utf8" do
      name = "UTF8 \xE2\x80\x94 the test"
      create :check_run, check_suite: @check_suite, name: name.dup.b, status: :completed, conclusion: :success, completed_at: 1.minute.ago
      result = CheckRun.recent_check_names_and_integrations(repo: @repo, start: 1.day.ago, limit: 3)
      assert result.keys.all? { |name| name.encoding == Encoding::UTF_8 }
    end

    test "ignores integrations deleted after the check runs" do
      run = create :check_run, check_suite: @check_suite, name: "a", status: :completed, conclusion: :success, completed_at: 4.minutes.ago
      second_run = create :check_run, check_suite: @check_suite, name: "b", status: :completed, conclusion: :success, completed_at: 1.minute.ago

      second_run.github_app.destroy

      result = CheckRun.recent_check_names_and_integrations(repo: @repo, start: 1.day.ago, limit: 3)

      assert_equal 2, result.size
      assert_equal 0, T.must(result["a"]).size
    end

    if !GitHub.enterprise?
      test "does not return required-workflow checks even if within cut-off" do
        org = @user
        source_repo = create(:repository, owner: org)

        target_repo = create(:repository, owner: org, from_example: :rebase_pull_request)

        # Create a PR between master and [existing] contrib branches on that repo.
        issue = create(:issue, user: @user, repository: target_repo)
        # Make a new commit on contrib branch,
        # so that there is a diff to compare after a Push of that commit
        before = target_repo.heads.find("contrib").target_oid
        metadata = { message: "blah", committer: @user }
        commit = target_repo.heads.find("contrib").append_commit(metadata, @user) do |files|
          files.add("foo", "dsfdsfsdfsd")
        end
        head_sha = commit.oid

        pull = create(:pull_request,
          repository: target_repo,
          base_repository: target_repo,
          base_user: target_repo.owner,
          base_ref: "master",
          head_repository: target_repo,
          head_user: target_repo.owner,
          head_ref: "contrib",
          issue: issue,
          user: issue.user,
        )

        # Create a Push for the fresh commit(s) on the feature branch.
        perform_enqueued_jobs(only: [CreateCheckSuitesJob]) do
          trigger_push_event(
            target_repo.shard_path,
            @user.login,
            [["refs/heads/feature-branch", before, head_sha]],
            Time.now,
            perform_hydro_push_jobs: [HydroRepositoriesOnPushJob]
          )
        end

        GitHub.stubs(:actions_enabled?).returns(true)
        make_trusted_oauth_apps_owner
        launch_app = create(:launch_integration)
        GitHub.stubs(:launch_github_app).returns(launch_app)

        req_workflow_path = "required/#{source_repo.id}/.github/required-workflows/required.yml"
        Actions::Workflow.create_or_update_workflow(req_workflow_path, "req-workflow-name", target_repo, nil, imposer_repository_id: source_repo.id)
        target_repo_workflow = Actions::Workflow.where(repository_id: target_repo.id, path: req_workflow_path, imposer_repository_id: source_repo.id).first
        check_suite = CheckSuite.create(repository: target_repo, head_sha: pull.head_sha, github_app_id: launch_app.id, workflow_file_path: req_workflow_path)

        Timecop.freeze(Time.now) do
          create :check_run_for_actions_app, check_suite: check_suite, name: "req-workflow-context", status: :completed, conclusion: :success, completed_at: 1.second.ago
          create :check_run, check_suite: @check_suite, name: "just-now", status: :completed, conclusion: :success, completed_at: 1.second.ago
          create :check_run, check_suite: @check_suite, name: "yesterday", status: :completed, conclusion: :success, completed_at: 1.day.ago + 1.second
          create :check_run, check_suite: @check_suite, name: "yesterday", status: :completed, conclusion: :success, completed_at: 1.day.ago + 1.minute # duplicate is removed

          create :check_run, check_suite: @check_suite, name: "too-long-ago", status: :completed, conclusion: :success, completed_at: 2.days.ago # missed cutoff

          result = CheckRun.recent_check_names_and_integrations(repo: @repo, start: 1.day.ago, limit: 100)
          assert_equal({ "just-now" => Set[@check_suite.github_app], "yesterday" => Set[@check_suite.github_app] }, result)
        end
      end
    end
  end

  context "required_for_pull_request?" do
    test "false if protected branches are not enabled" do
      refute @run.required_for_pull_request?(@pull)
    end

    test "false name doesn't match required context on protected branch" do
      branch_attributes = {
        name: @pull.base_ref,
        creator: @user,
        required_status_checks_enforcement_level: :everyone,
      }
      protected_branch = @repo.protected_branches.create(branch_attributes)
      protected_branch.replace_status_contexts("not-" + @run.name)

      refute @run.required_for_pull_request?(@pull)
    end

    test "true when name matches required context on protected branch" do
      branch_attributes = {
        name: @pull.base_ref,
        creator: @user,
        required_status_checks_enforcement_level: :everyone,
      }
      protected_branch = @repo.protected_branches.create(branch_attributes)
      protected_branch.replace_status_contexts(@run.name)

      assert @run.required_for_pull_request?(@pull)
    end

    test "true for context with emoji" do
      @run.update(name: "🚀 Ship it!")

      branch_attributes = {
        name: @pull.base_ref,
        creator: @user,
        required_status_checks_enforcement_level: :everyone,
      }
      protected_branch = @repo.protected_branches.create(branch_attributes)
      protected_branch.replace_status_contexts(@run.name)

      assert @run.required_for_pull_request?(@pull)
    end
  end

  context "analytics" do
    test "publishes hydro event when the status and the conclusion are modified" do
      check_suite = create :check_suite

      GitHub.stubs(:hydro_enabled?).returns(true)

      check_run = create(:check_run, check_suite: check_suite, status: :in_progress)
      check_run.status = :completed
      check_run.conclusion = :success
      check_run.completed_at = Time.now
      check_run.save

      assert_hydro_messages(count: 1, schema: "github.v1.CheckRunStatusChange")
      assert_hydro_published({
        check_run_id: check_run.id,
        previous_status: :IN_PROGRESS,
        current_status: :COMPLETED,
        previous_conclusion: :UNKNOWN_CONCLUSION,
        current_conclusion: :SUCCESS,
      }, schema: "github.v1.CheckRunStatusChange")
    end

    test "publishes hydro event when only the status is modified" do
      check_suite = create :check_suite

      GitHub.stubs(:hydro_enabled?).returns(true)

      check_run = create(:check_run, check_suite: check_suite, status: :queued)
      check_run.status = :in_progress
      check_run.save

      assert_hydro_messages(count: 1, schema: "github.v1.CheckRunStatusChange")
      assert_hydro_published({
        check_run_id: check_run.id,
        previous_status: :QUEUED,
        current_status: :IN_PROGRESS,
        previous_conclusion: :UNKNOWN_CONCLUSION,
        current_conclusion: :UNKNOWN_CONCLUSION,
      }, schema: "github.v1.CheckRunStatusChange")
    end

    test "publishes hydro event when only conclusion is modified" do
      check_suite = create :check_suite

      GitHub.stubs(:hydro_enabled?).returns(true)

      check_run = create(:completed_check_run, check_suite: check_suite)
      check_run.conclusion = :stale
      check_run.save

      assert_hydro_messages(count: 1, schema: "github.v1.CheckRunStatusChange")
      assert_hydro_published({
        check_run_id: check_run.id,
        previous_status: :COMPLETED,
        current_status: :COMPLETED,
        previous_conclusion: :SUCCESS,
        current_conclusion: :STALE,
      }, schema: "github.v1.CheckRunStatusChange")
    end

    test "does not publish hydro event when status remains the same" do
      check_suite = create :check_suite

      GitHub.stubs(:hydro_enabled?).returns(true)

      check_run = create(:check_run, check_suite: check_suite, status: :in_progress)
      check_run.status = :in_progress
      check_run.save

      assert_hydro_messages(count: 0, schema: "github.v1.CheckRunStatusChange")
    end
  end

  context "#details_url" do
    test "returns the run specific URL provided" do
      check_suite = create(:check_suite, repository: @repo, github_app: @github_app)
      check_run = CheckRun.new(check_suite: check_suite, details_url: "http://super-duper.com/run/123", repository: @repo)
      details_url = assert_query_count(0, ignore_feature_flags: true) do
        check_run.details_url
      end
      assert_equal "http://super-duper.com/run/123", details_url
    end

    test "returns the GitHub App's URL if no run specific URL provided" do
      check_suite = create(:check_suite, repository: @repo, github_app: @github_app)
      check_run = CheckRun.new(check_suite: check_suite, repository: @repo)
      details_url = assert_query_count(0, ignore_feature_flags: true) do
        check_run.details_url
      end
      assert_equal "http://super-duper.com", details_url
    end

    test "returns the permalink URL for Actions" do
      GitHub.stubs(:launch_github_app).returns(@check_suite.github_app)
      check_run = create(:check_run, check_suite: @check_suite)
      assert_predicate check_run.check_suite, :actions_app?

      details_url = assert_query_count(0, ignore_feature_flags: true) do
        check_run.details_url
      end
      assert_equal check_run.permalink(include_host: true), details_url
    end

    test "returns the permalink URL for Code Scanning" do
      check_suite = create(:check_suite, repository: @repo, github_app: @code_scanning_app)
      check_run = create(:check_run, check_suite: check_suite)
      assert_predicate check_suite, :code_scanning_app?

      details_url = assert_query_count(0, ignore_feature_flags: true) do
        check_run.details_url
      end
      assert_equal check_run.permalink(include_host: true), details_url
    end
  end

  context ".latest_for_sha_and_repository" do
    test "returns the latest check run per name, for all check suites with the given sha and repo" do
      app_a = create(:integration, default_permissions: { "checks" => :write })
      app_b = create(:integration, default_permissions: { "checks" => :write })
      repo = create :repository, owner: @user, from_example: :simple
      make_integration_installation(integration: app_a, repository: repo)
      make_integration_installation(integration: app_b, repository: repo)

      perform_enqueued_jobs(only: [CreateCheckSuitesJob]) do
        @push = push_changes(repository: repo, branch_name: "master", create_via_hydro_job: true)
        @sha  = @push.after
        assert_equal 2, CheckSuite.where(push_id: @push.id).count
      end

      check_suite_a = CheckSuite.where(push_id: @push.id).where(github_app_id: app_a.id).first
      check_suite_b = CheckSuite.where(push_id: @push.id).where(github_app_id: app_b.id).first

      check_run_a_1   = create(:check_run, check_suite: check_suite_a, name: "a_1")
      check_run_a_1_1 = create(:check_run, check_suite: check_suite_a, name: "a_1")
      check_run_a_2   = create(:check_run, check_suite: check_suite_a, name: "a_2")
      check_run_a_3   = create(:check_run, check_suite: check_suite_a, name: "a_3")

      check_run_b_1   = create(:check_run, check_suite: check_suite_b, name: "b_1")
      check_run_b_2   = create(:check_run, check_suite: check_suite_b, name: "b_2")
      check_run_b_2_1 = create(:check_run, check_suite: check_suite_b, name: "b_2")

      expected_runs = [
        check_run_a_1_1,
        check_run_a_2,
        check_run_a_3,
        check_run_b_1,
        check_run_b_2_1]
      returned_runs = CheckRun.latest_for_sha_and_repository(@sha, repo)

      assert_same_elements expected_runs.collect(&:name), returned_runs.collect(&:name)
    end

    test "returns the latest check for the latest re-run run per name, for Actions check suites with the given sha and repo" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      repo = create :repository, owner: @user, from_example: :simple

      app = create(:integration, default_permissions: { "checks" => :write })
      make_integration_installation(integration: app, repository: repo)

      Timecop.freeze do
        push_1 = push_changes(repository: repo, branch_name: "master",
          changes: { path: "README.md", content: "push 1" })

        check_suite = CheckSuite.create!(repository_id: repo.id, head_sha: push_1.after, github_app_id: app.id)
        check_suite_actions = create(:check_suite_for_actions_app, repository: repo, head_sha: push_1.after)

        check_run_b_1   = create(:check_run, check_suite: check_suite, name: "b_1")
        check_run_b_1_2 = create(:check_run, check_suite: check_suite, name: "b_1")

        # Check runs for Actions check suite, one created before a re-run, one created after
        check_run_actions_1   = create(:check_run, check_suite: check_suite_actions, name: "a_1", status: "completed", conclusion: "failure")

        Timecop.travel(10.minutes.from_now)
        check_suite_actions.rerequest(actor: @user)

        check_run_actions_2   = create(:check_run, check_suite: check_suite_actions, name: "a_2")

        expected_runs = [
          check_run_b_1_2,
          check_run_actions_2
        ]
        returned_runs = CheckRun.latest_for_sha_and_repository([push_1.after], repo)

        assert_same_elements expected_runs.collect(&:name), returned_runs.collect(&:name)
      end
    end

    test "returns the latest check run per name, for all check suites with the multiple given sha and repo" do
      app_a = create(:integration, default_permissions: { "checks" => :write })
      app_b = create(:integration, default_permissions: { "checks" => :write })
      repo = create :repository, owner: @user, from_example: :simple
      make_integration_installation(integration: app_a, repository: repo)
      make_integration_installation(integration: app_b, repository: repo)

      push_1 = push_changes(repository: repo, branch_name: "master",
        changes: { path: "README.md", content: "push 1" })

      check_suite_a_1 = CheckSuite.create!(repository_id: repo.id, head_sha: push_1.after, github_app_id: app_a.id)
      check_suite_b_1 = CheckSuite.create!(repository_id: repo.id, head_sha: push_1.after, github_app_id: app_b.id)

      # check runs for check_suites on @sha_1
      check_run_a_1_1   = create(:check_run, check_suite: check_suite_a_1, name: "a_1")
      check_run_a_1_1_1 = create(:check_run, check_suite: check_suite_a_1, name: "a_1") # latest
      check_run_b_1_1   = create(:check_run, check_suite: check_suite_b_1, name: "b_1") # different name

      push_2 = push_changes(repository: repo, branch_name: "master",
        changes: { path: "README.md", content: "push 2" })

      check_suite_a_2 = CheckSuite.create!(repository_id: repo.id, head_sha: push_2.after, github_app_id: app_a.id)
      check_suite_b_2 = CheckSuite.create!(repository_id: repo.id, head_sha: push_2.after, github_app_id: app_b.id)

      # check runs for check_suites on @sha_2
      # Using same names as check runs on other check_suite's check runs.
      check_run_a_2_1   = create(:check_run, check_suite: check_suite_a_2, name: "a_1")
      check_run_a_2_1_1 = create(:check_run, check_suite: check_suite_a_2, name: "a_1") # latest
      check_run_b_2_1   = create(:check_run, check_suite: check_suite_b_2, name: "b_1") # different name

      expected_runs = [
        check_run_a_1_1_1,
        check_run_a_2_1_1,
        check_run_b_1_1,
        check_run_b_2_1,
      ]
      returned_runs = CheckRun.latest_for_sha_and_repository([push_1.after, push_2.after], repo)

      assert_same_elements expected_runs.collect(&:name), returned_runs.collect(&:name)
    end
  end

  context ".latest_for_sha_and_event_in_repository" do
    test "returns the same amount of check runs as mapping over the shas" do
      app_a = create(:integration, default_permissions: { "checks" => :write })
      app_b = create(:integration, default_permissions: { "checks" => :write })
      repo = create :repository, owner: @user, from_example: :simple
      make_integration_installation(integration: app_a, repository: repo)
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)

      push_1 = push_changes(repository: repo, branch_name: "master",
        changes: { path: "README.md", content: "push 1" })

      check_suite_a_1 = CheckSuite.create!(repository_id: repo.id, head_sha: push_1.after, github_app_id: app_a.id)
      check_suite_b_1_1 = CheckSuite.create!(repository_id: repo.id, head_sha: push_1.after, github_app_id: launch_app.id, workflow_file_path: ".github/workflows/test1.yaml", event: "push")
      check_suite_b_1_2 = CheckSuite.create!(repository_id: repo.id, head_sha: push_1.after, github_app_id: launch_app.id, workflow_file_path: ".github/workflows/test2.yaml", event: "push")

      # check runs for check_suites on @sha_1
      check_run_a_1_1_1 = create(:check_run, check_suite: check_suite_a_1, name: "a_1") # latest
      check_run_b_1_1   = create(:check_run_for_actions_app, check_suite: check_suite_b_1_1, name: "b_1_1")
      check_run_b_1_2   = create(:check_run_for_actions_app, check_suite: check_suite_b_1_2, name: "b_1_2")

      push_2 = push_changes(repository: repo, branch_name: "master",
        changes: { path: "README.md", content: "push 2" })

      check_suite_a_2 = CheckSuite.create!(repository_id: repo.id, head_sha: push_2.after, github_app_id: app_a.id)
      check_suite_b_2_1 = CheckSuite.create!(repository_id: repo.id, head_sha: push_2.after, github_app_id: launch_app.id, workflow_file_path: ".github/workflows/test1.yaml", event: "push")
      check_suite_b_2_2 = CheckSuite.create!(repository_id: repo.id, head_sha: push_2.after, github_app_id: launch_app.id, workflow_file_path: ".github/workflows/test2.yaml", event: "push")

      # check runs for check_suites on @sha_2
      # Using same names as check runs on other check_suite's check runs.
      check_run_a_2_1_1 = create(:check_run, check_suite: check_suite_a_2, name: "a_1") # latest
      check_run_b_2_1   = create(:check_run_for_actions_app, check_suite: check_suite_b_2_1, name: "b_1_1")
      check_run_b_2_2   = create(:check_run_for_actions_app, check_suite: check_suite_b_2_2, name: "b_1_2")

      shas = [push_1.after, push_2.after]
      returned_bulk_runs = CheckRun.latest_for_sha_and_event_in_repository([push_1.after, push_2.after], repo).to_a
      returned_looped_runs = shas.flat_map { CheckRun.latest_for_sha_and_repository(_1, repo).to_a }

      assert_equal returned_bulk_runs.count, returned_looped_runs.count
    end
  end

  [:name, :title, :display_name].each do |field|
    test "supports emoji for #{field}" do
      check_run = create(:check_run, field => "we ❤️ emojis")

      assert_multibyte_tracked_changes(check_run, field)
    end
  end

  context "it clears the check run" do
    test "after check_suite destruction" do
      assert_difference('CheckRun.annotate("cross-shard-query-exempted").count', -1) do
        perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
          @check_suite.destroy
        end
      end
    end

    test "after repo soft-delete" do
      repo = @check_suite.repository

      assert_difference('CheckRun.annotate("cross-shard-query-exempted").count', -1) do
        perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
          repo.remove(repo.owner, synchronous: true)
        end
      end
    end
  end

  context "#request_action" do
    test "triggers check_run.request_action hook event method" do
      check_run = create :check_run
      events = subscribe "check_run.request_action"
      check_run.request_action(actor: @user, requested_action: { identifier: "fix_me" })

      expected_payload = {
        check_run_id: check_run.id,
        actor_id: @user.id,
        requested_action: {
          identifier: "fix_me",
        },
      }
      instrumentation_event = events.pop

      assert_equal "check_run.request_action", instrumentation_event.name
      assert expected_payload <= instrumentation_event.payload
    end
  end

  context "before_save" do
    test "sets completed_at to be now if the provided completed_at is in the future" do
      Timecop.freeze do
        run = create(:completed_check_run, completed_at: Time.now.utc + 2.years)

        assert_equal Time.now.utc.iso8601, run.completed_at.utc.iso8601
      end
    end

    test "sets completed_at, if conclusion is set" do
      run = create(:completed_check_run, completed_at: nil, conclusion: "failure")
      assert run.completed_at.present?
    end

    test "sets status to completed, if conclusion is set" do
      run = create(:completed_check_run, status: "in_progress", conclusion: "failure")
      assert_equal "completed", run.status
    end

    test "sets started_at, if none is provided" do
      Timecop.freeze do
        run = create(:completed_check_run, started_at: nil, conclusion: "failure")

        assert_equal Time.now.utc.iso8601, run.started_at.utc.iso8601
      end
    end
  end

  context "#seconds_to_completion" do
    test "returns seconds difference between completed_at and started_at" do
      start_time = Time.parse("2019-05-15T16:00:00Z")
      completion_time = start_time + 1.minute + 10.seconds
      check_run = build(:check_run, started_at: start_time, completed_at: completion_time)

      assert_equal 70, check_run.seconds_to_completion
    end

    test "returns 0 when completed_at and started_at are the same" do
      start_time = Time.parse("2019-05-15T16:00:00Z")
      completion_time = start_time
      check_run = build(:check_run, started_at: start_time, completed_at: completion_time)

      assert_equal 0, check_run.seconds_to_completion
    end

    test "returns nil when completed_at is earlier than started_at" do
      start_time = Time.parse("2019-05-15T16:00:00Z")
      completion_time = start_time - 1.second
      check_run = build(:check_run, started_at: start_time, completed_at: completion_time)

      assert_nil check_run.seconds_to_completion
    end

    test "returns nil when completed_at is nil" do
      start_time = Time.parse("2019-05-15T16:00:00Z")
      completion_time = nil
      check_run = build(:check_run, started_at: start_time, completed_at: completion_time)

      assert_nil check_run.seconds_to_completion
    end

    test "returns nil when started_at is nil" do
      start_time = nil
      completion_time = Time.parse("2019-05-15T16:00:00Z")
      check_run = build(:check_run, started_at: start_time, completed_at: completion_time)

      assert_nil check_run.seconds_to_completion
    end
  end

  context "#notify_socket_subscribers" do
    test "sends the has_steps attribute correctly when there are steps" do
      check_run = create(:check_run)
      GitHub::WebSocket.expects(:notify_repository_channel).with do |_repository, channel_id, data|
        if /check_run/ =~ channel_id && /updated/ =~ data[:reason]
          assert_equal data[:has_steps], true
        end
        true
      end.times(3) # twice from check_run, once from check_suite
      check_run.steps.build(name: "Step1", number: 0)
      check_run.save!
    end

    test "sends the has_steps attribute correctly when there are no steps" do
      check_run = create(:check_run)
      GitHub::WebSocket.expects(:notify_repository_channel).with do |_repository, channel_id, data|
        if /check_run/ =~ channel_id && /updated/ =~ data[:reason]
          assert_equal data[:has_steps], false
        end
        true
      end.times(3) # twice from check_run, once from check_suite
      check_run.update(status: :in_progress)
    end

    test "sends the conclusion, duration, and id attributes correctly" do
      check_run = create(:check_run, :failure)
      GitHub::WebSocket.expects(:notify_repository_channel).with do |_repository, channel_id, data|
        if /check_run/ =~ channel_id && /updated/ =~ data[:reason]
          assert_equal data[:id], check_run.global_relay_id
          assert_equal data[:conclusion], check_run.conclusion
          assert_equal data[:duration], check_run.duration
        end
        true
      end.times(3) # twice from check_run, once from check_suite
      check_run.save!
    end

    test "publishes to correct socket channels" do
      normal_actions_run = create(:check_run_for_actions_app, status: :in_progress)

      hidden_actions_suite = create(:check_suite_for_actions_app, event: "schedule")
      hidden_actions_run = create(:check_run_for_actions_app, status: :in_progress, check_suite: hidden_actions_suite)

      non_actions_run = create(:check_run, status: :in_progress)

      [
        normal_actions_run,
        hidden_actions_run,
        non_actions_run,
      ].each do |check_run|
        # always expect the check run channel
        GitHub::WebSocket.expects(:notify_repository_channel).with(check_run.repository, check_run.channel, anything).once
        # always expect the check suite channel (from a callback)
        GitHub::WebSocket.expects(:notify_repository_channel).with(check_run.repository, check_run.check_suite.channel, anything).at_least_once

        # only expect the workflow_job_run channel if it's an actions run
        if check_run.workflow_job_run
          GitHub::WebSocket.expects(:notify_repository_channel).with(check_run.repository, check_run.workflow_job_run.channel, anything).once
        end

        # we only expect the commit channel if it's a non-actions suite OR if it's a visible event (not hidden)
        is_hidden_actions_suite = check_run.check_suite.hidden && check_run.check_suite.workflow_file_path.present?
        expectation = is_hidden_actions_suite ? :never : :once

        GitHub::WebSocket.expects(:notify_repository_channel).with(check_run.repository, check_run.commit_channel, anything).send(expectation)

        check_run.update(status: :completed, conclusion: :success)
      end
    end
  end

  context ".latest_version_of" do
    test "returns latest version based on check suite and name" do
      check_run1 = create(:check_run, name: "foo", check_suite: @check_suite)
      check_run2 = create(:check_run, name: "foo", check_suite: @check_suite)
      assert_equal check_run2, CheckRun.latest_version_of(check_run1, @repo.id)
    end

    test "creates valid queries" do
      assert_no_query_warnings do
        check_run = create(:check_run, name: GRIN_EMOJI, check_suite: @check_suite)
        assert_equal check_run, CheckRun.latest_version_of(check_run, @repo.id)
      end
    end
  end

  context ".visible_name" do
    test "returns the name if the display_name is not defined" do
      check_run = create(:check_run, name: "foo", check_suite: @check_suite)
      assert_equal "foo", check_run.visible_name
    end

    test "returns the display_name if it's defined" do
      check_run = create(:check_run, name: "foo", display_name: "Foo bar", check_suite: @check_suite)
      assert_equal "Foo bar", check_run.visible_name
    end
  end

  context "expired_logs?" do
    test "return false if the completed_log_url is nil" do
      check_suite_actions = create(:check_suite_for_actions_app, :success_after_create, repository: @repo)
      check_run = create(:check_run, check_suite: check_suite_actions)

      refute check_run.expired_logs?
    end

    test "return false if the check_suite is not complete" do
      check_suite = create(:check_suite_for_actions_app, :pending, repository: @repo, head_sha: @head_sha, head_branch: nil)
      check_run = check_suite.check_runs.first
      check_run.completed_log_url = "https://logs.github.com/some-unique-slug-step1?retention=400"
      check_run.save!

      refute check_run.expired_logs?
    end

    test "No retention set on log url fallback to 400 days check" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      check_suite_actions = create(:check_suite_for_actions_app, repository: @repo)
      check_run_expired = create(:check_run, completed_log_url: "https://logs.github.com/something", created_at: 401.days.ago, check_suite: check_suite_actions)
      check_run_expired.check_suite.completed_at = 400.days.ago
      assert check_run_expired.expired_logs?

      check_run_valid = create(:check_run, completed_log_url: "https://logs.github.com/something", created_at: 399.days.ago, check_suite: check_suite_actions)
      refute check_run_valid.expired_logs?
    end

    test "honor retention set on log url for completed check_suites" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      check_suite_actions = create(:check_suite_for_actions_app, repository: @repo)

      check_run_expired = create(:check_run, completed_log_url: "https://logs.github.com/something?retention=10", check_suite: check_suite_actions)
      check_run_expired.check_suite.completed_at = 11.days.ago
      assert check_run_expired.expired_logs?

      check_run_valid = create(:check_run, completed_log_url: "https://logs.github.com/something?retention=12", check_suite: check_suite_actions)
      refute check_run_valid.expired_logs?
    end
  end

  context "create_for_code_scanning_analysis" do
    test "associates the suite with the code scanning app" do
      check_run = CheckRun.create_for_code_scanning_analysis(
        repository: @repo,
        annotated_commit_oid: @pull.head_sha,
        analyzed_commit_oid: @pull.head_sha,
        ref: "refs/heads/#{@pull.head_ref}",
        base_ref: "refs/heads/#{@pull.base_ref}",
        base_sha: @pull.base_sha,
      ).first

      assert_equal @code_scanning_app, check_run.github_app
      assert_equal @repo, check_run.repository
      assert_equal "Results", check_run.name
      assert_nil check_run.code_scanning_tool_name
      assert_equal "Code scanning results", check_run.check_suite.name
    end

    test "returns an existing suite if one already exists" do
      check_run1 = CheckRun.create_for_code_scanning_analysis(
        repository: @repo,
        annotated_commit_oid: @pull.head_sha,
        analyzed_commit_oid: @pull.head_sha,
        ref: "refs/heads/#{@pull.head_ref}",
        base_ref: "refs/heads/#{@pull.base_ref}",
        base_sha: @pull.base_sha,
      ).first

      refute_nil check_run1

      check_run2 = assert_no_difference(["CheckSuite.where(repository_id: #{@repo.id}).count", 'CheckRun.annotate("cross-shard-query-exempted").count']) do
        CheckRun.create_for_code_scanning_analysis(
          repository: @repo,
          annotated_commit_oid: @pull.head_sha,
          analyzed_commit_oid: @pull.head_sha,
          ref: "refs/heads/#{@pull.head_ref}",
          base_ref: "refs/heads/#{@pull.base_ref}",
          base_sha: @pull.base_sha,
        ).first
      end

      assert_equal check_run1, check_run2
    end

    test "creates a non-rerunnable suite" do
      check_run = CheckRun.create_for_code_scanning_analysis(
        repository: @repo,
        annotated_commit_oid: @pull.head_sha,
        analyzed_commit_oid: @pull.head_sha,
        ref: "refs/heads/#{@pull.head_ref}",
        base_ref: "refs/heads/#{@pull.base_ref}",
        base_sha: @pull.base_sha,
      ).first
      check_run.update!(conclusion: "failure")

      refute_predicate check_run.check_suite, :check_runs_rerunnable?
      refute_predicate check_run.check_suite, :rerequestable?
      refute_predicate check_run.check_suite, :rerunnable?
    end

    test "creates one check run per tool name" do
      check_runs = CheckRun.create_for_code_scanning_analysis(
        repository: @repo,
        annotated_commit_oid: @pull.head_sha,
        analyzed_commit_oid: @pull.head_sha,
        tool_names: ["CodeQL command-line toolchain", "Golang security checks by gosec"],
        ref: "refs/heads/#{@pull.head_ref}",
        base_ref: "refs/heads/#{@pull.base_ref}",
        base_sha: @pull.base_sha,
      )

      assert_equal 2, check_runs.size
      assert_equal "CodeQL", check_runs.first.name
      assert_equal "CodeQL", check_runs.first.code_scanning_tool_name
      assert_equal "gosec", check_runs.second.name
      assert_equal "gosec", check_runs.second.code_scanning_tool_name
    end

    test "ignores duplicate tool names" do
      check_runs = CheckRun.create_for_code_scanning_analysis(
        repository: @repo,
        annotated_commit_oid: @pull.head_sha,
        analyzed_commit_oid: @pull.head_sha,
        tool_names: %w[foo foo],
        ref: "refs/heads/#{@pull.head_ref}",
        base_ref: "refs/heads/#{@pull.base_ref}",
        base_sha: @pull.base_sha,
      )

      assert_equal 1, check_runs.size
      assert_equal "foo", check_runs.first.name
    end

    test "annotates the annotated commit and stores the analyzed commit" do
      merge_commit_sha = @pull.create_merge_commit

      check_runs = CheckRun.create_for_code_scanning_analysis(
        repository: @repo,
        ref: @pull.merge_ref,
        annotated_commit_oid: @pull.head_sha,
        analyzed_commit_oid: merge_commit_sha,
        tool_names: ["CodeQL"],
        base_ref: "refs/heads/#{@pull.base_ref}",
        base_sha: @pull.base_sha,
      )

      assert_equal 1, check_runs.size
      assert_equal "CodeQL", check_runs.first.name
      assert_equal @pull.merge_ref, CodeScanningCheckSuite.for_check_run(check_runs.first).pull_request_ref
      assert_equal merge_commit_sha, CodeScanningCheckSuite.for_check_run(check_runs.first).pull_request_sha
    end
  end

  context "align_checkruns_with_tools" do

    test "deletes checkruns without corresponding tool_name" do

      args = {
        repository: @repo,
        annotated_commit_oid: @pull.head_sha,
        analyzed_commit_oid: @pull.head_sha,
        ref: "refs/heads/#{@pull.head_ref}",
      }
      check_runs = CheckRun.create_for_code_scanning_analysis(
        tool_names: %w[Foo bar],
        base_ref: "refs/heads/#{@pull.base_ref}",
        base_sha: @pull.base_sha,
        **args,
      )
      check_run_foo = check_runs.find { |c| c.code_scanning_tool_name == "Foo" }
      check_run_bar = check_runs.find { |c| c.code_scanning_tool_name == "bar" }

      aligned_checkruns = CheckRun.align_checkruns_with_tools(
          check_run_ids: check_runs.map(&:id),
          tools: [{ name: "foo" }],
          **args
      )

      assert_equal [check_run_foo], aligned_checkruns
    end

    test "creates new checkrun when one is missing" do
      args = {
        repository: @repo,
        annotated_commit_oid: @pull.head_sha,
        analyzed_commit_oid: @pull.head_sha,
        ref: "refs/heads/#{@pull.head_ref}",
      }
      check_run_foo = CheckRun.create_for_code_scanning_analysis(
        tool_names: ["foo"],
        base_ref: "refs/heads/#{@pull.base_ref}",
        base_sha: @pull.base_sha,
        **args,
      ).first

      check_runs = CheckRun.align_checkruns_with_tools(
        check_run_ids: [check_run_foo.id],
        tools: [{ name: "foo" }, { name: "bar" }],
        **args
      )
      assert_equal 2, check_runs.size
      assert_includes check_runs, check_run_foo

      new_check_run = ActiveRecord::Base.connected_to(role: :reading) do
        CheckRun.where(id: check_runs.map(&:id) - [check_run_foo.id]).load
      end.first
      assert_equal new_check_run.code_scanning_tool_name, "bar"
    end

    test "throws error if non-code-scanning checkrun is passed" do

      @integration = create(:integration)

      Apps::Privileged::Registry.configure(
        app: @integration,
        app_alias: :some_internal_app,
        id: ->() { @integration.id },
      )

      check_suite = Checks::Service.find_or_create_check_suite(
        head_sha: @pull.head_sha,
        github_app_id: Apps::Privileged.integration_id(:some_internal_app),
        repo: @repo,
      )
      check_run = check_suite.check_runs.create(attrs = {
        name: "Check Run",
        external_id: @pull.head_ref,
        repository: @repo,
      })

      args = {
        repository: @repo,
        annotated_commit_oid: @pull.head_sha,
        analyzed_commit_oid: @pull.head_sha,
        ref: "refs/heads/#{@pull.head_ref}",
      }

      assert_raises CheckRun::CodeScanningDependency::CodeScanningCheckRunError do
        CheckRun.align_checkruns_with_tools(
          check_run_ids: [check_run.id],
          tools: [{ name: "foo" },],
          **args
        )
      end
    end
  end

  context "delete_previous_check_runs" do
    test "deletes old check runs" do
      check_suite = create :check_suite
      name = "coverage"

      old_check_run = create(:check_run, check_suite: check_suite, name: name)
      another_run = create(:check_run, check_suite: check_suite, name: "another name")

      CheckRun.stub_const(:MAX_CHECK_RUNS_PER_NAME, 1) do
        perform_enqueued_jobs only: DeleteOldCheckRuns do
          5.times do
            create(:check_run, check_suite: check_suite, name: name)
          end
        end
      end

      assert_equal 2, check_suite.check_runs.where(repository_id: check_suite.repository.id).size
      assert_nil CheckRun.find_by(id: old_check_run.id)
      assert CheckRun.find_by(id: another_run.id)
    end

    test "does not delete anything if there aren't too many check runs" do
      check_suite = create :check_suite
      name = "coverage"

      old_check_run = create(:check_run, check_suite: check_suite, name: name)
      last_run = CheckRun.stub_const(:MAX_CHECK_RUNS_PER_NAME, 2) do
        perform_enqueued_jobs only: DeleteOldCheckRuns do
          create(:check_run, check_suite: check_suite, name: name)
        end
      end

      assert_equal 2, check_suite.check_runs.where(repository_id: check_suite.repository.id).size
      assert CheckRun.find_by(id: last_run.id)
      assert CheckRun.find_by(id: old_check_run.id)
    end
  end

  context "call auto-merge job enqueuer" do
    test "does nothing if not successful" do
      @run.conclusion = :failure
      @run.status = :completed

      PullRequest.any_instance.expects(:enqueue_auto_merge_job_if_enabled).times(0)

      @run.call_auto_merge_job_enqueuer
    end

    test "calls enqueue_auto_merge_job_if_enabled on each PR related to the checkrun creation" do
      @run.conclusion = :success
      @run.status = :completed

      PullRequest.any_instance.expects(:enqueue_auto_merge_job_if_enabled).once

      @run.call_auto_merge_job_enqueuer
    end

    test "calls enqueue_auto_merge_job_if_enabled on each fork PR if check_suite head sha matches PR head sha" do
      @fork_pull = create(:pull_request,
        repository: @repo,
        base_repository: @repo,
        base_user: @repo.owner,
        base_ref: "master",
        head_repository: @fork,
        head_user: @fork_user,
        head_ref: "contrib",
      )

      @fork_check_suite = create(:check_suite, repository: @repo, head_sha: @fork_pull.head_sha)

      PullRequest.any_instance.expects(:enqueue_auto_merge_job_if_enabled).once

      create(:check_run, check_suite: @fork_check_suite, name: "fork_coverage", conclusion: :success, status: :completed)
    end
  end

  context "#create_workflow_run" do
    test "rollback when a workflow job run creation fails" do
      repository = create :repository
      check_suite = create :check_suite_for_actions_app, repository: repository
      assert_no_difference -> { CheckRun.count } do
        exception = ActiveRecord::StatementInvalid
        CheckRun.any_instance.stubs(:create_workflow_job_run).raises(exception)
        assert_raises(exception) do
          create :check_run, check_suite: check_suite
        end
      end
    end

    test "creates a workflow_job_run with job_key, labels, parent_job_id, and summary_url" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      job_key = "a-job-key"
      parent_job_id = "the-parent-job-id"
      labels = %w[foo bar baz]
      summary_url = "https://summary-test.url"

      repository = create :repository

      check_suite = create :check_suite_for_actions_app, repository: repository
      check_run = create :check_run, check_suite: check_suite, job_key: job_key, parent_job_id: parent_job_id, labels: labels, summary_url: summary_url

      workflow_job_run = check_run.workflow_job_run

      assert workflow_job_run
      assert_equal job_key, workflow_job_run.job_key
      assert_equal parent_job_id, workflow_job_run.parent_job_id
      assert_equal labels, workflow_job_run.label_data
      assert_equal summary_url, workflow_job_run.summary_url
    end

    test "creates a workflow_job_run with an execution and default original execution" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      repository = create :repository

      check_suite = create :check_suite_for_actions_app, repository: repository
      check_run = create :check_run, check_suite: check_suite

      workflow_job_run = check_run.workflow_job_run
      assert workflow_job_run

      execution = workflow_job_run.workflow_run_execution

      assert execution
      assert_equal execution, workflow_job_run.original_workflow_run_execution
    end

    test "creates a workflow_job_run with an execution and original execution of previous workflow" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      job_key = "a-job-key"

      repository = create :repository

      check_suite = create :check_suite_for_actions_app, repository: repository
      check_run = create :check_run, check_suite: check_suite, job_key: job_key
      workflow_run = check_suite.workflow_run
      workflow_run.create_new_workflow_execution(external_id: SimpleUUID::UUID.new.to_guid, attempt: 2)
      check_run_rerun = create :check_run, check_suite: check_suite, job_key: job_key, is_cloned_from_previous_run: true

      workflow_job_run = check_run.workflow_job_run
      workflow_job_run_rerun = check_run_rerun.workflow_job_run
      assert workflow_job_run
      assert workflow_job_run_rerun

      execution = workflow_job_run_rerun.original_workflow_run_execution

      assert execution
      assert_equal execution, workflow_job_run.workflow_run_execution
      refute_equal execution, workflow_job_run_rerun.workflow_run_execution
    end

    test "creates a workflow_job_run with an execution and new original execution for nonexistent previous original execution" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      repository = create :repository

      check_suite = create :check_suite_for_actions_app, repository: repository
      check_run = create :check_run, check_suite: check_suite, is_cloned_from_previous_run: true

      workflow_job_run = check_run.workflow_job_run
      assert workflow_job_run

      execution = workflow_job_run.original_workflow_run_execution

      assert execution
      assert_equal execution, workflow_job_run.workflow_run_execution
    end

    test "does not create workflow_job_run for check runs not created by the Actions app" do
      check_run = create :check_run

      workflow_run = Actions::WorkflowJobRun.find_by(check_run_id: check_run.id, repository_id: check_run.repository_id)
      refute workflow_run
    end
  end

  context "#create_deployment" do
    test "updates to environment_url even if same status exists" do
      check_run = create :check_run, status = "success"
      check_run.create_deployment("staging")
      check_run.create_deployment_status(nil)
      check_run.deployment.reload_latest_status

      check_run.create_deployment_status("https://github.com")
      check_run.deployment.reload_latest_status

      refute_nil check_run.deployment.statuses[0].environment_url
      assert_equal 1, check_run.deployment.statuses.count
    end

    test "queues job to mark previous deployments as inactive when block feature flag is not enabled" do
      check_run = create :check_run
      check_run.create_deployment("staging")

      GitHub.flipper[:actions_environments_block_auto_inactive].disable

      assert_enqueued_with(job: ::CreateAutoInactiveDeploymentStatuses) do
        check_run.create_deployment_status("https://github.com")
      end
    end

    test "does not queue job to mark previous deployments as inactive when block feature flag is enabled" do
      check_run = create :check_run
      check_run.create_deployment("staging")

      GitHub.flipper[:actions_environments_block_auto_inactive].enable

      assert_no_enqueued_jobs(only: ::CreateAutoInactiveDeploymentStatuses) do
        check_run.create_deployment_status("https://github.com")
      end
    end

    test "marks Pages as the performer if the creator is a User and is a dynamic Pages workflow" do
      check_run = create :check_run_for_actions_app
      check_run.check_suite.workflow_run.workflow.update!(path: "dynamic/pages/page-build-deployment")

      deployment = check_run.create_deployment("staging")

      refute_nil check_run.check_suite.creator
      assert check_run.check_suite.creator.user?
      refute check_run.check_suite.creator.bot?
      assert_equal check_run.deployment.creator, check_run.check_suite.creator
      refute_nil check_run.deployment.performed_by_integration_id
      assert_equal check_run.deployment.performed_by_integration_id, GitHub.pages_github_app.id
      refute_equal check_run.deployment.performed_by_integration_id, check_run.check_suite.github_app_id
      refute_equal check_run.deployment.performed_by_integration_id, GitHub.launch_github_app.id
    end

    test "marks Actions as the performer if the creator is a User" do
      check_run = create :check_run_for_actions_app
      deployment = check_run.create_deployment("staging")

      refute_nil check_run.check_suite.creator
      assert check_run.check_suite.creator.user?
      refute check_run.check_suite.creator.bot?
      assert_equal check_run.deployment.creator, check_run.check_suite.creator
      refute_nil check_run.deployment.performed_by_integration_id
      assert_equal check_run.deployment.performed_by_integration_id, check_run.check_suite.github_app_id
      assert_equal check_run.deployment.performed_by_integration_id, GitHub.launch_github_app.id
    end

    test "does not mark Actions as the performer if the creator is a Bot" do
      check_suite = create(:check_suite_for_actions_app, creator: create(:bot))
      check_run = create(:check_run_for_actions_app, check_suite: check_suite)
      deployment = check_run.create_deployment("staging")

      refute_nil check_run.check_suite.creator
      refute check_run.check_suite.creator.user?
      assert check_run.check_suite.creator.bot?
      assert_equal check_run.deployment.creator, check_run.check_suite.creator
      assert_nil check_run.deployment.performed_by_integration_id
    end

    test "does not mark Actions as the performer if App is not Actions" do
      check_run = create :check_run
      deployment = check_run.create_deployment("staging")

      refute_nil check_run.check_suite.creator
      assert check_run.check_suite.creator.user?
      refute check_run.check_suite.creator.bot?
      assert_equal check_run.deployment.creator, check_run.check_suite.creator
      assert_nil check_run.deployment.performed_by_integration_id
    end
  end

  context "#update_status_and_deployment_from_gates" do
    test "creates a deployment status" do
      check_run = create :check_run
      check_run.create_deployment("staging")
      check_run.update_status_and_deployment_from_gates

      assert_equal "queued", check_run.status
      assert check_run.errors[:deployment].blank?
      assert_equal 1, check_run.deployment.statuses.count
    end

    test "updates deployment status only once if there are multiple calls" do
      check_run = create :check_run
      check_run.create_deployment("staging")

      check_run.deployment.reload
      check_run.update_status_and_deployment_from_gates
      assert_equal 1, check_run.deployment.statuses.count

      check_run.deployment.reload
      check_run.update_status_and_deployment_from_gates
      assert_equal 1, check_run.deployment.statuses.count

      assert_equal "queued", check_run.status
      assert_empty check_run.errors[:deployment]
      refute_nil check_run.deployment.statuses[0].log_url, "log_url should also be set"
    end

    test "updates to waiting if there is at least one closed gate" do
      @gate_request.update(state: :closed)

      @gated_check_run.update_status_and_deployment_from_gates

      assert_equal "waiting", @gated_check_run.status
      assert @gated_check_run.errors[:deployment].blank?
    end

    test "updates to queued if all gates are open" do
      @gate_request.update(state: :open)
      @gated_check_run.update_status_and_deployment_from_gates

      assert_equal "queued", @gated_check_run.status
      assert @gated_check_run.errors[:deployment].blank?
    end

    test "updates check run status even if missing deployment" do
      @gate_request.update(state: :closed)
      @gated_deployment.delete

      @gated_check_run.update_status_and_deployment_from_gates

      assert_equal "waiting", @gated_check_run.status
      refute @gated_check_run.errors[:deployment].blank?
    end
  end

  context "#truncate_fields" do
    test "truncates varbinary fields" do
      too_long = "a" * 2000

      check_run = create :check_run, name: too_long, title: too_long, display_name: too_long
      assert_equal CheckRun::MAX_VARBINARY_FIELD_LENGTH, check_run.name.bytesize
      assert_equal CheckRun::MAX_VARBINARY_FIELD_LENGTH, check_run.title.bytesize
      assert_equal CheckRun::MAX_VARBINARY_FIELD_LENGTH, check_run.display_name.bytesize
    end

    test "truncates external id" do
      too_long = "a" * 300

      check_run = create :check_run, external_id: too_long
      assert_equal 255, check_run.external_id.length
    end


    test "reports truncation stats to datadog" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      create :check_run, name: "a" * 2000

      assert_equal 1, GitHub.dogstats.increments("field_truncator", tags: ["class:CheckRun", "field:name"]).length
    end
  end

  context "contextual_name" do
    test "contains check suite name and check run display name if check suite is present without event" do
      check_suite = create :check_suite, name: "check suite name", event: nil
      check_run = create :check_run, name: "check run name", check_suite: check_suite
      assert_equal "#{check_suite.name} / #{check_run.name}", check_run.contextual_name
    end

    test "contains check suite name, check run display name and event if check suite present with event" do
      check_suite = create :check_suite, name: "check suite name", event: "workflow_dispatch"
      check_run = create :check_run, name: "check run name", check_suite: check_suite
      assert_equal "#{check_suite.name} / #{check_run.name} (workflow_dispatch)", check_run.contextual_name
    end

    test "matches check run display name if no check suite exists" do
      check_run = create :check_run, name: "check run name"

      # possible nil check_suite if replication lag is high and check suite is not copied over to replica that has the check run, safe default to check_run name
      CheckRun.any_instance.stubs(:check_suite).returns(nil)
      assert_equal check_run.name, check_run.contextual_name
    end
  end

  context "#get_completed_log_url_from_actions_service" do
    test "successfully returns a signed completed job URL when a results URL is present" do
      check_run = create(:check_run_for_actions_app, :results_completed_log_url)

      ActionsResults::Twirp::LogClient
      .any_instance
      .expects(:get_completed_job_log_url)
      .with(equals({
        workflow_run_backend_id: check_run.check_suite.external_id,
        workflow_job_run_backend_id: check_run.external_id,
      }))
      .returns(TwirpResponse.new(
        status: 200,
        call_succeeded: true,
        value: @results_log_url_payload
      ))

      assert_equal @completed_log_url_from_results, check_run.get_signed_completed_log_url
    end

    test "successfully returns a signed completed job URL when no results URL is present" do
      check_run = build(:completed_check_run, completed_log_url: @authenticated_url)

      ActionsResults::Twirp::LogClient
      .any_instance
      .expects(:get_completed_job_log_url)
      .never

      mock_completed_job_log_exchange_url(
        unauthenticated_url: check_run.completed_log_url,
        authenticated_url: @authenticated_url,
        repository: check_run.repository,
      )

      assert_equal check_run.get_signed_completed_log_url, @authenticated_url
    end

    test "returns nil if a completed job URL does not exist" do
      check_run = build(:check_run)

      assert_nil check_run.get_signed_completed_log_url
    end

    test "returns nil if request to Actions Service fails" do
      check_run = build(:completed_check_run, completed_log_url: @authenticated_url)

      ActionsResults::Twirp::LogClient
      .any_instance
      .expects(:get_completed_job_log_url)
      .never

      mock_completed_job_log_exchange_url(
        unauthenticated_url: check_run.completed_log_url,
        authenticated_url: @authenticated_url,
        repository: check_run.repository,
        response_status: 500,
      )

      assert_nil check_run.get_signed_completed_log_url
    end

    test "falls back to Actions Service if the request to the Results Service raises an error" do
      check_run = create(:check_run_for_actions_app, :results_completed_log_url)

      ActionsResults::Twirp::LogClient
      .any_instance
      .expects(:get_completed_job_log_url)
      .returns(TwirpResponse.new(
        status: 500,
        call_succeeded: false,
      ))

      mock_completed_job_log_exchange_url(
        authenticated_url: @authenticated_url,
        repository: check_run.repository,
      )

      refute_nil check_run.get_signed_completed_log_url
    end

    test "falls back to Actions Service if the request to the Results Service returns an empty URL" do
      check_run = create(:check_run_for_actions_app, :results_completed_log_url)
      empty_log_url = MonolithTwirp::ActionsResults::Core::V1::GetCompletedJobLogResponse.new(
        log_url: ""
      ).freeze

      ActionsResults::Twirp::LogClient
      .any_instance
      .expects(:get_completed_job_log_url)
      .returns(TwirpResponse.new(
        status: 200,
        call_succeeded: true,
        value: empty_log_url
      ))

      mock_completed_job_log_exchange_url(
        authenticated_url: @authenticated_url,
        repository: check_run.repository,
      )

      refute_nil check_run.get_signed_completed_log_url
    end
  end

  context "#get_log_scrollback_from_results" do
    test "successfully returns backscrolls", skip_enterprise: true do
      GitHub.flipper[:actions_opt_out_results_service].disable

      check_run = build(:check_run, external_id: SimpleUUID::UUID.new.to_guid)
      check_run.check_suite.external_id = SimpleUUID::UUID.new.to_guid
      check_run.check_suite.save!
      step_external_id = "6cb15225-bace-5236-3d64-8b6d88bf381f"
      logs_backscroll = MonolithTwirp::ActionsResults::Core::V1::GetStepLogScrollbackResponse.new(
        lines: [
          MonolithTwirp::ActionsResults::Core::V1::GetStepLogScrollbackResponse::LogLine.new(
            id: "0-1", line: "line 1"
          ),
          MonolithTwirp::ActionsResults::Core::V1::GetStepLogScrollbackResponse::LogLine.new(
            id: "0-2", line: "line 2"
          )
        ]
      )

      ActionsResults::Twirp::LogClient
        .any_instance
        .expects(:get_step_log_scrollback)
        .with(equals({
          workflow_run_backend_id: check_run.check_suite.external_id,
          workflow_job_run_backend_id: check_run.external_id,
          workflow_step_backend_id: step_external_id,
        }))
        .returns(TwirpResponse.new(
          status: 200,
          call_succeeded: true,
          value: logs_backscroll
        ))

      res = check_run.get_log_scrollback_from_results(step_external_id)
      refute_nil res
      lines = res["lines"]
      assert_equal 2, lines.length
      assert_equal "line 1", lines[0]["line"]
      assert_equal "line 2", lines[1]["line"]
    end

    test "returns nil with any exceptions", skip_enterprise: true do
      GitHub.flipper[:actions_opt_out_results_service].disable

      check_run = build(:check_run, external_id: SimpleUUID::UUID.new.to_guid)
      check_run.check_suite.external_id = SimpleUUID::UUID.new.to_guid
      check_run.check_suite.save!
      step_external_id = "6cb15225-bace-5236-3d64-8b6d88bf381f"
      logs_backscroll = { "lines" => [{ "id" => 1, "line" => "line 1" }, { "id" => 2, "line" => "line 2" }] }

      ActionsResults::Twirp::LogClient
        .any_instance
        .expects(:get_step_log_scrollback)
        .with(equals({
          workflow_run_backend_id: check_run.check_suite.external_id,
          workflow_job_run_backend_id: check_run.external_id,
          workflow_step_backend_id: step_external_id,
        }))
        .returns(TwirpResponse.new(
          status: 500,
          call_succeeded: false,
        ))

      res = check_run.get_log_scrollback_from_results(step_external_id)
      assert_nil res
    end
  end

  context "field compression" do
    [:summary, :text].each do |field|
      test "compresses #{field} field" do
        dummy_field = "a" * 2000
        check_run = build :check_run
        check_run[field] = dummy_field
        check_run.save!

        raw = check_run.read_attribute_before_type_cast(field)

        assert_equal check_run[field], dummy_field
        refute_equal raw.to_s, dummy_field
        assert Checks::MaybeCompressed.is_compressed?(raw.to_s)
      end
    end
  end

  test "check_run_action YAML compatibility" do
    # This is the format that was serialized before we added a custom
    # encode_with. Valid in the database will still have this form so we need
    # to load them correctly.

    yaml = <<~YAML.strip
--- &1 !ruby/object:CheckRunAction
label: label
identifier: identifier
description: description
validation_context:
errors: !ruby/object:ActiveModel::Errors
  base: *1
  errors: []
YAML

    # In this case ActiveModel::Errors is required
    round_trip = YAML.load(yaml, permitted_classes: [CheckRunAction, ActiveModel::Errors], aliases: true)

    assert_equal "label", round_trip.label
    assert_equal "identifier", round_trip.identifier
    assert_equal "description", round_trip.description
  end

  test "check_run_action YAML round trip" do
    action = CheckRunAction.new("label", "identifier", "description")
    assert action.valid?

    yaml = YAML.dump(action)

    assert_equal <<YAML, yaml
--- !ruby/object:CheckRunAction
label: label
identifier: identifier
description: description
YAML

    # We load _without_ ActiveModel::Errors, which should not have been
    # included in the dumped YAML
    round_trip = YAML.load(yaml, permitted_classes: [CheckRunAction], aliases: true)

    assert_equal "label", round_trip.label
    assert_equal "identifier", round_trip.identifier
    assert_equal "description", round_trip.description
  end
end
