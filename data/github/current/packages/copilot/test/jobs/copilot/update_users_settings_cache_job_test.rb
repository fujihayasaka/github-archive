# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::UpdateUsersSettingsCacheJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  context "perform" do
    test "it will call create_copilot_settings_cache with the users" do
      org = create(:copilot_for_business_enabled_organization)
      seat1 = create(:copilot_seat, organization: org)
      seat2 = create(:copilot_seat, organization: org)
      # this is a seat that is not part of the org and should be excluded
      create(:copilot_seat)
      seat4 = create(:copilot_seat, organization: org)

      mock = Minitest::Mock.new
      3.times { mock.expect(:create_copilot_settings_cache, true, [Copilot::Public::User::CURRENT_VERSION]) }
      Copilot::User.expects(:new).with(seat1.assigned_user).returns(mock)
      Copilot::User.expects(:new).with(seat2.assigned_user).returns(mock)
      # seat 3 is not invoked
      Copilot::User.expects(:new).with(seat4.assigned_user).returns(mock)

      Copilot::UpdateUserSettingsCacheJob.perform_now(org.id, seat1.id, seat4.id)
    end

    test "does not re-enqueue itself if hashed value is the same while ignoring timestamps" do
      seat = create(:copilot_seat)
      org = seat.organization
      Copilot::Configuration.any_instance.stubs(:attributes).returns(
        { "chat_enabled": 1, "created_at": "2024-09-04 00:00:00.000000 +0000" }.with_indifferent_access,
        { "chat_enabled": 1, "created_at": "2024-09-03 00:00:00.000000 +0000" }.with_indifferent_access,
      )
      Copilot::UpdateUserSettingsCacheJob.perform_now(org.id, seat.id, seat.id)
      refute enqueued_jobs.any? { |j| j[:job] == Copilot::UpdateUserSettingsCacheJob }
    end

    test "does re-enqueue itself with the same arguments if hashed value has change" do
      seat = create(:copilot_seat)
      org = seat.organization
      Copilot::Configuration.any_instance.stubs(:attributes).returns(
        { "chat_enabled": 0 },
        { "chat_enabled": 1 }
      )
      Copilot::UpdateUserSettingsCacheJob.perform_now(org.id, seat.id, seat.id)
      job = enqueued_jobs.find { |j| j[:job] == Copilot::UpdateUserSettingsCacheJob }
      assert_equal [org.id, seat.id, seat.id], job[:args]
    end

    test "resolves tenant on a multi-tenant enterprise with business owner" do
      on_multi_tenant_enterprise do
        # Simulate no tenant being set
        GitHub::CurrentTenant.remove
        assert_nil GitHub::CurrentTenant.get
        business = create(:business)
        organization = create(:organization, business: business)

        Copilot::UpdateUserSettingsCacheJob.perform_now(organization.id, 0, 1)

        refute_nil GitHub::CurrentTenant.get
        assert_equal business, GitHub::CurrentTenant.get
      end
    end
  end
end if GitHub.copilot_enabled?
