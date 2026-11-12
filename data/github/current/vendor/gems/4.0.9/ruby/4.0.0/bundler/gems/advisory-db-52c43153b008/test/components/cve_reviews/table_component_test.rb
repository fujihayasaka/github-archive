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

  test "renders assignee column header" do
    render_inline(CVEReviews::TableComponent.new(cve_reviews: []))
    assert_text "Assignee"
  end

  test "renders bulk assign dropdown in header" do
    render_inline(CVEReviews::TableComponent.new(cve_reviews: []))
    assert_text "Bulk assign to"
  end

  test "renders assigned avatar when assignee is present" do
    review = create(:cve_review, assignee: "testcurator")
    render_inline(CVEReviews::TableComponent.new(cve_reviews: [review]))
    assert_selector "[data-assigned-curator='testcurator']"
    assert_selector "img[src*='github.com/testcurator.png']"
  end

  test "renders empty placeholder when no assignee" do
    review = create(:cve_review, assignee: nil)
    render_inline(CVEReviews::TableComponent.new(cve_reviews: [review]))
    assert_selector ".cve-avatar-empty-placeholder"
  end

  test "renders bulk assign curators list" do
    render_inline(CVEReviews::TableComponent.new(cve_reviews: []))
    assert_selector "button[data-action='click:cve-review-list#bulkAssignClicked']", visible: :all
  end

  test "renders bulk unassign option" do
    render_inline(CVEReviews::TableComponent.new(cve_reviews: []))
    assert_selector "button[data-action='click:cve-review-list#bulkAssignClicked'][data-curator='']", visible: :all
  end

  test "does not render unassign option when no assignee" do
    review = create(:cve_review, assignee: nil)
    render_inline(CVEReviews::TableComponent.new(cve_reviews: [review]))
    assert_no_selector ".js-cve-review-unassign", visible: :all
  end

  test "bulk assign buttons have curator data attributes" do
    render_inline(CVEReviews::TableComponent.new(cve_reviews: []))
    AdvisoryDB::Config::ActiveCurators::CURATORS.each do |curator|
      assert_selector "button[data-curator='#{curator}']", visible: :all
    end
  end
end
