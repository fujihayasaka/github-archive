# typed: true
# frozen_string_literal: true

require "test_helper"

# rubocop:disable ViewComponent/EncouragePreviewsForScannableComponents
# Pending https://github.com/github/maintainer-love/issues/87
class Forks::Controls::PeriodComponentTest < GitHub::TestCase
  include Forks::SelectMenuTestHelpers
  include Forks::FixtureHelpers

  context "render" do
    test "renders with the correct default option selected" do
      render_inline(Forks::Controls::PeriodComponent.new(path_resolver), allowed_queries: 0)
      assert_selected_option "2 years"
    end

    test "renders with correct override option selected" do
      render_inline(Forks::Controls::PeriodComponent.new(path_resolver(period: "1mo")), allowed_queries: 0)
      assert_selected_option "1 month"
    end

    context "When the ControlState unbound_period feature is enabled" do
      test "it renders the All time option" do
        render_inline(Forks::Controls::PeriodComponent.new(
          path_resolver(period: "", enabled_features: [:unbound_period])), allowed_queries: 0
        )
        assert_selected_option "All time"
      end
    end

    context "When the ControlState unbound_period feature is disabled" do
      test "does not render or select the All time option" do
        render_inline(Forks::Controls::PeriodComponent.new(path_resolver(period: "")), allowed_queries: 0)
        refute_rendered_option "All time", expect_selected: "2 years"
      end
    end
  end
end
