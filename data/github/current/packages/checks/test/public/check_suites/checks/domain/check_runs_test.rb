# typed: true
# frozen_string_literal: true

require "test_helper"

class CheckRunsDomainTest < GitHub::TestCase
  context "#latest_ids" do
    test "returns the last runs per name" do
      check_suite = create(:check_suite)
      check_run1   = create(:check_run, check_suite: check_suite, name: "a", status: "completed", conclusion: "failure", completed_at: Time.now.utc)
      check_run2_1 = create(:check_run, check_suite: check_suite, name: "b", status: "in_progress", conclusion: nil)
      check_run2_2 = create(:check_run, check_suite: check_suite, name: "b", status: "in_progress", conclusion: nil)

      ids = Checks.domain.check_runs.latest_ids(repository_id: check_suite.repository_id, check_suite_id: check_suite.id, head_sha: check_suite.head_sha, latest_check_suite_run_only: false)
      assert_same_elements [check_run1.id, check_run2_2.id], ids
    end

    test "latest_check_suite_run_only: returns only the runs created since the check suite started" do
      user = create(:user)
      repo = create(:repository, owner: user)
      check_suite = create(:check_suite, repository: repo)

      Timecop.freeze do
        check_run1 = create(:check_run, check_suite: check_suite, name: "a", status: "completed", conclusion: "failure", completed_at: Time.now.utc)

        Timecop.travel(10.minutes)

        check_suite.rerequest(actor: user)

        check_run2_1 = create(:check_run, check_suite: check_suite, name: "b", status: "in_progress", conclusion: nil)
        check_run2_2 = create(:check_run, check_suite: check_suite, name: "b", status: "in_progress", conclusion: nil)

        ids = Checks.domain.check_runs.latest_ids(repository_id: check_suite.repository_id, check_suite_id: check_suite.id, head_sha: check_suite.head_sha, latest_check_suite_run_only: true)
        assert_same_elements [check_run2_2.id], ids
      end
    end
  end

  context "#latest_ids_for_check_suite" do
    test "returns the last runs per name" do
      check_suite = create(:check_suite)
      check_run1   = create(:check_run, check_suite: check_suite, name: "a", status: "completed", conclusion: "failure", completed_at: Time.now.utc)
      check_run2_1 = create(:check_run, check_suite: check_suite, name: "b", status: "in_progress", conclusion: nil)
      check_run2_2 = create(:check_run, check_suite: check_suite, name: "b", status: "in_progress", conclusion: nil)

      ids = Checks.domain.check_runs.latest_ids_for_check_suite(check_suite)
      assert_same_elements [check_run1.id, check_run2_2.id], ids
    end

    test "returns only the runs created since the check suite started for Actions" do
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

        ids = Checks.domain.check_runs.latest_ids_for_check_suite(check_suite)
        assert_same_elements [check_run2_2.id], ids
      end
    end
  end

  context "#latest_for_check_suite" do
    test "returns the last CheckRun per name" do
      check_suite = create :check_suite

      check_run1   = create(:check_run, check_suite: check_suite, name: "a", status: "completed", conclusion: "failure", completed_at: Time.now.utc)
      check_run2_1 = create(:check_run, check_suite: check_suite, name: "b", status: "in_progress", conclusion: nil)
      sleep 1
      check_run2_2 = create(:check_run, check_suite: check_suite, name: "b", status: "in_progress", conclusion: nil)

      assert_same_elements [check_run1.id, check_run2_2.id], Checks.domain.check_runs.latest_for_check_suite(check_suite).collect(&:id)
    end

    test "scopes the check runs to the check suite" do
      check_suite1 = create :check_suite
      check_suite2 = create(:check_suite, repository: check_suite1.repository, head_sha: check_suite1.head_sha)

      check_run1   = create(:check_run, check_suite: check_suite1, name: "a", status: "completed", conclusion: "failure", completed_at: Time.now.utc)
      check_run2   = create(:check_run, check_suite: check_suite2, name: "b", status: "completed", conclusion: "failure", completed_at: Time.now.utc)

      assert_same_elements [check_run1.id], Checks.domain.check_runs.latest_for_check_suite(check_suite1).collect(&:id)
      assert_same_elements [check_run2.id], Checks.domain.check_runs.latest_for_check_suite(check_suite2).collect(&:id)
    end

    test "returns an empty array when no check runs are in the check suite" do
      check_suite = create :check_suite
      assert_predicate Checks.domain.check_runs.latest_for_check_suite(check_suite), :none?
    end

    context "with first_only" do
      test "returns the last CheckRun" do
        check_suite = create :check_suite
        check_run1 = create(:check_run, check_suite: check_suite, name: "a", status: "completed", conclusion: "failure", completed_at: Time.now.utc)
        check_run2 = create(:check_run, check_suite: check_suite, name: "b", status: "in_progress", conclusion: nil)

        results = Checks.domain.check_runs.latest_for_check_suite(check_suite, first_only: true)
        assert_equal 1, results.size
        assert_equal check_run1, results.first
      end

      test "returns nil when no check runs are in the check suite" do
        check_suite = create :check_suite

        results = Checks.domain.check_runs.latest_for_check_suite(check_suite, first_only: true)
        assert_equal 0, results.size
      end
    end
  end
end
