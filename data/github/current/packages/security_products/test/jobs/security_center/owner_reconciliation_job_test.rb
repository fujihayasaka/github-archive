# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require_relative "../../../app/models/security_center/k_v"

module SecurityCenter
  class OwnerReconciliationJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include JobTestHelper

    fixtures do
      @business = create(:business)
      @org = create(:organization, business: @business).tap do |o|
        3.times do
          create(:repository, owner: o)
        end
      end

      @user = GitHub.enterprise? ? create(:user) : create(:emu)
      3.times do
        create(:private_repository, force_user_owned: true, owner: @user)
      end
    end

    setup do
      # remove the lock to allow reconciliation to be queued
      SecurityCenter::KV.store.del("#{OwnerReconciliationJob.name}:#{@org.id}")
      unless GitHub.enterprise?
        SecurityCenter::KV.store.del("#{OwnerReconciliationJob.name}:#{@user.id}")
      end
    end

    context "#perform for orgs" do
      context "when source_event is reconciliation" do
        test "queues reconciliation job for each repository" do
          assert_enqueued_jobs @org.repositories.count, only: ::SecurityCenter::RepositoryReconciliationJob do
            OwnerReconciliationJob.perform_now(owner_id: @org.id, source_event: OwnerReconciliationJob::RECONCILIATION_EVENT)
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
            OwnerReconciliationJob.perform_now(owner_id: org.id, source_event: OwnerReconciliationJob::RECONCILIATION_EVENT)
          end

          assert_nil Repository.find_by(id: non_existent_repo_id)
          assert_dogstats_increment(1, "security_center.reconciliation_job.fanout.count", tags: ["orphaned:true"])
        end
      end

      context "when source_event is non-reconciliation fanout" do
        test "queues update job for each repository" do
          expected_update_jobs = @org.repositories.count * SecurityFeatures.all.count
          assert_enqueued_jobs expected_update_jobs, only: ::SecurityCenter::RepositorySyncJob do
            OwnerReconciliationJob.perform_now(owner_id: @org.id, source_event: "security_center.change_fanout")
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
            OwnerReconciliationJob.perform_now(owner_id: org.id, source_event: "security_center.change_fanout")
          end

          assert_nil Repository.find_by(id: non_existent_repo_id)
          assert_dogstats_increment(1, "security_center.reconciliation_job.fanout.count", tags: ["orphaned:true"])
        end
      end
    end

    context "#perform for users" do
      context "when source_event is reconciliation" do
        test "queues reconciliation job for each repository" do
          assert_enqueued_jobs @user.repositories.count, only: ::SecurityCenter::RepositoryReconciliationJob do
            OwnerReconciliationJob.perform_now(owner_id: @user.id, source_event: OwnerReconciliationJob::RECONCILIATION_EVENT)
          end
        end

        test "queues reconciliation job for each orphaned RepositorySecurityCenterConfig record" do
          non_existent_repo_id = Repository.maximum(:id) + 1
          user = create(:user)
          biz_id = 0
          unless GitHub.enterprise?
            emu_biz = @user.enterprise_managed_business
            user = create(:emu, business: emu_biz)
            biz_id = emu_biz.id
          end

          user.tap do |o|
            # create a config record for non-existent repo
            create(
              :repository_security_center_config,
              repository: nil,
              repository_id: non_existent_repo_id,
              owner: o,
              owner_type: "USER",
              business_id: biz_id,
              name: "repo-name",
              visibility: :private,
              archived: false,
              last_push: nil,
            )
          end

          assert_enqueued_jobs 1, only: ::SecurityCenter::RepositoryReconciliationJob do
            OwnerReconciliationJob.perform_now(owner_id: user.id, source_event: OwnerReconciliationJob::RECONCILIATION_EVENT)
          end

          assert_nil Repository.find_by(id: non_existent_repo_id)
          assert_dogstats_increment(1, "security_center.reconciliation_job.fanout.count", tags: ["orphaned:true"])
        end
      end

      context "when source_event is non-reconciliation fanout" do
        test "queues update job for each repository" do
          expected_update_jobs = @user.repositories.count * SecurityFeatures.all.count
          assert_enqueued_jobs expected_update_jobs, only: ::SecurityCenter::RepositorySyncJob do
            OwnerReconciliationJob.perform_now(owner_id: @user.id, source_event: "security_center.change_fanout")
          end
        end

        test "queues update job for each orphaned RepositorySecurityCenterConfig record" do
          non_existent_repo_id = Repository.maximum(:id) + 1
          user = create(:user)
          biz_id = 0
          unless GitHub.enterprise?
            emu_biz = @user.enterprise_managed_business
            user = create(:emu, business: emu_biz)
            biz_id = emu_biz.id
          end

          user.tap do |o|
            # create a config record for non-existent repo
            create(
              :repository_security_center_config,
              repository: nil,
              repository_id: non_existent_repo_id,
              owner: o,
              owner_type: "USER",
              business_id: biz_id,
              name: "repo-name",
              visibility: :private,
              archived: false,
              last_push: nil,
            )
          end

          expected_update_jobs = SecurityFeatures.all.count
          assert_enqueued_jobs expected_update_jobs, only: ::SecurityCenter::RepositorySyncJob do
            OwnerReconciliationJob.perform_now(owner_id: user.id, source_event: "security_center.change_fanout")
          end

          assert_nil Repository.find_by(id: non_existent_repo_id)
          assert_dogstats_increment(1, "security_center.reconciliation_job.fanout.count", tags: ["orphaned:true"])
        end
      end
    end

    context "batch job" do
      test "queues subsequent jobs for batching for orgs" do
        org = create(:organization).tap do |o|
          10.times do
            create(:repository, owner: o)
          end
        end

        # remove the lock to allow reconciliation to be queued
        SecurityCenter::KV.store.del("#{OwnerReconciliationJob.name}:#{org.id}")

        OwnerReconciliationJob.stub_const(:BATCH_SIZE, 3) do
          assert_performed_jobs 4, only: OwnerReconciliationJob do
            perform_enqueued_jobs(only: OwnerReconciliationJob) do
              OwnerReconciliationJob.perform_later(owner_id: org.id, source_event: OwnerReconciliationJob::RECONCILIATION_EVENT)
            end
          end
        end
      end

      test "queues subsequent jobs for batching for users" do
        user2 = GitHub.enterprise? ? create(:user) : create(:emu, business: @emu_biz)
        10.times do
          create(:repository, owner: user2)
        end

        # remove the lock to allow reconciliation to be queued
        SecurityCenter::KV.store.del("#{OwnerReconciliationJob.name}:#{user2.id}")

        OwnerReconciliationJob.stub_const(:BATCH_SIZE, 3) do
          assert_performed_jobs 4, only: OwnerReconciliationJob do
            perform_enqueued_jobs(only: OwnerReconciliationJob) do
              OwnerReconciliationJob.perform_later(owner_id: user2.id, source_event: OwnerReconciliationJob::RECONCILIATION_EVENT)
            end
          end
        end
      end
    end

    context "hash lock" do
      test "disallows concurrent jobs for same org" do
        assert_enqueued_jobs 1, only: OwnerReconciliationJob do
          OwnerReconciliationJob.perform_later(owner_id: @org.id, source_event: OwnerReconciliationJob::RECONCILIATION_EVENT)
          OwnerReconciliationJob.perform_later(owner_id: @org.id, source_event: OwnerReconciliationJob::RECONCILIATION_EVENT)
          OwnerReconciliationJob.perform_later(owner_id: @org.id, source_event: OwnerReconciliationJob::RECONCILIATION_EVENT)
        end

        assert_dogstats_increment(0, "security_center.reconciliation_job.skip_recent.count")
      end

      test "disallows concurrent jobs for same user" do
        assert_enqueued_jobs 1, only: OwnerReconciliationJob do
          OwnerReconciliationJob.perform_later(owner_id: @user.id, source_event: OwnerReconciliationJob::RECONCILIATION_EVENT)
          OwnerReconciliationJob.perform_later(owner_id: @user.id, source_event: OwnerReconciliationJob::RECONCILIATION_EVENT)
          OwnerReconciliationJob.perform_later(owner_id: @user.id, source_event: OwnerReconciliationJob::RECONCILIATION_EVENT)
        end

        assert_dogstats_increment(0, "security_center.reconciliation_job.skip_recent.count")
      end
    end

    context "locking time window" do
      test "disallows jobs for the same org within the lock window" do
        assert_performed_jobs 1, only: OwnerReconciliationJob do
          perform_enqueued_jobs only: OwnerReconciliationJob do
            OwnerReconciliationJob.perform_later(owner_id: @org.id, source_event: OwnerReconciliationJob::RECONCILIATION_EVENT)
          end
        end

        assert_performed_jobs 0, only: OwnerReconciliationJob do
          perform_enqueued_jobs only: OwnerReconciliationJob do
            OwnerReconciliationJob.perform_later(owner_id: @org.id, source_event: OwnerReconciliationJob::RECONCILIATION_EVENT)
          end
        end

        assert_dogstats_increment(1, "security_center.reconciliation_job.skip_recent.count")
      end

      test "allows jobs for the same org after window has expired" do
        assert_performed_jobs 1, only: OwnerReconciliationJob do
          perform_enqueued_jobs only: OwnerReconciliationJob do
            OwnerReconciliationJob.perform_later(owner_id: @org.id, source_event: OwnerReconciliationJob::RECONCILIATION_EVENT)
          end
        end

        Timecop.travel(7.days.from_now) do
          assert_performed_jobs 1, only: OwnerReconciliationJob do
            perform_enqueued_jobs only: OwnerReconciliationJob do
              OwnerReconciliationJob.perform_later(owner_id: @org.id, source_event: OwnerReconciliationJob::RECONCILIATION_EVENT)
            end
          end
        end

        assert_dogstats_increment(0, "security_center.reconciliation_job.skip_recent.count")
      end

      test "allows jobs for the same org if source_event supports lock stealing" do
        assert_performed_jobs 2, only: OwnerReconciliationJob do
          perform_enqueued_jobs only: OwnerReconciliationJob do
            OwnerReconciliationJob.perform_later(owner_id: @org.id, source_event: OwnerReconciliationJob::RECONCILIATION_EVENT)
          end
          perform_enqueued_jobs only: OwnerReconciliationJob do
            OwnerReconciliationJob.perform_later(owner_id: @org.id, source_event: "org.advanced_security_toggled")
          end
        end

        assert_dogstats_increment(1, "security_center.reconciliation_job.interrupted.count")
      end

      test "does not allow jobs for the same org if source_event doesn't support lock stealing" do
        assert_performed_jobs 1, only: OwnerReconciliationJob do
          perform_enqueued_jobs only: OwnerReconciliationJob do
            OwnerReconciliationJob.perform_later(owner_id: @org.id, source_event: OwnerReconciliationJob::RECONCILIATION_EVENT)
          end
          OwnerReconciliationJob::NON_INCREMENTAL_EVENTS.each do |event|
            perform_enqueued_jobs only: OwnerReconciliationJob do
              OwnerReconciliationJob.perform_later(owner_id: @org.id, source_event: event)
            end
          end
        end

        assert_dogstats_increment(0, "security_center.reconciliation_job.interrupted.count")
      end

      test "disallows jobs for the same user within the lock window" do
        assert_performed_jobs 1, only: OwnerReconciliationJob do
          perform_enqueued_jobs only: OwnerReconciliationJob do
            OwnerReconciliationJob.perform_later(owner_id: @user.id, source_event: OwnerReconciliationJob::RECONCILIATION_EVENT)
          end
        end

        assert_performed_jobs 0, only: OwnerReconciliationJob do
          perform_enqueued_jobs only: OwnerReconciliationJob do
            OwnerReconciliationJob.perform_later(owner_id: @user.id, source_event: OwnerReconciliationJob::RECONCILIATION_EVENT)
          end
        end

        assert_dogstats_increment(1, "security_center.reconciliation_job.skip_recent.count")
      end

      test "allows jobs for the same user after window has expired" do
        assert_performed_jobs 1, only: OwnerReconciliationJob do
          perform_enqueued_jobs only: OwnerReconciliationJob do
            OwnerReconciliationJob.perform_later(owner_id: @user.id, source_event: OwnerReconciliationJob::RECONCILIATION_EVENT)
          end
        end

        Timecop.travel(7.days.from_now) do
          assert_performed_jobs 1, only: OwnerReconciliationJob do
            perform_enqueued_jobs only: OwnerReconciliationJob do
              OwnerReconciliationJob.perform_later(owner_id: @user.id, source_event: OwnerReconciliationJob::RECONCILIATION_EVENT)
            end
          end
        end

        assert_dogstats_increment(0, "security_center.reconciliation_job.skip_recent.count")
      end

      test "allows jobs for the same user if source_event supports lock stealing" do
        assert_performed_jobs 2, only: OwnerReconciliationJob do
          perform_enqueued_jobs only: OwnerReconciliationJob do
            OwnerReconciliationJob.perform_later(owner_id: @user.id, source_event: OwnerReconciliationJob::RECONCILIATION_EVENT)
          end
          perform_enqueued_jobs only: OwnerReconciliationJob do
            OwnerReconciliationJob.perform_later(owner_id: @user.id, source_event: "user.advanced_security_toggled")
          end
        end

        assert_dogstats_increment(1, "security_center.reconciliation_job.interrupted.count")
      end

      test "does not allow jobs for the same user if source_event doesn't support lock stealing" do
        assert_performed_jobs 1, only: OwnerReconciliationJob do
          perform_enqueued_jobs only: OwnerReconciliationJob do
            OwnerReconciliationJob.perform_later(owner_id: @user.id, source_event: OwnerReconciliationJob::RECONCILIATION_EVENT)
          end
          OwnerReconciliationJob::NON_INCREMENTAL_EVENTS.each do |event|
            perform_enqueued_jobs only: OwnerReconciliationJob do
              OwnerReconciliationJob.perform_later(owner_id: @user.id, source_event: event)
            end
          end
        end

        assert_dogstats_increment(0, "security_center.reconciliation_job.interrupted.count")
      end
    end
  end
end
