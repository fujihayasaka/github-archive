# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Licensing::TriggerScheduledLicensingModelTransitionsJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @business1 = create(:business)
    @business2 = create(:business)
  end

  test "enqueues transition jobs from scheduled records" do
    Timecop.freeze do
      create(:licensing_licensing_model_transition, customer: @business1.customer)
      create(:licensing_licensing_model_transition, customer: @business2.customer)

      assert_enqueued_jobs 2, only: Licensing::TransitionEnterpriseToMeteredLicensingJob do
        Licensing::TriggerScheduledLicensingModelTransitionsJob.perform_now
      end
    end
  end

  test "does not re-enqueue a job that has already been processed" do
    Timecop.freeze do
      create(:licensing_licensing_model_transition, customer: @business1.customer)
      create(:licensing_licensing_model_transition, customer: @business2.customer, status: "running")

      assert_enqueued_jobs 1, only: Licensing::TransitionEnterpriseToMeteredLicensingJob do
        Licensing::TriggerScheduledLicensingModelTransitionsJob.perform_now
      end
    end
  end
end unless GitHub.single_business_environment?
