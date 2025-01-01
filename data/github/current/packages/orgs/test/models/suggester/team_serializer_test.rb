# typed: true
# frozen_string_literal: true

require "test_helper"

class SuggesterTeamSerializerTest < GitHub::TestCase
  fixtures do
    @team = create(:team, description: "A team")
    @format = Suggester::TeamSerializer.new(get_avatars: true).freeze
  end

  test "dumps team attributes" do
    expected = {
      type: "team",
      id: @team.id,
      name: @team.combined_slug,
      description: @team.description,
      avatarUrl: @team.primary_avatar_url
    }
    result = @format.dump(@team)
    assert_equal expected, result
  end

  test "maps team attributes as a proc" do
    expected = @format.dump(@team)
    result = [@team].map(&@format).first
    assert_equal expected, result
  end
end
