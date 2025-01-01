# typed: strict
# frozen_string_literal: true

require "test_helper"

class Copilot::Organizations::SeatManagement::DetailTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  context "#sortable_name" do
    context "when the assignable is a team" do
      test "it returns the team's slug and members display logins" do
        org = FactoryBot.create(:copilot_for_business_enabled_organization)
        team = FactoryBot.create(:team, organization: org, name: "team-slug")
        user = FactoryBot.create(:user, login: "user-login")
        user2 = FactoryBot.create(:user, login: "user-login2")

        org.add_member(user)
        org.add_member(user2)
        team.add_member(user)
        team.add_member(user2)

        detail = Copilot::Organizations::SeatManagement::Detail.new(
          organization: org,
          seat_assignment_id: 0,
          assignable: team,
          pending_cancellation_date: Date.current,
          last_activity_at: Time.now,
        )

        assert_equal "team-slug user-login user-login2", detail.sortable_name
      end
    end

    context "when the assignable is an organization invitation" do
      test "it returns the invitee's login when the invitee exists" do
        invitee = User.new(login: "invitee-login")
        invitation = OrganizationInvitation.new(email: "invitee@email.com", invitee: invitee)
        org = build(:organization)
        detail = Copilot::Organizations::SeatManagement::Detail.new(
          organization: org,
          seat_assignment_id: 0,
          assignable: invitation,
          pending_cancellation_date: Date.current,
          last_activity_at: Time.now,
        )

        assert_equal "invitee-login", detail.sortable_name
      end

      test "it returns the invitation email when the invitee does not exist" do
        invitation = OrganizationInvitation.new(email: "invitee@email.com")
        org = build(:organization)
        detail = Copilot::Organizations::SeatManagement::Detail.new(
          organization: org,
          seat_assignment_id: 0,
          assignable: invitation,
          pending_cancellation_date: Date.current,
          last_activity_at: Time.now,
        )

        assert_equal "invitee@email.com", detail.sortable_name
      end
    end

    context "when the assignable is a user" do
      test "it returns the user's login" do
        user = User.new(login: "user-login")
        org = build(:organization)
        detail = Copilot::Organizations::SeatManagement::Detail.new(
          organization: org,
          seat_assignment_id: 0,
          assignable: user,
          pending_cancellation_date: Date.current,
          last_activity_at: Time.now,
        )

        assert_equal "user-login", detail.sortable_name
      end
    end

    context "when the assignable is nil" do
      test "it returns an empty string" do
        org = build(:organization)
        detail = Copilot::Organizations::SeatManagement::Detail.new(
          organization: org,
          seat_assignment_id: 0,
          assignable: nil,
          pending_cancellation_date: Date.current,
          last_activity_at: Time.now,
        )

        assert_equal "", detail.sortable_name
      end
    end
  end
end if GitHub.copilot_enabled?
