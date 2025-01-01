# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityCenter
  module AlertPrioritization
    module CopilotPromptExperiments
      class OwnerRepoClassificationSliceJobTest < GitHub::TestCase
        include JobTestHelper
        include ::SecurityCenter::TestFixtures

        fixtures do
          create_org_level_fixtures
          @actor = @owner

          # Create two more repositories in addition to two created above to make sure each of 4 slices has one repo
          2.times do
            create(:private_repository, owner: @org)
          end

          # Create a production deployment for all repos except the last.
          @org.repositories.order(:id).find_each.with_index do |repo, idx|
            next if idx == @org.repositories.size - 1

            create(:deployment, latest_environment: "production", repository: repo, creator: @owner)
          end

          GitHub.flipper[:copilot_knowledge_bases_fgp].enable
          create(:copilot_chat_integration)
        end

        setup do
          ::SecurityCenter::FeatureFlagHelper.stubs(:show_repo_id_in_alert_prioritization_experiment_csv?).returns(true)
          ::SecurityCenter::FeatureFlagHelper.stubs(:disable_alert_prioritization_owner_csv_job?).returns(false)

          # Stub Blackbird API calls.
          AlertPrioritizationHelper.stubs(:is_repo_indexed_for_semantic_search).returns(true)

          # Stub Copilot API.
          ::SecurityCenter::AlertPrioritization::CopilotApiClient.any_instance.stubs(:async_send_platform_agent_chat_message).returns(
            ::Promise.resolve({
              "answer" => true,
              "confidence" => 100,
              "reasoning" => "Copilot reasoning.",
              "code_search_success" => true
            }.to_json)
          )

          # Stub BlobStorageService.
          ::SecurityCenter::Export::AzureBlobStorageService.any_instance.stubs(:create)
          ::SecurityCenter::Export::AzureBlobStorageService.any_instance.stubs(:store)
          ::SecurityCenter::Export::AzureBlobStorageService.any_instance.stubs(:retrieve).returns(
            ::SecurityCenter::Export::BlobStorageService::BlobServiceResponse.new(
              blob_url: GitHub.url,
              blob_size: 1
            )
          )
        end

        context ".job_id" do
          test "it returns a string" do
            assert_equal("security_center.alert_prioritization.copilot_prompt_experiments.owner_repo_classification_slice_job.#{@org.id}.0", OwnerRepoClassificationSliceJob.job_id(@org, 0))
          end
        end

        context ".status" do
          context "when a JobStatus exists" do
            test "it returns the JobStatus" do
              job_status = JobStatus.create({ id: OwnerRepoClassificationSliceJob.job_id(@org, 0) })
              assert_equal(OwnerRepoClassificationSliceJob.status(@org, 0).try(:id), job_status.id)
            end
          end

          context "when a JobStatus does not exist" do
            test "it returns nil" do
              assert_nil(OwnerRepoClassificationSliceJob.status(@org, 0))
            end
          end
        end

        context ".perform_later" do
          context "when a JobStatus exists" do
            test "it does not create another JobStatus" do
              job_status = JobStatus.create({ id: OwnerRepoClassificationSliceJob.job_id(@org, 0) })

              assert_no_changes(
                -> { OwnerRepoClassificationSliceJob.status(@org, 0).try(:id) },
                from: job_status.id
              ) do
                OwnerRepoClassificationSliceJob.perform_later(actor: @actor, blob_storage_key: "", owner: @org, slice_id: 0)
              end
            end
          end

          context "when a JobStatus does not exist" do
            test "it creates a JobStatus" do
              assert_changes(
                -> { OwnerRepoClassificationSliceJob.status(@org, 0) },
                from: nil
              ) do
                OwnerRepoClassificationSliceJob.perform_later(actor: @actor, blob_storage_key: "", owner: @org, slice_id: 0)
              end
            end
          end
        end

        context ".perform_now" do
          context "when a JobStatus exists" do
            test "it does not create another JobStatus" do
              job_status = JobStatus.create({ id: OwnerRepoClassificationSliceJob.job_id(@org, 0) })

              assert_no_changes(
                -> { OwnerRepoClassificationSliceJob.status(@org, 0).try(:id) },
                from: job_status.id
              ) do
                OwnerRepoClassificationSliceJob.perform_now(actor: @actor, blob_storage_key: "", owner: @org, slice_id: 0)
              end
            end
          end

          context "when a JobStatus does not exist" do
            test "it creates a JobStatus" do
              assert_changes(
                -> { OwnerRepoClassificationSliceJob.status(@org, 0) },
                from: nil
              ) do
                OwnerRepoClassificationSliceJob.perform_now(actor: @actor, blob_storage_key: "", owner: @org, slice_id: 0)
              end
            end
          end
        end

        context "#perform" do
          context 'when feature flag "disable_alert_prioritization_owner_csv_job" is enabled' do
            test "it does not process any repos" do
              ::SecurityCenter::FeatureFlagHelper.stubs(:disable_alert_prioritization_owner_csv_job?).returns(true)

              ::SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).never

              perform_enqueued_jobs(only: OwnerRepoClassificationSliceJob) do
                OwnerRepoClassificationSliceJob.perform_later(actor: @actor, blob_storage_key: "", owner: @org, slice_id: 0)
              end
            end

            context 'when feature flag "disable_alert_prioritization_owner_csv_job" is enabled mid-sequence' do
              test "it stops processing repos" do
                OwnerRepoClassificationSliceJob.any_instance.stubs(:timeout_sec).returns(0.0)

                OwnerRepoClassificationSliceJob.perform_now(actor: @actor, blob_storage_key: "", owner: @org, slice_id: 0)
                assert_enqueued_jobs(1, only: OwnerRepoClassificationSliceJob)

                ::SecurityCenter::FeatureFlagHelper.stubs(:disable_alert_prioritization_owner_csv_job?).returns(true)
                AlertPrioritizationHelper.expects(:is_repo_indexed_for_semantic_search).never
                perform_enqueued_jobs(only: OwnerRepoClassificationSliceJob)
              end
            end
          end

          context "failures" do
            context "when the actor does not have an active session" do
              test "it raises an error" do
                assert_raises(AlertPrioritizationHelper::UserMissingActiveSessionError) do
                  OwnerRepoClassificationSliceJob.perform_now(actor: create(:user), blob_storage_key: "", owner: @org, slice_id: 0)
                end
              end
            end

            context "when Blackbird fails" do
              test "it does not raise an error" do
                AlertPrioritizationHelper.stubs(:is_repo_indexed_for_semantic_search).returns(Promise.new.reject(StandardError))

                assert_nothing_raised do
                  OwnerRepoClassificationSliceJob.perform_now(actor: @actor, blob_storage_key: "", owner: @org, slice_id: 0)
                end
              end
            end

            context "when a CAPI request fails" do
              test "it does not raise an error" do
                ::SecurityCenter::AlertPrioritization::CopilotApiClient.any_instance.stubs(:async_send_platform_agent_chat_message).returns(Promise.new.reject(StandardError))

                assert_nothing_raised do
                  OwnerRepoClassificationSliceJob.perform_now(actor: @actor, blob_storage_key: "", owner: @org, slice_id: 0)
                end
              end
            end
          end

          test "it skips repos that already have kv value populated" do
            @org.repositories.each do |repo|
              ::SecurityCenter::KV.store.set(OwnerRepoClassificationSliceJob.repo_results_kv_key(repo.id, is_experimental: false), "woof")
            end

            OwnerRepoClassificationSliceJob.any_instance.expects(:write_csv_row).never

            OwnerRepoClassificationSliceJob.perform_now(actor: @actor, blob_storage_key: SecureRandom.uuid, owner: @org, slice_id: 0)
          end

          test "it succeeds" do
            blob_storage_key = SecureRandom.uuid

            # Stub our KV store, so we can test it separately from generic GitHub:KV, which is used by job for storing jobstatus.
            storage = {}
            expected_storage = {}
            store = SecurityCenter::KV.store
            store.stubs(:set).with do |key, value|
              storage[key] = value
            end

            ::SecurityCenter::KV.stubs(:store).returns(store)

            @org.repositories.order(:id).find_each.with_index do |repo, idx|
              has_prod_deployment = idx == @org.repositories.size - 1 ? nil : true
              ::SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).with(
                blob_storage_key,
                [
                  repo.id,
                  repo.name_with_display_owner,
                  false,
                  false,
                  has_prod_deployment,
                  OwnerRepoClassificationControlJob::DEFAULT_PROMPT_DEPLOYED_TO_PROD,
                  true,
                  100,
                  "Copilot reasoning.",
                  "",
                  "\"#{OwnerRepoClassificationControlJob::DEFAULT_PROMPT_HANDLES_PII}\"",
                  true,
                  100,
                  "Copilot reasoning.",
                  "",
                  "\"#{OwnerRepoClassificationControlJob::DEFAULT_PROMPT_BUSINESS_CRITICAL}\"",
                  true,
                  100,
                  "Copilot reasoning.",
                  "",
                  OwnerRepoClassificationControlJob::DEFAULT_PROMPT_INTERNET_ACCESSIBLE,
                  true,
                  100,
                  "Copilot reasoning.\n"
                ].join(","),
                OwnerRepoClassificationControlJob::CSV_FEATURE,
              )

              expected_storage[OwnerRepoClassificationSliceJob::KV_PREFIX + repo.id.to_s] =
                [
                  OwnerRepoClassificationSliceJob::RepositoryEvaluationPromptResult.new(
                    prompt_id: "deployed_to_prod",
                    known_answer: has_prod_deployment,
                    copilot_prompt: OwnerRepoClassificationControlJob::DEFAULT_PROMPT_DEPLOYED_TO_PROD,
                    copilot_answer: true,
                    copilot_confidence: 100,
                    copilot_reasoning: "Copilot reasoning."
                  ),
                  OwnerRepoClassificationSliceJob::RepositoryEvaluationPromptResult.new(
                    prompt_id: "handles_pii",
                    known_answer: nil,
                    copilot_prompt: OwnerRepoClassificationControlJob::DEFAULT_PROMPT_HANDLES_PII,
                    copilot_answer: true,
                    copilot_confidence: 100,
                    copilot_reasoning: "Copilot reasoning."
                  ),
                  OwnerRepoClassificationSliceJob::RepositoryEvaluationPromptResult.new(
                    prompt_id: "business_critical",
                    known_answer: nil,
                    copilot_prompt: OwnerRepoClassificationControlJob::DEFAULT_PROMPT_BUSINESS_CRITICAL,
                    copilot_answer: true,
                    copilot_confidence: 100,
                    copilot_reasoning: "Copilot reasoning."
                  ),
                  OwnerRepoClassificationSliceJob::RepositoryEvaluationPromptResult.new(
                    prompt_id: "internet_accessible",
                    known_answer: nil,
                    copilot_prompt: OwnerRepoClassificationControlJob::DEFAULT_PROMPT_INTERNET_ACCESSIBLE,
                    copilot_answer: true,
                    copilot_confidence: 100,
                    copilot_reasoning: "Copilot reasoning."
                  )
                ].to_json
            end

            OwnerRepoClassificationSliceJob.perform_now(actor: @actor, blob_storage_key:, owner: @org, slice_id: 0)
            OwnerRepoClassificationSliceJob.perform_now(actor: @actor, blob_storage_key:, owner: @org, slice_id: 1)
            OwnerRepoClassificationSliceJob.perform_now(actor: @actor, blob_storage_key:, owner: @org, slice_id: 2)
            OwnerRepoClassificationSliceJob.perform_now(actor: @actor, blob_storage_key:, owner: @org, slice_id: 3)

            assert_equal(expected_storage, storage)
          end

          test "it updates job status once the job sequence is complete" do
            OwnerRepoClassificationSliceJob.any_instance.stubs(:timeout_sec).returns(0.0)
            ::JobStatus.any_instance.expects(:success!).once

            # The job will be enqueued twice, once for data processing, plus once for final no-op job.
            assert_performed_jobs(2, only: OwnerRepoClassificationSliceJob) do
              OwnerRepoClassificationSliceJob.perform_later(actor: @actor, blob_storage_key: "", owner: @org, slice_id: 0)
            end
          end

          context "when Copilot returns data in an unexpected format" do
            test "it does not raise an error" do
              ::SecurityCenter::AlertPrioritization::CopilotApiClient.any_instance.stubs(:async_send_platform_agent_chat_message).returns(Promise.resolve("Exception"))

              assert_nothing_raised do
                OwnerRepoClassificationSliceJob.perform_now(actor: @actor, blob_storage_key: "", owner: @org, slice_id: 0)
              end
            end
          end

          test "it skips prompts whose values are nil" do
            blob_storage_key = SecureRandom.uuid

            @org.repositories.order(:id).find_each.with_index do |repo, idx|
              has_prod_deployment = idx == @org.repositories.size - 1 ? nil : true
              ::SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).with(
                blob_storage_key,
                [
                  repo.id,
                  repo.name_with_display_owner,
                  false,
                  false,
                  "",
                  "\"#{OwnerRepoClassificationControlJob::DEFAULT_PROMPT_HANDLES_PII}\"",
                  true,
                  100,
                  "Copilot reasoning.",
                  "",
                  "\"#{OwnerRepoClassificationControlJob::DEFAULT_PROMPT_BUSINESS_CRITICAL}\"",
                  true,
                  100,
                  "Copilot reasoning.",
                  "",
                  OwnerRepoClassificationControlJob::DEFAULT_PROMPT_INTERNET_ACCESSIBLE,
                  true,
                  100,
                  "Copilot reasoning.\n"
                ].join(","),
                OwnerRepoClassificationControlJob::CSV_FEATURE,
              )
            end

            OwnerRepoClassificationSliceJob.perform_now(actor: @actor, blob_storage_key:, owner: @org, slice_id: 0, prompt_deployed_to_prod: nil)
            OwnerRepoClassificationSliceJob.perform_now(actor: @actor, blob_storage_key:, owner: @org, slice_id: 1, prompt_deployed_to_prod: nil)
            OwnerRepoClassificationSliceJob.perform_now(actor: @actor, blob_storage_key:, owner: @org, slice_id: 2, prompt_deployed_to_prod: nil)
            OwnerRepoClassificationSliceJob.perform_now(actor: @actor, blob_storage_key:, owner: @org, slice_id: 3, prompt_deployed_to_prod: nil)
          end

          context "with experimental prompt" do
            test "it does not skip repos that already have kv value populated" do
              @org.repositories.each do |repo|
                ::SecurityCenter::KV.store.set(OwnerRepoClassificationSliceJob.repo_results_kv_key(repo.id, is_experimental: true), "woof")
              end

              OwnerRepoClassificationSliceJob.any_instance.expects(:write_csv_row).once

              OwnerRepoClassificationSliceJob.perform_now(actor: @actor, blob_storage_key: SecureRandom.uuid, owner: @org, slice_id: 0, prompt_experimental: "woof")
            end

            test "it succeeds" do
              blob_storage_key = SecureRandom.uuid
              prompt_experimental = "woof woof barr barr"

              # Stub our KV store, so we can test it separately from generic GitHub:KV, which is used by job for storing jobstatus.
              storage = {}
              expected_storage = {}
              store = SecurityCenter::KV.store
              store.stubs(:set).with do |key, value|
                storage[key] = value
              end
              ::SecurityCenter::KV.stubs(:store).returns(store)

              @org.repositories.order(:id).find_each.with_index do |repo, idx|
                has_prod_deployment = idx == @org.repositories.size - 1 ? nil : true
                ::SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).with(
                  blob_storage_key,
                  [
                    repo.id,
                    repo.name_with_display_owner,
                    false,
                    false,
                    "",
                    prompt_experimental,
                    true,
                    100,
                    "Copilot reasoning.\n"
                  ].join(","),
                  OwnerRepoClassificationControlJob::CSV_FEATURE,
                )

                expected_storage["#{OwnerRepoClassificationSliceJob::KV_PREFIX}experimental.#{repo.id}"] =
                  [
                    OwnerRepoClassificationSliceJob::RepositoryEvaluationPromptResult.new(
                      prompt_id: "experimental",
                      known_answer: nil,
                      copilot_prompt: prompt_experimental,
                      copilot_answer: true,
                      copilot_confidence: 100,
                      copilot_reasoning: "Copilot reasoning."
                    )
                  ].to_json
              end

              OwnerRepoClassificationSliceJob.perform_now(actor: @actor, blob_storage_key:, owner: @org, slice_id: 0, prompt_experimental:)
              OwnerRepoClassificationSliceJob.perform_now(actor: @actor, blob_storage_key:, owner: @org, slice_id: 1, prompt_experimental:)
              OwnerRepoClassificationSliceJob.perform_now(actor: @actor, blob_storage_key:, owner: @org, slice_id: 2, prompt_experimental:)
              OwnerRepoClassificationSliceJob.perform_now(actor: @actor, blob_storage_key:, owner: @org, slice_id: 3, prompt_experimental:)

              assert_equal(expected_storage, storage)
            end
          end
        end
      end
    end
  end
end
