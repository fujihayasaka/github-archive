# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Suggestions
    module Orgs
      class TeamTest < GitHub::TestCase
        fixtures do
          @user = create(:user)
          @org_1 = create(:organization, admin: @user, login: "org-1")
          org_2 = create(:organization, admin: @user, login: "org-2")

          # Teams in org 1.
          @team_1 = create(:team, organization: @org_1, name: "Team 1")
          @team_2 = create(:team, organization: @org_1, name: "Team 2")
          @team_3 = create(:team, organization: @org_1, name: "Team 3")

          # Teams in org 2.
          team_4 = create(:team, organization: org_2, name: "Team 4")
        end

        test "it does not return teams in other organizations" do
          suggestions = Team.new(
            organization: @org_1,
            user: @user,
            value: "eam"
          ).suggestions

          assert_same_elements(
            [
              Suggestion.new(label: @team_1.name, value: @team_1.slug, description: @team_1.slug),
              Suggestion.new(label: @team_2.name, value: @team_2.slug, description: @team_2.slug),
              Suggestion.new(label: @team_3.name, value: @team_3.slug, description: @team_3.slug)
            ],
            suggestions
          )
        end

        context "when selected values are provided" do
          test "it returns suggestions omitting the selected values" do
            suggestions = Team.new(
              organization: @org_1,
              selected_values: [@team_1.slug, @team_2.slug],
              user: @user
            ).suggestions

            assert_same_elements([Suggestion.new(label: @team_3.name, value: @team_3.slug, description: @team_3.slug)], suggestions)
          end
        end

        context "when a value is provided" do
          test "it returns suggestions whose names match the value" do
            suggestions = Team.new(
              organization: @org_1,
              user: @user,
              value: "eam"
            ).suggestions

            assert_same_elements(
              [
                Suggestion.new(label: @team_1.name, value: @team_1.slug, description: @team_1.slug),
                Suggestion.new(label: @team_2.name, value: @team_2.slug, description: @team_2.slug),
                Suggestion.new(label: @team_3.name, value: @team_3.slug, description: @team_3.slug)
              ],
              suggestions
            )
          end
        end

        context "when selected values and a value are provided" do
          test "it returns suggestions matching the value and omitting the selected values" do
            suggestions = Team.new(
              organization: @org_1,
              selected_values: [@team_1.slug],
              user: @user,
              value: "eam"
            ).suggestions

            assert_same_elements(
              [
                Suggestion.new(label: @team_2.name, value: @team_2.slug, description: @team_2.slug),
                Suggestion.new(label: @team_3.name, value: @team_3.slug, description: @team_3.slug)
              ],
              suggestions
            )
          end
        end

        test "it returns suggestions in ascending alphabetical order by label" do
          suggestions = Team.new(
            organization: @org_1,
            user: @user,
            value: "eam"
          ).suggestions

          assert_same_elements(
            [
              Suggestion.new(label: @team_1.name, value: @team_1.slug, description: @team_1.slug),
              Suggestion.new(label: @team_2.name, value: @team_2.slug, description: @team_2.slug),
              Suggestion.new(label: @team_3.name, value: @team_3.slug, description: @team_3.slug)
            ],
            suggestions
          )
        end

        context "limit" do
          test "it limits the number of suggestions returned" do
            suggestions = Team.new(
              limit: 2,
              organization: @org_1,
              user: @user,
              value: "eam"
            ).suggestions

            assert_same_elements(
              [
                Suggestion.new(label: @team_1.name, value: @team_1.slug, description: @team_1.slug),
                Suggestion.new(label: @team_2.name, value: @team_2.slug, description: @team_2.slug)
              ],
              suggestions
            )
          end
        end
      end
    end
  end
end
