# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Suggestions
    module Businesses
      class TeamTest < GitHub::TestCase
        include DuplicateQueryTestHelper

        fixtures do
          @orgs_admin = create(:user, name: "orgs-admin")
          @org_member = create(:user, name: "member")
          @admin_and_member = create(:user, name: "admin-and-member")
          @security_manager = create(:user, name: "org-security-manager")
          @org_member_no_teams = create(:user, name: "member-no-teams") # Do not add this user to any teams.

          ###### Org 1:

          @org_1 = create(:organization, name: "org-1")

          # Add users to org.
          @org_1.add_admin(@orgs_admin)
          @org_1.add_admin(@admin_and_member)
          @org_1.add_member(@org_member)
          @org_1.add_member(@org_member_no_teams)

          # Create teams.
          @org_1_team_1 = create(:team, organization: @org_1, name: "team-1")
          @org_1_team_2 = create(:team, organization: @org_1, name: "team-2")
          @org_1_security_manager_team_1 = create(:security_manager_team, organization: @org_1, name: "#{@org_1}-security-manager-team-1")

          # Add users to the teams.
          [@org_member].each { |u| @org_1_team_1.add_member(u) }
          [@org_member].each { |u| @org_1_team_2.add_member(u) }
          @org_1_security_manager_team_1.add_member(@security_manager)

          ###### Org 2:

          @org_2 = create(:organization, name: "org-2")

          # Add users to org.
          @org_2.add_admin(@orgs_admin)
          @org_2.add_admin(@admin_and_member)
          @org_2.add_member(@org_member)

          # Create teams.
          @org_2_team_1 = create(:team, organization: @org_2, name: "team-1") # No users will be added to this team.

          ###### Org 3:

          @org_3 = create(:organization, name: "org-3")

          # Make more users.
          @org_3_admin = create(:user, name: "#{@org_3}-owner")
          @org_3_member = create(:user, name: "#{@org_3}-member")
          @org_3_member_no_teams = create(:user, name: "#{@org_3}-member-no-teams")

          # Add users to org.
          @org_3.add_admin(@orgs_admin)
          @org_3.add_admin(@org_3_admin)
          @org_3.add_member(@admin_and_member)
          @org_3.add_member(@org_member)
          @org_3.add_member(@org_3_member)
          @org_3.add_member(@org_3_member_no_teams)

          # Create teams.
          @org_3_team_1 = create(:team, organization: @org_3, name: "team-1")
          @org_3_team_2 = create(:team, organization: @org_3, name: "team-2")
          @org_3_security_manager_team_1 = create(:security_manager_team, organization: @org_3, name: "#{@org_3}-security-manager-team-1")

          # Add users to the teams.
          [@org_3_security_manager, @org_3_member].each { |u| @org_3_team_1.add_member(u) }
          [@org_3_security_manager, @org_3_member].each { |u| @org_3_team_2.add_member(u) }
          @org_3_security_manager_team_1.add_member(@security_manager)

          ###### Org 4: (no teams)

          @org_4 = create(:organization, name: "org-4")

          # Add users to org.
          @org_4.add_admin(@orgs_admin)

          @all_orgs = [@org_1, @org_2, @org_3, @org_4]
        end

        context "when no authorized orgs are provided" do
          test "it returns an empty array" do
            suggestions = Team.new(
              authorized_orgs: [],
              user: @orgs_admin
            ).suggestions

            assert_same_elements([], suggestions)
          end
        end

        test "it returns suggestions for all authorized orgs" do
          ###### 3 authorized orgs.

          suggestions = T.let([], T::Array[Suggestion])
          assert_duplicate_query_detection(Team, 0) do
            suggestions = Team.new(
              authorized_orgs: @all_orgs,
              user: @orgs_admin
            ).suggestions
          end

          expected_suggestions = [@org_1_team_1, @org_1_team_2, @org_1_security_manager_team_1, @org_2_team_1, @org_3_team_1, @org_3_team_2, @org_3_security_manager_team_1].map do |team|
            Suggestion.new(
              description: "#{team.organization.display_login}/#{team.slug}",
              label: team.name,
              value: team.to_s
            )
          end

          assert_same_elements(expected_suggestions, suggestions)

          ###### 1 authorized org.

          suggestions = Team.new(
            authorized_orgs: [@org_3],
            user: @orgs_admin
          ).suggestions

          expected_suggestions = [@org_3_team_1, @org_3_team_2, @org_3_security_manager_team_1].map do |team|
            Suggestion.new(
              description: "#{team.organization.display_login}/#{team.slug}",
              label: team.name,
              value: team.to_s
            )
          end

          assert_same_elements(expected_suggestions, suggestions)
        end

        test "it only returns suggestions for teams the user can access" do
          ###### @orgs_admin

          suggestions = Team.new(
            authorized_orgs: @all_orgs,
            user: @orgs_admin
          ).suggestions

          expected_suggestions = [@org_1_team_1, @org_1_team_2, @org_1_security_manager_team_1, @org_2_team_1, @org_3_team_1, @org_3_team_2, @org_3_security_manager_team_1].map do |team|
            Suggestion.new(
              description: "#{team.organization.display_login}/#{team.slug}",
              label: team.name,
              value: team.to_s
            )
          end

          assert_same_elements(expected_suggestions, suggestions)

          ###### @org_3_admin

          suggestions = Team.new(
            authorized_orgs: @all_orgs,
            user: @org_3_admin
          ).suggestions

          expected_suggestions = [@org_3_team_1, @org_3_team_2, @org_3_security_manager_team_1].map do |team|
            Suggestion.new(
              description: "#{team.organization.display_login}/#{team.slug}",
              label: team.name,
              value: team.to_s
            )
          end

          assert_same_elements(expected_suggestions, suggestions)

          ###### @org_member

          suggestions = Team.new(
            authorized_orgs: @all_orgs,
            user: @org_member
          ).suggestions

          expected_suggestions = [@org_1_team_1, @org_1_team_2].map do |team|
            Suggestion.new(
              description: "#{team.organization.display_login}/#{team.slug}",
              label: team.name,
              value: team.to_s
            )
          end

          assert_same_elements(expected_suggestions, suggestions)

          ###### @admin_and_member

          suggestions = Team.new(
            authorized_orgs: @all_orgs,
            user: @admin_and_member
          ).suggestions

          expected_suggestions = [@org_1_team_1, @org_1_team_2, @org_1_security_manager_team_1, @org_2_team_1].map do |team|
            Suggestion.new(
              description: "#{team.organization.display_login}/#{team.slug}",
              label: team.name,
              value: team.to_s
            )
          end

          assert_same_elements(expected_suggestions, suggestions)

          ###### @security_manager

          suggestions = Team.new(
            authorized_orgs: @all_orgs,
            user: @security_manager
          ).suggestions

          expected_suggestions = [@org_1_security_manager_team_1, @org_3_security_manager_team_1].map do |team|
            Suggestion.new(
              description: "#{team.organization.display_login}/#{team.slug}",
              label: team.name,
              value: team.to_s
            )
          end

          assert_same_elements(expected_suggestions, suggestions)

          ###### @org_member_no_teams

          suggestions = Team.new(
            authorized_orgs: @all_orgs,
            user: @org_member_no_teams
          ).suggestions

          assert_same_elements([], suggestions)
        end

        context "when selected values are provided" do
          test "it returns suggestions omitting the selected values" do
            suggestions = Team.new(
              authorized_orgs: @all_orgs,
              selected_values: [@org_1_team_1.to_s, @org_3_team_1.to_s],
              user: @orgs_admin
            ).suggestions

            expected_suggestions = [@org_1_team_2, @org_1_security_manager_team_1, @org_2_team_1, @org_3_team_2, @org_3_security_manager_team_1].map do |team|
              Suggestion.new(
                description: "#{team.organization.display_login}/#{team.slug}",
                label: team.name,
                value: team.to_s
              )
            end

            assert_same_elements(expected_suggestions, suggestions)
          end
        end

        context 'when a value of the form "org/team" is provided' do
          test "it returns suggestions for that org only" do
            suggestions = Team.new(
              authorized_orgs: @all_orgs,
              user: @orgs_admin,
              value: "#{@org_1}/am-1"
            ).suggestions

            expected_suggestions = [@org_1_team_1, @org_1_security_manager_team_1].map do |team|
              Suggestion.new(
                description: "#{team.organization.display_login}/#{team.slug}",
                label: team.name,
                value: team.to_s
              )
            end

            assert_same_elements(expected_suggestions, suggestions)
          end

          context "when selected values and a value are provided" do
            test "it returns suggestions matching the value and omitting the selected values" do
              suggestions = Team.new(
                authorized_orgs: @all_orgs,
                selected_values: [@org_1_team_1.to_s],
                user: @orgs_admin,
                value: "#{@org_1}/am-1"
              ).suggestions

              expected_suggestions = [@org_1_security_manager_team_1].map do |team|
                Suggestion.new(
                  description: "#{team.organization.display_login}/#{team.slug}",
                  label: team.name,
                  value: team.to_s
                )
              end

              assert_same_elements(expected_suggestions, suggestions)
            end
          end
        end

        context 'when a value without a "/" is provided' do
          test "it returns suggestions where the org or team name matches the value" do
            suggestions = Team.new(
              authorized_orgs: @all_orgs,
              user: @orgs_admin,
              value: "-1"
            ).suggestions

            expected_suggestions = [@org_1_team_1, @org_1_team_2, @org_1_security_manager_team_1, @org_2_team_1, @org_3_team_1, @org_3_security_manager_team_1].map do |team|
              Suggestion.new(
                description: "#{team.organization.display_login}/#{team.slug}",
                label: team.name,
                value: team.to_s
              )
            end

            assert_same_elements(expected_suggestions, suggestions)
          end

          context "when selected values and a value are provided" do
            test "it returns suggestions matching the value and omitting the selected values" do
              suggestions = Team.new(
                authorized_orgs: @all_orgs,
                selected_values: [@org_1_team_2.to_s, @org_1_security_manager_team_1.to_s],
                user: @orgs_admin,
                value: "-1"
              ).suggestions

              expected_suggestions = [@org_3_security_manager_team_1, @org_1_team_1, @org_2_team_1, @org_3_team_1].map do |team|
                Suggestion.new(
                  description: "#{team.organization.display_login}/#{team.slug}",
                  label: team.name,
                  value: team.to_s
                )
              end

              assert_same_elements(expected_suggestions, suggestions)
            end
          end
        end

        test "it returns suggestions in ascending alphabetical order by team name" do
          suggestions = Team.new(
            authorized_orgs: @all_orgs,
            user: @orgs_admin
          ).suggestions

          expected_suggestions = [@org_1_security_manager_team_1, @org_3_security_manager_team_1, @org_1_team_1, @org_2_team_1, @org_3_team_1, @org_1_team_2, @org_3_team_2].map do |team|
            Suggestion.new(
              description: "#{team.organization.display_login}/#{team.slug}",
              label: team.name,
              value: team.to_s
            )
          end

          assert_equal(expected_suggestions, suggestions)
        end

        context "limit" do
          test "it limits the number of suggestions returned" do
            suggestions = Team.new(
              authorized_orgs: @all_orgs,
              limit: 3,
              user: @orgs_admin
            ).suggestions

            expected_suggestions = [@org_1_security_manager_team_1, @org_3_security_manager_team_1, @org_1_team_1].map do |team|
              Suggestion.new(
                description: "#{team.organization.display_login}/#{team.slug}",
                label: team.name,
                value: team.to_s
              )
            end

            assert_same_elements(expected_suggestions, suggestions)
          end
        end
      end
    end
  end
end
