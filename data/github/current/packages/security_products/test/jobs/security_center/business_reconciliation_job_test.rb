# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require_relative "../../../app/models/security_center/k_v"

module SecurityCenter
  class BusinessReconciliationJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include JobTestHelper

    fixtures do
      # Business
      @business = if GitHub.enterprise?
        create(:global_business)
      else
        create(:business, :enterprise_managed)
      end

      # EMUs
      10.times.each do
        if GitHub.enterprise?
          create(:user, business: @business)
        else
          create(:emu, business: @business)
        end
      end

      # Organizations
      10.times.each do
        create(:organization, business: @business, admin: @business.owners.first)
      end

      unless GitHub.single_business_environment?
        @non_managed_business = create(:business)
        create(:user, business: @non_managed_business)
      end
    end

    setup do
      # Clear locks on downstream org reconcilation to allow queues to proceed
      @business.organizations.each do |org|
        SecurityCenter::KV.store.del("#{OwnerReconciliationJob.name}:#{org.id}")
      end

      GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true) if GitHub.enterprise?
      Business.any_instance.stubs(:advanced_security_purchased?).returns(true)

      all_user_ids = if GitHub.enterprise?
        User.where(type: "User").pluck(:id)
      else
        ExternalIdentity.by_provider(@business.external_provider).pluck(:user_id)
      end
      @emus = User.where(id: all_user_ids).order(:id)
      @emus.pluck(:id).each do |user_id|
        SecurityCenter::KV.store.del("#{OwnerReconciliationJob.name}:#{user_id}")
      end
    end

    context "#perform org" do
      test "it enqueues a reconciliation job for each org in the current batch" do
        SecureRandom.stubs(:uuid).returns("stubbed")
        BusinessReconciliationJob.perform_now(business_id: @business.id)
        assert_enqueued_jobs(@business.organizations.count, only: OwnerReconciliationJob)
        @business.organizations.each do |org|
          assert_enqueued_with(job: OwnerReconciliationJob, args: [{ owner_id: org.id, source_event: nil, session_id: "stubbed" }])
        end
      end

      context "when no business is found" do
        test "it does not enqueue any business or org reconciliation jobs" do
          non_existent_business_id = Business.maximum(:id).next
          BusinessReconciliationJob.perform_now(business_id: non_existent_business_id)
          assert_no_enqueued_jobs(only: [BusinessReconciliationJob, OwnerReconciliationJob])
        end
      end

      context "when there are no orgs to reconcile" do
        test "it does not enqueue any business or reconciliation jobs" do
          @business.organizations.destroy_all

          assert_no_enqueued_jobs(only: [BusinessReconciliationJob, OwnerReconciliationJob]) do
            BusinessReconciliationJob.perform_now(business_id: @business.id)
          end
        end
      end

      context "soft-delete organizations", skip_enterprise: true do
        test "it does not enqueue jobs for soft-deleted organizations" do
          org_admin = create :emu, business: @business

          soft_deleted_org = create :organization, login: "soft-deleted-org", admin: org_admin, business: @business

          assert_equal 11, @business.organizations.count

          perform_enqueued_jobs only: [SoftDeleteBusinessJob] do
            soft_deleted_org.soft_delete!(org_admin)
          end

          assert_predicate soft_deleted_org, :soft_deleted?
          assert_equal 10, @business.organizations.count
          assert_equal 1, @business.soft_deleted_organizations.count

          SecureRandom.stubs(:uuid).returns("stubbed")
          BusinessReconciliationJob.perform_now(business_id: @business.id)

          assert_enqueued_jobs(10, only: OwnerReconciliationJob)
          @business.organizations.each do |org|
            assert_enqueued_with(job: OwnerReconciliationJob, args: [{ owner_id: org.id, source_event: nil, session_id: "stubbed" }])
          end
        end
      end
    end

    context "#perform user" do
      test "it enqueues a reconciliation job for each user in the current batch" do
        SecureRandom.stubs(:uuid).returns("stubbed")
        BusinessReconciliationJob.perform_now(business_id: @business.id, entity_type: BusinessReconciliationJob::EntityType::User)
        assert_enqueued_jobs(@emus.length, only: OwnerReconciliationJob)
        @emus.each do |emu|
          assert_enqueued_with(job: OwnerReconciliationJob, args: [{ owner_id: emu.id, source_event: nil, session_id: "stubbed" }])
        end
      end

      test "does not enqueue any jobs for users if GHAS is not purchased" do
        Business.any_instance.stubs(:advanced_security_purchased?).returns(false)
        SecureRandom.stubs(:uuid).returns("stubbed")
        BusinessReconciliationJob.perform_now(business_id: @business.id, entity_type: BusinessReconciliationJob::EntityType::User)
        assert_no_enqueued_jobs(only: [BusinessReconciliationJob, OwnerReconciliationJob])
      end

      context "when no business is found" do
        test "it does not enqueue any business or user reconciliation jobs" do
          non_existent_business_id = Business.maximum(:id).next
          BusinessReconciliationJob.perform_now(business_id: non_existent_business_id, entity_type: BusinessReconciliationJob::EntityType::User)
          assert_no_enqueued_jobs(only: [BusinessReconciliationJob, OwnerReconciliationJob])
        end
      end

      # skipping enterprise because atleast 1 user is required in enterprise mode
      context "when there are no users to reconcile", skip_enterprise: true do
        test "it does not enqueue any business or reconciliation jobs" do
          @emus.each(&:destroy!)
          BusinessReconciliationJob.perform_now(business_id: @business.id, entity_type: BusinessReconciliationJob::EntityType::User)
          assert_no_enqueued_jobs(only: [BusinessReconciliationJob, OwnerReconciliationJob])
        end
      end

      # skipping enterprise because no 2 businesses can coexist in enterprise mode
      context "when a business is non enterprise managed", skip_enterprise: true do
        test "it does not enqueue any reconciliation jobs" do
          BusinessReconciliationJob.perform_now(business_id: @non_managed_business.id, entity_type: BusinessReconciliationJob::EntityType::User)
          assert_no_enqueued_jobs(only: [BusinessReconciliationJob, OwnerReconciliationJob])
        end
      end
    end

    context "batch job" do
      test "queues subsequent jobs for batching" do
        BusinessReconciliationJob.stub_const(:BATCH_SIZE, 3) do
          assert_performed_jobs 4, only: BusinessReconciliationJob do
            perform_enqueued_jobs(only: BusinessReconciliationJob) do
              BusinessReconciliationJob.perform_later(business_id: @business.id)
            end
          end
        end
      end

      test "queues subsequent user jobs for batching" do
        BusinessReconciliationJob.stub_const(:BATCH_SIZE, 3) do
          # 5 in enterprise because enterprise creates ghost users
          assert_performed_jobs GitHub.enterprise? ? 5 : 4, only: BusinessReconciliationJob do
            perform_enqueued_jobs(only: BusinessReconciliationJob) do
              BusinessReconciliationJob.perform_later(business_id: @business.id, entity_type: BusinessReconciliationJob::EntityType::User)
            end
          end
        end
      end
    end

    context "hash lock" do
      test "disallows concurrent jobs for same org" do
        assert_enqueued_jobs 1, only: BusinessReconciliationJob do
          BusinessReconciliationJob.perform_later(business_id: @business.id)
          BusinessReconciliationJob.perform_later(business_id: @business.id)
          BusinessReconciliationJob.perform_later(business_id: @business.id)
        end
      end

      test "disallows concurrent jobs for same user" do
        assert_enqueued_jobs 1, only: BusinessReconciliationJob do
          BusinessReconciliationJob.perform_later(business_id: @business.id, entity_type: BusinessReconciliationJob::EntityType::User)
          BusinessReconciliationJob.perform_later(business_id: @business.id, entity_type: BusinessReconciliationJob::EntityType::User)
          BusinessReconciliationJob.perform_later(business_id: @business.id, entity_type: BusinessReconciliationJob::EntityType::User)
        end
      end

      test "allows concurrent jobs for different entity types" do
        assert_enqueued_jobs 2, only: BusinessReconciliationJob do
          BusinessReconciliationJob.perform_later(business_id: @business.id, entity_type: BusinessReconciliationJob::EntityType::Organization)
          BusinessReconciliationJob.perform_later(business_id: @business.id)
          BusinessReconciliationJob.perform_later(business_id: @business.id, entity_type: BusinessReconciliationJob::EntityType::User)
          BusinessReconciliationJob.perform_later(business_id: @business.id)
          BusinessReconciliationJob.perform_later(business_id: @business.id, entity_type: BusinessReconciliationJob::EntityType::User)
        end
      end
    end
  end
end
