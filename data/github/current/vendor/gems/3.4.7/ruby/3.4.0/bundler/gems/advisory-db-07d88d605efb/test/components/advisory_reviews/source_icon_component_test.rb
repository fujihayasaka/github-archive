# frozen_string_literal: true

require "test_helper"

class AdvisoryReviewsSourceIconComponentTest < ViewComponent::TestCase
  test "renders with a link" do
    render_inline(AdvisoryReviews::SourceIconComponent.new(source: "nvd"))
    assert_selector "[data-test-selector=advisory-source-icon]", text: "NVD"
    assert_selector "[data-test-selector=advisory-source-link]", count: 1
  end

  test "renders without a link" do
    render_inline(AdvisoryReviews::SourceIconComponent.new(source: "nvd", with_link: false))
    assert_selector "[data-test-selector=advisory-source-icon]", text: "NVD"
    assert_selector "[data-test-selector=advisory-source-link]", count: 0
  end

  test "doesn't link invalid source" do
    render_inline(AdvisoryReviews::SourceIconComponent.new(source: ""))
    assert_selector "[data-test-selector=advisory-source-icon]", text: "?"
    assert_selector "[data-test-selector=advisory-source-link]", count: 0
  end
end
