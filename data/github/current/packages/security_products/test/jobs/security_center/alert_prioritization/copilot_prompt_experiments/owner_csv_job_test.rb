# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityCenter
  module AlertPrioritization
    module CopilotPromptExperiments
      class OwnerCsvJobTest < GitHub::TestCase
        include JobTestHelper
        include ::SecurityCenter::TestFixtures

        fixtures do
          create_org_level_fixtures
          @actor = @owner

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
          ::SecurityCenter::AlertPrioritization::CopilotApiClient.any_instance.stubs(:send_platform_agent_chat_message).returns({
            "answer" => true,
            "confidence" => 100,
            "reasoning" => "Copilot reasoning."
          }.to_json)

          # Stub BlobStorageService.
          ::SecurityCenter::Export::AzureBlobStorageService.any_instance.stubs(:create)
          ::SecurityCenter::Export::AzureBlobStorageService.any_instance.stubs(:store)
          ::SecurityCenter::Export::AzureBlobStorageService.any_instance.stubs(:retrieve).returns(
            ::SecurityCenter::Export::BlobStorageService::BlobServiceResponse.new(
              blob_url: GitHub.url,
              blob_size: 1
            )
          )

          # Stub mailer.
          ::SecurityCenterMailer.stubs(:alert_prioritization_copilot_prompt_experiment_csv_ready).returns(stub(deliver_later: true))
        end

        context ".job_id" do
          test "it returns a string" do
            assert_equal("security_center.alert_prioritization.copilot_prompt_experiments.owner_csv_job.#{@org.id}", OwnerCsvJob.job_id(@org))
          end
        end

        context ".status" do
          context "when a JobStatus exists" do
            test "it returns the JobStatus" do
              job_status = JobStatus.create({ id: OwnerCsvJob.job_id(@org) })
              assert_equal(OwnerCsvJob.status(@org).try(:id), job_status.id)
            end
          end

          context "when a JobStatus does not exist" do
            test "it returns nil" do
              assert_nil(OwnerCsvJob.status(@org))
            end
          end
        end

        context ".perform_later" do
          context "when a JobStatus exists" do
            test "it does not create another JobStatus" do
              job_status = JobStatus.create({ id: OwnerCsvJob.job_id(@org) })

              assert_no_changes(
                -> { OwnerCsvJob.status(@org).try(:id) },
                from: job_status.id
              ) do
                OwnerCsvJob.perform_later(actor: @actor, owner: @org)
              end
            end
          end

          context "when a JobStatus does not exist" do
            test "it creates a JobStatus" do
              assert_changes(
                -> { OwnerCsvJob.status(@org) },
                from: nil
              ) do
                OwnerCsvJob.perform_later(actor: @actor, copilot_api_sleep_sec: 0, owner: @org)
              end
            end
          end
        end

        context ".perform_now" do
          context "when a JobStatus exists" do
            test "it does not create another JobStatus" do
              job_status = JobStatus.create({ id: OwnerCsvJob.job_id(@org) })

              assert_no_changes(
                -> { OwnerCsvJob.status(@org).try(:id) },
                from: job_status.id
              ) do
                OwnerCsvJob.perform_now(actor: @actor, copilot_api_sleep_sec: 0, owner: @org)
              end
            end
          end

          context "when a JobStatus does not exist" do
            test "it creates a JobStatus" do
              assert_changes(
                -> { OwnerCsvJob.status(@org) },
                from: nil
              ) do
                OwnerCsvJob.perform_now(actor: @actor, copilot_api_sleep_sec: 0, owner: @org)
              end
            end
          end
        end

        context "#perform" do
          context 'when feature flag "disable_alert_prioritization_owner_csv_job" is enabled' do
            test "it does not process any repos" do
              ::SecurityCenter::FeatureFlagHelper.stubs(:disable_alert_prioritization_owner_csv_job?).returns(true)

              ::SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).never

              perform_enqueued_jobs(only: OwnerCsvJob) do
                OwnerCsvJob.perform_later(actor: @actor, copilot_api_sleep_sec: 0, owner: @org)
              end
            end

            context 'when feature flag "disable_alert_prioritization_owner_csv_job" is enabled mid-sequence' do
              context "when always_send_email is true" do
                test "it stops processing repos and emails the actor" do
                  OwnerCsvJob.any_instance.stubs(:timeout_sec).returns(0.0)

                  OwnerCsvJob.perform_now(actor: @actor, owner: @org, always_send_email: true, copilot_api_sleep_sec: 0,)
                  assert_enqueued_jobs(1, only: OwnerCsvJob)

                  ::SecurityCenterMailer.expects(:alert_prioritization_copilot_prompt_experiment_csv_ready).returns(stub(deliver_later: true))
                  ::SecurityCenter::FeatureFlagHelper.stubs(:disable_alert_prioritization_owner_csv_job?).returns(true)
                  perform_enqueued_jobs(only: OwnerCsvJob)
                end
              end
            end
          end

          context "failures" do
            context "when the actor does not have an active session" do
              test "it raises an error" do
                assert_raises(AlertPrioritizationHelper::UserMissingActiveSessionError) do
                  OwnerCsvJob.perform_now(actor: create(:user), copilot_api_sleep_sec: 0, owner: @org)
                end
              end
            end

            context "when Blackbird fails" do
              test "it does not raise an error" do
                AlertPrioritizationHelper.stubs(:is_repo_indexed_for_semantic_search).raises(StandardError)

                assert_nothing_raised do
                  OwnerCsvJob.perform_now(actor: @actor, copilot_api_sleep_sec: 0, owner: @org)
                end
              end
            end

            context "when a CAPI request fails" do
              test "it does not raise an error" do
                ::SecurityCenter::AlertPrioritization::CopilotApiClient.any_instance.stubs(:send_platform_agent_chat_message).raises(StandardError)

                assert_nothing_raised do
                  OwnerCsvJob.perform_now(actor: @actor, copilot_api_sleep_sec: 0, owner: @org)
                end
              end
            end
          end

          test "it succeeds" do
            blob_storage_key = SecureRandom.uuid
            ::SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).with(blob_storage_key, true)
            ::SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).with(
              blob_storage_key,
              [
                "Repo ID",
                "Repo NWO",
                "Repo is archived?",
                "Repo is public?",
                "Is repo deployed to production? - Known answer",
                "Is repo deployed to production? - Copilot prompt",
                "Is repo deployed to production? - Copilot's answer",
                "Is repo deployed to production? - Copilot's confidence",
                "Is repo deployed to production? - Copilot's reasoning",
                "Does repo handle PII? - Known answer",
                "Does repo handle PII? - Copilot prompt",
                "Does repo handle PII? - Copilot's answer",
                "Does repo handle PII? - Copilot's confidence",
                "Does repo handle PII? - Copilot's reasoning",
                "Is repo business critical? - Known answer",
                "Is repo business critical? - Copilot prompt",
                "Is repo business critical? - Copilot's answer",
                "Is repo business critical? - Copilot's confidence",
                "Is repo business critical? - Copilot's reasoning",
                "Is repo internet accessible? - Known answer",
                "Is repo internet accessible? - Copilot prompt",
                "Is repo internet accessible? - Copilot's answer",
                "Is repo internet accessible? - Copilot's confidence",
                "Is repo internet accessible? - Copilot's reasoning\n"
              ].join(","),
              OwnerCsvJob::CSV_FEATURE,
              true
            )

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
                  OwnerCsvJob::DEFAULT_PROMPT_DEPLOYED_TO_PROD,
                  true,
                  100,
                  "Copilot reasoning.",
                  "",
                  "\"#{OwnerCsvJob::DEFAULT_PROMPT_HANDLES_PII}\"",
                  true,
                  100,
                  "Copilot reasoning.",
                  "",
                  "\"#{OwnerCsvJob::DEFAULT_PROMPT_BUSINESS_CRITICAL}\"",
                  true,
                  100,
                  "Copilot reasoning.",
                  "",
                  OwnerCsvJob::DEFAULT_PROMPT_INTERNET_ACCESSIBLE,
                  true,
                  100,
                  "Copilot reasoning.\n"
                ].join(","),
                OwnerCsvJob::CSV_FEATURE,
                true
              )
            end

            OwnerCsvJob.perform_now(actor: @actor, blob_storage_key:, copilot_api_sleep_sec: 0, owner: @org)
          end

          test "it sends an email when the job sequence is complete" do
            OwnerCsvJob.any_instance.stubs(:timeout_sec).returns(0.0)
            ::SecurityCenterMailer.expects(:alert_prioritization_copilot_prompt_experiment_csv_ready).once.returns(stub(deliver_later: true))

            assert_performed_jobs(@org.repositories.size + 1, only: OwnerCsvJob) do
              OwnerCsvJob.perform_later(actor: @actor, copilot_api_sleep_sec: 0, owner: @org)
            end
          end

          context "when Copilot returns data in an unexpected format" do
            test "it does not raise an error" do
              ::SecurityCenter::AlertPrioritization::CopilotApiClient.any_instance.stubs(:send_platform_agent_chat_message).returns("Test")

              assert_nothing_raised do
                OwnerCsvJob.perform_now(actor: @actor, copilot_api_sleep_sec: 0, owner: @org)
              end
            end
          end

          test "it skips prompts whose values are nil" do
            blob_storage_key = SecureRandom.uuid
            ::SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).with(blob_storage_key, true)
            ::SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).with(
              blob_storage_key,
              [
                "Repo ID",
                "Repo NWO",
                "Repo is archived?",
                "Repo is public?",
                "Does repo handle PII? - Known answer",
                "Does repo handle PII? - Copilot prompt",
                "Does repo handle PII? - Copilot's answer",
                "Does repo handle PII? - Copilot's confidence",
                "Does repo handle PII? - Copilot's reasoning",
                "Is repo business critical? - Known answer",
                "Is repo business critical? - Copilot prompt",
                "Is repo business critical? - Copilot's answer",
                "Is repo business critical? - Copilot's confidence",
                "Is repo business critical? - Copilot's reasoning",
                "Is repo internet accessible? - Known answer",
                "Is repo internet accessible? - Copilot prompt",
                "Is repo internet accessible? - Copilot's answer",
                "Is repo internet accessible? - Copilot's confidence",
                "Is repo internet accessible? - Copilot's reasoning\n"
              ].join(","),
              OwnerCsvJob::CSV_FEATURE,
              true
            )

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
                  "\"#{OwnerCsvJob::DEFAULT_PROMPT_HANDLES_PII}\"",
                  true,
                  100,
                  "Copilot reasoning.",
                  "",
                  "\"#{OwnerCsvJob::DEFAULT_PROMPT_BUSINESS_CRITICAL}\"",
                  true,
                  100,
                  "Copilot reasoning.",
                  "",
                  OwnerCsvJob::DEFAULT_PROMPT_INTERNET_ACCESSIBLE,
                  true,
                  100,
                  "Copilot reasoning.\n"
                ].join(","),
                OwnerCsvJob::CSV_FEATURE,
                true
              )
            end

            OwnerCsvJob.perform_now(actor: @actor, blob_storage_key:, copilot_api_sleep_sec: 0, owner: @org, prompt_deployed_to_prod: nil)
          end
        end
      end
    end
  end
end
