# frozen_string_literal: true

require "test_helper"

class CVEReviewsSidebarComponentTest < ViewComponent::TestCase
  setup do
    AdvisoryDB::Features.stubs(:enabled?).returns(false)
  end

  test "does not show the ecosystem, package, affected versions, and patches if the cve request affected_products_payload is not defined" do
    cve_review = create(:cve_review)
    cve_request = create(
      :cve_request,
      affected_products_payload: nil,
    )
    cve_review.cve_requests << cve_request

    render_inline CVEReviews::SidebarComponent.new(cve_review: cve_review, cve_request: cve_review.current_cve_request)

    refute_selector "[data-test-selector='ecosystem']"
    refute_selector "[data-test-selector='package']"
    refute_selector "[data-test-selector='affected-versions']"
    refute_selector "[data-test-selector='patches']"
  end

  test "does not show the ecosystem, package, affected versions, and patches if the cve request affected_products_payload is empty" do
    cve_review = create(:cve_review)
    cve_request = create(
      :cve_request,
      affected_products_payload: [],
    )
    cve_review.cve_requests << cve_request

    render_inline CVEReviews::SidebarComponent.new(cve_review: cve_review, cve_request: cve_review.current_cve_request)

    refute_selector "[data-test-selector='ecosystem']"
    refute_selector "[data-test-selector='package']"
    refute_selector "[data-test-selector='affected-versions']"
    refute_selector "[data-test-selector='patches']"
  end

  test "shows the ecosystem, package, affected versions, and patches from the first item in affected_products_payload if that field is defined" do
    cve_review = create(:cve_review)
    cve_request = create(
      :cve_request,
      affected_products_payload: [
        {
          ecosystem: "rubygems",
          package: "rubymon",
          affected_versions: "< 2.3.4",
          patches: "2.3.4",
        },
        {
          ecosystem: "nuget",
          package: "nugetmon",
          affected_versions: "< 1.2.3",
          patches: "1.2.3",
        },
        {
          ecosystem: "go",
          package: "gomon",
          affected_versions: "< 3.4.5",
          patches: "3.4.5",
        },
      ],
    )
    cve_review.cve_requests << cve_request

    render_inline CVEReviews::SidebarComponent.new(cve_review: cve_review, cve_request: cve_review.current_cve_request)

    assert_selector "[data-test-selector='ecosystem']", count: 1, text: "rubygems"
    assert_selector "[data-test-selector='package']", count: 1, text: "rubymon"
    assert_selector "[data-test-selector='affected-versions']", count: 1, text: "< 2.3.4"
    assert_selector "[data-test-selector='patches']", count: 1, text: "2.3.4"
  end

  test "does not mention there are more affected products if affected_products_payload for the cve request has only one item" do
    cve_review = create(:cve_review)
    cve_request = create(
      :cve_request,
      affected_products_payload: [
        {
          ecosystem: "rubygems",
          package: "rubymon",
          affected_versions: "< 2.3.4",
          patches: "2.3.4",
        },
      ],
    )
    cve_review.cve_requests << cve_request

    render_inline CVEReviews::SidebarComponent.new(cve_review: cve_review, cve_request: cve_review.current_cve_request)

    assert_selector "[data-test-selector='additional-affected-products-message']", count: 0
  end

  test "mentions there are more affected products if affected_products_payload for the cve request has more than one item" do
    cve_review = create(:cve_review)
    cve_request = create(
      :cve_request,
      affected_products_payload: [
        {
          ecosystem: "rubygems",
          package: "rubymon",
          affected_versions: "< 2.3.4",
          patches: "2.3.4",
        },
        {
          ecosystem: "nuget",
          package: "nugetmon",
          affected_versions: "< 1.2.3",
          patches: "1.2.3",
        },
        {
          ecosystem: "go",
          package: "gomon",
          affected_versions: "< 3.4.5",
          patches: "3.4.5",
        },
      ],
    )
    cve_review.cve_requests << cve_request

    render_inline CVEReviews::SidebarComponent.new(cve_review: cve_review, cve_request: cve_review.current_cve_request)

    assert_selector "[data-test-selector='additional-affected-products-message']", count: 1, text: "And 2 more affected products."

    # singular case
    cve_request.update!(
      affected_products_payload: cve_request.affected_products_payload[1..],
    )
    render_inline CVEReviews::SidebarComponent.new(cve_review: cve_review, cve_request: cve_review.current_cve_request)
    assert_selector "[data-test-selector='additional-affected-products-message']", count: 1, text: "And 1 more affected product."
  end

  test "shows the button to reopen the CVE Review" do
    cve_review = create(:cve_review, :curation_state_published)

    render_inline CVEReviews::SidebarComponent.new(cve_review: cve_review, cve_request: cve_review.current_cve_request)

    assert_selector "[data-test-selector='cve-reviews-sidebar-component-reopen-button']", count: 1, text: "Reopen CVE review"
  end

  test "hides the button to reopen the CVE Review when it is not possible" do
    [:curation_state_in_triage, :curation_state_waiting, :curation_state_open, :curation_state_closed].each do |curation_state_trait|
      cve_review = create(:cve_review, curation_state_trait)
      render_inline CVEReviews::SidebarComponent.new(cve_review: cve_review, cve_request: cve_review.current_cve_request)
      assert_selector "[data-test-selector='cve-reviews-sidebar-component-reopen-button']", count: 0
    end
  end

  test "shows the button to update the CVE Review on MITRE if it has been reopened" do
    cve_review = create(:cve_review, :curation_state_open_update)
    render_inline CVEReviews::SidebarComponent.new(cve_review: cve_review, cve_request: cve_review.current_cve_request)
    assert_selector "[data-test-selector='cve-reviews-sidebar-component-publish-button']", count: 1
  end

  test "hides the button to update the CVE Review on MITRE if it is not reopened" do
    [:curation_state_in_triage, :curation_state_waiting, :curation_state_closed, :curation_state_published].each do |curation_state_trait|
      cve_review = create(:cve_review, curation_state_trait)
      render_inline CVEReviews::SidebarComponent.new(cve_review: cve_review, cve_request: cve_review.current_cve_request)
      assert_selector "[data-test-selector='cve-reviews-sidebar-component-publish-button']", count: 0
    end
  end
end
