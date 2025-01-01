# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class RepositoryCodeqlVariantAnalysisDependencySerializersTest < Api::SerializerTestCase
  fixtures do
    @owner = create(:paid_user)
    @org = create(:organization, admin: @owner)

    @controller_repo = create(:private_repository, owner: @org)

    @variant_analysis = create(:codeql_variant_analysis, controller_repo: @controller_repo)

    make_trusted_oauth_apps_owner
  end

  # The `test_helpers/api_serializer_helper` file uses method_missing magic to automatically
  # define these methods just-in-time when they are called. We are defining these
  # methods explicitly, so we can hint to Sorbet that these methods exist.
  def repository_codeql_variant_analysis(hash)
    method_missing(:repository_codeql_variant_analysis, hash)
  end

  def repository_codeql_variant_analysis_repo_task(task)
    method_missing(:repository_codeql_variant_analysis_repo_task, task)
  end

  def simple_repository_codeql_variant_analysis_repo_task(task, options)
    method_missing(:simple_repository_codeql_variant_analysis_repo_task, task, options)
  end

  def repository_codeql_variant_analysis_repo(repo)
    method_missing(:repository_codeql_variant_analysis_repo, repo)
  end

  context "dotcom", skip_enterprise: true do
    context "#repository_codeql_variant_analysis_hash" do
      test "constructs hash for a variant analysis" do
        output = repository_codeql_variant_analysis({ variant_analysis: @variant_analysis })

        assert_kind_of Hash, output
        assert_equal @variant_analysis.id, output["id"]
        assert_equal @variant_analysis.controller_repo.id, output["controller_repo"]["id"]
        assert_equal @variant_analysis.actor.id, output["actor"]["id"]
        assert_equal @variant_analysis.query_language, output["query_language"]
        refute_nil output["query_pack_url"]
        assert_equal @variant_analysis.created_at.iso8601, output["created_at"]
        assert_equal @variant_analysis.updated_at.iso8601, output["updated_at"]
        assert_equal "in_progress", output["status"]
        assert output.exclude?("completed_at")
        assert output.exclude?("failure_reason")
        assert output.exclude?("actions_workflow_run_id")
        assert output.exclude?("scanned_repositories")
        assert output.exclude?("skipped_repositories")
      end

      test "constructs the hash when the variant analysis has a failure reason" do
        variant_analysis = create(:codeql_variant_analysis, controller_repo: @controller_repo, failure_reason: "no_repos_queried")
        output = repository_codeql_variant_analysis({ variant_analysis: variant_analysis })

        assert_equal "failed", output["status"]
        assert_equal "no_repos_queried", output["failure_reason"]
        assert output.exclude?("completed_at")
      end

      test "constructs the hash when the actions run never ran" do
        variant_analysis = create(:codeql_variant_analysis, controller_repo: @controller_repo, created_at: 12.hours.ago)
        output = repository_codeql_variant_analysis({ variant_analysis: variant_analysis })

        assert_equal "failed", output["status"]
        assert_equal "internal_error", output["failure_reason"]
        assert_equal (variant_analysis.created_at + 5.hours).iso8601, output["completed_at"]
      end

      test "constructs the hash when the actions run is running" do
        actions_workflow_run = create(:check_suite_for_actions_app,
          status: "in_progress",
          repository: @controller_repo,
          head_repository: @controller_repo).workflow_run
        variant_analysis = create(:codeql_variant_analysis, controller_repo: @controller_repo, actions_workflow_run: actions_workflow_run)
        output = repository_codeql_variant_analysis({ variant_analysis: variant_analysis })

        assert_equal "in_progress", output["status"]
        assert_equal actions_workflow_run.id, output["actions_workflow_run_id"]
        assert output.exclude?("completed_at")
      end

      test "constructs the hash when the variant analysis is complete" do
        actions_workflow_run = create(:check_suite_for_actions_app,
          status: "completed",
          completed_at: DateTime.now,
          conclusion: "success",
          repository: @controller_repo,
          head_repository: @controller_repo).workflow_run
        variant_analysis = create(:codeql_variant_analysis, :completed, controller_repo: @controller_repo, actions_workflow_run: actions_workflow_run)
        associated_repo_ids = [
          variant_analysis.codeql_variant_analysis_repo_tasks.map(&:repository_id),
          variant_analysis.privacy_mismatch_repo_ids&.split(","),
          variant_analysis.no_codeql_db_repo_ids&.split(","),
          variant_analysis.over_limit_repo_ids&.split(","),
        ].compact.flatten
        associated_repositories = Repository.where(id: associated_repo_ids)
        output = repository_codeql_variant_analysis({ variant_analysis: variant_analysis, repositories: associated_repositories.index_by(&:id) })

        assert_equal "succeeded", output["status"]
        assert_equal variant_analysis.codeql_variant_analysis_repo_tasks.length, output["scanned_repositories"].length
        assert_equal actions_workflow_run.completed_at.iso8601, output["completed_at"]
      end

      test "constructs the hash when the variant analysis is cancelled" do
        actions_workflow_run = create(:check_suite_for_actions_app,
          status: "completed",
          completed_at: DateTime.now,
          cancelled_at: DateTime.now,
          conclusion: "cancelled",
          repository: @controller_repo,
          head_repository: @controller_repo).workflow_run
        variant_analysis = create(:codeql_variant_analysis, :completed, controller_repo: @controller_repo, actions_workflow_run: actions_workflow_run)
        output = repository_codeql_variant_analysis({ variant_analysis: variant_analysis, repositories: {} })

        assert_equal "cancelled", output["status"]
        assert output.exclude?("failure_reason")
        assert_equal actions_workflow_run.completed_at.iso8601, output["completed_at"]
      end

      test "constructs the hash when the variant analysis has failed" do
        actions_workflow_run = create(:check_suite_for_actions_app,
          status: "completed",
          completed_at: DateTime.now,
          conclusion: "failure",
          repository: @controller_repo,
          head_repository: @controller_repo).workflow_run
        variant_analysis = create(:codeql_variant_analysis, :completed, controller_repo: @controller_repo, actions_workflow_run: actions_workflow_run)
        output = repository_codeql_variant_analysis({ variant_analysis: variant_analysis, repositories: {} })

        assert_equal "failed", output["status"]
        assert_equal "actions_workflow_run_failed", output["failure_reason"]
        assert_equal actions_workflow_run.completed_at.iso8601, output["completed_at"]
      end
    end

    context "#repository_codeql_variant_analysis_repo_task_hash" do
      test "constructs hash for a repository task" do
        variant_analysis_repo_task = create(:codeql_variant_analysis_repo_task, codeql_variant_analysis: @variant_analysis)

        output = repository_codeql_variant_analysis_repo_task(variant_analysis_repo_task)

        assert_kind_of Hash, output
        assert_equal variant_analysis_repo_task.repository.id, output["repository"]["id"]
        assert_equal variant_analysis_repo_task.repository.nwo, output["repository"]["full_name"]
        assert_equal "pending", output["analysis_status"]
        assert output.exclude?("artifact_size_in_bytes")
        assert output.exclude?("result_count")
        assert output.exclude?("database_commit_sha")
        assert output.exclude?("source_location_prefix")
        assert output.exclude?("artifact_url")
      end

      test "constructs hash for a succeeded repository task with an upload" do
        variant_analysis_repo_task = create(:codeql_variant_analysis_repo_task, :succeeded, codeql_variant_analysis: @variant_analysis)

        output = repository_codeql_variant_analysis_repo_task(variant_analysis_repo_task)

        assert_kind_of Hash, output
        assert_equal variant_analysis_repo_task.repository.id, output["repository"]["id"]
        assert_equal variant_analysis_repo_task.repository.nwo, output["repository"]["full_name"]
        assert_equal "succeeded", output["analysis_status"]
        assert_equal variant_analysis_repo_task.artifact_size, output["artifact_size_in_bytes"]
        assert_equal variant_analysis_repo_task.result_count, output["result_count"]
        assert_equal variant_analysis_repo_task.database_commit_sha, output["database_commit_sha"]
        assert_equal variant_analysis_repo_task.source_location_prefix, output["source_location_prefix"]
        refute_nil output["artifact_url"]
      end

      test "constructs hash for a succeeded repository task without an upload" do
        variant_analysis_repo_task = create(:codeql_variant_analysis_repo_task, :succeeded_no_upload, codeql_variant_analysis: @variant_analysis)

        output = repository_codeql_variant_analysis_repo_task(variant_analysis_repo_task)

        assert_kind_of Hash, output
        assert_equal variant_analysis_repo_task.repository.id, output["repository"]["id"]
        assert_equal variant_analysis_repo_task.repository.nwo, output["repository"]["full_name"]
        assert_equal "succeeded", output["analysis_status"]
        assert_equal variant_analysis_repo_task.result_count, output["result_count"]
        assert_equal variant_analysis_repo_task.database_commit_sha, output["database_commit_sha"]
        assert_equal variant_analysis_repo_task.source_location_prefix, output["source_location_prefix"]
        assert output.exclude?("artifact_size_in_bytes")
        assert output.exclude?("artifact_url")
      end
    end

    context "#repository_codeql_variant_analysis_repo_hash" do
      test "with repository object" do
        repository = create(:repository)

        output = repository_codeql_variant_analysis_repo(repository)

        assert_kind_of Hash, output
        assert_equal repository.id, output["id"]
        assert_equal repository.name, output["name"]
        assert_equal repository.nwo, output["full_name"]
        assert_equal repository.stargazer_count, output["stargazers_count"]
        assert_equal repository.updated_at.iso8601, output["updated_at"]
      end

      test "with repository hash" do
        repository = create(:repository)

        output = repository_codeql_variant_analysis_repo({
          id: repository.id,
          name: repository.name,
          nwo: repository.nwo,
          private: repository.private?,
          stargazer_count: repository.stargazer_count,
          updated_at: repository.updated_at.iso8601,
        })

        assert_kind_of Hash, output
        assert_equal repository.id, output["id"]
        assert_equal repository.name, output["name"]
        assert_equal repository.nwo, output["full_name"]
        assert_equal repository.stargazer_count, output["stargazers_count"]
        assert_equal repository.updated_at.iso8601, output["updated_at"]
      end
    end
  end
end
