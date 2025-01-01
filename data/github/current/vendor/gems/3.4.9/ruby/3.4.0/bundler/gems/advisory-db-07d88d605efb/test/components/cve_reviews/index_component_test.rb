# frozen_string_literal: true

require "test_helper"

class CVEReviewsIndexComponentTest < ViewComponent::TestCase
  test "lists default CVE reviews" do
    component = CVEReviews::IndexComponent.new(sort: nil, state: nil, page: nil, query: nil)
    assert_equal 0, component.cve_reviews.length

    # open reviews to be rendered
    create(:cve_review, :curation_state_open)
    create(:cve_review, :curation_state_open)

    # reviews not to be rendered
    create(:not_assigned_cve_review, :notified)
    create(:assigned_cve_review, :notified)

    component = CVEReviews::IndexComponent.new(sort: nil, state: nil, page: nil, query: nil)
    assert_equal 2, component.cve_reviews.length
  end

  test "paginates CVE reviews" do
    create_list(:cve_review, 35, :curation_state_open)

    component = CVEReviews::IndexComponent.new(sort: nil, state: nil, page: nil, query: nil)
    assert_equal 30, component.cve_reviews.length

    component = CVEReviews::IndexComponent.new(sort: nil, state: nil, page: 2, query: nil)
    assert_equal 5, component.cve_reviews.length
  end

  test "sorts CVE reviews" do
    create(:cve_review, :curation_state_open, review_requested_at: 2.days.ago, cve_request_title: "older cve review")
    create(:cve_review, :curation_state_open, review_requested_at: 1.day.ago, cve_request_title: "newer cve review")

    component = CVEReviews::IndexComponent.new(sort: nil, state: nil, page: nil, query: nil)
    # default when not provided is "asc"
    assert_equal "older cve review", component.cve_reviews.first.current_cve_request.title
    assert_equal "newer cve review", component.cve_reviews.last.current_cve_request.title

    component = CVEReviews::IndexComponent.new(sort: "desc", state: nil, page: nil, query: nil)
    assert_equal "newer cve review", component.cve_reviews.first.current_cve_request.title
    assert_equal "older cve review", component.cve_reviews.last.current_cve_request.title
  end

  test "filters CVE reviews" do
    in_triage = create :cve_review, :curation_state_in_triage
    waiting = create :cve_review, :curation_state_waiting
    open = create :cve_review, :curation_state_open
    published = create :cve_review, :curation_state_published
    closed = create :cve_review, :curation_state_closed

    component = CVEReviews::IndexComponent.new(sort: nil, state: nil, page: nil, query: nil)
    assert_equal [open], component.cve_reviews

    component = CVEReviews::IndexComponent.new(sort: nil, state: "in_triage", page: nil, query: nil)
    assert_equal [in_triage], component.cve_reviews

    component = CVEReviews::IndexComponent.new(sort: nil, state: "waiting", page: nil, query: nil)
    assert_equal [waiting], component.cve_reviews

    component = CVEReviews::IndexComponent.new(sort: nil, state: "open", page: nil, query: nil)
    assert_equal [open], component.cve_reviews

    component = CVEReviews::IndexComponent.new(sort: nil, state: "published", page: nil, query: nil)
    assert_equal [published], component.cve_reviews

    component = CVEReviews::IndexComponent.new(sort: nil, state: "closed", page: nil, query: nil)
    assert_equal [closed], component.cve_reviews
  end

  test "searches CVE reviews" do
    review_1 = create(:cve_review, :curation_state_open, cve_request_title: "title 1")
    review_2 = create(:cve_review, :curation_state_open, cve_request_title: "title 2")
    create(:cve_review, :curation_state_open, cve_request_title: "title 3")

    component = CVEReviews::IndexComponent.new(sort: nil, state: nil, page: nil, query: review_1.ghsa_id)
    assert_equal 1, component.cve_reviews.length

    component = CVEReviews::IndexComponent.new(sort: nil, state: nil, page: nil, query: "#{review_1.ghsa_id}+#{review_2.ghsa_id[0..12]}")
    assert_equal 2, component.cve_reviews.length
  end
end
