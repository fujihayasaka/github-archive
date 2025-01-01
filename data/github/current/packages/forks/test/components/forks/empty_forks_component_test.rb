# typed: true
# frozen_string_literal: true

require "test_helper"

class Forks::EmptyForksComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  test "it renders the component with no known forks" do
    render_inline(Forks::EmptyForksComponent.new(create(:repository), false, false))

    assert_test_selector "empty-forks", text: "No one has forked this repository yet"
    assert_test_selector "empty-forks", text: "Forks are a great way to contribute"
  end

  test "it renders the component with no search results" do
    render_inline(Forks::EmptyForksComponent.new(create(:repository), true, false))

    assert_test_selector "empty-forks", text: "No forked repositories found"
    assert_test_selector "empty-forks", text: "Try changing your filters"
  end

  test "it doesn't render the component when forks exist" do
    render_inline(Forks::EmptyForksComponent.new(create(:repository), true, true))

    refute_test_selector "empty-forks"
  end
end
