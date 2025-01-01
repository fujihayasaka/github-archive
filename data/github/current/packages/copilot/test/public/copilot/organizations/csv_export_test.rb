# typed: strict
# frozen_string_literal: true

require "test_helper"

class Copilot::Organizations::CSVExportTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  context "to_csv" do
    test "organization has no seats or seat assignments" do
      organization = create(:organization)
      assert_nil Copilot::Organization.new(organization).to_csv
    end

    test "organization has seat assignments but no seats" do
      assignment = create(:copilot_seat_assignment, :team)
      assert_nil Copilot::Organization.new(assignment.organization).to_csv
    end

    test "organization has seats - teams" do
      user = create(:user)
      assignment = create(:copilot_seat_assignment, :team)
      team = assignment.assignable
      team.add_member(user)
      assignment.convert_to_seats
      assignment.reload

      assignment.seats.each do |seat|
        create(:copilot_aggregate_usage_detail, user: seat.assigned_user, usage_date: Date.new(2020, 1, 1), editor_details: "editor_details")
      end
      headers, body = T.must(Copilot::Organization.new(assignment.organization).to_csv).split("\n")
      assert_equal Copilot::Organizations::CsvExport::HEADER, T.must(headers).split(",")
      assert_equal body, "#{user.display_login},Active,#{team.name},2020-01-01,editor_details"
    end

    test "organization has multiple seats - teams" do
      user = create(:user, login: "firstuser")
      other_user = create(:user, login: "otheruser")
      assignment = create(:copilot_seat_assignment, :team)
      team = assignment.assignable
      team.add_member(user)
      team.add_member(other_user)
      assignment.convert_to_seats
      assignment.reload

      assignment.seats.each do |seat|
        create(:copilot_aggregate_usage_detail, user: seat.assigned_user, usage_date: Date.new(2020, 1, 1), editor_details: "editor_details")
      end
      headers, first, second = T.must(Copilot::Organization.new(assignment.organization).to_csv).split("\n")
      assert_equal Copilot::Organizations::CsvExport::HEADER, T.must(headers).split(",")
      assert_match first, "#{user.display_login},Active,#{team.name},2020-01-01,editor_details"
      assert_match second, "#{other_user.display_login},#{other_user.name},Active,#{team.name},2020-01-01,editor_details"
    end

    test "organization has seats - teams pending cancellation" do
      user = create(:user)
      assignment = create(:copilot_seat_assignment, :team)
      team = assignment.assignable
      team.add_member(user)
      assignment.convert_to_seats
      assignment.unassign!(assignment.organization.admins.first)
      assignment.reload

      assignment.seats.each do |seat|
        create(:copilot_aggregate_usage_detail, user: seat.assigned_user, usage_date: Date.new(2020, 1, 1), editor_details: "editor_details")
      end
      headers, body = T.must(Copilot::Organization.new(assignment.organization).to_csv).split("\n")
      assert_equal Copilot::Organizations::CsvExport::HEADER, T.must(headers).split(",")
      assert_equal body, "#{user.display_login},Pending cancellation #{assignment.pending_cancellation_date.strftime("%Y-%m-%d")},#{team.name},2020-01-01,editor_details"
    end

    test "organization has seats - individual user" do
      assignment = create(:copilot_seat_assignment, :user)
      user = assignment.assignable
      assignment.convert_to_seats
      assignment.reload

      assignment.seats.each do |seat|
        create(:copilot_aggregate_usage_detail, user: seat.assigned_user, usage_date: Date.new(2020, 1, 1), editor_details: "editor_details")
      end
      headers, body = T.must(Copilot::Organization.new(assignment.organization).to_csv).split("\n")
      assert_equal Copilot::Organizations::CsvExport::HEADER, T.must(headers).split(",")
      assert_equal body, "#{user.display_login},Active,No team,2020-01-01,editor_details"
    end

    test "organization has seats - individual user pending cancellation" do
      assignment = create(:copilot_seat_assignment, :user)
      user = assignment.assignable
      assignment.convert_to_seats
      assignment.unassign!(assignment.organization.admins.first)
      assignment.reload

      assignment.seats.each do |seat|
        create(:copilot_aggregate_usage_detail, user: seat.assigned_user, usage_date: Date.new(2020, 1, 1), editor_details: "editor_details")
      end
      headers, body = T.must(Copilot::Organization.new(assignment.organization).to_csv).split("\n")
      assert_equal Copilot::Organizations::CsvExport::HEADER, T.must(headers).split(",")
      assert_equal body, "#{user.display_login},Pending cancellation #{assignment.pending_cancellation_date.strftime("%Y-%m-%d")},No team,2020-01-01,editor_details"
    end
  end
end if GitHub.copilot_enabled?
