# typed: true
# frozen_string_literal: true

require "test_helper"

# rubocop:disable ViewComponent/EncouragePreviewsForScannableComponents
# Pending https://github.com/github/maintainer-love/issues/87
class Forks::Controls::SortComponentTest < GitHub::TestCase
  include Forks::SelectMenuTestHelpers
  include Forks::FixtureHelpers

  context "render" do
    test "it renders the correct default" do
      render_inline(Forks::Controls::SortComponent.new(path_resolver), allowed_queries: 0)
      assert_selected_option("Most starred")
    end

    test "it renders the correct override" do
      render_inline(Forks::Controls::SortComponent.new(path_resolver(sort_by: :last_updated)), allowed_queries: 0)
      assert_selected_option("Recently updated")
    end
  end
end
