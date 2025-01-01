# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require_relative "../../../app/models/security_center/k_v"


module SecurityCenter
  class OrganizationReconciliationJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include JobTestHelper

    fixtures do
      @business = create(:business)
      @org = create(:organization, business: @business).tap do |o|
        3.times do
          create(:repository, owner: o)
        end
      end
    end

    setup do
      # remove the lock to allow reconciliation to be queued
      SecurityCenter::KV.store.del("#{OrganizationReconciliationJob.name}:#{@org.id}")
    end

    context "#perform" do
      context "when source_event is reconciliation" do
        test "queues reconciliation job for each repository" do
          assert_enqueued_jobs @org.repositories.count, only: ::SecurityCenter::RepositoryReconciliationJob do
            OrganizationReconciliationJob.perform_now(organization_id: @org.id, source_event: OrganizationReconciliationJob::RECONCILIATION_EVENT)
          end
        end

        test "queues reconciliation job for each orphaned RepositorySecurityCenterConfig record" do
          non_existent_repo_id = Repository.maximum(:id) + 1
          org = create(:organization, business: @business).tap do |o|
            # create a config record for non-existent repo
            create(
              :repository_security_center_config,
              repository: nil,
              repository_id: non_existent_repo_id,
              owner: o,
              owner_type: "ORGANIZATION",
              business_id: @business.id,
              name: "repo-name",
              visibility: :private,
              archived: false,
              last_push: nil,
            )
          end

          assert_enqueued_jobs 1, only: ::SecurityCenter::RepositoryReconciliationJob do
            OrganizationReconciliationJob.perform_now(organization_id: org.id, source_event: OrganizationReconciliationJob::RECONCILIATION_EVENT)
          end

          assert_nil Repository.find_by(id: non_existent_repo_id)
          assert_dogstats_increment(1, "security_center.reconciliation_job.fanout.count", tags: ["orphaned:true"])
        end
      end

      context "when source_event is non-reconciliation fanout" do
        test "queues update job for each repository" do
          expected_update_jobs = @org.repositories.count * SecurityFeatures.all.count
          assert_enqueued_jobs expected_update_jobs, only: ::SecurityCenter::RepositorySyncJob do
            OrganizationReconciliationJob.perform_now(organization_id: @org.id, source_event: "security_center.change_fanout")
          end
        end

        test "queues update job for each orphaned RepositorySecurityCenterConfig record" do
          non_existent_repo_id = Repository.maximum(:id) + 1
          org = create(:organization, business: @business).tap do |o|
            # create a config record for non-existent repo
            create(
              :repository_security_center_config,
              repository: nil,
              repository_id: non_existent_repo_id,
              owner: o,
              owner_type: "ORGANIZATION",
              business_id: @business.id,
              name: "repo-name",
              visibility: :private,
              archived: false,
              last_push: nil,
            )
          end

          expected_update_jobs = SecurityFeatures.all.count
          assert_enqueued_jobs expected_update_jobs, only: ::SecurityCenter::RepositorySyncJob do
            OrganizationReconciliationJob.perform_now(organization_id: org.id, source_event: "security_center.change_fanout")
          end

          assert_nil Repository.find_by(id: non_existent_repo_id)
          assert_dogstats_increment(1, "security_center.reconciliation_job.fanout.count", tags: ["orphaned:true"])
        end
      end
    end

    context "batch job" do
      test "queues subsequent jobs for batching" do
        org = create(:organization).tap do |o|
          10.times do
            create(:repository, owner: o)
          end
        end

        # remove the lock to allow reconciliation to be queued
        SecurityCenter::KV.store.del("#{OrganizationReconciliationJob.name}:#{org.id}")

        OrganizationReconciliationJob.stub_const(:BATCH_SIZE, 3) do
          assert_performed_jobs 4, only: OrganizationReconciliationJob do
            perform_enqueued_jobs(only: OrganizationReconciliationJob) do
              OrganizationReconciliationJob.perform_later(organization_id: org.id, source_event: OrganizationReconciliationJob::RECONCILIATION_EVENT)
            end
          end
        end
      end
    end

    context "hash lock" do
      test "disallows concurrent jobs for same org" do
        assert_enqueued_jobs 1, only: OrganizationReconciliationJob do
          OrganizationReconciliationJob.perform_later(organization_id: @org.id, source_event: OrganizationReconciliationJob::RECONCILIATION_EVENT)
          OrganizationReconciliationJob.perform_later(organization_id: @org.id, source_event: OrganizationReconciliationJob::RECONCILIATION_EVENT)
          OrganizationReconciliationJob.perform_later(organization_id: @org.id, source_event: OrganizationReconciliationJob::RECONCILIATION_EVENT)
        end

        assert_dogstats_increment(0, "security_center.reconciliation_job.skip_recent.count")
      end
    end

    context "locking time window" do
      test "disallows jobs for the same org within the lock window" do
        assert_performed_jobs 1, only: OrganizationReconciliationJob do
          perform_enqueued_jobs only: OrganizationReconciliationJob do
            OrganizationReconciliationJob.perform_later(organization_id: @org.id, source_event: OrganizationReconciliationJob::RECONCILIATION_EVENT)
          end
        end

        assert_performed_jobs 0, only: OrganizationReconciliationJob do
          perform_enqueued_jobs only: OrganizationReconciliationJob do
            OrganizationReconciliationJob.perform_later(organization_id: @org.id, source_event: OrganizationReconciliationJob::RECONCILIATION_EVENT)
          end
        end

        assert_dogstats_increment(1, "security_center.reconciliation_job.skip_recent.count")
      end

      test "allows jobs for the same org after window has expired" do
        assert_performed_jobs 1, only: OrganizationReconciliationJob do
          perform_enqueued_jobs only: OrganizationReconciliationJob do
            OrganizationReconciliationJob.perform_later(organization_id: @org.id, source_event: OrganizationReconciliationJob::RECONCILIATION_EVENT)
          end
        end

        Timecop.travel(7.days.from_now) do
          assert_performed_jobs 1, only: OrganizationReconciliationJob do
            perform_enqueued_jobs only: OrganizationReconciliationJob do
              OrganizationReconciliationJob.perform_later(organization_id: @org.id, source_event: OrganizationReconciliationJob::RECONCILIATION_EVENT)
            end
          end
        end

        assert_dogstats_increment(0, "security_center.reconciliation_job.skip_recent.count")
      end

      test "allows jobs for the same org if source_event supports lock stealing" do
        assert_performed_jobs 2, only: OrganizationReconciliationJob do
          perform_enqueued_jobs only: OrganizationReconciliationJob do
            OrganizationReconciliationJob.perform_later(organization_id: @org.id, source_event: OrganizationReconciliationJob::RECONCILIATION_EVENT)
          end
          perform_enqueued_jobs only: OrganizationReconciliationJob do
            OrganizationReconciliationJob.perform_later(organization_id: @org.id, source_event: "org.advanced_security_toggled")
          end
        end

        assert_dogstats_increment(1, "security_center.reconciliation_job.interrupted.count")
      end

      test "does not allow jobs for the same org if source_event doesn't support lock stealing" do
        assert_performed_jobs 1, only: OrganizationReconciliationJob do
          perform_enqueued_jobs only: OrganizationReconciliationJob do
            OrganizationReconciliationJob.perform_later(organization_id: @org.id, source_event: OrganizationReconciliationJob::RECONCILIATION_EVENT)
          end
          OrganizationReconciliationJob::NON_INCREMENTAL_EVENTS.each do |event|
            perform_enqueued_jobs only: OrganizationReconciliationJob do
              OrganizationReconciliationJob.perform_later(organization_id: @org.id, source_event: event)
            end
          end
        end

        assert_dogstats_increment(0, "security_center.reconciliation_job.interrupted.count")
      end
    end
  end
end
