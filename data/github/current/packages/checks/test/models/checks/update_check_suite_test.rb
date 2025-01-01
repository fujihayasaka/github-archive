# typed: true
# frozen_string_literal: true

require "test_helper"

class Checks::UpdateCheckSuiteTest < GitHub::TestCase
  include PlatformTestHelpers::InterfaceHelpers
  include PushTestHelper

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
  end

  fixtures do
    @user = create(:user, plan:  "pro")
    @repository = create(:repository, name: "hello-world", owner: @user, from_example: :rebase_pull_request)


    commit = @repository.heads.find("contrib").append_commit({ message: "blah", committer: @user }, @user) do |files|
      files.add("foo", "dsfdsfsdfsd")
    end
    @sha = commit.oid

    make_trusted_oauth_apps_owner

    @check_suite = create(:check_suite_for_actions_app, repository: @repository, head_sha: @sha, head_branch: nil)
  end

  def setup
    @subject = Checks::UpdateCheckSuite
  end

  context "call" do
    context "updating check suite" do
      test "updates the check suite values" do
        @subject.call(
          check_suite: @check_suite,
          update_properties: {
            check_suite_updates: {
              completed_log_url: "https://logs.github.com/some-unique-slug-step1",
            }
          }
        )

        @check_suite.reload

        assert_equal "https://logs.github.com/some-unique-slug-step1", @check_suite.completed_log_url
      end

      test "does not overwrite existing values with nil" do
        @check_suite.update(external_id: "1234abcde")
        @subject.call(
          check_suite: @check_suite,
          update_properties: {
            check_suite_updates: {}
          },
        )

        @check_suite.reload

        assert_equal "1234abcde", @check_suite.external_id
      end

      test "calls create artifacts service with the correct steps arguments when the FF is disabled" do
        disable_feature_flag(:checks_create_check_artifacts_job_enabled)

        artifacts_data = [{
          name: "Artifact 1",
          source_url: "https://dev.azure.com/Account/project/_build/artifacts_1.zip",
          size: 102400,
          created_at: Time.now,
          expires_at: Time.now,
          repository_id: @repository.id,
        }]

        Checks::CreateArtifacts.expects(:call).with(has_entries(
          check_suite: responds_with(:id, @check_suite.id),
          artifacts: artifacts_data,
        ))

        @subject.call(
          check_suite: @check_suite,
          update_properties: {
            check_suite_updates: {},
            artifacts: artifacts_data,
          },
        )
      end

      test "calls create artifacts job with the correct steps arguments when the FF is enabled" do
        enable_feature_flag(:checks_create_check_artifacts_job_enabled)

        artifacts_data = [{
          name: "Artifact 1",
          source_url: "https://dev.azure.com/Account/project/_build/artifacts_1.zip",
          size: 102400,
          created_at: Time.now,
          expires_at: Time.now,
          repository_id: @repository.id,
        }]


        Checks::CreateArtifacts.expects(:call).never

        CreateArtifactsJob.expects(:perform_later).with(has_entries(
          check_suite_id: @check_suite.id,
          artifacts: artifacts_data,
        ))

        @subject.call(
          check_suite: @check_suite,
          update_properties: {
            check_suite_updates: {},
            artifacts: artifacts_data,
          },
        )
      end

      test "creates a check suite with check suite concurrency" do
        GitHub.stubs(:actions_enabled?).returns(true)
        check_suite = create(:check_suite_for_actions_app, repository: @repository, head_sha: @sha, head_branch: nil)

        concurrency = {
          group: "testGroup",
          waiting_on_resource: {
            check_suite_id: check_suite.id,
          }
        }

        @subject.call(
          check_suite: check_suite,
          update_properties: {
            concurrency: concurrency,
            check_suite_updates: {
              completed_log_url: "https://logs.github.com/some-unique-slug-step1"
            }
          }
        )

        check_suite.reload
        assert_equal "https://logs.github.com/some-unique-slug-step1", check_suite.completed_log_url
        refute_nil check_suite.workflow_run&.concurrency
        concurrency_json = JSON.parse(check_suite.workflow_run.concurrency)
        refute_nil concurrency_json

        assert_equal concurrency_json["group"], "testGroup"
        waiting_on_resource_json = concurrency_json["waiting_on_resource"]
        refute_nil waiting_on_resource_json
        assert_nil waiting_on_resource_json["check_run_id"]
        refute_nil waiting_on_resource_json["check_suite_id"]
        assert_equal check_suite.id, waiting_on_resource_json["check_suite_id"].to_i
        assert_equal "pending", check_suite.status
      end

      test "creates a check suite with check run concurrency" do
        GitHub.stubs(:actions_enabled?).returns(true)
        check_suite = create(:check_suite_for_actions_app, repository: @repository, head_sha: @sha, head_branch: nil, explicit_completion: true)
        check_run = create(:check_run_for_actions_app, :failure, check_suite: check_suite)

        check_suite.reload # Make sure we have the latest status due to check_run callbacks

        concurrency = {
          group: "testGroup",
          waiting_on_resource: {
            check_run_id: check_run.id
          }
        }

        @subject.call(
          check_suite: check_suite,
          update_properties: {
            concurrency: concurrency,
            check_suite_updates: {
              completed_log_url: "https://logs.github.com/some-unique-slug-step1"
            },
          },
        )

        check_suite.reload
        concurrency_json = JSON.parse(check_suite&.workflow_run.concurrency)
        refute_nil concurrency_json

        assert_equal concurrency_json["group"], "testGroup"
        waiting_on_resource_json = concurrency_json["waiting_on_resource"]
        refute_nil waiting_on_resource_json
        assert_nil waiting_on_resource_json["check_suite_id"]
        assert_equal check_run.id, waiting_on_resource_json["check_run_id"].to_i
        assert_equal "pending", check_suite.status
      end

      test "updates status using a conditional query for workflow run execution" do
        GitHub.stubs(:actions_enabled?).returns(true)

        check_suite = create(:check_suite_for_actions_app, repository: @repository, head_sha: @sha, explicit_completion: true)
        check_run = create(:check_run_for_actions_app, :failure, check_suite: check_suite)

        check_suite.reload # Make sure we have the latest status due to check_run callbacks

        concurrency = {
          group: "testGroup",
          waiting_on_resource: {
            check_run_id: check_run.id
          }
        }

        @subject.call(
          check_suite: check_suite,
          update_properties: {
            concurrency: concurrency,
            check_suite_updates: {
              completed_log_url: "https://logs.github.com/some-unique-slug-step1"
            },
          },
        )

        workflow_run_execution = check_suite.workflow_run.latest_workflow_run_execution
        assert_equal "pending", workflow_run_execution.status
      end

      test "updates status using a conditional query for check suite with check run concurrency when the feature is enabled" do
        enable_feature_flag(:check_suite_update_conclusion_with_conditional_query)
        GitHub.stubs(:actions_enabled?).returns(true)

        check_suite = create(:check_suite_for_actions_app, repository: @repository, head_sha: @sha, explicit_completion: true)
        check_run = create(:check_run_for_actions_app, :failure, check_suite: check_suite)

        check_suite.reload # Make sure we have the latest status due to check_run callbacks

        concurrency = {
          group: "testGroup",
          waiting_on_resource: {
            check_run_id: check_run.id
          }
        }

        _, queries = log_queries do
          @subject.call(
            check_suite: check_suite,
            update_properties: {
              concurrency: concurrency,
              check_suite_updates: {
                completed_log_url: "https://logs.github.com/some-unique-slug-step1"
              },
            },
          )
        end

        update_queries = queries.map(&:digested_sql).select { |q| q.start_with?("UPDATE check_suites") }
        assert update_queries.any? { |q| q.match?(/\AUPDATE check_suites SET (.*) WHERE(.*)check_suites.status != ?(.*)\Z/) }, "Expected update query to be conditional to status. Got:\n#{update_queries}"

        check_suite.reload
        assert_equal "pending", check_suite.status
      end

      test "updates conclusion for a check suite with explicit conclusion" do
        @check_suite.update(explicit_completion: true, status: "in_progress", conclusion: nil)
        create :check_run_for_actions_app, :failure, check_suite: @check_suite
        assert_equal "in_progress", @check_suite.status
        refute_predicate @check_suite, :conclusion

        @subject.call(
          check_suite: @check_suite,
          update_properties: {
            check_suite_updates: {},
            conclusion: "failure",
          },
        )

        @check_suite.reload
        assert_equal "completed", @check_suite.status
        assert_equal "failure", @check_suite.conclusion
        refute_nil @check_suite.completed_at
      end

      test "triggers socket updates for a check suite with explicit conclusion" do
        enable_feature_flag(:check_suite_update_conclusion_with_conditional_query)

        @check_suite.update(explicit_completion: true, status: "in_progress", conclusion: nil)
        create :check_run_for_actions_app, :failure, check_suite: @check_suite
        assert_equal "in_progress", @check_suite.status
        refute_predicate @check_suite, :conclusion

        GitHub::WebSocket.expects(:notify_repository_channel).once

        @subject.call(
          check_suite: @check_suite,
          update_properties: {
            check_suite_updates: {},
            conclusion: "failure",
          },
        )
      end

      test "updates conclusion using a conditional query for a check suite with explicit conclusion when the feature is enabled" do
        enable_feature_flag(:check_suite_update_conclusion_with_conditional_query)

        @check_suite.update(explicit_completion: true, status: "in_progress", conclusion: nil)
        create :check_run_for_actions_app, :failure, check_suite: @check_suite
        assert_equal "in_progress", @check_suite.status
        refute_predicate @check_suite, :conclusion

        _, queries = log_queries do
          @subject.call(
            check_suite: @check_suite,
            update_properties: {
              check_suite_updates: {},
              conclusion: "failure",
            },
          )
        end

        update_queries = queries.map(&:digested_sql).select { |q| q.start_with?("UPDATE check_suites") }

        assert update_queries.any? { |q| q.match?(/\AUPDATE check_suites SET (.*) \? WHERE(.*)check_suites.status != ?(.*)\Z/) }, "Expected update query to be conditional to status. Got:\n#{update_queries}"

        @check_suite.reload
        assert_equal "completed", @check_suite.status
        assert_equal "failure", @check_suite.conclusion
        refute_nil @check_suite.completed_at
      end

      test "calls create annotations service with the correct steps arguments" do
        annotations = [{
          repository_id: @repository.id,
          warning_level: "warning",
          message: "This might be a problem, because reasons.",
          raw_details: "",
          filename: "README.md",
          start_line: 19,
          end_line: 19,
          start_column: 20,
          end_column: 22,
          title: "This is a Title"
        }]

        Checks::CreateCheckAnnotations.expects(:call).with(has_entries(
          check_suite: responds_with(:id, @check_suite.id),
          annotations: annotations,
        ))

        @subject.call(
          check_suite: @check_suite,
          update_properties: {
            check_suite_updates: {},
            annotations: annotations,
          },
        )
      end
    end
  end
end
