# typed: strict
# frozen_string_literal: true

require "test_helper"

class Copilot::Organizations::TokenUsageTest < GitHub::TestCase
  context "last_token_activity" do
    context "users" do
      test "returns the last token activity for a user" do
        organization = create(:organization)
        copilot_organization = Copilot::Organization.new(organization)
        user = create(:user)
        organization.add_member(user)
        create(:copilot_aggregate_usage_detail, user: user, usage_date: Date.today - 2.days)
        detail = create(:copilot_aggregate_usage_detail, user: user, usage_date: Date.today - 1.day)

        result = copilot_organization.last_token_activity(user)
        assert_equal detail.updated_at.time, result
      end

      test "returns nil if there is no token activity for a user" do
        organization = create(:organization)
        copilot_organization = Copilot::Organization.new(organization)
        user = create(:user)
        organization.add_member(user)

        refute copilot_organization.last_token_activity(user)
      end
    end

    context "teams" do
      test "returns the last token activity for a team" do
        organization = create(:organization)
        copilot_organization = Copilot::Organization.new(organization)
        user = create(:user)
        team = create(:team, organization: organization)
        team.add_member(user)

        detail = create(:copilot_aggregate_usage_detail, user: user, usage_date: Date.today - 1.day)
        result = copilot_organization.last_token_activity(team)
        assert_equal detail.updated_at.time, result
      end

      test "returns the last token activity for multiple members of team" do
        organization = create(:organization)
        copilot_organization = Copilot::Organization.new(organization)
        team = create(:team, organization: organization)

        10.times do |i|
          user = create(:user)
          team.add_member(user)
          create(:copilot_aggregate_usage_detail, user: user, usage_date: Date.today - (i * 1.day))
        end

        user = create(:user)
        team.add_member(user)
        detail = create(:copilot_aggregate_usage_detail, user: user, usage_date: Date.today)
        result = copilot_organization.last_token_activity(team)
        assert_equal detail.updated_at.time, result
      end
    end
  end
end if GitHub.copilot_enabled?
