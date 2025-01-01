# typed: true
# frozen_string_literal: true

require "test_helper"

class Team::SizeDependencyTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @team = create(:team, organization: @org, privacy: :closed)
    @subteam = create(:team, organization: @org, privacy: :closed, parent_team_id: @team.id)
    @subteam_sibling = create(:team, organization: @org, privacy: :closed, parent_team_id: @team.id)
    @subsubteam = create(:team, organization: @org, privacy: :closed, parent_team_id: @subteam.id)
  end

  context "teams#large?" do
    test "detects team exceeding threshold at individual level" do
      1.upto(3) do |count|
        @team.add_member(create(:user))
        refute @team.large?(threshold: 3), "team should not be large with #{count} members and threshold of 3"
      end
      @team.add_member(create(:user))
      assert @team.large?(threshold: 3)
    end

    test "don't double-count a user if they belong to more than one team on the hierarchy" do
      2.times do
        @team.add_member(create(:user))
        @subteam.add_member(create(:user))
      end
      shared_user = create(:user)
      @team.add_member(shared_user)
      @subteam.add_member(shared_user)

      # Count of unique members from the top is 5 (2 unique in team, 2 unique in subteam, 1 shared)
      assert @team.large?(threshold: 4)
      refute @team.large?(threshold: 5)
    end

    test "count by navigating hierarchy deep and wide" do
      @team.add_member(create(:user))
      @subteam.add_member(create(:user))
      @subteam_sibling.add_member(create(:user))
      @subsubteam.add_member(create(:user))

      assert @team.large?(threshold: 3)
      refute @team.large?(threshold: 4)
    end

  end
end
