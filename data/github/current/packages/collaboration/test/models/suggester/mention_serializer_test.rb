# typed: true
# frozen_string_literal: true

require "test_helper"

class SuggesterMentionSerializerTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @team = create(:team, description: "A team")
    @participant = create(:user)
  end

  setup { @format = Suggester::MentionSerializer.new(viewer: @user) }

  test "combines users and teams into mentions list" do
    user = {
      type: "user",
      id: @user.id,
      login: @user.login,
      name: @user.profile_name || "",
    }
    team = {
      type: "team",
      id: @team.id,
      name: @team.combined_slug,
      description: @team.description,
    }
    result = @format.dump([@user], [@team])
    assert_equal user, result.first
    assert_equal team, result.second
  end

  test "combines users, teams, and participants into mentions list" do
    user = {
      type: "user",
      id: @user.id,
      login: @user.login,
      name: @user.profile_name || "",
    }
    team = {
      type: "team",
      id: @team.id,
      name: @team.combined_slug,
      description: @team.description,
    }
    participant = {
      type: "user",
      id: @participant.id,
      login: @participant.login,
      name: @participant.profile_name || "",
      participant: true
    }
    result = @format.dump([@user], [@team], [@participant])

    assert_equal participant, result.first
    assert_equal user, result.second
    assert_equal team, result.third
  end
end
