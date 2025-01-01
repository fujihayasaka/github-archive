# typed: true
# frozen_string_literal: true
require "test_helper"

class CombinedStatusCheckRunAdapterTest < GitHub::TestCase
  test "passes values through to the underlying check run" do
    check_run   = CheckRun.new(conclusion: :timed_out)
    wrapped_run = CombinedStatus::CheckRunAdapter.new(check_run)
    assert T.unsafe(wrapped_run).timed_out?
  end

  test "state defaults to conclusion if present" do
    check_run   = CheckRun.new(status: :completed, conclusion: :success)
    wrapped_run = CombinedStatus::CheckRunAdapter.new(check_run)
    assert_equal "success", wrapped_run.state
  end

  test "state falls back to status" do
    check_run   = CheckRun.new(status: :in_progress, conclusion: nil)
    wrapped_run = CombinedStatus::CheckRunAdapter.new(check_run)
    assert_equal "in_progress", wrapped_run.state
  end

  test "state changed at uses completion time if concluded" do
    ts1 = Time.current - 30
    ts2 = ts1 + 10
    ts3 = ts2 + 10
    ts4 = ts3 + 10
    check_run = CheckRun.new(status: :completed, conclusion: :success, created_at: ts1, updated_at: ts2, started_at: ts3, completed_at: ts4)
    wrapped_run = CombinedStatus::CheckRunAdapter.new(check_run)
    assert_same_time ts4, wrapped_run.state_changed_at
  end

  test "state changed at uses start time if run is in progress" do
    ts1 = Time.current - 30
    ts2 = ts1 + 10
    ts3 = ts2 + 10
    check_run = CheckRun.new(status: :in_progress, conclusion: nil, created_at: ts1, updated_at: ts2, started_at: ts3)
    wrapped_run = CombinedStatus::CheckRunAdapter.new(check_run)
    assert_same_time ts3, wrapped_run.state_changed_at
  end

  test "state changed at uses created at if run is requested" do
    ts1 = Time.current - 30
    ts2 = ts1 + 10
    check_run = CheckRun.new(status: :requested, conclusion: nil, created_at: ts1, updated_at: ts2)
    wrapped_run = CombinedStatus::CheckRunAdapter.new(check_run)
    assert_same_time ts1, wrapped_run.state_changed_at
  end

  test "order by number" do
    check_suite = CheckSuite.new
    run1 = CombinedStatus::CheckRunAdapter.new(CheckRun.new(id: 1, number: 3, status: :in_progress, conclusion: nil, name: "a", check_suite: check_suite))
    run2 = CombinedStatus::CheckRunAdapter.new(CheckRun.new(id: 2, number: 2, status: :completed, conclusion: :success, name: "a", check_suite: check_suite))
    run3 = CombinedStatus::CheckRunAdapter.new(CheckRun.new(id: 3, number: 1, status: :completed, conclusion: :failure, name: "a", check_suite: check_suite))

    results = T.let([run1, run2, run3], T.untyped)
    assert_equal [3, 2, 1], results.sort_by(&:sort_order).map(&:id)
  end

  test "order by state" do
    check_suite = CheckSuite.new
    run1 = CombinedStatus::CheckRunAdapter.new(CheckRun.new(id: 1, status: :in_progress, conclusion: nil, name: "a", check_suite: check_suite))
    run2 = CombinedStatus::CheckRunAdapter.new(CheckRun.new(id: 2, status: :completed, conclusion: :success, name: "a", check_suite: check_suite))
    run3 = CombinedStatus::CheckRunAdapter.new(CheckRun.new(id: 3, status: :completed, conclusion: :failure, name: "a", check_suite: check_suite))

    results = T.let([run1, run2, run3], T.untyped)
    assert_equal [3, 1, 2], results.sort_by(&:sort_order).map(&:id)
  end

  test "order by deprecated state" do
    check_suite = CheckSuite.new
    run1 = CombinedStatus::CheckRunAdapter.new(CheckRun.new(id: 1, status: :in_progress, conclusion: nil, name: "a", check_suite: check_suite))
    run2 = CombinedStatus::CheckRunAdapter.new(CheckRun.new(id: 2, status: :requested, conclusion: nil, name: "a", check_suite: check_suite))
    run3 = CombinedStatus::CheckRunAdapter.new(CheckRun.new(id: 3, status: :completed, conclusion: :failure, name: "a", check_suite: check_suite))

    results = T.let([run1, run2, run3], T.untyped)
    assert_equal [3, 2, 1], results.sort_by(&:sort_order).map(&:id)
  end

  test "order by state with name as tie breaker" do
    check_suite = CheckSuite.new
    run1 = CombinedStatus::CheckRunAdapter.new(CheckRun.new(id: 1, status: :completed, conclusion: :success, name: "b", check_suite: check_suite))
    run2 = CombinedStatus::CheckRunAdapter.new(CheckRun.new(id: 2, status: :completed, conclusion: :success, name: "c", check_suite: check_suite))
    run3 = CombinedStatus::CheckRunAdapter.new(CheckRun.new(id: 3, status: :completed, conclusion: :success, name: "a", check_suite: check_suite))

    results = T.let([run1, run2, run3], T.untyped)
    assert_equal [3, 1, 2], results.sort_by(&:sort_order).map(&:id)
  end

  test "#contextual_name" do
    GitHub.stubs(:actions_enabled?).returns(true)
    make_trusted_oauth_apps_owner

    wrapped_run = CombinedStatus::CheckRunAdapter.new(CheckRun.new(name: "the-name", check_suite: CheckSuite.new))
    assert_equal "the-name", T.unsafe(wrapped_run).contextual_name
    assert_equal "the-name", wrapped_run.context

    check_suite = create(:check_suite_for_actions_app, name: "Workflow name", event: nil)
    wrapped_run = CombinedStatus::CheckRunAdapter.new(CheckRun.new(name: "the-name", check_suite: check_suite))
    assert_equal "Workflow name / the-name", T.unsafe(wrapped_run).contextual_name
    assert_equal "the-name", wrapped_run.context

    check_suite = create(:check_suite_for_actions_app, name: "Workflow name", event: "push")
    wrapped_run = CombinedStatus::CheckRunAdapter.new(CheckRun.new(name: "the-name", check_suite: check_suite))
    assert_equal "Workflow name / the-name (push)", T.unsafe(wrapped_run).contextual_name
    assert_equal "the-name", wrapped_run.context

    check_suite = create(:check_suite_for_actions_app, event: "push")
    wrapped_run = CombinedStatus::CheckRunAdapter.new(CheckRun.new(name: "the-name", check_suite: check_suite))
    assert_equal "the-name (push)", T.unsafe(wrapped_run).contextual_name
    assert_equal "the-name", wrapped_run.context

    check_suite = create(:check_suite_for_actions_app, name: "Workflow name")
    wrapped_run = CombinedStatus::CheckRunAdapter.new(CheckRun.new(name: "the-name", display_name: "The name", check_suite: check_suite))
    assert_equal "Workflow name / The name (push)", T.unsafe(wrapped_run).contextual_name
    assert_equal "The name", wrapped_run.context
  end

  test "aliases title to description" do
    wrapped_run = CombinedStatus::CheckRunAdapter.new(CheckRun.new(title: "the title"))
    assert_equal "the title", wrapped_run.description
  end

  # It should never be this hard to set up test data.
  test "target url" do
    repository = Repository.new
    T.unsafe(repository).singleton_class.send(:define_method, :name_with_display_owner) do
      "owner/name"
    end
    check_run   = CheckRun.new(id: 1, check_suite: CheckSuite.new(repository: repository), repository: repository)
    wrapped_run = CombinedStatus::CheckRunAdapter.new(check_run)
    assert_equal "/owner/name/runs/1", wrapped_run.target_url
  end

  # This deeply nested fixture is a bit of a code smell.
  test "creator" do
    check_run   = CheckRun.new(check_suite: CheckSuite.new(github_app: Integration.new(bot: Bot.new(login: "robot[bot]"))))
    wrapped_run = CombinedStatus::CheckRunAdapter.new(check_run)
    assert_equal "robot[bot]", wrapped_run.creator.login
  end

  test "creator when github_app is deleted returns Ghost" do
    check_run   = CheckRun.new(check_suite: CheckSuite.new(github_app: nil))

    wrapped_run = CombinedStatus::CheckRunAdapter.new(check_run)
    assert_equal User.ghost, wrapped_run.creator
  end

  test "satisfies interface required by check status rollup" do
    check_run   = CheckRun.new
    wrapped_run = CombinedStatus::CheckRunAdapter.new(check_run)
    StatusCheckRollup::REQUIRED_DUCK_TYPE_METHODS.each do |method|
      assert T.unsafe(wrapped_run).respond_to?(method), "Expected CheckRunAdapter to respond to #{method.inspect} to satisfy the duck type for StatusCheckRollup"
    end
  end

  test "tree_oid" do
    repository = create(:repository, from_example: :simple)
    commit = repository.refs.find("master").target_oid
    tree_oid = repository.commits.find(commit).tree_oid

    check_run   = CheckRun.new(id: 1, check_suite: CheckSuite.new(repository: repository, head_sha: commit))
    wrapped_run = CombinedStatus::CheckRunAdapter.new(check_run)

    assert_equal tree_oid, wrapped_run.tree_oid
  end

  test "sha" do
    repository = create(:repository, from_example: :simple)
    sha = repository.refs.find("master").target_oid

    check_run   = CheckRun.new(id: 1, check_suite: CheckSuite.new(repository: repository, head_sha: sha))
    wrapped_run = CombinedStatus::CheckRunAdapter.new(check_run)
    assert_equal sha, wrapped_run.sha
  end

  context "duration_in_seconds" do
    test "returns duration in normal case" do
      Timecop.freeze do
        started_at = Time.now - 2.seconds
        completed_at = Time.now
        check_run = create(:completed_check_run, started_at: started_at, completed_at: completed_at)
        wrapped_run = CombinedStatus::CheckRunAdapter.new(check_run)

        assert_equal 2, wrapped_run.duration_in_seconds
      end
    end

    test "returns 0 when completed_at is in the future" do
      Timecop.freeze do
        CheckRun.skip_callback(:save, :before, :completed_at_not_in_future)
        started_at = Time.now - 2.seconds
        completed_at = Time.now + 50.years
        check_run = create(:completed_check_run, started_at: started_at, completed_at: completed_at)
        CheckRun.set_callback(:save, :before, :completed_at_not_in_future)

        wrapped_run = CombinedStatus::CheckRunAdapter.new(check_run)

        assert_equal 0, wrapped_run.duration_in_seconds
      end
    end
  end
end
