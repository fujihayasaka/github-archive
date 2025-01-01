# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::Organizations::SeatManagement::PayloadBuilders::OrganizationTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags
  include AvatarHelper

  fixtures do
    @organization = T.let(create(:copilot_for_business_enabled_organization), T.untyped) # rubocop:todo Sorbet/ForbidTUntyped
    @assigned_user = T.let(create(:user), T.untyped) # rubocop:todo Sorbet/ForbidTUntyped
  end

  setup do
    Copilot::Organization.new(@organization).seat_management_selected_teams_and_users!
  end

  def seat_detail(assignable)
    Copilot::Organizations::SeatManagement::Detail.new(organization: @organization,
                                                       seat_assignment_id: 0,
                                                       assignable: assignable,
                                                       pending_cancellation_date: nil,
                                                       last_activity_at: Time.at(0),
                                                       assigned_user: @assigned_user)
  end

  context "#call" do
    context "when the seat_detail does not have an assignable" do
      test "returns nil" do
        builder = Copilot::Organizations::SeatManagement::PayloadBuilders::Organization.new(seat_detail: seat_detail(nil))

        assert_nil builder.call
      end
    end

    context "when the seat_detail has an assignable" do
      test "returns the correct payload based off of assigned_user rather than assignable" do
        expected = {
          assignable_type: "Organization",
          pending_cancellation_date: nil,
          last_activity_at: Time.at(0),
          invitation_date: nil,
          invitation_expired: nil,
          assignable: {
            id: @assigned_user.id,
            display_name: @assigned_user.profile_name,
            login: @assigned_user.display_login,
            avatar_url: avatar_url_for(@assigned_user, 96),
            slug: nil,
            combined_slug: nil,
            member_count: nil,
            member_ids: nil,
            email: nil,
            invitee: nil
          },
        }
        builder = Copilot::Organizations::SeatManagement::PayloadBuilders::Organization.new(seat_detail: seat_detail(@organization))

        assert_equal expected, builder.call
      end
    end
  end
end if GitHub.copilot_enabled?
