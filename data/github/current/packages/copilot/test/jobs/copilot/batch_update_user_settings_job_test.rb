# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::BatchUpdateUserSettingsJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  context "perform" do
    test "it will do nothing if the org has no seats" do
      org = create(:organization)
      assert_no_changes -> { enqueued_jobs.count } do
        Copilot::BatchUpdateUserSettingsJob.perform_now(org.id)
      end
    end

    test "it will enqueue with a single seat" do
      seat = create(:copilot_seat)
      org_id = seat.organization.id
      Copilot::BatchUpdateUserSettingsJob.perform_now(org_id)
      job = enqueued_jobs[-1]

      assert_equal Copilot::UpdateUserSettingsCacheJob, job[:job]
      assert_equal [org_id, seat.id, seat.id], job[:args]
    end

    test "it will enqueue with multiple seats" do
      org = create(:organization)
      # create more seats than the size of the batch, which will enqueue 2 jobs
      seat_ids = (Copilot::BatchUpdateUserSettingsJob::BATCH_SIZE + 1).times.map { create(:copilot_seat, organization: org).id }

      org_id = org.id
      Copilot::BatchUpdateUserSettingsJob.perform_now(org_id)
      # first enqueued
      batch_job_1 = enqueued_jobs[-2]
      # next enqueued
      batch_job_2 = enqueued_jobs[-1]

      assert_equal Copilot::UpdateUserSettingsCacheJob, batch_job_1[:job]
      assert_equal [org_id, seat_ids[0], seat_ids[-2]], batch_job_1[:args]
      assert_equal Copilot::UpdateUserSettingsCacheJob, batch_job_2[:job]
      assert_equal [org_id, seat_ids[-1], seat_ids[-1]], batch_job_2[:args]
    end

    test "resolves tenant on a multi-tenant enterprise with business owner" do
      on_multi_tenant_enterprise do
        org = create(:organization)
        business = create(:business, organizations: [org])
        # Simulate no tenant being set
        GitHub::CurrentTenant.remove
        assert_nil GitHub::CurrentTenant.get

        Copilot::BatchUpdateUserSettingsJob.perform_now(org.id)

        assert_equal business, GitHub::CurrentTenant.get
      end
    end
  end
end if GitHub.copilot_enabled?
