# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityOverviewAnalytics
  class Initialization
    class BusinessJobTest < GitHub::TestCase
      include JobTestHelper

      fixtures do
        # Business
        @biz = if GitHub.enterprise?
          create(:global_business)
        else
          create(:business, :enterprise_managed)
        end

        # EMUs
        10.times.each do
          if GitHub.enterprise?
            create(:user, business: @biz)
          else
            create(:emu, business: @biz)
          end
        end

        # Organizations
        @orgs = create_list(:organization, 10, business: @biz, admin: @biz.owners.first)

        unless GitHub.single_business_environment?
          @non_managed_business = create(:business)
          create(:user, business: @non_managed_business)
        end
      end

      setup do
        GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true) if GitHub.enterprise?
        Business.any_instance.stubs(:advanced_security_purchased?).returns(true)

        all_user_ids = if GitHub.enterprise?
          User.where(type: "User").pluck(:id)
        else
          ExternalIdentity.by_provider(@biz.external_provider).pluck(:user_id)
        end
        @emus = User.where(id: all_user_ids).order(:id)
      end

      test "it is a TenantBaseJob" do
        assert_kind_of(TenantBaseJob, BusinessJob.new)
      end

      context "#perform org" do
        test "it enqueues an organization job for each org" do
          perform_enqueued_jobs(only: BusinessJob) do
            BusinessJob.perform_later(business_id: @biz.id)
          end

          assert_enqueued_jobs(@biz.organizations.size, only: OrganizationJob)
        end

        test "it enqueues an organization reconciliation for an org that was already initialized" do
          Initialization.for(@orgs.first).set_all_to_initialized

          perform_enqueued_jobs(only: BusinessJob) do
            BusinessJob.perform_later(business_id: @biz.id)
          end

          assert_enqueued_jobs(@biz.organizations.size - 1, only: OrganizationJob)
          assert_enqueued_jobs(1, only: Reconciliation::OrganizationReconciliationJob)
        end
      end

      context "#perform user" do
        test "it enqueues a user job for each user" do
          perform_enqueued_jobs(only: BusinessJob) do
            BusinessJob.perform_later(business_id: @biz.id, type: Initialization::Type::Users.serialize)
          end

          assert_enqueued_jobs(@emus.length, only: UserJob)
        end

        test "it enqueues a user reconciliation for a user that was already initialized" do
          Initialization.for(@emus.first).set_all_to_initialized

          perform_enqueued_jobs(only: BusinessJob) do
            BusinessJob.perform_later(business_id: @biz.id, type: Initialization::Type::Users.serialize)
          end

          assert_enqueued_jobs(@emus.length - 1, only: UserJob)
          # TODO: add user reconciliation job once that ships
        end

        test "it enqueues a user job for each user if there were already orgs initialized" do
          @orgs.each do |org|
            Initialization.for(org).set_all_to_initialized
          end

          perform_enqueued_jobs(only: BusinessJob) do
            BusinessJob.perform_later(business_id: @biz.id, type: Initialization::Type::Users.serialize)
          end

          assert_enqueued_jobs(0, only: OrganizationJob)
          assert_enqueued_jobs(@emus.length, only: UserJob)
        end
      end
    end
  end
end
