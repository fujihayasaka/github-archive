# typed: true
# frozen_string_literal: true

require "test_helper"

# rubocop:disable ViewComponent/EncouragePreviewsForScannableComponents
class Forks::DetailTimeComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  test "it renders" do
    render_inline(Forks::DetailTimeComponent.new("Created", Time.now), allowed_queries: 0)
    assert_selector "span", text: "Created"
  end
end
