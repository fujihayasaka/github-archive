# frozen_string_literal: true

require "test_helper"

class HomepageControllerTest < ActionDispatch::IntegrationTest
  test "shows number of open reviews" do
    # Reviews to be counted
    create_list(:cve_review, 2, :curation_state_in_triage)
    create_list(:cve_review, 3, :curation_state_open) # also creates open advisory reviews
    create_list(:advisory_review, 5, :curation_state_open)
    create_list(:advisory_review, 4, :curation_state_ready_to_publish)

    # Reviews not to be counted
    create(:cve_review, :curation_state_waiting)
    create(:cve_review, :curation_state_published) # also creates an open advisory review
    create(:cve_review, :curation_state_closed)
    create(:advisory_review, :curation_state_waiting)
    create(:advisory_review, :curation_state_published)
    create(:advisory_review, :curation_state_withdrawn)
    create(:advisory_review, :curation_state_closed)
    create(:campaign, review_count: 5)

    user = create(:user)
    get "/", headers: { "X-Okta-Username" => user.email }

    assert_response :ok
    assert_select "[data-test-selector=in-triage-cve-review-count]", text: "2 in triage"
    assert_select "[data-test-selector=open-cve-review-count]", text: "3 open"
    assert_select "[data-test-selector=open-advisory-review-count]", text: "9 open"
    assert_select "[data-test-selector=ready-advisory-review-count]", text: "4 ready"
  end

  test "raises if advisory inbox hmac secret is not set" do
    AdvisoryDB.stubs(:verify_advisory_inbox_hmac_secret?).returns(true)
    AdvisoryDB.stubs(:advisory_inbox_hmac_secret).returns("")

    assert_raises(InboxController::MissingAdvisoryInboxHMACSecretError) do
      get "/"
    end
  end

  test "fails when the token does not match the expected value" do
    AdvisoryDB.stubs(:verify_advisory_inbox_hmac_secret?).returns(true)

    get "/", headers: {
      "X-ONG-HMAC-Token": "21fdf76aa53c806ec949b82aba71cb26455194b4c0022529b81ba214e3437dd6",
      "X-ONG-HMAC-Timestamp": "2020-04-20T01:53:23Z",
      "X-Okta-Username": "monalisa@github.com",
    }

    assert_response :unauthorized
    assert_equal "Invalid Okta network gateway HMAC token", response.body
  end

  test "succeeds when the token matches the expected value" do
    AdvisoryDB.stubs(:verify_advisory_inbox_hmac_secret?).returns(true)

    get "/", headers: {
      "X-ONG-HMAC-Token": "21fdf76aa53c806ec949b82aba71cb26455194b4c0022529b81ba214e3437dd6",
      "X-ONG-HMAC-Timestamp": "2020-04-20T01:53:23Z",
      "X-Okta-Username": "hubot@github.com",
    }

    assert_response :ok
  end
end
