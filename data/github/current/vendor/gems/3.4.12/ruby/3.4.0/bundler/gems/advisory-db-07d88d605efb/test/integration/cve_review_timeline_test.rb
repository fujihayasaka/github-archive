# frozen_string_literal: true

require "test_helper"

class CVEReviewTimelineTest < ActionDispatch::IntegrationTest
  setup do
    CheckSuiteRunner.stubs(run_checks: true)
    CheckSuiteRunner.stubs(checks_passed?: true)
  end

  test "the cve review timeline renders its important activity" do
    user = create(:user)
    cve_review = create(:cve_review, :curation_state_in_triage, :repository_advisory_published, :all_fields_populated)

    # Get the timeline before all the interesting stuff happens!
    get timeline_cve_review_path(cve_review),
      headers: { "X-Okta-Username" => user.email }
    assert_response :ok

    # Assert the content of the minimal timeline.
    assert_select "[data-test-selector^=timeline-item-cve-review]", count: 1
    assert_select "[data-test-selector=timeline-item-cve-review-open]", count: 1

    # Now we'll make a series of changes to the cve review to produce an
    # interesting timeline that we can make new assertions on.\

    # Close the cve review
    put close_cve_review_triage_path(cve_review),
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
      params: {
        comment: "Doesn't meet the counting rules.",
      },
      as: :json
    assert_response :redirect

    # Reopen the cve review (eg. new cve request came in)
    cve_review.reload.receive_request!

    # Assign a cve_id to the cve review
    put open_cve_review_triage_path(cve_review),
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
      params: {
        assigned_cve_id: "CVE-2021-1234",
        comment: "You have a security vulnerability.",
      },
      as: :json
    assert_response :redirect

    # Update the cve review's title
    put cve_review_path(cve_review),
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
      params: {
        cve_review: {
          title: "This is a better title for the CVE Review",
        },
      },
      as: :json
    assert_response :redirect

    # Publish the cve
    VCR.use_cassette("cve_api_create_cve_2021_1234") do
      put publish_cve_review_path(cve_review),
        headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
        params: { pull_request_url: "api" },
        as: :json
    end
    assert_response :redirect

    # All done! Now it's time to get the timeline again and see what we find.
    get timeline_cve_review_path(cve_review),
      headers: { "X-Okta-Username" => user.email }
    assert_response :ok

    # Assert the content of the fully populated timeline.
    assert_select "[data-test-selector^=timeline-item-cve-review]", count: 6 do |timeline_items|
      assert_equal "timeline-item-cve-review-open", timeline_items[0]["data-test-selector"]
      assert_equal "timeline-item-cve-review-close", timeline_items[1]["data-test-selector"]
      assert_equal "timeline-item-cve-review-reopen", timeline_items[2]["data-test-selector"]
      assert_equal "timeline-item-cve-review-assign", timeline_items[3]["data-test-selector"]
      assert_equal "timeline-item-cve-review-update", timeline_items[4]["data-test-selector"]
      assert_equal "timeline-item-cve-review-publish", timeline_items[5]["data-test-selector"]
    end
  end

  test "for reopen after publication" do
    cve_review = create(:cve_review, :curation_state_published)
    cve_review.reopen!

    get timeline_cve_review_path(cve_review), headers: { "X-Okta-Username" => create(:user).email }

    assert_select "[data-test-selector='timeline-item-cve-review-reopen']", count: 1
  end

  test "for reject after publication" do
    cve_review = create(:cve_review, :curation_state_published)
    cve_review.reopen!
    cve_review.reject!

    get timeline_cve_review_path(cve_review), headers: { "X-Okta-Username" => create(:user).email }

    assert_select "[data-test-selector='timeline-item-cve-review-reject']", count: 1
  end
end
