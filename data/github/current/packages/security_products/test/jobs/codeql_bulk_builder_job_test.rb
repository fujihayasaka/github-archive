# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CodeqlBulkBuilderJobTest < GitHub::TestCase
  fixtures do
    @public_repo = create(:repository)
    @public_repo2 = create(:repository)
    @public_repo_java = create(:repository)
    @public_repo_swift = create(:repository)
    @private_repo = create(:private_repository)
    @to_be_archived_repository = create(:repository)

    @public_repo.onboard_language_for_codeql_bulk_building("javascript")
    @public_repo.onboard_language_for_codeql_bulk_building("java")
    @public_repo2.onboard_language_for_codeql_bulk_building("javascript")
    @public_repo_java.onboard_language_for_codeql_bulk_building("java")
    @public_repo_swift.onboard_language_for_codeql_bulk_building("swift")
    @private_repo.onboard_language_for_codeql_bulk_building("javascript")
    @to_be_archived_repository.onboard_language_for_codeql_bulk_building("javascript")
  end

  setup do
    GitHub.flipper[:disable_codeql_database_builder_job].disable
    GitHub.flipper[:code_scanning_codeql_disable_bulk_builder_swift].disable
    @to_be_archived_repository.set_archived
  end

  context "dotcom only", skip_enterprise: true do
    test "is scheduled on dotcom" do
      assert_predicate CodeqlBulkBuilderJob, :enabled?
    end

    test "does not enqueue if feature flag is set" do
      GitHub.flipper[:disable_codeql_database_builder_job].enable

      assert_enqueued_jobs(0) do
        CodeqlBulkBuilderJob.perform_now
      end
    end

    test "does not refresh repos if all are up to date" do
      CodeqlBulkBuilderConfig.update_all(last_attempted: 1.hour.ago)
      assert_enqueued_jobs(0) do
        CodeqlBulkBuilderJob.perform_now
      end
    end

    test "enqueues a batch per language with multiple repos" do
      CodeqlBulkBuilderJob.stub_const(:FRESHNESS_DURATION, 1.hour) do
        CodeqlBulkBuilderJob.stub_const(:SCHEDULE_INTERVAL, 1.hour) do
          assert_enqueued_jobs(3, only: CodeqlBulkBuilderBatchJob) do
            assert_enqueued_with(job: CodeqlBulkBuilderBatchJob, args: proc { |args|
              args[0][:repos_to_build].map { |id, _, _| id }.to_set == [@public_repo.id, @public_repo2.id, @private_repo.id, @to_be_archived_repository.id].to_set &&
              args[0][:repos_to_build].map { |_, language, _| language }.uniq == ["javascript"] &&
              args[0][:repos_to_build].map { |_, _, last_attempted| last_attempted }.uniq == [CodeqlBulkBuilderConfig::NEVER_HAPPENED]
            }) do
              assert_enqueued_with(job: CodeqlBulkBuilderBatchJob, args: proc { |args|
                args[0][:repos_to_build].map { |id, _, _| id }.to_set == [@public_repo.id, @public_repo_java.id].to_set &&
                args[0][:repos_to_build].map { |_, language, _| language }.uniq == ["java"] &&
                args[0][:repos_to_build].map { |_, _, last_attempted| last_attempted }.uniq == [CodeqlBulkBuilderConfig::NEVER_HAPPENED]
              }) do
                assert_enqueued_with(job: CodeqlBulkBuilderBatchJob, args: proc { |args|
                  args[0][:repos_to_build].map { |id, _, _| id }.to_set == [@public_repo_swift.id].to_set &&
                  args[0][:repos_to_build].map { |_, language, _| language }.uniq == ["swift"] &&
                  args[0][:repos_to_build].map { |_, _, last_attempted| last_attempted }.uniq == [CodeqlBulkBuilderConfig::NEVER_HAPPENED]
                }) do
                  CodeqlBulkBuilderJob.perform_now
                end
              end
            end
          end
        end
      end
    end

    test "enqueues a batch even if repository has a database" do
      # Create a database for public_repo, so that it shouldn't be built
      create(:codeql_database, repository: @public_repo, language: "javascript")
      assert_enqueued_jobs(3, only: CodeqlBulkBuilderBatchJob) do
        assert_enqueued_with(job: CodeqlBulkBuilderBatchJob, args: proc {
          |args| args[0][:repos_to_build].map { |id, language, _| [id, language] }.include?([@public_repo.id, "javascript"])
        }) do
          CodeqlBulkBuilderJob.perform_now
        end
      end
    end

    test "passes the last_attempted value to the batch" do
      # We need to ensure that @public_repo gets scheduled first
      CodeqlBulkBuilderConfig.update_all(last_attempted: 8.days.ago)
      config = CodeqlBulkBuilderConfig.find_by!(repository: @public_repo, language: "javascript")
      config.update!(last_attempted: 10.days.ago)

      assert_enqueued_jobs(3, only: CodeqlBulkBuilderBatchJob) do
        assert_enqueued_with(job: CodeqlBulkBuilderBatchJob, args: proc { |args|
          args[0][:repos_to_build].include?([@public_repo.id, "javascript", config.last_attempted])
        }) do
          CodeqlBulkBuilderJob.perform_now
        end
      end
    end

    test "batches are spread across the hour" do
      Timecop.freeze do
        assert_enqueued_jobs(7, only: CodeqlBulkBuilderBatchJob) do
          CodeqlBulkBuilderJob.stub_const(:FRESHNESS_DURATION, 1.hour) do
            CodeqlBulkBuilderJob.stub_const(:SCHEDULE_INTERVAL, 1.hour) do
              CodeqlBulkBuilderJob.stub_const(:BATCH_SIZE, 1) do
                CodeqlBulkBuilderJob.perform_now

                4.times do |batch_num|
                  wait = CodeqlBulkBuilderJob::SCHEDULE_INTERVAL * batch_num / 4
                  assert_enqueued_with(job: CodeqlBulkBuilderBatchJob, at: wait.from_now, args: proc { |args| args[0][:repos_to_build].all? { |_, language, _| language == "javascript" } })
                end

                2.times do |batch_num|
                  wait = CodeqlBulkBuilderJob::SCHEDULE_INTERVAL * batch_num / 2
                  assert_enqueued_with(job: CodeqlBulkBuilderBatchJob, at: wait.from_now, args: proc { |args| args[0][:repos_to_build].all? { |_, language, _| language == "java" } })
                end

                assert_enqueued_with(job: CodeqlBulkBuilderBatchJob, at: 0.seconds.from_now, args: proc { |args| args[0][:repos_to_build].all? { |_, language, _| language == "swift" } })
              end
            end
          end
        end
      end
    end

    context "when Swift is disabled" do
      test "enqueues a batch per language with multiple repos" do
        GitHub.flipper[:code_scanning_codeql_disable_bulk_builder_swift].enable

        CodeqlBulkBuilderJob.stub_const(:FRESHNESS_DURATION, 1.hour) do
          CodeqlBulkBuilderJob.stub_const(:SCHEDULE_INTERVAL, 1.hour) do
            assert_enqueued_jobs(2, only: CodeqlBulkBuilderBatchJob) do
              assert_enqueued_with(job: CodeqlBulkBuilderBatchJob, args: proc { |args|
                args[0][:repos_to_build].map { |id, _, _| id }.to_set == [@public_repo.id, @public_repo2.id, @private_repo.id, @to_be_archived_repository.id].to_set
              }) do
                assert_enqueued_with(job: CodeqlBulkBuilderBatchJob, args: proc { |args|
                  args[0][:repos_to_build].map { |id, _, _| id }.to_set == [@public_repo.id, @public_repo_java.id].to_set &&
                  args[0][:repos_to_build].map { |_, language, _| language }.uniq == ["java"]
                }) do
                  CodeqlBulkBuilderJob.perform_now
                end
              end
            end
          end
        end
      end

      test "batches are spread across the hour" do
        GitHub.flipper[:code_scanning_codeql_disable_bulk_builder_swift].enable

        Timecop.freeze do
          assert_enqueued_jobs(6, only: CodeqlBulkBuilderBatchJob) do
            CodeqlBulkBuilderJob.stub_const(:FRESHNESS_DURATION, 1.hour) do
              CodeqlBulkBuilderJob.stub_const(:SCHEDULE_INTERVAL, 1.hour) do
                CodeqlBulkBuilderJob.stub_const(:BATCH_SIZE, 1) do
                  CodeqlBulkBuilderJob.perform_now

                  4.times do |batch_num|
                    wait = CodeqlBulkBuilderJob::SCHEDULE_INTERVAL * batch_num / 4
                    assert_enqueued_with(job: CodeqlBulkBuilderBatchJob, at: wait.from_now, args: proc { |args| args[0][:repos_to_build].all? { |_, language, _| language == "javascript" } })
                  end

                  2.times do |batch_num|
                    wait = CodeqlBulkBuilderJob::SCHEDULE_INTERVAL * batch_num / 2
                    assert_enqueued_with(job: CodeqlBulkBuilderBatchJob, at: wait.from_now, args: proc { |args| args[0][:repos_to_build].all? { |_, language, _| language == "java" } })
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
