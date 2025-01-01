# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::TelemetrySnapshotTest < GitHub::TestCase
  include DogstatsTestHelpers
  include CopilotTestHelper # automatically disables Copilot feature flags
  include GitHub::QueryAssertionTestHelpers

  fixtures do
    @user = create(:user)
  end

  context "builds event" do
    test "plain user without access doesn't generate anything" do
      snapshot = Copilot::TelemetrySnapshot.new(Copilot::User.new(@user))
      refute snapshot.telemetry_snapshot_id
    end

    test "cfi user doesn't generate anything" do
      user = create(:user)
      create(
        :copilot_free_user,
        user: user,
        subscribed: true,
        free_user_type: "Educational",
        last_checked_date: Date.new(9999, 12, 31),
      )
      snapshot = Copilot::TelemetrySnapshot.new(Copilot::User.new(user))
      refute snapshot.telemetry_snapshot_id
    end

    test "CFB Seat - works with feature flag" do
      seat = create(:copilot_seat)
      user = seat.assigned_user
      organization = seat.seat_assignment.owner
      business = organization.business
      team = create(:team, organization: organization)
      team.add_member(user)
      Copilot::User.any_instance.expects(:copilot_authorizer_object).returns(stub(access_type: :COPILOT_FOR_BUSINESS_SEAT))
      Copilot::User.any_instance.expects(:copilot_businesses).returns([Copilot::Business.new(business)])
      Copilot::User.any_instance.expects(:copilot_organizations).returns([Copilot::Organization.new(organization)])
      Copilot::User.any_instance.expects(:enterprise_team_ids).returns([1, 3, 5])
      val = "u:#{user.id}|a:COPILOT_FOR_BUSINESS_SEAT|s:token_endpoint|t:|e:#{business.id}|o:#{organization.id}|et:1,3,5"

      snapshot = Copilot::TelemetrySnapshot.new(Copilot::User.new(user))
      assert_equal "ts-#{Digest::SHA256.hexdigest(val)}", snapshot.telemetry_snapshot_id
      assert_equal :COPILOT_FOR_BUSINESS_SEAT, snapshot.access_type
      assert_equal "token_endpoint", snapshot.source
      assert_equal business.id, T.must(snapshot.businesses.first).id
      assert_equal organization.id, T.must(snapshot.organizations.first).id
      assert_equal [1, 3, 5], snapshot.enterprise_team_ids
    end
  end
end if GitHub.copilot_enabled?
