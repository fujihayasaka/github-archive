# typed: true
# frozen_string_literal: true

require "test_helper"

# rubocop:disable ViewComponent/EncouragePreviewsForScannableComponents
class Forks::ForksControlsComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers
  include Forks::FixtureHelpers

  test "it renders all forks controls" do
    render_inline Forks::ForksControlsComponent.new(path_resolver)

    assert_test_selector "forks-period-control"
    assert_test_selector "forks-filter-control"
    assert_test_selector "forks-sort-control"
  end
end
