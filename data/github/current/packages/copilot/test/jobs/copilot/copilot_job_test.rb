# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::CopilotJobTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include JobTestHelper
  include DogstatsTestHelpers
  include CopilotTestHelper # automatically disables Copilot feature flags

  context "flag_enabled" do
    test "handles a single flag as one does" do
      disable_feature_flag(:banana)
      CopilotJob.gate_with_feature_flag(:banana)
      job = CopilotJob.new

      refute job.flag_enabled

      enable_feature_flag(:banana)

      assert job.flag_enabled
    end

    test "handles multiple flags as one does" do
      disable_feature_flag(:banana)
      disable_feature_flag(:hammock)

      CopilotJob.gate_with_feature_flag(%i(banana hammock))
      job = CopilotJob.new

      refute job.flag_enabled

      enable_feature_flag(:banana)

      refute job.flag_enabled

      enable_feature_flag(:hammock)

      assert job.flag_enabled
    end
  end

  context "org_and_biz_ids_through_seats" do
    test "returns the enterprise ids" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      organization.add_member(user)
      seat = create(:copilot_seat, organization: organization, assigned_user: user)

      other_organization = create(:copilot_for_business_enabled_organization)
      other_user = create(:user)
      other_organization.add_member(other_user)
      other_seat = create(:copilot_seat, organization: other_organization, assigned_user: other_user)

      standalone_organization = create(:organization)
      Copilot::Organization.new(standalone_organization).enable_copilot!
      standalone_seat = create(:copilot_seat, organization: standalone_organization)

      entity_ids = CopilotJob.new.org_and_biz_ids_through_seats
      T.must(entity_ids[:business_ids]).to_a.sort!
      T.must(entity_ids[:organization_ids]).to_a.sort!

      expected = {
        business_ids: Set.new([seat.organization.business.id, other_seat.organization.business.id].sort),
        organization_ids: Set.new([standalone_seat.organization.id])
      }

      assert_equal expected, entity_ids
    end
  end
end if GitHub.copilot_enabled?
