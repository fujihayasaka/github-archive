# typed: true
# frozen_string_literal: true

require "test_helper"

class FundingPlatformsTest < GitHub::TestCase
  fixtures do
    @repo = create :repository, from_example: :funding_links
  end

  test ".all returns all funding platforms" do
    all = FundingPlatforms::ALL
    assert all[:patreon]
    assert all[:open_collective]
    assert all[:ko_fi]
    assert all[:custom]
  end

  context ".find" do
    test "finds the platform for a valid key" do
      assert FundingPlatforms.find(:patreon)
    end

    test "returns nil for an non-existent key"  do
      refute FundingPlatforms.find(:jokers)
    end
  end
end
