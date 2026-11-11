# frozen_string_literal: true

require "test_helper"

class CVEReviewsBulkOperationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    AdvisoryDB::Features.stubs(:enabled?).returns(false)
    @user = create(:user)
    @headers = { "X-Okta-Username" => @user.email, "Accept" => "application/json" }
  end

  test "bulk assignment assigns a curator to multiple CVE reviews" do
    reviews = create_list(:cve_review, 3, :curation_state_open)
    curator = AdvisoryDB::Config::ActiveCurators::CURATORS.first

    post "/cve_reviews/bulk_assignment",
      params: { ghsa_ids: reviews.map(&:ghsa_id), assignee: curator },
      as: :json,
      headers: @headers

    assert_response :ok
    reviews.each do |review|
      assert_equal curator, review.reload.assignee
    end
  end

  test "bulk assignment unassigns when assignee is empty" do
    curator = AdvisoryDB::Config::ActiveCurators::CURATORS.first
    reviews = create_list(:cve_review, 2, :curation_state_open, assignee: curator)

    post "/cve_reviews/bulk_assignment",
      params: { ghsa_ids: reviews.map(&:ghsa_id), assignee: "" },
      as: :json,
      headers: @headers

    assert_response :ok
    reviews.each do |review|
      assert_nil review.reload.assignee
    end
  end

  test "bulk assignment returns bad request when ghsa_ids is missing" do
    post "/cve_reviews/bulk_assignment",
      params: { assignee: "curator1" },
      as: :json,
      headers: @headers

    assert_response :bad_request
    assert_equal "ghsa_ids must be a non-empty array", response.parsed_body["error"]
  end

  test "bulk assignment returns bad request when ghsa_ids is not an array" do
    post "/cve_reviews/bulk_assignment",
      params: { ghsa_ids: "not-an-array", assignee: "curator1" },
      as: :json,
      headers: @headers

    assert_response :bad_request
    assert_equal "ghsa_ids must be a non-empty array", response.parsed_body["error"]
  end

  test "bulk assignment returns bad request when ghsa_ids exceeds max size" do
    ghsa_ids = (1..101).map { |i| "GHSA-#{i}" }

    post "/cve_reviews/bulk_assignment",
      params: { ghsa_ids: ghsa_ids, assignee: "curator1" },
      as: :json,
      headers: @headers

    assert_response :bad_request
    assert_match(/cannot exceed 100/, response.parsed_body["error"])
  end

  test "bulk assignment returns unprocessable entity for invalid assignee" do
    reviews = create_list(:cve_review, 2, :curation_state_open)

    post "/cve_reviews/bulk_assignment",
      params: { ghsa_ids: reviews.map(&:ghsa_id), assignee: "not-a-real-curator" },
      as: :json,
      headers: @headers

    assert_response :unprocessable_entity
    assert_match(/Invalid assignee/, response.parsed_body["error"])
    reviews.each do |review|
      assert_nil review.reload.assignee
    end
  end

  test "bulk assignment allows nil assignee to unassign without validation error" do
    curator = AdvisoryDB::Config::ActiveCurators::CURATORS.first
    reviews = create_list(:cve_review, 2, :curation_state_open, assignee: curator)

    post "/cve_reviews/bulk_assignment",
      params: { ghsa_ids: reviews.map(&:ghsa_id), assignee: nil },
      as: :json,
      headers: @headers

    assert_response :ok
    reviews.each do |review|
      assert_nil review.reload.assignee
    end
  end
end
