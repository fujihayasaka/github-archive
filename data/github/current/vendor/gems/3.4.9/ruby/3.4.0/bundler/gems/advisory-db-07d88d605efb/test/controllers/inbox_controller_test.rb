# frozen_string_literal: true

require "test_helper"

class InboxControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user)
    create(:cve_review, :curation_state_in_triage)
    create(:cve_review, :curation_state_open, assigned_cve_id: "CVE-2022-0001") # Also creates advisory review
    create(:cve_review, :curation_state_waiting, assigned_cve_id: "CVE-2022-0002")
    create(:cve_review, :curation_state_published, assigned_cve_id: "CVE-2022-0003") # Also creates advisory review
    create(:cve_review, :curation_state_closed)
    create(:advisory_review, :open, cve_id: "CVE-2022-0004")
    create(:advisory_review, :curation_state_open, cve_id: "CVE-2022-0005")
    create(:advisory_review, :curation_state_waiting, cve_id: "CVE-2022-0006")
    create(:advisory_review, :curation_state_published, cve_id: "CVE-2022-0007")
    create(:advisory_review, :curation_state_withdrawn, cve_id: "CVE-2022-0008")
    create(:advisory_review, :curation_state_closed, cve_id: "CVE-2022-0009")
    create(:campaign, advisory_reviews: AdvisoryReview.limit(2))
  end

  test "search renders blank state" do
    get "/search", headers: { "X-Okta-Username" => @user.email }

    assert_response :ok
    assert_select "[data-test-selector=advisory-review-count]", text: "8"
    assert_select "[data-test-selector=cve-review-count]", text: "5"
    assert_select "[data-test-selector=advisory-review-row]", count: 8
  end

  test "search accepts a non-default search type" do
    get "/search", headers: { "X-Okta-Username" => @user.email }, params: { search_type: "cve_review" }

    assert_response :ok
    assert_select "[data-test-selector=advisory-review-count]", text: "8"
    assert_select "[data-test-selector=cve-review-count]", text: "5"
    assert_select "[data-test-selector=cve-review-row]", count: 5
  end

  test "search accepts a CVE ID query" do
    get "/search", headers: { "X-Okta-Username" => @user.email }, params: { search_query: "CVE-2022-0001" }

    assert_response :ok
    assert_select "[data-test-selector=advisory-review-count]", text: "1"
    assert_select "[data-test-selector=cve-review-count]", text: "1"
    assert_select "[data-test-selector=advisory-review-row]", count: 1
  end

  test "search accepts a GHSA ID query" do
    get "/search", headers: { "X-Okta-Username" => @user.email }, params: { search_query: AdvisoryReview.last.ghsa_id }

    assert_response :ok
    assert_select "[data-test-selector=advisory-review-count]", text: "1"
    assert_select "[data-test-selector=cve-review-count]", text: "0"
    assert_select "[data-test-selector=advisory-review-row]", count: 1
  end

  test "search accepts a base-level CVE/GHSA ID requests" do
    get "/CVE-2022-0001", headers: { "X-Okta-Username" => @user.email }

    assert_response :ok
    assert_select "[data-test-selector=advisory-review-count]", text: "1"
    assert_select "[data-test-selector=cve-review-count]", text: "1"
    assert_select "[data-test-selector=advisory-review-row]", count: 1

    get "/#{AdvisoryReview.last.ghsa_id}", headers: { "X-Okta-Username" => @user.email }

    assert_response :ok
    assert_select "[data-test-selector=advisory-review-count]", text: "1"
    assert_select "[data-test-selector=cve-review-count]", text: "0"
    assert_select "[data-test-selector=advisory-review-row]", count: 1
  end
end
