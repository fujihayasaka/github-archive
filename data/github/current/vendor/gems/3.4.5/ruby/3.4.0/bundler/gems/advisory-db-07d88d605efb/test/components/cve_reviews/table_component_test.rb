# frozen_string_literal: true

require "test_helper"

class CVEReviewsTableComponentTest < ViewComponent::TestCase
  test "renders empty" do
    render_inline(CVEReviews::TableComponent.new(cve_reviews: []))
    assert_selector "[data-test-selector=cve-review-row]", count: 0
    assert_selector "[data-test-selector=no-cve-reviews]", count: 1
  end

  test "renders rows" do
    reviews = create_list(:cve_review, 10)
    render_inline(CVEReviews::TableComponent.new(cve_reviews: reviews))
    assert_selector "[data-test-selector=cve-review-row]", count: 10
    assert_selector "[data-test-selector=no-cve-reviews]", count: 0
  end
end
