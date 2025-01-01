# typed: true
# frozen_string_literal: true

require "test_helper"

class SuggesterBlockedUserFilterTest < GitHub::TestCase
  fixtures do
    @blocker = create(:user)
    @blocked = create(:user)
  end

  test "filters out users who are blocking the viewer" do
    filter = Suggester::BlockedUserFilter.new(viewer: @blocked)
    refute filter.to_proc.call(@blocker)

    @blocker.block(@blocked)

    filter = Suggester::BlockedUserFilter.new(viewer: @blocked)
    assert filter.to_proc.call(@blocker)
  end
end
