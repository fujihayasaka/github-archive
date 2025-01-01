# typed: strict
# frozen_string_literal: true

require "test_helper"

class Copilot::Businesses::CSVExportTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  fixtures do
    @standalone_business = T.let(create(:business, :enterprise_managed_business, seats_plan_type: :basic), T.untyped) # rubocop:todo Sorbet/ForbidTUntyped
    @enterprise_team = T.let(create(:copilot_enterprise_team, business: @standalone_business), T.untyped) # rubocop:todo Sorbet/ForbidTUntyped
    @enterprise_team_assignment = T.let(EnterpriseTeamAssignment.create!(enterprise_team: @enterprise_team, assignment_type: "copilot"), T.untyped) # rubocop:todo Sorbet/ForbidTUntyped
    @standalone_seat_assignment = T.let(create(:copilot_seat_assignment, :enterprise_team, assignable: @enterprise_team, owner: @standalone_business), T.untyped) # rubocop:todo Sorbet/ForbidTUntyped
  end

  context "to_csv" do
    context "when generating a csv for a standard business with orgs" do
      test "business has no seats or seat assignments" do
        business = create(:business)
        assert_nil Copilot::Business.new(business).to_csv
      end

      test "business has seat assignments but no seats" do
        assignment = create(:copilot_seat_assignment, :team, organization: create(:copilot_for_business_enabled_organization))
        organization = assignment.organization.reload
        assert organization.business.present?
        assert_nil Copilot::Business.new(organization.business).to_csv
      end

      test "organization has seats - teams" do
        assignment = create(:copilot_seat_assignment, :team, organization: create(:copilot_for_business_enabled_organization))
        organization = assignment.organization.reload

        user = create(:user)

        team = assignment.assignable
        team.add_member(user)

        assignment.convert_to_seats
        assignment.reload

        assignment.seats.each do |seat|
          create(:copilot_aggregate_usage_detail, user: seat.assigned_user, usage_date: Date.new(2020, 1, 1), editor_details: "editor_details")
        end
        headers, body = T.must(Copilot::Business.new(organization.business).to_csv).split("\n")
        assert_equal Copilot::Businesses::CsvExport::HEADER, T.must(headers).split(",")
        assert_equal body, "#{user.display_login},#{organization.login},Active,2020-01-01,editor_details"
      end

      test "business has multiple seats - teams" do
        assignment = create(:copilot_seat_assignment, :team, organization: create(:copilot_for_business_enabled_organization))
        organization = assignment.organization.reload

        user = create(:user, login: "firstuser")
        other_user = create(:user, login: "otheruser")
        team = assignment.assignable
        team.add_member(user)
        team.add_member(other_user)
        assignment.convert_to_seats
        assignment.reload

        assignment.seats.each do |seat|
          create(:copilot_aggregate_usage_detail, user: seat.assigned_user, usage_date: Date.new(2020, 1, 1), editor_details: "editor_details")
        end
        headers, first, second = T.must(Copilot::Business.new(organization.business).to_csv).split("\n")
        assert_equal Copilot::Businesses::CsvExport::HEADER, T.must(headers).split(",")
        assert_match first, "#{user.display_login},#{organization.login},Active,2020-01-01,editor_details"
        assert_match second, "#{other_user.display_login},#{organization.login},Active,2020-01-01,editor_details"
      end

      test "business has multiple seats - teams pending cancellation" do
        assignment = create(:copilot_seat_assignment, :team, organization: create(:copilot_for_business_enabled_organization))
        organization = assignment.organization.reload

        user = create(:user, login: "firstuser")
        other_user = create(:user, login: "otheruser")
        team = assignment.assignable
        team.add_member(user)
        team.add_member(other_user)
        assignment.convert_to_seats
        assignment.unassign!(organization.admins.first)
        assignment.reload

        assignment.seats.each do |seat|
          create(:copilot_aggregate_usage_detail, user: seat.assigned_user, usage_date: Date.new(2020, 1, 1), editor_details: "editor_details")
        end
        headers, first, second = T.must(Copilot::Business.new(organization.business).to_csv).split("\n")
        assert_equal Copilot::Businesses::CsvExport::HEADER, T.must(headers).split(",")
        assert_match first, "#{user.display_login},#{organization.login},Pending cancellation #{assignment.pending_cancellation_date.strftime("%Y-%m-%d")},2020-01-01,editor_details"
        assert_match second, "#{other_user.display_login},#{organization.login},Pending cancellation #{assignment.pending_cancellation_date.strftime("%Y-%m-%d")},2020-01-01,editor_details"
      end

      test "business has seats - individual user" do
        assignment = create(:copilot_seat_assignment, :user, organization: create(:copilot_for_business_enabled_organization))
        organization = assignment.organization.reload
        user = assignment.assignable
        assignment.convert_to_seats
        assignment.reload

        assignment.seats.each do |seat|
          create(:copilot_aggregate_usage_detail, user: seat.assigned_user, usage_date: Date.new(2020, 1, 1), editor_details: "editor_details")
        end
        headers, body = T.must(Copilot::Business.new(organization.business).to_csv).split("\n")
        assert_equal Copilot::Businesses::CsvExport::HEADER, T.must(headers).split(",")
        assert_equal body, "#{user.display_login},#{organization.login},Active,2020-01-01,editor_details"
      end

      test "business has seats - individual user pending cancellation" do
        assignment = create(:copilot_seat_assignment, :user, organization: create(:copilot_for_business_enabled_organization))
        organization = assignment.organization.reload
        user = assignment.assignable
        assignment.convert_to_seats
        assignment.reload
        assignment.unassign!(organization.admins.first)

        assignment.seats.each do |seat|
          create(:copilot_aggregate_usage_detail, user: seat.assigned_user, usage_date: Date.new(2020, 1, 1), editor_details: "editor_details")
        end
        headers, body = T.must(Copilot::Business.new(organization.business).to_csv).split("\n")
        assert_equal Copilot::Businesses::CsvExport::HEADER, T.must(headers).split(",")
        assert_equal body, "#{user.display_login},#{organization.login},Pending cancellation #{assignment.pending_cancellation_date.strftime("%Y-%m-%d")},2020-01-01,editor_details"
      end

      test "business has seats - individual user in two organizations" do
        first_assignment = create(:copilot_seat_assignment, :user, organization: create(:copilot_for_business_enabled_organization))
        first_organization = first_assignment.organization.reload
        first_user = first_assignment.assignable.reload
        business = first_organization.business
        first_assignment.convert_to_seats

        second_organization = create(:copilot_for_business_enabled_organization, business: business)
        second_organization.add_member(first_user)

        second_assignment = create(:copilot_seat_assignment, :user, assignable: first_user, organization: second_organization)
        second_user = second_assignment.assignable.reload
        second_assignment.convert_to_seats

        refute_equal first_organization.id, second_organization.id
        assert_equal first_organization.business.id, second_organization.business.id
        assert_equal first_user.id, second_user.id

        first_assignment.seats.each do |seat|
          create(:copilot_aggregate_usage_detail, user: seat.assigned_user, usage_date: Date.new(2020, 1, 1), editor_details: "editor_details")
        end
        headers, body = T.must(Copilot::Business.new(business).to_csv).split("\n")
        assert_equal Copilot::Businesses::CsvExport::HEADER, T.must(headers).split(",")
        assert_includes body, first_user.display_login
        assert_includes body, first_organization.login
        assert_includes body, second_organization.login
      end
    end

    context "when generating a csv for a standalone business" do
      test "returns nil if the business has no seats" do
        assert_nil Copilot::Business.new(@standalone_business).to_csv
      end

      test "generates rows of active seats" do
        @standalone_seat_assignment.convert_to_seats

        @enterprise_team.member_user_ids.each do |user_id|
          create(:copilot_aggregate_usage_detail, user_id: user_id, usage_date: Date.new(2020, 1, 1), editor_details: "editor_details")
        end

        headers, *rows = T.must(Copilot::Business.new(@standalone_business.reload).to_csv).split("\n")

        assert_equal Copilot::Businesses::CsvExport::STANDALONE_HEADER, T.must(headers).split(",")
        assert rows.size.positive?
        assert rows.size, @enterprise_team.member_user_ids.size
        @enterprise_team.member_user_ids.each do |user_id|
          assert_includes rows, "#{User.find(user_id).display_login},Active,2020-01-01,editor_details"
        end
      end

      test "generates rows of seats pending cancellation" do
        @standalone_seat_assignment.convert_to_seats
        @standalone_seat_assignment.update!(pending_cancellation_date: Date.new(2022, 1, 1))

        @enterprise_team.member_user_ids.each do |user_id|
          create(:copilot_aggregate_usage_detail, user_id: user_id, usage_date: Date.new(2020, 1, 1), editor_details: "editor_details")
        end

        headers, *rows = T.must(Copilot::Business.new(@standalone_business.reload).to_csv).split("\n")

        assert_equal Copilot::Businesses::CsvExport::STANDALONE_HEADER, T.must(headers).split(",")
        assert rows.size.positive?
        assert rows.size, @enterprise_team.member_user_ids.size
        expected_cancellation_date = "Pending cancellation #{@standalone_seat_assignment.pending_cancellation_date.strftime("%Y-%m-%d")}"
        @enterprise_team.member_user_ids.each do |user_id|
          assert_includes rows, "#{User.find(user_id).display_login},#{expected_cancellation_date},2020-01-01,editor_details"
        end
      end
    end
  end
end if GitHub.copilot_enabled?
