# frozen_string_literal: true

require "test_helper"

class CVEReviewTriageTest < ActionDispatch::IntegrationTest
  setup do
    ENV["FEATURE_FLAG_CVE_AUTOMATIC_ASSIGNMENT"] = "false"
    ENV["FEATURE_FLAG_CVE_AUTOMATIC_RESERVATION"] = "false"
  end

  teardown do
    ENV["FEATURE_FLAG_CVE_AUTOMATIC_ASSIGNMENT"] = nil
    ENV["FEATURE_FLAG_CVE_AUTOMATIC_RESERVATION"] = nil
  end

  test "index redirects to done if no CVE reviews are in triage" do
    user = create(:user)
    create(:cve_review, :curation_state_waiting)
    create(:cve_review, :curation_state_closed)

    get cve_review_triage_index_path,
      headers: { "X-Okta-Username" => user.email }

    assert_redirected_to done_cve_review_triage_index_path
    follow_redirect! headers: { "X-Okta-Username" => user.email }

    assert_select "[data-test-selector=triage-zero]"
    assert_select "[data-test-selector=cve-reviews-link]"
  end

  test "index redirects to the first in-triage CVE review" do
    user = create(:user)
    create(:cve_review, :curation_state_waiting)
    create(:cve_review, :curation_state_closed)
    cve_review = create(:cve_review, :curation_state_in_triage)
    create(:cve_review, :curation_state_in_triage)

    get cve_review_triage_index_path,
      headers: { "X-Okta-Username" => user.email }

    assert_redirected_to cve_review_triage_path(cve_review)
  end

  test "show redirects to index if the CVE review is already triaged" do
    user = create(:user)
    cve_review = create(:cve_review, :curation_state_closed)
    next_cve_review = create(:cve_review, :curation_state_in_triage)

    get cve_review_triage_path(cve_review),
      headers: { "X-Okta-Username" => user.email }

    assert_redirected_to cve_review_triage_path(next_cve_review)
    assert flash[:alert]
  end

  test "show renders basic information for the CVE review" do
    user = create(:user)
    cve_review = create(:cve_review, :curation_state_in_triage)
    create(:cve_request, {
      cve_review: cve_review,
      title: title = "Test CVE Request",
      description: description = "This package has a vulnerability.",
      severity: severity = "high",
      affected_products_payload: [
        {
          ecosystem: ecosystem = "npm",
          package: package = "example-package",
          affected_versions: "< 1.2.3",
          patches: "1.2.3",
        },
      ],
      advisory_permalink: advisory_permalink = "https://github.com/foo/bar/security/advisories/GHSA-4444-4444-4444",
    })

    get cve_review_triage_path(cve_review),
      headers: { "X-Okta-Username" => user.email }

    assert_response :ok
    assert_select "[data-test-selector=title]", text: title
    assert_select "[data-test-selector=description]", text: description
    assert_select "[data-test-selector=severity]", text: severity
    assert_select "[data-test-selector=ecosystem]", text: ecosystem
    assert_select "[data-test-selector=package]", text: package
    assert_select "[data-test-selector=advisory-permalink]", text: advisory_permalink, count: 1 do |(link)|
      assert_equal advisory_permalink, link["href"]
    end
  end

  test "open changes the curation state to open and moves on" do
    user = create(:user)
    cve_review = create(:cve_review, :curation_state_in_triage)
    next_cve_review = create(:cve_review, :curation_state_in_triage)

    assert_changes -> { cve_review.reload.curation_state }, to: "waiting" do
      put open_cve_review_triage_path(cve_review),
        headers: { "X-Okta-Username" => user.email },
        params: { assigned_cve_id: "CVE-2021-1234" },
        as: :json
    end

    assert_redirected_to cve_review_triage_path(next_cve_review)
    refute flash[:alert]

    assert_equal "CVE-2021-1234", cve_review.assigned_cve_id
  end

  test "open accepts a comment" do
    user = create(:user)
    cve_review = create(:cve_review, :curation_state_in_triage)
    next_cve_review = create(:cve_review, :curation_state_in_triage)

    assert_changes -> { cve_review.reload.curation_state }, to: "waiting" do
      put open_cve_review_triage_path(cve_review),
        headers: { "X-Okta-Username" => user.email },
        params: {
          assigned_cve_id: "CVE-2021-1234",
          comment: "Test comment with placeholder ${{CVEID}} that gets replaced.",
        },
        as: :json
    end

    assert_redirected_to cve_review_triage_path(next_cve_review)
    refute flash[:alert]

    assert_equal "CVE-2021-1234", cve_review.assigned_cve_id
    assert_equal "Test comment with placeholder CVE-2021-1234 that gets replaced.", cve_review.comment
  end

  test "open redirects to done if no CVE reviews remain in triage" do
    user = create(:user)
    cve_review = create(:cve_review, :curation_state_in_triage)

    assert_changes -> { cve_review.reload.curation_state }, to: "waiting" do
      put open_cve_review_triage_path(cve_review),
        headers: { "X-Okta-Username" => user.email },
        params: { assigned_cve_id: "CVE-2021-1234" },
        as: :json
    end

    assert_redirected_to done_cve_review_triage_index_path
  end

  test "open moves on if the CVE review is already open" do
    user = create(:user)
    cve_review = create(:cve_review, :curation_state_waiting)

    assert_no_changes -> { cve_review.reload.curation_state } do
      put open_cve_review_triage_path(cve_review),
        headers: { "X-Okta-Username" => user.email }
    end

    assert_response :redirect
    refute flash[:alert]
  end

  test "open moves on if the CVE review is already closed" do
    user = create(:user)
    cve_review = create(:cve_review, :curation_state_closed)

    assert_no_changes -> { cve_review.reload.curation_state } do
      put open_cve_review_triage_path(cve_review),
        headers: { "X-Okta-Username" => user.email }
    end

    assert_response :redirect
    assert flash[:alert]
  end

  test "open, in automatic assignment, errors out if there is no available CVE for the current year" do
    ENV["FEATURE_FLAG_CVE_AUTOMATIC_ASSIGNMENT"] = "true"

    assert_equal 0, CVE.count
    cve_review = create(:cve_review, :curation_state_in_triage)

    put open_cve_review_triage_path(cve_review), headers: { "X-Okta-Username" => create(:user).email }

    assert_response :redirect
    assert_equal "No CVE ID available for assignment.", flash[:alert]
    assert_equal 0, CVE.count
    assert_equal "in_triage", cve_review.reload.curation_state
  end

  test "open, in automatic assignment, assigns an available CVE for the current year" do
    ENV["FEATURE_FLAG_CVE_AUTOMATIC_ASSIGNMENT"] = "true"

    cve_review = create(:cve_review, :curation_state_in_triage)
    current_year = Time.zone.now.year
    create(:cve, cve_id: "CVE-#{current_year - 1}-1234", year: current_year - 1)
    create(:cve, cve_id: "CVE-#{current_year + 1}-1234", year: current_year + 1)
    cve = create(:cve, cve_id: "CVE-#{current_year}-1234", year: current_year)
    refute cve.assigned_at

    put open_cve_review_triage_path(cve_review), headers: { "X-Okta-Username" => create(:user).email }

    assert_response :redirect
    refute flash[:alert]
    assert cve.reload.assigned_at
    assert_equal "waiting", cve_review.reload.curation_state
  end

  test "open, in automatic assignment, records the user who assigned the CVE" do
    ENV["FEATURE_FLAG_CVE_AUTOMATIC_ASSIGNMENT"] = "true"

    user = create(:user)
    cve_review = create(:cve_review, :curation_state_in_triage)
    cve = create(:cve)
    refute cve.assigned_at

    Timecop.freeze(2022, 6, 1) do
      put open_cve_review_triage_path(cve_review), headers: { "X-Okta-Username" => user.email }
    end

    assert_equal user, cve.reload.assigner
  end

  test "open, in automatic assignment, after assigning a CVE calls to possibly reserve more CVEs" do
    ENV["FEATURE_FLAG_CVE_AUTOMATIC_ASSIGNMENT"] = "true"
    ENV["FEATURE_FLAG_CVE_AUTOMATIC_RESERVATION"] = "true"

    Timecop.freeze(2022, 6, 1) do
      cve_review = create(:cve_review, :curation_state_in_triage)
      create(:cve)

      assert_enqueued_jobs 1, only: ReserveCVEJob do
        put open_cve_review_triage_path(cve_review), headers: { "X-Okta-Username" => create(:user).email }
      end
    end
  end

  test "close marks the CVE review as closed and moves on" do
    user = create(:user)
    cve_review = create(:cve_review, :curation_state_in_triage)
    next_cve_review = create(:cve_review, :curation_state_in_triage)

    assert_changes -> { cve_review.reload.curation_state }, to: "closed" do
      put close_cve_review_triage_path(cve_review),
        headers: { "X-Okta-Username" => user.email },
        params: { comment: "Test comment." },
        as: :json
    end

    assert_redirected_to cve_review_triage_path(next_cve_review)
    refute flash[:alert]

    assert_equal "Test comment.", cve_review.comment
  end

  test "close redirects to done if no CVE reviews remain in triage" do
    user = create(:user)
    cve_review = create(:cve_review, :curation_state_in_triage)

    assert_changes -> { cve_review.reload.curation_state }, to: "closed" do
      put close_cve_review_triage_path(cve_review),
        headers: { "X-Okta-Username" => user.email },
        params: { comment: "Test comment." },
        as: :json
    end

    assert_redirected_to done_cve_review_triage_index_path
    refute flash[:alert]
  end

  test "close does nothing if the CVE review is already closed" do
    user = create(:user)
    cve_review = create(:cve_review, :curation_state_closed)

    assert_no_changes -> { cve_review.reload.curation_state } do
      put close_cve_review_triage_path(cve_review),
        headers: { "X-Okta-Username" => user.email },
        params: { comment: "Test comment." },
        as: :json
    end

    assert_response :redirect
    refute flash[:alert]
  end

  test "close moves on if the CVE review is already open" do
    user = create(:user)
    cve_review = create(:cve_review, :curation_state_waiting)

    assert_no_changes -> { cve_review.reload.curation_state } do
      put close_cve_review_triage_path(cve_review),
        headers: { "X-Okta-Username" => user.email }
    end

    assert_response :redirect
    assert flash[:alert]
  end

  test "skip leaves the CVE review alone and moves on" do
    user = create(:user)
    cve_review = create(:cve_review, :curation_state_in_triage)
    next_cve_review = create(:cve_review, :curation_state_in_triage)

    assert_no_changes -> { cve_review.reload.curation_state } do
      put skip_cve_review_triage_path(cve_review),
        headers: { "X-Okta-Username" => user.email }
    end

    assert_redirected_to cve_review_triage_path(next_cve_review)
    refute flash[:alert]
  end

  test "skip redirects to done if no CVE reviews remain in triage" do
    user = create(:user)
    cve_review = create(:cve_review, :curation_state_in_triage)

    assert_no_changes -> { cve_review.reload.curation_state } do
      put skip_cve_review_triage_path(cve_review),
        headers: { "X-Okta-Username" => user.email }
    end

    assert_redirected_to done_cve_review_triage_index_path
    refute flash[:alert]
  end

  test "shows progress as the user performs triage" do
    user = create(:user)
    cve_reviews = create_list(:cve_review, 5, :curation_state_in_triage)

    get cve_review_triage_index_path,
      headers: { "X-Okta-Username" => user.email }
    assert_redirected_to cve_review_triage_path(cve_reviews[0])
    follow_redirect! headers: { "X-Okta-Username" => user.email }
    assert_response :ok

    assert_progress_bar total: 5

    put open_cve_review_triage_path(cve_reviews[0]),
      headers: { "X-Okta-Username" => user.email },
      params: { assigned_cve_id: "CVE-2021-1234" },
      as: :json
    assert_redirected_to cve_review_triage_path(cve_reviews[1])
    follow_redirect! headers: { "X-Okta-Username" => user.email }
    assert_response :ok

    assert_progress_bar total: 5, opened: 1

    put close_cve_review_triage_path(cve_reviews[1]),
      headers: { "X-Okta-Username" => user.email },
      params: { comment: "Test comment." },
      as: :json
    assert_redirected_to cve_review_triage_path(cve_reviews[2])
    follow_redirect! headers: { "X-Okta-Username" => user.email }
    assert_response :ok

    assert_progress_bar total: 5, opened: 1, closed: 1

    put skip_cve_review_triage_path(cve_reviews[2]),
      headers: { "X-Okta-Username" => user.email }
    assert_redirected_to cve_review_triage_path(cve_reviews[3])
    follow_redirect! headers: { "X-Okta-Username" => user.email }
    assert_response :ok

    assert_progress_bar total: 5, opened: 1, closed: 1, skipped: 1

    put open_cve_review_triage_path(cve_reviews[3]),
      headers: { "X-Okta-Username" => user.email },
      params: { assigned_cve_id: "CVE-2021-1235" },
      as: :json
    assert_redirected_to cve_review_triage_path(cve_reviews[4])
    follow_redirect! headers: { "X-Okta-Username" => user.email }
    assert_response :ok

    assert_progress_bar total: 5, opened: 2, closed: 1, skipped: 1

    put close_cve_review_triage_path(cve_reviews[4]),
      headers: { "X-Okta-Username" => user.email },
      params: { comment: "Test comment." },
      as: :json
    assert_redirected_to done_cve_review_triage_index_path
    follow_redirect! headers: { "X-Okta-Username" => user.email }
    assert_response :ok

    assert_progress_bar total: 5, opened: 2, closed: 2, skipped: 1
    assert_select "[data-test-selector=triage-zero]"

    # Finishing triage resets the user's session-stored progress. Loading
    # the triage index again restarts progress for the skipped CVE review.
    get cve_review_triage_index_path,
      headers: { "X-Okta-Username" => user.email }
    assert_redirected_to cve_review_triage_path(cve_reviews[2])
    follow_redirect! headers: { "X-Okta-Username" => user.email }
    assert_response :ok

    assert_progress_bar total: 1

    put close_cve_review_triage_path(cve_reviews[2]),
      headers: { "X-Okta-Username" => user.email },
      params: { comment: "Test comment." },
      as: :json
    assert_redirected_to done_cve_review_triage_index_path
    follow_redirect! headers: { "X-Okta-Username" => user.email }
    assert_response :ok

    assert_progress_bar total: 1, closed: 1
    assert_select "[data-test-selector=triage-zero]"

    # Finishing triage resets the user's session-stored progress. Loading
    # the triage index again shows no progress for triage zero.
    get cve_review_triage_index_path,
      headers: { "X-Okta-Username" => user.email }

    assert_redirected_to done_cve_review_triage_index_path
    follow_redirect! headers: { "X-Okta-Username" => user.email }

    refute_progress_bar
    assert_select "[data-test-selector=triage-zero]"
  end
end
