# typed: true
# frozen_string_literal: true

require "test_helper"

class ProfileItemShowcaseTest < GitHub::TestCase
  context "#items" do
    test "does not return gists when they are not pinned" do
      user = create(:user)
      fan = create(:user)
      gist = create(:gist, user: user)
      repo = create(:repository, owner: user)
      fan.star(gist)
      fan.star(repo)
      showcase = ProfileItemShowcase.new(user: user, viewer: user)

      result = showcase.items

      assert_includes result, repo
      refute_includes result, gist
    end
  end
end
