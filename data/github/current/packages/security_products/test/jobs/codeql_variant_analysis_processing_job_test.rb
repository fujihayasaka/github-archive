# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "test_helpers/launch/identity_helper"
require "github/codeql/action"

class CodeqlVariantAnalysisProcessingJobTest < GitHub::TestCase
  include Launch::IdentityHelper

  fixtures do
    @controller_repo = create(:public_repository)
    @variant_analysis = create(:codeql_variant_analysis, controller_repo: @controller_repo)

    @public_repo1 = create(:public_repository)
    @public_repo2 = create(:public_repository)

    @private_repo1 = create(:private_repository)
    @private_repo2 = create(:private_repository)

    @no_codeql_db_repo = create(:public_repository)

    add_codeql_db(@public_repo1)
    add_codeql_db(@public_repo2)
    add_codeql_db(@private_repo1)
    add_codeql_db(@private_repo2)

    make_trusted_oauth_apps_owner
    @actions_app = create :launch_integration
    make_integration_installation integration: @actions_app, target: @controller_repo.owner, permissions: { "actions" => :write }

    @github_org = github_org
    @action_repo = create(:public_repository, id: VariantAnalysis::ActionsWorkflowHelper::CODEQL_VARIANT_ANALYSIS_ACTION_REPO_ID, name: "codeql-variant-analysis-action", owner: @github_org, from_example: :simple)
    @action_repo.default_branch_ref.append_commit({ message: "blah", committer: @github_org.admin }, github_org.admin) do |files|
      files.add(VariantAnalysis::ActionsWorkflowHelper::WORKFLOW_FILE_PATH, "")
    end
    @action_repo.heads.create("main", @action_repo.default_branch_ref.commit.oid, @action_repo.owner)
  end

  def setup
    @azure_client = mock("Azure::Storage::Blob::BlobService")
    @azure_client.stubs(:create_block_blob)
    CodeScanningQueriesHelper.stubs(:azure_client).returns(@azure_client)
    GitHub.flipper[:remote_queries_queries_onboard_repos].enable(@variant_analysis.actor)
    GitHub.stubs(:launch_github_app).returns(@actions_app)
  end

  def add_codeql_db(repo)
    CodeqlDatabase.create!(
      repository: repo, uploader: repo.owner, state: :uploaded, size: 1234,
      name: "#{@variant_analysis.query_language}.zip", content_type: "application/zip", language: @variant_analysis.query_language
    )
  end

  def assert_repo_id_arrays_equal(expected_array, repo_ids_string)
    arr = repo_ids_string.tr("\"[] ", "").split(",").map(&:to_i)
    assert_equal expected_array.to_set, arr.to_set
  end

  def set_up_run_dynamic_workflow_for_success(repo: @controller_repo)
    Launch::Twirp::DeployerClient.any_instance.expects(:rpc)
      .with(:RunDynamicWorkflow, has_entries({
        repository_id: launch_identity(repo),
        workflow_name: "CodeQL query",
        slug: "queries",
        integration_name: "codeql",
      }))
      .returns(
        TwirpResponse.new(
          value: GitHub::Launch::Services::Deploy::RunDynamicWorkflowResponse.new(
            execution_id: "2426991c-1d90-40e4-887a-13e34575710a",
            workflow_run_id: 100,
          ),
          status: 200,
          call_succeeded: true,
      )).once
  end

  context "dotcom only", skip_enterprise: true do
    test "it fails if variant analysis does not exist" do
      ex = assert_raises do
        CodeqlVariantAnalysisProcessingJob.perform_now(
          variant_analysis_id: 12345,
          action_repo_ref: "main",
          repository_ids: [1, 2, 3]
        )
      end

      assert_equal "Invalid variant analysis id 12345", ex.message
    end

    test "it fails the variant analysis if no repositories found" do
      non_existent_repo_ids = [12345, 67890, 54321]
      CodeqlVariantAnalysisProcessingJob.perform_now(
        variant_analysis_id: @variant_analysis.id,
        action_repo_ref: "main",
        repository_ids: non_existent_repo_ids
      )

      @variant_analysis.reload

      assert_equal "no_repos_queried", @variant_analysis.failure_reason
      assert_empty Failbot.reports
      assert_empty @variant_analysis.codeql_variant_analysis_repo_tasks
    end

    test "filters repos to skip from processing and fails if all filtered out" do
      repo_ids = [@public_repo1.id, @private_repo1.id, @private_repo2.id, @no_codeql_db_repo.id]
      non_existent_repo_ids = [12345, 67890, 54321]

      VariantAnalysis::RepositoryValidationHelper.stub_const(:REPOSITORIES_COUNT_LIMIT, 0) do
        CodeqlVariantAnalysisProcessingJob.perform_now(
          variant_analysis_id: @variant_analysis.id,
          action_repo_ref: "main",
          repository_ids: repo_ids + non_existent_repo_ids
        )
      end

      @variant_analysis.reload

      assert_equal "no_repos_queried", @variant_analysis.failure_reason
      assert_empty Failbot.reports
      assert_empty @variant_analysis.codeql_variant_analysis_repo_tasks
      assert_repo_id_arrays_equal [@private_repo1.id, @private_repo2.id], @variant_analysis.privacy_mismatch_repo_ids
      assert_equal 2, @variant_analysis.privacy_mismatch_repo_count
      assert_repo_id_arrays_equal [@no_codeql_db_repo.id], @variant_analysis.no_codeql_db_repo_ids
      assert_equal 1, @variant_analysis.no_codeql_db_repo_count
    end

    test "onboards repos to the bulk builder even when all repos are filtered out" do
      repo_ids = [@public_repo1.id, @private_repo1.id, @private_repo2.id, @no_codeql_db_repo.id]
      non_existent_repo_ids = [12345, 67890, 54321]

      CodeqlBulkBuilderOnboardJob.expects(:perform_later).with(
        repos_and_languages: [[@no_codeql_db_repo.id, @variant_analysis.query_language]]
      ).once

      VariantAnalysis::RepositoryValidationHelper.stub_const(:REPOSITORIES_COUNT_LIMIT, 0) do
        CodeqlVariantAnalysisProcessingJob.perform_now(
          variant_analysis_id: @variant_analysis.id,
          action_repo_ref: "main",
          repository_ids: repo_ids + non_existent_repo_ids
        )
      end

      @variant_analysis.reload

      assert_equal "no_repos_queried", @variant_analysis.failure_reason
      assert_empty Failbot.reports
    end

    test "it fails the variant analysis and reports error if Actions workflow cannot be created" do
      repositories = [@public_repo1, @public_repo2]

      Repository.any_instance.expects(:run_dynamic_workflow)
        .once
        .returns(nil)

      Failbot.expects(:report).with(
        instance_of(VariantAnalysis::ActionsWorkflowHelper::UnableToLaunch),
        "gh.code_scanning.variant_analysis.id": @variant_analysis.id)

      CodeqlVariantAnalysisProcessingJob.perform_now(
        variant_analysis_id: @variant_analysis.id,
        action_repo_ref: "main",
        repository_ids: repositories.map(&:id)
      )

      @variant_analysis.reload

      updated_variant_analysis = CodeqlVariantAnalysis.find_by(id: @variant_analysis.id)
      assert_equal "internal_error", @variant_analysis.failure_reason
    end

    test "it runs successfully" do
      repositories = [@public_repo1, @public_repo2, @private_repo1, @private_repo2, @no_codeql_db_repo]

      valid_repos = [@public_repo1, @public_repo2]

      set_up_run_dynamic_workflow_for_success

      GlobalInstrumenter.expects(:instrument).with(
        "code_scanning.remote_query_run",
        has_entries({
          controller_repository: @controller_repo,
          actor: @variant_analysis.actor,
          language: @variant_analysis.query_language,
          repositories_count: valid_repos.count
        })
      ).once

      CodeqlBulkBuilderOnboardJob.expects(:perform_later).with(
        repos_and_languages: [[@no_codeql_db_repo.id, @variant_analysis.query_language]]
      ).once

      @azure_client.expects(:create_block_blob).once.with do |_, target, contents|
        assert_equal "variant_analyses/#{@variant_analysis.id}/instructions", target

        instructions_body = JSON.parse(contents)
        assert_equal valid_repos.size, instructions_body["repositories"].size

        expected_features = GitHub::CodeQLAction.default_version_flags(@controller_repo).transform_keys(&:to_s)
        assert_equal expected_features, instructions_body["features"]
      end

      CodeqlVariantAnalysisProcessingJob.perform_now(
        variant_analysis_id: @variant_analysis.id,
        action_repo_ref: "main",
        repository_ids: repositories.map(&:id)
      )

      @variant_analysis.reload

      assert_nil @variant_analysis.failure_reason

      assert_equal valid_repos.map(&:id).to_set, @variant_analysis.codeql_variant_analysis_repo_tasks.map(&:repository_id).to_set
      assert_repo_id_arrays_equal [@private_repo1.id, @private_repo2.id], @variant_analysis.privacy_mismatch_repo_ids
      assert_equal 2, @variant_analysis.privacy_mismatch_repo_count
      assert_repo_id_arrays_equal [@no_codeql_db_repo.id], @variant_analysis.no_codeql_db_repo_ids
      assert_equal 1, @variant_analysis.no_codeql_db_repo_count
    end

    test "does not run bulk onboarding if feature flag not enabled for user" do
      GitHub.flipper[:remote_queries_queries_onboard_repos].disable(@variant_analysis.actor)

      repositories = [@public_repo1, @no_codeql_db_repo]

      set_up_run_dynamic_workflow_for_success

      CodeqlBulkBuilderOnboardJob.expects(:perform_later).never

      CodeqlVariantAnalysisProcessingJob.perform_now(
        variant_analysis_id: @variant_analysis.id,
        action_repo_ref: "main",
        repository_ids: repositories.map(&:id)
      )

      @variant_analysis.reload
      assert_nil @variant_analysis.failure_reason
      assert_equal [@public_repo1.id], @variant_analysis.codeql_variant_analysis_repo_tasks.map(&:repository_id)
      assert_repo_id_arrays_equal [@no_codeql_db_repo.id], @variant_analysis.no_codeql_db_repo_ids
      assert_equal 1, @variant_analysis.no_codeql_db_repo_count
    end

    test "runs successfully actions when actions is not enabled on repository owner" do
      controller_repo = create(:public_repository)
      variant_analysis = create(:codeql_variant_analysis, controller_repo: controller_repo)

      repositories = [@public_repo1, @no_codeql_db_repo]

      set_up_run_dynamic_workflow_for_success(repo: controller_repo)

      CodeqlBulkBuilderOnboardJob.expects(:perform_later).never

      CodeqlVariantAnalysisProcessingJob.perform_now(
        variant_analysis_id: variant_analysis.id,
        action_repo_ref: "main",
        repository_ids: repositories.map(&:id)
      )

      variant_analysis.reload

      assert_nil variant_analysis.failure_reason
      refute_nil variant_analysis.actions_workflow_run_id
    end


    test "runs successfully when actios is not enabled on repository, but is enabled on other repository of owner" do

      other_repo = create(:public_repository)
      make_integration_installation integration: @actions_app, repository: other_repo, permissions: { "actions" => :write }

      controller_repo = create(:public_repository, owner: other_repo.owner)
      variant_analysis = create(:codeql_variant_analysis, controller_repo: controller_repo)

      repositories = [@public_repo1, @no_codeql_db_repo]

      set_up_run_dynamic_workflow_for_success(repo: controller_repo)

      CodeqlBulkBuilderOnboardJob.expects(:perform_later).never

      CodeqlVariantAnalysisProcessingJob.perform_now(
        variant_analysis_id: variant_analysis.id,
        action_repo_ref: "main",
        repository_ids: repositories.map(&:id)
      )

      variant_analysis.reload

      assert_nil variant_analysis.failure_reason
      refute_nil variant_analysis.actions_workflow_run_id
    end
  end
end
