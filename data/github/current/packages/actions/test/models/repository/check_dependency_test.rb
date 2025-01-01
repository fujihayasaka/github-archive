# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dependabot_github_app_helper"

class RepositoryChecksDependencyTest < GitHub::TestCase
  include PushTestHelper
  include DependabotGithubAppHelper

  fixtures do
    @org        = create :organization
    @org_admin  = @org.admins.first
    @repository = create(:repository, owner: @org)
    @github_app = create :integration, default_permissions: { "checks" => :write }
    make_integration_installation integration: @github_app, repository: @repository
  end

  setup do
    reset_cache
    example_repo :simple, @repository

    perform_enqueued_jobs(only: [CreateCheckSuitesJob]) do
      @push = push_changes(repository: @repository, branch_name: "master",
        changes: { path: "README.md", content: "# Header" }, create_via_hydro_job: true)
      @sha  = @push.after
    end

    @check_suite = CheckSuite.find_by(repository_id: @repository.id, head_sha: @sha, github_app_id: @github_app.id)
    @check_run = create(:check_run, check_suite: @check_suite, name: "coverage", status: :in_progress, started_at: Time.now)

    make_trusted_oauth_apps_owner
    reset_dependabot_github_app_memoization
    @dependabot_app = create(:dependabot_integration)
    GitHub.stubs(:dependabot_enabled?).returns(true)
    GitHub.stubs(:actions_enabled?).returns(true)
  end

  context "#annotations_for" do
    test "returns check annotations for the given sha" do
      @check_annotation = @check_run.annotations.create({
        filename: "README.md",
        start_line: 123,
        end_line: 124,
        warning_level: "warning",
        message: "Please don't do that",
        repository: @repository,
      })

      assert_includes @repository.annotations_for(sha: @sha, limit: CheckAnnotation::MAX_READ_LIMIT), @check_annotation

      GitHub::RequestDurationManager.with_budget_control(total_window_ms: 100) do
        assert_includes @repository.annotations_for(sha: @sha, limit: CheckAnnotation::MAX_READ_LIMIT), @check_annotation
      end
    end

    test "database query is capped to prevent web request timeouts" do
      @check_annotation = @check_run.annotations.create({
        filename: "README.md",
        start_line: 123,
        end_line: 124,
        warning_level: "warning",
        message: "Please don't do that",
        repository: @repository,
      })

      GitHub::RequestDurationManager.with_budget_control(total_window_ms: 10000) do
        GitHub::RequestDurationManager.enable_time_budget_control

        _, queries = log_queries do
          assert_includes @repository.annotations_for(sha: @sha, limit: CheckAnnotation::MAX_READ_LIMIT), @check_annotation
        end

        # Ignore feature flag queries
        queries.reject! do |q|
          q.sql.include?("flipper_features") || q.sql.include?("flipper_gates") || q.sql.include?("/* loading for pp */")
        end
      end
    end

    test "returns empty if there are no annotations" do
      assert_empty @repository.annotations_for(sha: @sha, limit: CheckAnnotation::MAX_READ_LIMIT)
    end

    test "returns check annotations for the filenames" do
      @readme = @check_run.annotations.create({
        filename: "README.md",
        start_line: 123,
        end_line: 124,
        warning_level: "warning",
        message: "Please don't do that",
        repository: @repository,
      })

      @contrib = @check_run.annotations.create({
        filename: "contrib.md",
        start_line: 123,
        end_line: 124,
        warning_level: "warning",
        message: "Please don't do that",
        repository: @repository,
      })

      annotations = @repository.annotations_for(sha: @sha, filenames: ["README.md"], limit: CheckAnnotation::MAX_READ_LIMIT)
      assert_includes annotations, @readme
      refute_includes annotations, @contrib
    end

    test "can return inline annotations only" do
      @inline_annotation = @check_run.annotations.create!({
        filename: "contrib.md",
        start_line: 123,
        end_line: 124,
        warning_level: "warning",
        message: "Please don't do that",
        repository: @repository,
      })
      @non_inline_annotation = @check_run.annotations.create!({
        filename: "README.md",
        start_line: 0,
        end_line: 0,
        warning_level: "failure",
        message: "Boom",
        repository: @repository,
      })

      query_count = 2

      annotations = assert_query_count(query_count, ignore_feature_flags: true) do
        @repository.annotations_for(sha: @sha, inline_only: true, limit: CheckAnnotation::MAX_READ_LIMIT)
      end

      assert_equal 1, annotations.count
      assert_includes annotations, @inline_annotation
      refute_includes annotations, @non_inline_annotation
    end
  end

  context "#auto_trigger_checks_for?" do
    test "defaults to true for github apps" do
      assert @repository.auto_trigger_checks_for?(app_id: @github_app.id)
    end

    test "returns false if Actions is the github_app" do
      launch_app = create(:launch_integration)
      GitHub.stubs(:launch_github_app).returns(launch_app)
      refute @repository.auto_trigger_checks_for?(app_id: launch_app.id)
    end

    test "returns false if Dependabot is the github_app" do
      refute @repository.auto_trigger_checks_for?(app_id: @dependabot_app.id)
    end
  end
end
