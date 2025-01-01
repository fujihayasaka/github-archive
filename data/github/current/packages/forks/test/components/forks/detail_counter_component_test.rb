# typed: true
# frozen_string_literal: true

require "test_helper"

class Forks::DetailCounterComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  fixtures do
    @repo = create(:repository, owner: create(:user))
  end

  context "it renders" do
    test "with all fields present" do
      render_inline(Forks::DetailCounterComponent.new("value", "label", "star", "https://www.github.com"), allowed_queries: 0)
      assert_selector "a[href='https://www.github.com']", text: /value/
      assert_selector "svg.octicon-star"
    end

    test "with no url" do
      render_inline(Forks::DetailCounterComponent.new(42, "label", "star"), allowed_queries: 0)
      refute_selector "a"
      assert_selector "svg.octicon-star"
      assert_selector "span", text: "42"
    end
  end
end
