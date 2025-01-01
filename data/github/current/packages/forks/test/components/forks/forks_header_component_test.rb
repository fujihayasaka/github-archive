# typed: true
# frozen_string_literal: true

require "test_helper"

# rubocop:disable ViewComponent/EncouragePreviewsForScannableComponents
# Pending https://github.com/github/maintainer-love/issues/87
class ForksHeaderComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers
  include Forks::FixtureHelpers

  test "it renders the component including controls" do
    render_inline(Forks::ForksHeaderComponent.new(path_resolver, true), allowed_queries: 0)
    assert_test_selector "forks-period-control"
    assert_test_selector "forks-filter-control"
    assert_test_selector "forks-sort-control"
  end

  test "it renders the component but not the controls" do
    render_inline(Forks::ForksHeaderComponent.new(path_resolver, false), allowed_queries: 0)
    refute_test_selector "forks-period-control"
    refute_test_selector "forks-filter-control"
    refute_test_selector "forks-sort-control"
  end
end
