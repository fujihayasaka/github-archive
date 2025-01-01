# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityOverviewAnalytics
  class Initialization
    module ScopeStrategy
      class BusinessTest < GitHub::TestCase
        include JobTestHelper

        fixtures do
          @business = create(:business)
          @emu_business = create(:business, :enterprise_managed) if !GitHub.enterprise?
        end

        context "#enqueue for ghec emu business" do
          test "enqueues a business initialization jobs for organizations and users" do
            strategy = ScopeStrategy::Business.new(business: @emu_business)

            assert_enqueued_jobs(2, only: Initialization::BusinessJob) do
              strategy.enqueue
            end

            assert_enqueued_with(job: Initialization::BusinessJob, args: [business_id: @emu_business.id, type: Initialization::Type::Organizations.serialize])
            assert_enqueued_with(job: Initialization::BusinessJob, args: [business_id: @emu_business.id, type: Initialization::Type::Users.serialize])
          end
        end if !GitHub.enterprise?

        context "#enqueue for ghec non-emu business" do
          test "enqueues a business initialization jobs for organizations only" do
            strategy = ScopeStrategy::Business.new(business: @business)

            assert_enqueued_jobs(1, only: Initialization::BusinessJob) do
              strategy.enqueue
            end

            assert_enqueued_with(job: Initialization::BusinessJob, args: [business_id: @business.id, type: Initialization::Type::Organizations.serialize])
          end
        end if !GitHub.enterprise?

        context "#enqueue for ghes business" do
          test "enqueues a business initialization jobs for organizations and users" do
            strategy = ScopeStrategy::Business.new(business: @business)

            assert_enqueued_jobs(2, only: Initialization::BusinessJob) do
              strategy.enqueue
            end

            assert_enqueued_with(job: Initialization::BusinessJob, args: [business_id: @business.id, type: Initialization::Type::Organizations.serialize])
            assert_enqueued_with(job: Initialization::BusinessJob, args: [business_id: @business.id, type: Initialization::Type::Users.serialize])
          end
        end if GitHub.enterprise?
      end
    end
  end
end
