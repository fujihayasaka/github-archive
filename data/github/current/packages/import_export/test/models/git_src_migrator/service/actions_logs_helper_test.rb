# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/launch_test_helpers"
require "test_helpers/launch/exchange_url_helper"

class ActionsLogsHelperTest < GitHub::TestCase
  include LaunchTestHelpers
  include Launch::ArtifactExchangeUrlHelper

  fixtures do
    @owner        = create :paid_user, login: "octocat"
    @org          = create :organization, admin: @owner, login: "github"
    @repo         = create :private_repository, owner: @owner, name: "Hello-World", from_example: :simple
    @github_app   = create :integration, default_permissions: { "checks" => :write },
                      name: "Super-Duper", owner: @org, url: "http://super-duper.com"


    setup_launch_backend_stubs

    make_trusted_oauth_apps_owner
    @launch_app = create(:launch_integration)
    make_integration_installation(integration: @launch_app, repository: @repo)

    @launch_lab_app = create(:launch_lab_integration)
    make_integration_installation(integration: @launch_lab_app, repository: @repo)

    commit = @repo.refs.find("master").commit

    @launch_check_suite = create(:check_suite_for_actions_app, github_app: @launch_app, repository: @repo, head_sha: commit.oid)
    @launch_check_run   = create :check_run, check_suite: @launch_check_suite, status: "queued"
  end

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
  end

  context "download_logs_archive_url_from_backend" do
    test "returns a signed url for a workflow run's logs" do
      enable_feature_flag(:actions_favor_results_service_logs)
      disable_feature_flag(:actions_opt_out_results_service)

      Timecop.freeze do
        completed_log_url = "https://logs.github.com/some-unique-slug-check-suite"
        check_suite = create(:check_suite_for_actions_app, repository: @repo, completed_log_url: completed_log_url)
        create(:check_run, check_suite: check_suite, status: "completed", conclusion: "success", created_at: Time.now.utc - 1.day, completed_log_url: "https://github.com")
        create(:check_run, check_suite: check_suite, status: "completed", conclusion: "success", created_at: Time.now.utc - 1.day, completed_log_url: "https://github.com")

        authenticated_url = "https://logs.github.com/some-unique-slug-check-suite?token=1234"
        if GitHub.flipper[:actions_favor_results_service_logs].enabled? && !GitHub.flipper[:actions_opt_out_results_service].enabled?
          ActionsResults::Twirp::LogClient
            .any_instance
            .expects(:get_completed_run_log_archive)
            .with(workflow_run_backend_id: check_suite.external_id)
            .returns(TwirpResponse.new(
              status: 200,
              call_succeeded: true,
              value: MonolithTwirp::ActionsResults::Core::V1::GetCompletedRunLogArchiveResponse.new(
                log_url: authenticated_url
              )
            ))
        else
          mock_completed_run_log_exchange_url(
            unauthenticated_url: check_suite.completed_log_url,
            authenticated_url:,
            repository: @repo,
          )
        end

        redirect_url = GitSrcMigrator::Service::ActionsLogsHelper.new.download_logs_archive_url_from_backend(completed_log_url, check_suite, check_suite.external_id, @repo.next_global_id)
        assert_equal authenticated_url, redirect_url
      end

    end

    test "returns nil if there's an error generating url" do
      enable_feature_flag(:actions_favor_results_service_logs)
      disable_feature_flag(:actions_opt_out_results_service)

      Timecop.freeze do
        completed_log_url = "https://logs.github.com/some-unique-slug-check-suite"
        check_suite = create(:check_suite_for_actions_app, repository: @repo, completed_log_url: completed_log_url)
        create(:check_run, check_suite: check_suite, status: "completed", conclusion: "success", created_at: Time.now.utc - 1.day, completed_log_url: "https://github.com")
        create(:check_run, check_suite: check_suite, status: "completed", conclusion: "success", created_at: Time.now.utc - 1.day, completed_log_url: "https://github.com")

        error = ActionsResults::Twirp::Error.new("github-launch service unavailable")

        if GitHub.flipper[:actions_favor_results_service_logs].enabled? && !GitHub.flipper[:actions_opt_out_results_service].enabled?
          ActionsResults::Twirp::LogClient
            .any_instance
            .expects(:get_completed_run_log_archive)
            .returns(TwirpResponse.new(
              status: 500,
              call_succeeded: false,
            ))
        else
          raise error
        end

        redirect_url = GitSrcMigrator::Service::ActionsLogsHelper.new.download_logs_archive_url_from_backend(completed_log_url, check_suite, check_suite.external_id, @repo.next_global_id)
        assert_nil redirect_url
      end
    end
  end
end
