# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CodeqlBulkBuilderBatchJobTest < GitHub::TestCase
  fixtures do
    @org = create(:organization, login: "codeql")
    @controller_repo = create(:private_repository, owner: @org, name: "bulk-builder")

    @public_repo = create(:repository)
    @public_repo2 = create(:repository)
    @private_repo = create(:private_repository)
    @to_be_archived_repository = create(:repository)

    typescript_language_name = create(:language_name, name: "TypeScript")
    typescript_language = create(:language, repository: @public_repo, language_name: typescript_language_name)
    typescript_language = create(:language, repository: @public_repo2, language_name: typescript_language_name)
    typescript_language = create(:language, repository: @private_repo, language_name: typescript_language_name)
    typescript_language = create(:language, repository: @to_be_archived_repository, language_name: typescript_language_name)

    @public_repo.onboard_language_for_codeql_bulk_building("javascript")

    make_trusted_oauth_apps_owner
    @code_scanning_app = create(:code_scanning_integration)
  end

  setup do
    disable_feature_flag(:disable_codeql_database_builder_job)
    @to_be_archived_repository.set_archived

    @last_attempted = CodeqlBulkBuilderConfig::NEVER_HAPPENED
  end

  context "dotcom only", skip_enterprise: true do
    test "triggers one workflow per repository" do
      Repository.any_instance.expects(:dispatch_workflow_event).twice
      CodeqlBulkBuilderBatchJob.perform_now(repos_to_build: [[@public_repo.id, "javascript", @last_attempted], [@public_repo2.id, "javascript", @last_attempted]])
    end

    test "doesnt trigger workflow for unknown repo ids" do
      # Generate an ID that we know doesn't correspond to any existing repo
      deleted_repo = create(:repository)
      deleted_repo.destroy

      Repository.any_instance.expects(:dispatch_workflow_event).never
      CodeqlBulkBuilderBatchJob.perform_now(repos_to_build: [[deleted_repo.id, "javascript", @last_attempted]])
    end

    test "deletes non existent repos from config" do
      deleted_repo = create(:repository)
      deleted_repo.onboard_language_for_codeql_bulk_building("javascript")
      deleted_repo.destroy

      assert_changes -> { CodeqlBulkBuilderConfig.count }, from: 2, to: 1 do
        CodeqlBulkBuilderBatchJob.perform_now(repos_to_build: [[deleted_repo.id, "javascript", @last_attempted]])
      end
    end

    test "doesnt trigger workflow for private repos" do
      Repository.any_instance.expects(:dispatch_workflow_event).never
      CodeqlBulkBuilderBatchJob.perform_now(repos_to_build: [[@private_repo.id, "javascript", @last_attempted]])
    end

    test "deletes private repos from config" do
      @private_repo.onboard_language_for_codeql_bulk_building("javascript")

      assert_changes -> { CodeqlBulkBuilderConfig.count }, from: 2, to: 1 do
        CodeqlBulkBuilderBatchJob.perform_now(repos_to_build: [[@private_repo.id, "javascript", @last_attempted]])
      end
    end

    test "doesnt trigger workflow for archived repo" do
      Repository.any_instance.expects(:dispatch_workflow_event).never
      CodeqlBulkBuilderBatchJob.perform_now(repos_to_build: [[@to_be_archived_repository.id, "javascript", @last_attempted]])
    end

    test "deletes archived repos from config" do
      @to_be_archived_repository.onboard_language_for_codeql_bulk_building("javascript")

      assert_changes -> { CodeqlBulkBuilderConfig.count }, from: 2, to: 1 do
        CodeqlBulkBuilderBatchJob.perform_now(repos_to_build: [[@to_be_archived_repository.id, "javascript", @last_attempted]])
      end
    end

    test "doesnt trigger workflow for repos that have fresh databases" do
      create(:codeql_database, repository: @public_repo, language: "javascript")

      Repository.any_instance.expects(:dispatch_workflow_event).never
      CodeqlBulkBuilderBatchJob.perform_now(repos_to_build: [[@public_repo.id, "javascript", @last_attempted]])
    end

    test "does trigger workflow for repos that have databases uploaded by bulk builder" do
      create(:codeql_database, repository: @public_repo, language: "javascript", uploader: @code_scanning_app.bot)

      Repository.any_instance.expects(:dispatch_workflow_event).once
      CodeqlBulkBuilderBatchJob.perform_now(repos_to_build: [[@public_repo.id, "javascript", @last_attempted]])
    end

    test "doesn't trigger workflow for repos that have databases uploaded by a user" do
      create(:codeql_database, repository: @public_repo, language: "javascript", uploader: create(:user))

      Repository.any_instance.expects(:dispatch_workflow_event).never
      CodeqlBulkBuilderBatchJob.perform_now(repos_to_build: [[@public_repo.id, "javascript", @last_attempted]])
    end

    test "deletes repos from config that have databases uploaded by a user" do
      create(:codeql_database, repository: @public_repo, language: "javascript", uploader: create(:user))

      assert_changes -> { CodeqlBulkBuilderConfig.count }, from: 1, to: 0 do
        CodeqlBulkBuilderBatchJob.perform_now(repos_to_build: [[@public_repo.id, "javascript", @last_attempted]])
      end
    end

    test "doesn't trigger workflow for repos that have not been pushed to since last attempt" do
      @public_repo.update!(pushed_at: 14.days.ago)

      Repository.any_instance.expects(:dispatch_workflow_event).never
      CodeqlBulkBuilderBatchJob.perform_now(repos_to_build: [[@public_repo.id, "javascript", 8.days.ago]])
    end

    test "doesn't trigger workflow for repos that have never been pushed to" do
      @public_repo.update!(pushed_at: nil)

      Repository.any_instance.expects(:dispatch_workflow_event).never
      CodeqlBulkBuilderBatchJob.perform_now(repos_to_build: [[@public_repo.id, "javascript", 8.days.ago]])
    end

    test "does trigger workflow for repos that have not been attempted" do
      @public_repo.update!(pushed_at: 14.days.ago)

      Repository.any_instance.expects(:dispatch_workflow_event).once
      CodeqlBulkBuilderBatchJob.perform_now(repos_to_build: [[@public_repo.id, "javascript", CodeqlBulkBuilderConfig::NEVER_HAPPENED]])
    end

    test "ignores databases for other languages" do
      create(:codeql_database, repository: @public_repo, language: "ruby")

      Repository.any_instance.expects(:dispatch_workflow_event).once
      CodeqlBulkBuilderBatchJob.perform_now(repos_to_build: [[@public_repo.id, "javascript", @last_attempted]])
    end

    test "aborts if feature flag is set" do
      enable_feature_flag(:disable_codeql_database_builder_job)

      Repository.any_instance.expects(:dispatch_workflow_event).never
      CodeqlBulkBuilderBatchJob.perform_now(repos_to_build: [[@public_repo.id, "javascript", @last_attempted]])
    end

    test "triggers workflow when no last_attempted value is given" do
      # We added the third value in the array while the code accepting two values was already in production,
      # so this ensures that we can handle batch jobs that were scheduled before the new code was deployed.
      # This test can be removed once the deploy is complete.
      Repository.any_instance.expects(:dispatch_workflow_event).once
      CodeqlBulkBuilderBatchJob.perform_now(repos_to_build: [[@public_repo.id, "javascript"]])
    end

    test "deletes repos without the onboarded language" do
      @private_repo.onboard_language_for_codeql_bulk_building("java")

      Repository.any_instance.expects(:dispatch_workflow_event).never
      assert_changes -> { CodeqlBulkBuilderConfig.count }, from: 2, to: 1 do
        CodeqlBulkBuilderBatchJob.perform_now(repos_to_build: [[@private_repo.id, "java", @last_attempted]])
      end
    end
  end
end
