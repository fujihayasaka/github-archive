# frozen_string_literal: true

require "test_helper"

class AdvisoryReviewsTableComponentTest < ViewComponent::TestCase
  test "renders empty" do
    with_controller_class(InboxController) do
      render_inline(AdvisoryReviews::TableComponent.new(advisory_reviews: []))
    end
    assert_selector "[data-test-selector=advisory-review-row]", count: 0
    assert_selector "[data-test-selector=no-advisory-reviews]", count: 1
  end

  test "renders rows" do
    reviews = create_list(:advisory_review, 10)
    with_controller_class(InboxController) do
      render_inline(AdvisoryReviews::TableComponent.new(advisory_reviews: reviews))
    end
    assert_selector "[data-test-selector=advisory-review-row]", count: 10
    assert_selector "[data-test-selector=no-advisory-reviews]", count: 0
  end

  test "ecosystems_with_package_names collapses vulns" do
    review = create(:advisory_review, :open)
    review["advisory_payload"]["vulnerabilities"] = {
      "0": { ecosystem: "golang", package_name: "somegopack" },
      "1": { ecosystem: "golang", package_name: "somegopack" }, # make sure we dedupe
      "2": { ecosystem: "other", package_name: "someotherpack" }, # make sure we show more than one unique entry
      "3": { ecosystem: "erlang" }, # should still work with only ecosystem
      "4": {}, # empty entries happen in inbox, it shouldn't show up or break anything
    }
    review.save!
    component = AdvisoryReviews::TableComponent.new(advisory_reviews: [review])
    collapsed = component.ecosystems_with_package_names(review)
    assert_equal "golang:somegopack, other:someotherpack, erlang", collapsed
  end

  test "maps feed entries to source icons" do
    review = create(:advisory_review, :open, feed_entry_type: :repository_advisory_feed_entry)
    create(:cve_feed_entry, advisory_review: review)
    create(:cve_review_feed_entry, advisory_review: review)
    create(:rubysec_feed_entry, advisory_review: review)
    create(:rustsec_feed_entry, advisory_review: review)
    create(:friends_of_php_feed_entry, advisory_review: review)
    create(:friends_of_php_feed_entry, advisory_review: review)
    create(:advisory_improvement_feed_entry, advisory_review: review)

    with_controller_class(InboxController) do
      render_inline(AdvisoryReviews::TableComponent.new(advisory_reviews: [review]))
    end
    assert_selector "[data-test-selector=advisory-source-icon]", count: 7
    assert_selector "[data-test-selector=advisory-source-icon]", text: "GHA"
    assert_selector "[data-test-selector=advisory-source-icon]", text: "NVD"
  end

  test "maps severities to icons" do
    reviews = []
    reviews << create(:advisory_review, advisory_payload: build(:advisory_payload, severity: "high", cvss_v3: ""))
    reviews << create(:advisory_review, advisory_payload: build(:advisory_payload, severity: "critical", cvss_v3: ""))

    with_controller_class(InboxController) do
      render_inline(AdvisoryReviews::TableComponent.new(advisory_reviews: reviews))
    end
    assert_selector "[data-test-selector=advisory-severity-icon]", count: 2
    assert_selector "[data-test-selector=advisory-severity-icon][title=Critical]"
    assert_selector "[data-test-selector=advisory-severity-icon][title=High]"
  end
end
