# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  class Initialization
    class BatchedResetJobTest < GitHub::TestCase
      include DogstatsTestHelpers

      fixtures do
        @biz = create(:business)
        @orgs = create_list(:organization, 4, business: @biz)
      end

      setup do
        TenantValidationHelper.stubs(:is_owner_in_scope?).returns(true)
      end

      context "#perform" do
        test "reports and queues reset job on found organizations" do
          ResetJob.expects(:perform_later).with(organization_ids: @orgs.map(&:id), type: nil, initialization_only: false).once

          assert_performed_jobs 1, only: BatchedResetJob do
            BatchedResetJob.perform_later
          end
        end

        test "reports and queues reset job on found organizations based on inputs" do
          target_org_id = @orgs.first.id
          ResetJob.expects(:perform_later).with(organization_ids: [target_org_id], type: Type::SecretScanningAlert.serialize, initialization_only: false).once

          assert_performed_jobs 1, only: BatchedResetJob do
            BatchedResetJob.perform_later(organization_ids: [target_org_id], type: Type::SecretScanningAlert.serialize)
          end
        end

        test "reports and queues reset job with initialization_only input" do
          ResetJob.expects(:perform_later).with(organization_ids: @orgs.map(&:id), type: nil, initialization_only: true).once

          assert_performed_jobs 1, only: BatchedResetJob do
            BatchedResetJob.perform_later(initialization_only: true)
          end
        end

        test "does not queue reset job with initialization_only input if org has all types initialized" do
          ResetJob.expects(:perform_later).with(organization_ids: @orgs.map(&:id), type: nil, initialization_only: true).never
          @orgs.each do |org|
            Initialization.for(org).set_all_to_initialized
          end

          assert_performed_jobs 1, only: BatchedResetJob do
            BatchedResetJob.perform_later(initialization_only: true)
          end
        end

        test "reports and queues reset job with initialization_only input when initialization type provided" do
          ResetJob.expects(:perform_later).with(organization_ids: @orgs.map(&:id), type: Type::SecretScanningAlert.serialize, initialization_only: true).once

          assert_performed_jobs 1, only: BatchedResetJob do
            BatchedResetJob.perform_later(type: Type::SecretScanningAlert.serialize, initialization_only: true)
          end
        end

        test "does not queue reset job with initialization_only input if the target type is initialized" do
          ResetJob.expects(:perform_later).with(organization_ids: @orgs.map(&:id), type: Type::SecretScanningAlert.serialize, initialization_only: true).never
          @orgs.each do |org|
            Initialization.for(org).set_type_to_initialized(type: Type::SecretScanningAlert)
          end

          assert_performed_jobs 1, only: BatchedResetJob do
            BatchedResetJob.perform_later(type: Type::SecretScanningAlert.serialize, initialization_only: true)
          end
        end

        test "does not queue reset job if target org not in scope" do
          TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)
          ResetJob.expects(:perform_later).never

          assert_performed_jobs 1, only: BatchedResetJob do
            BatchedResetJob.perform_later
          end
        end

        test "does not queue reset job for private beta business and orgs" do
          non_biz_org1 = create(:organization)
          non_biz_org2 = create(:organization)

          GitHub.flipper[:security_center_private_beta].disable
          feature = T.let(FlipperFeature.send(:find_or_create_by, name: :security_center_private_beta), FlipperFeature)
          feature.enable(@biz)
          feature.enable(non_biz_org1)

          ResetJob.expects(:perform_later).with(organization_ids: [non_biz_org2.id], type: nil, initialization_only: false).once

          assert_performed_jobs 1, only: BatchedResetJob do
            BatchedResetJob.perform_later
          end
        end

        test "enqueues reset job also for private beta business and orgs if requested" do
          non_biz_org1 = create(:organization)
          non_biz_org2 = create(:organization)

          GitHub.flipper[:security_center_private_beta].disable
          feature = T.let(FlipperFeature.send(:find_or_create_by, name: :security_center_private_beta), FlipperFeature)
          feature.enable(@biz)
          feature.enable(non_biz_org1)

          ResetJob.expects(:perform_later).with(organization_ids: [
            @orgs.map(&:id),
            non_biz_org1.id,
            non_biz_org2.id
          ].flatten, type: nil, initialization_only: false).once

          assert_performed_jobs 1, only: BatchedResetJob do
            BatchedResetJob.perform_later(include_private_beta: true)
          end
        end
      end

      context "batched job" do
        test "queues subsequent jobs for batching" do
          # Total 9 orgs including ones created from fixtures.
          5.times do
            create(:organization)
          end

          BatchedResetJob.stub_const(:BATCH_SIZE, 5) do
            assert_performed_jobs 2, only: BatchedResetJob do
              perform_enqueued_jobs only: BatchedResetJob do
                BatchedResetJob.perform_later
              end
            end
          end
        end
      end

      context "hash lock" do
        test "does not allow enqueue multiple jobs for default inputs" do
          assert_enqueued_jobs 1, only: BatchedResetJob do
            BatchedResetJob.perform_later
            BatchedResetJob.perform_later(offset_item_id: 123)
          end
        end

        test "does not allow enqueue multiple jobs for default inputs with the same types" do
          assert_enqueued_jobs 1, only: BatchedResetJob do
            BatchedResetJob.perform_later(type: Type::SecretScanningAlert.serialize)
            BatchedResetJob.perform_later(type: Type::SecretScanningAlert.serialize)
          end
        end

        test "does not allow enqueue multiple jobs for default inputs with the same target orgs" do
          assert_enqueued_jobs 1, only: BatchedResetJob do
            BatchedResetJob.perform_later(organization_ids: [1, 2])
            BatchedResetJob.perform_later(organization_ids: [1, 2])
          end
        end

        test "does not allow enqueue multiple jobs for default inputs with the same target businesses" do
          assert_enqueued_jobs 1, only: BatchedResetJob do
            BatchedResetJob.perform_later(business_ids: [1, 2])
            BatchedResetJob.perform_later(business_ids: [1, 2])
          end
        end
      end
    end
  end
end
