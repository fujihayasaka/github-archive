# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityCenter
  module AlertPrioritization
    module CopilotPromptExperiments
      class OwnerRepoClassificationControlJobTest < GitHub::TestCase
        include JobTestHelper
        include ::SecurityCenter::TestFixtures
        include SecurityCenter::TestHelpers

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
            assert_equal("security_center.alert_prioritization.copilot_prompt_experiments.owner_repo_classification_control_job.#{@org.id}", OwnerRepoClassificationControlJob.job_id(@org))
          end
        end

        context ".status" do
          context "when a JobStatus exists" do
            test "it returns the JobStatus" do
              job_status = JobStatus.create({ id: OwnerRepoClassificationControlJob.job_id(@org) })
              assert_equal(OwnerRepoClassificationControlJob.status(@org).try(:id), job_status.id)
            end
          end

          context "when a JobStatus does not exist" do
            test "it returns nil" do
              assert_nil(OwnerRepoClassificationControlJob.status(@org))
            end
          end
        end

        context ".perform_later" do
          context "when a JobStatus exists" do
            test "it does not create another JobStatus" do
              job_status = JobStatus.create({ id: OwnerRepoClassificationControlJob.job_id(@org) })

              assert_no_changes(
                -> { OwnerRepoClassificationControlJob.status(@org).try(:id) },
                from: job_status.id
              ) do
                perform_enqueued_jobs(only: OwnerRepoClassificationControlJob) do
                  OwnerRepoClassificationControlJob.perform_later(actor: @actor, owner: @org)
                end
              end
            end
          end

          context "when a JobStatus does not exist" do
            test "it creates a JobStatus" do
              assert_changes(
                -> { OwnerRepoClassificationControlJob.status(@org) },
                from: nil
              ) do
                perform_enqueued_jobs(only: OwnerRepoClassificationControlJob) do
                  OwnerRepoClassificationControlJob.perform_later(actor: @actor, owner: @org)
                end
              end
            end
          end
        end

        context ".perform_now" do
          context "when a JobStatus exists" do
            test "it does not create another JobStatus" do
              job_status = JobStatus.create({ id: OwnerRepoClassificationControlJob.job_id(@org) })

              assert_no_changes(
                -> { OwnerRepoClassificationControlJob.status(@org).try(:id) },
                from: job_status.id
              ) do
                OwnerRepoClassificationControlJob.perform_now(actor: @actor, owner: @org)
              end
            end
          end

          context "when a JobStatus does not exist" do
            test "it creates a JobStatus" do
              assert_changes(
                -> { OwnerRepoClassificationControlJob.status(@org) },
                from: nil
              ) do
                OwnerRepoClassificationControlJob.perform_now(actor: @actor, owner: @org)
              end
            end
          end
        end

        context "#perform" do
          context 'when feature flag "disable_alert_prioritization_owner_csv_job" is enabled' do
            test "it does not start" do
              ::SecurityCenter::FeatureFlagHelper.stubs(:disable_alert_prioritization_owner_csv_job?).returns(true)

              ::SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).never

              perform_enqueued_jobs(only: OwnerRepoClassificationControlJob) do
                OwnerRepoClassificationControlJob.perform_later(actor: @actor, owner: @org)
              end
            end

            context 'when feature flag "disable_alert_prioritization_owner_csv_job" is enabled mid-sequence' do
              test "it stops re-running itself" do
                OwnerRepoClassificationControlJob.any_instance.stubs(:timeout_sec).returns(0.0)

                ::SecurityCenterMailer.expects(:alert_prioritization_copilot_prompt_experiment_csv_ready).never
                ::SecurityCenter::FeatureFlagHelper.stubs(:disable_alert_prioritization_owner_csv_job?).returns(true)

                assert_enqueued_jobs(0) do
                  OwnerRepoClassificationControlJob.perform_now(actor: @actor, owner: @org)
                end
              end
            end
          end

          context "failures" do
            context "when the actor does not have an active session" do
              test "it raises an error" do
                assert_raises(AlertPrioritizationHelper::UserMissingActiveSessionError) do
                  OwnerRepoClassificationControlJob.perform_now(actor: create(:user), owner: @org)
                end
              end
            end
          end

          test "it succeeds creating CSV file and scheduling jobs" do
            blob_storage_key = SecureRandom.uuid
            ::SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).with(blob_storage_key)
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
              OwnerRepoClassificationControlJob::CSV_FEATURE,
            )

            assert_enqueued_jobs(3, only: [OwnerRepoClassificationSliceJob, OwnerRepoClassificationControlJob]) do
              OwnerRepoClassificationControlJob.perform_now(actor: @actor, blob_storage_key:, owner: @org)
            end
          end

          test "it succeeds re-running itself if slice jobs didn't finish yet" do
            blob_storage_key = SecureRandom.uuid
            JobStatus.create({ id: OwnerRepoClassificationSliceJob.job_id(@org, 0) }).started!
            JobStatus.create({ id: OwnerRepoClassificationSliceJob.job_id(@org, 1) }).success!


            ::SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).never
            ::SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).never

            assert_enqueued_jobs(1, only: OwnerRepoClassificationControlJob) do
              OwnerRepoClassificationControlJob.perform_now(actor: @actor, blob_storage_key:, owner: @org, first_run: false)
            end
          end

          test "it doesn't do anything if attempting first run and slice jobs didn't finish yet" do
            JobStatus.create({ id: OwnerRepoClassificationSliceJob.job_id(@org, 0) }).started!
            JobStatus.create({ id: OwnerRepoClassificationSliceJob.job_id(@org, 1) }).success!


            ::SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).never
            ::SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).never

            assert_enqueued_jobs(0) do
              assert_logged_statements([{ Body: "Jobs are still running. Skipping CSV file creation." }]) do
                OwnerRepoClassificationControlJob.perform_now(actor: @actor, blob_storage_key: "", owner: @org, first_run: true)
              end
            end
          end

          test "it succeeds emailing the CSV file after slice jobs completed" do
            JobStatus.create({ id: OwnerRepoClassificationSliceJob.job_id(@org, 0) }).success!
            JobStatus.create({ id: OwnerRepoClassificationSliceJob.job_id(@org, 1) }).success!

            OwnerRepoClassificationControlJob.any_instance.stubs(:timeout_sec).returns(0.0)
            ::SecurityCenterMailer.expects(:alert_prioritization_copilot_prompt_experiment_csv_ready).once.returns(stub(deliver_later: true))

            assert_performed_jobs(1, only: OwnerRepoClassificationControlJob) do
              OwnerRepoClassificationControlJob.perform_later(actor: @actor, owner: @org, first_run: false)
            end
          end

          context "with experimental prompt" do
            test "it succeeds creating CSV file and scheduling jobs" do
              blob_storage_key = SecureRandom.uuid
              ::SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:create).with(blob_storage_key)
              ::SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).with(
                blob_storage_key,
                [
                  "Repo ID",
                  "Repo NWO",
                  "Repo is archived?",
                  "Repo is public?",
                  "Experimental - Known answer",
                  "Experimental - Copilot prompt",
                  "Experimental - Copilot's answer",
                  "Experimental - Copilot's confidence",
                  "Experimental - Copilot's reasoning\n"
                ].join(","),
                OwnerRepoClassificationControlJob::CSV_FEATURE,
              )
              prompt_experimental = "woof woof barr barr"

              OwnerRepoClassificationSliceJob.expects(:perform_later).with do |kwargs|
                kwargs[:prompt_experimental] == prompt_experimental
              end.twice
              OwnerRepoClassificationControlJob.set(wait: 5.minutes).class.any_instance.expects(:perform_later).with do |kwargs|
                kwargs[:prompt_experimental] == prompt_experimental
              end.once

              OwnerRepoClassificationControlJob.perform_now(actor: @actor, blob_storage_key:, owner: @org, prompt_experimental:)
            end
          end
        end
      end
    end
  end
end
