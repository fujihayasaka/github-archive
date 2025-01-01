# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityOverviewAnalytics
  class Initialization
    class ResetJobTest < GitHub::TestCase
      include JobTestHelper

      fixtures do
        @biz_1 = create(:business)
        @orgs_1 = create_list(:organization, 4, business: @biz_1)

        unless GitHub.enterprise?
          @biz_2 = create(:business)
          @orgs_2 = create_list(:organization, 5, business: @biz_2)
        end
      end

      setup do
        GitHub.flipper[:security_center_private_beta].disable

        feature = T.let(FlipperFeature.send(:find_or_create_by, name: :security_center_private_beta), FlipperFeature)
        feature.enable(@biz_1)
        @orgs_2.each { |org| feature.enable(org) }
      end

      test "it retries on certain errors", skip_enterprise: true do
        assert_retry_conditions(job: ResetJob)
      end

      context "when private_beta is false", skip_enterprise: true do
        test "it deletes everything for the provided business IDs" do
          DeletionHelper.expects(:delete_all_for_businesses).with(business_ids: [@biz_1.id, @biz_2.id], type: nil)
          ResetJob.perform_now(business_ids: [@biz_1.id, @biz_2.id])
        end

        test "it deletes everything for the provided organization IDs" do
          DeletionHelper.expects(:delete_all_for_organizations).with(organization_ids: @orgs_1.map(&:id), type: nil)
          ResetJob.perform_now(organization_ids: @orgs_1.map(&:id))
        end

        test "it enqueues initialization jobs" do
          ResetJob.perform_now(business_ids: [@biz_1.id], organization_ids: @orgs_2.map(&:id))
          assert_enqueued_jobs(1, only: ::SecurityOverviewAnalytics::Initialization::BusinessJob)
          assert_enqueued_jobs(@orgs_2.size, only: ::SecurityOverviewAnalytics::Initialization::OrganizationJob)
        end
      end

      context "when private_beta is true", skip_enterprise: true do
        test "it deletes everything for the private beta business and organization IDs" do
          DeletionHelper.expects(:delete_all_for_businesses).with(business_ids: [@biz_1.id], type: nil)
          DeletionHelper.expects(:delete_all_for_organizations).with(organization_ids: @orgs_2.map(&:id), type: nil)
          ResetJob.perform_now(private_beta: true)
        end

        test "it ignores the provided business and organization IDs" do
          DeletionHelper.expects(:delete_all_for_businesses).with(business_ids: [@biz_1.id], type: nil)
          DeletionHelper.expects(:delete_all_for_organizations).with(organization_ids: @orgs_2.map(&:id), type: nil)
          ResetJob.perform_now(business_ids: [@biz_2.id], organization_ids: @orgs_1.map(&:id), private_beta: true)
        end

        test "it enqueues initialization jobs" do
          ResetJob.perform_now(private_beta: true)
          assert_enqueued_jobs(1, only: ::SecurityOverviewAnalytics::Initialization::BusinessJob)
          assert_enqueued_jobs(@orgs_2.size, only: ::SecurityOverviewAnalytics::Initialization::OrganizationJob)
        end
      end

      context "when initialization_only is true", skip_enterprise: true do
        test "it skips data deletion everything for the private beta business and organization IDs" do
          DeletionHelper.expects(:delete_all_for_businesses).never
          DeletionHelper.expects(:delete_all_for_organizations).never
          ResetJob.perform_now(initialization_only: true)
        end

        test "it enqueues initialization jobs" do
          ResetJob.perform_now(business_ids: [@biz_1.id], organization_ids: @orgs_2.map(&:id), initialization_only: true)
          assert_enqueued_jobs(1, only: ::SecurityOverviewAnalytics::Initialization::BusinessJob)
          assert_enqueued_jobs(@orgs_2.size, only: ::SecurityOverviewAnalytics::Initialization::OrganizationJob)
        end
      end

      Initialization::Type.all.each do |type|
        type_name = type.serialize

        context "when initialization type is #{type_name}", skip_enterprise: true do
          test "it deletes everything for the private beta business and organization IDs" do
            DeletionHelper.expects(:delete_all_for_businesses).with(business_ids: [@biz_1.id], type:)
            DeletionHelper.expects(:delete_all_for_organizations).with(organization_ids: @orgs_2.map(&:id), type:)
            ResetJob.perform_now(private_beta: true, type: type_name)
          end

          test "it deletes everything for the provided business and organization IDs" do
            DeletionHelper.expects(:delete_all_for_businesses).with(business_ids: [@biz_2.id], type:)
            DeletionHelper.expects(:delete_all_for_organizations).with(organization_ids: @orgs_1.map(&:id), type:)
            ResetJob.perform_now(business_ids: [@biz_2.id], organization_ids: @orgs_1.map(&:id), type: type_name)
          end

          test "it enqueues initialization jobs with the correct type" do
            ResetJob.perform_now(private_beta: true, type: type_name)
            assert_enqueued_jobs(1, only: ::SecurityOverviewAnalytics::Initialization::BusinessJob)
            assert_enqueued_with(job: ::SecurityOverviewAnalytics::Initialization::BusinessJob, args: [business_id: @biz_1.id, type: type_name])

            assert_enqueued_jobs(@orgs_2.size, only: ::SecurityOverviewAnalytics::Initialization::OrganizationJob)
            @orgs_2.each do |org|
              assert_enqueued_with(job: ::SecurityOverviewAnalytics::Initialization::OrganizationJob, args: [organization_id: org.id, type: type_name])
            end
          end
        end
      end
    end
  end
end
