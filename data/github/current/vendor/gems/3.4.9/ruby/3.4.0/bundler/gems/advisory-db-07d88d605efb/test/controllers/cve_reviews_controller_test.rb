# frozen_string_literal: true

require "test_helper"

class CVEReviewsControllerTest < ActionDispatch::IntegrationTest
  setup do
    AdvisoryDB::Features.stubs(:enabled?).returns(false)
  end

  def create_params
    {
      cve_review: {
        ghsl_request: {
          ghsl_id: "GHSL-2022-066",
          ghsl_issue: "https://github.com/github/securitylab-vulnerabilities/issues/977",
        },
        version_values: ["< 1.2.3", "< 2.3.4"],
        vendor_name: "noname",
        product: "unknown",
        cvss_vectorString: "CVSS:4.0/AV:A/AC:H/AT:N/PR:L/UI:N/VC:L/VI:H/VA:H/SC:H/SI:L/SA:H",
        problemtype_values: ["CWE-11: ASP.NET Misconfiguration: Creating Debug Binary", "CWE-7: J2EE Misconfiguration: Missing Custom Error Page"],
        confirm_reference: "https://securitylab.github.com/advisories/GHSL-2022-066_iowow/",
        misc_references: ["abc", "def"],
        title: "IOWOW is a C utility library",
        description: "IOWOW is a C utility library and persistent key/value storage engine.",
        review_notes: "abcdef",
      },
    }
  end

  test "create returns bad request if no params are passed" do
    post "/cve_reviews", headers: { "X-Okta-Username" => create(:user).email }
    assert_response :bad_request
  end

  test "create requires the title be filled" do
    create(:cve)

    request_params = create_params
    request_params[:cve_review][:title] = ""
    post cve_reviews_path, headers: { "X-Okta-Username" => create(:user).email }, params: request_params

    assert_response :unprocessable_entity
  end

  test "create does not keep lingering records if the CVE Request fails to save" do
    assert_equal 0, CVERequest.count
    assert_equal 0, CVEReview.count
    create(:cve)
    assert_equal 0, GHSLRequest.count

    request_params = create_params
    request_params[:cve_review][:confirm_reference] = nil
    post cve_reviews_path, headers: { "X-Okta-Username" => create(:user).email }, params: request_params

    assert_response :unprocessable_entity
    assert_equal 0, CVERequest.count
    assert_equal 0, CVEReview.count
    assert_equal 1, CVE.count
    assert_equal 0, GHSLRequest.count
  end

  test "create does not keep lingering records if the CVE Review fails to save" do
    assert_equal 0, CVERequest.count
    assert_equal 0, CVEReview.count
    create(:cve)
    assert_equal 0, GHSLRequest.count

    request_params = create_params
    request_params[:cve_review][:cvss_vectorString] = "invalid"
    post cve_reviews_path, headers: { "X-Okta-Username" => create(:user).email }, params: request_params

    assert_response :unprocessable_entity
    assert_equal 0, CVERequest.count
    assert_equal 0, CVEReview.count
    assert_equal 1, CVE.count
    assert_equal 0, GHSLRequest.count
  end

  test "create does not keep lingering records if the GHSL Request fails to save" do
    assert_equal 0, CVERequest.count
    assert_equal 0, CVEReview.count
    create(:cve)
    assert_equal 0, GHSLRequest.count

    request_params = create_params
    request_params[:cve_review][:ghsl_request][:ghsl_id] = nil
    post cve_reviews_path, headers: { "X-Okta-Username" => create(:user).email }, params: request_params

    assert_response :unprocessable_entity
    assert_equal 0, CVERequest.count
    assert_equal 0, CVEReview.count
    assert_equal 1, CVE.count
    assert_equal 0, GHSLRequest.count
  end

  test "create does not keep lingering records if the CVE assignment fails" do
    assert_equal 0, CVERequest.count
    assert_equal 0, CVEReview.count
    assert_equal 0, CVE.count
    assert_equal 0, GHSLRequest.count

    post "/cve_reviews", headers: { "X-Okta-Username" => create(:user).email }, params: create_params

    assert_equal 0, CVERequest.count
    assert_equal 0, CVEReview.count
    assert_equal 0, CVE.count
    assert_equal 0, GHSLRequest.count
  end

  test "create does not keep the CVE assigned if the transaction fails" do
    assert_equal 0, CVERequest.count
    assert_equal 0, CVEReview.count
    cve = create(:cve)
    assert_equal 1, CVE.count
    refute cve.assigned_at

    request_params = create_params
    request_params[:cve_review][:confirm_reference] = nil
    post "/cve_reviews", headers: { "X-Okta-Username" => create(:user).email }, params: request_params

    refute cve.reload.assigned_at
  end

  test "create makes a CVE Review" do
    assert_equal 0, CVEReview.count
    create(:cve)

    Timecop.freeze(2022, 6, 1) do
      request_params = create_params
      post "/cve_reviews", headers: { "X-Okta-Username" => create(:user).email }, params: request_params

      cve_review = CVEReview.last
      assert cve_review.ghsa_id
      assert_equal "notified", cve_review.state
      review_params = request_params[:cve_review]
      assert_equal review_params[:ghsl_request][:ghsl_id], cve_review.ghsl_request.ghsl_id
      assert_equal review_params[:ghsl_request][:ghsl_issue], cve_review.ghsl_request.ghsl_issue
      assert_equal review_params[:version_values][0], cve_review.version_values[0]
      assert_equal review_params[:version_values][1], cve_review.version_values[1]
      assert_equal review_params[:vendor_name], cve_review.vendor_name
      assert_equal review_params[:product], cve_review.product
      assert_equal review_params[:cvss_vectorString], cve_review.cvss_vectorString
      assert_equal review_params[:cvss_vectorString], cve_review.cvss_v4
      assert_equal review_params[:problemtype_values][0], cve_review.problemtype_values[0]
      assert_equal review_params[:problemtype_values][1], cve_review.problemtype_values[1]
      assert_equal review_params[:confirm_reference], cve_review.confirm_reference
      assert_equal review_params[:misc_references][0], cve_review.misc_references[0]
      assert_equal review_params[:misc_references][1], cve_review.misc_references[1]
      assert_equal review_params[:title], cve_review.title
      assert_equal review_params[:description], cve_review.description
      assert_equal review_params[:review_notes], cve_review.review_notes
    end
  end

  test "create makes a CVE Request that associates with CVE Review" do
    assert_equal 0, CVERequest.count
    create(:cve)
    user = create(:user)

    Timecop.freeze(2022, 6, 1) do
      request_params = create_params
      post "/cve_reviews", headers: { "X-Okta-Username" => user.email }, params: request_params

      assert_equal 1, CVERequest.count
      cve_request = CVERequest.last
      cve_review = cve_request.cve_review
      assert_equal cve_review.ghsa_id, cve_request.ghsa_id
      assert_equal user.id, cve_request.actor_id
      assert_equal user.login, cve_request.actor_login
      assert_equal request_params[:cve_review][:confirm_reference], cve_request.advisory_permalink
      assert_equal "open", cve_request.advisory_state
      assert_equal request_params[:cve_review][:title], cve_request.title
      assert_equal request_params[:cve_review][:description], cve_request.description
    end
  end

  test "create makes a GHSL Request that associates with CVE Review" do
    assert_equal 0, GHSLRequest.count
    create(:cve)

    Timecop.freeze(2022, 6, 1) do
      request_params = create_params
      post "/cve_reviews", headers: { "X-Okta-Username" => create(:user).email }, params: request_params

      assert_equal 1, GHSLRequest.count
      cve_review = CVEReview.last
      ghsl_request = cve_review.ghsl_request
      assert_equal cve_review.ghsa_id, ghsl_request.ghsa_id
      assert_equal request_params[:cve_review][:ghsl_request][:ghsl_id], ghsl_request.ghsl_id
      assert_equal request_params[:cve_review][:ghsl_request][:ghsl_issue], ghsl_request.ghsl_issue
    end
  end

  test "create makes an associated advisory review" do
    create(:cve)
    refute CVEReview.last

    Timecop.freeze(2022, 6, 1) do
      perform_enqueued_jobs(only: [ImportJob, ResolveFeedEntryJob, PublishImportFeedEntryToHydroJob]) do
        post "/cve_reviews", headers: { "X-Okta-Username" => create(:user).email }, params: create_params
      end

      assert_enqueued_jobs 0
      assert CVEReview.last.advisory_review
    end
  end

  test "index displays CVE reviews" do
    create_list(:cve_review, 10, :curation_state_open)
    user = create(:user)

    get "/cve_reviews",
      headers: { "X-Okta-Username" => user.email }

    assert_response :ok
    assert_select "[data-test-selector=cve-review-row]", 10
  end

  test "index by default includes CVE reviews created by the user that don't have an associated repository advisory, but a GHSL request" do
    cve_review = create(:cve_review, :assigned, :notified)
    refute cve_review.repository_advisory_feed_entry
    create(:ghsl_request, cve_review: cve_review)

    get "/cve_reviews", headers: { "X-Okta-Username" => create(:user).email }

    assert_select "[data-test-selector=cve-review-row]", 1
  end

  test "new displays a form" do
    get "/cve_reviews/new", headers: { "X-Okta-Username" => create(:user).email }

    assert_response :ok
    assert_select "[id=cve-review-form]"
  end

  test "reject returns 404 if there is no cve review for the ghsa id" do
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_cve_reviews_reject_published").at_least_once.returns(true)

    put "/cve_reviews/GHSA-9999-99999/reject", headers: { "X-Okta-Username" => create(:user).email }

    assert_response :not_found
  end

  test "reject does not succeed if rejection reason is not included" do
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_cve_reviews_reject_published").at_least_once.returns(true)

    cve_review = create(:cve_review, :assigned, :submitted)

    put "/cve_reviews/#{cve_review.ghsa_id}/reject", headers: { "X-Okta-Username" => create(:user).email, "Accept" => "text/html" }, params: { rejection: { reason_template: "invalid", reason: "", resolved_by: "" } }, as: :json

    refute cve_review.rejected?
    assert_response :unprocessable_entity
  end

  test "reject can reject a CVE Review that is not yet published" do
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_cve_reviews_reject_published").at_least_once.returns(true)

    cve_review = create(:cve_review, :curation_state_open, assigned_cve_id: "CVE-2022-20001")
    refute cve_review.submitted?
    assert_equal 0, MITRECVESubmission.count

    VCR.use_cassette("cve_api_reject_unpublished_cve") do
      put "/cve_reviews/#{cve_review.ghsa_id}/reject", headers: { "X-Okta-Username" => create(:user).email, "Accept" => "text/html" }, params: { rejection: { reason_template: "invalid", reason: "invalid!", resolved_by: "" } }, as: :json
    end

    assert cve_review.reload.rejected?
    assert_equal 1, MITRECVESubmission.count
    WebMock.assert_requested(
      :post,
      "#{AdvisoryDB.cve_services_api_url}/api/cve/#{cve_review.assigned_cve_id}/reject",
    )
    assert_redirected_to cve_review_path(cve_review.ghsa_id)
  end

  test "reject rejects a CVE Review if it is already published, after being reopened" do
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_cve_reviews_reject_published").at_least_once.returns(true)

    cve_id = "CVE-2022-20001"
    cve_review = create(:cve_review, :curation_state_published, assigned_cve_id: cve_id)
    refute cve_review.may_reject?
    cve_review.reopen!

    VCR.use_cassette("cve_api_reject_published_cve") do
      put "/cve_reviews/#{cve_review.ghsa_id}/reject",
        headers: { "X-Okta-Username" => create(:user).email, "Accept" => "text/html" },
        params: {
          rejection: {
            reason: "the reason",
          },
        },
        as: :json
    end

    WebMock.assert_requested(
      :put,
      "#{AdvisoryDB.cve_services_api_url}/api/cve/#{cve_id}/reject",
    )
    assert cve_review.reload.rejected?
    assert_redirected_to cve_review_path(cve_review.ghsa_id)
  end

  test "reject can include a value for replaced by field" do
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_cve_reviews_reject_published").at_least_once.returns(true)

    cve_id = "CVE-2022-20001"
    cve_review = create(:cve_review, :curation_state_published, assigned_cve_id: cve_id)
    cve_review.reopen!

    VCR.use_cassette("cve_api_reject_published_cve_replaced_by") do
      put "/cve_reviews/#{cve_review.ghsa_id}/reject",
        headers: { "X-Okta-Username" => create(:user).email, "Accept" => "text/html" },
        params: {
          rejection: {
            reason: "the reason",
            replaced_by: "CVE-2022-20002",
          },
        },
        as: :json
    end

    WebMock.assert_requested(
      :put,
      "#{AdvisoryDB.cve_services_api_url}/api/cve/#{cve_id}/reject",
    )
    assert cve_review.reload.rejected?
    assert_redirected_to cve_review_path(cve_review.ghsa_id)
  end

  test "show displays a CVE review's details w/ its current request info" do
    cve_review = create(
      :assigned_cve_review,
      :notified,
      :all_fields_populated,
      vendor_name: "vendor",
      product: "product",
      confirm_reference: "https://github.com",
      title: "this is a test",
      review_notes: "review notes here",
    )
    user = create(:user)

    get "/cve_reviews/#{cve_review.ghsa_id}",
      headers: { "X-Okta-Username" => user.email }

    assert_response :ok
    assert_select "[data-test-selector=review-title]", text: "this is a test"
    assert_select "[data-test-selector=review-state]", text: "Waiting"
    assert_select "[data-test-selector=read-only-badge]", count: 0
    assert_select "[data-test-selector=cve-review-sidebar-button]", count: 1
    # no publish button is shown when curation_state == "waiting"
    assert_select "[data-test-selector=cve-reviews-sidebar-component-publish-button]", count: 0

    assert_select "[data-test-selector='vendor-name']", text: "vendor"
    assert_select "[data-test-selector='product']", text: "product"
    assert_select "[data-test-selector='confirm-reference']", text: "https://github.com"
    assert_select "[data-test-selector='cve-review-notes']", text: "review notes here"

    assert_select "[data-test-selector='ecosystem']", text: cve_review.current_cve_request.affected_products_payload[0]["ecosystem"]
    assert_select "[data-test-selector='package']", text: cve_review.current_cve_request.affected_products_payload[0]["package"]
    assert_select "[data-test-selector='affected-versions']", text: cve_review.current_cve_request.affected_products_payload[0]["affected_versions"]
    assert_select "[data-test-selector='patches']", text: cve_review.current_cve_request.affected_products_payload[0]["patches"]
  end

  test "show displays a read-only CVE review" do
    cve_review = create(:not_assigned_cve_review)
    user = create(:user)

    get "/cve_reviews/#{cve_review.ghsa_id}",
      headers: { "X-Okta-Username" => user.email }

    assert_response :ok
    assert_select "[data-test-selector=review-title]", text: cve_review.title
    assert_select "[data-test-selector=review-state]", text: "Triage"
    assert_select "[data-test-selector=read-only-badge]", count: 1
    assert_select "[data-test-selector=cve-review-sidebar-button]", count: 0
  end

  test "show triggers a check suite" do
    cve_review = create(:cve_review)
    user = create(:user)

    assert_equal(0, CheckSuiteRunner.get_checks(review: cve_review).count { |check| check["status"] })

    get "/cve_reviews/#{cve_review.ghsa_id}",
      headers: { "X-Okta-Username" => "#{user.login}@github.com" }

    assert CheckSuiteRunner.get_checks(review: cve_review).count { |check| check["status"] } > 0
  end

  test "show shows Publish to MITRE button" do
    cve_review = create(:cve_review, :curation_state_open)

    get "/cve_reviews/#{cve_review.ghsa_id}",
      headers: { "X-Okta-Username" => create(:user).email }

    assert_select("[data-test-selector='cve-reviews-sidebar-component-publish-button']", count: 1)
    assert_select("form[action='/cve_reviews/#{cve_review.ghsa_id}/publish']", count: 1)
  end

  test "show includes section for internal use fields ghsl_id and ghsl_issue if CVE Review has an associated GHSL Request record" do
    cve_review = create(:cve_review, :curation_state_open)
    create(:ghsl_request, cve_review: cve_review)

    get "/cve_reviews/#{cve_review.ghsa_id}",
      headers: { "X-Okta-Username" => create(:user).email }

    assert_select("[data-test-selector='cve-review-fields-for-internal-use']", count: 1)
    assert_select("[data-test-selector='cve-review-ghsl-request-ghsl-id']", count: 1)
    assert_select("[data-test-selector='cve-review-ghsl-request-ghsl-issue']", count: 1)
  end

  test "show does not include section for internal use fields ghsl_id and ghsl_issue if CVE Review does not have an associated GHSL Request record" do
    cve_review = create(:cve_review, :curation_state_open)
    refute cve_review.ghsl_request

    get "/cve_reviews/#{cve_review.ghsa_id}",
      headers: { "X-Okta-Username" => create(:user).email }

    assert_select("[data-test-selector='cve-review-fields-for-internal-use']", count: 0)
    assert_select("[data-test-selector='cve-review-ghsl-request-ghsl-id']", count: 0)
    assert_select("[data-test-selector='cve-review-ghsl-request-ghsl-issue']", count: 0)
  end

  test "show includes a banner about GHSL if CVE Review has an associated GHSL Request record" do
    cve_review = create(:cve_review, :curation_state_open)
    create(:ghsl_request, cve_review: cve_review)

    get "/cve_reviews/#{cve_review.ghsa_id}",
      headers: { "X-Okta-Username" => create(:user).email }

    assert_select("[data-test-selector='cve-review-ghsl-request-banner']", count: 1)
  end

  test "show does not include banner about GHSL if CVE Review does not have an associated GHSL Request record" do
    cve_review = create(:cve_review, :curation_state_open)
    refute cve_review.ghsl_request

    get "/cve_reviews/#{cve_review.ghsa_id}",
      headers: { "X-Okta-Username" => create(:user).email }

    assert_select("[data-test-selector='cve-review-ghsl-request-banner']", count: 0)
  end

  test "update updates the GHSL Request associated with the CVE Review" do
    cve_review = create(:cve_review, :curation_state_open)
    create(:ghsl_request, cve_review: cve_review, ghsl_id: "", ghsl_issue: "")

    put("/cve_reviews/#{cve_review.ghsa_id}",
      headers: { "X-Okta-Username" => create(:user).email },
      params: {
        cve_review: {
          ghsl_request: {
            ghsl_id: "GHSL-2021-123",
            ghsl_issue: "https://github.com/github/securitylab-vulnerabilities/issues/912",
          },
        },
      },
      as: :json)

    cve_review.reload
    assert_equal "GHSL-2021-123", cve_review.ghsl_request.ghsl_id
    assert_equal "https://github.com/github/securitylab-vulnerabilities/issues/912", cve_review.ghsl_request.ghsl_issue
  end

  test "update updates the cvss_v4 attribute when cvss_vectorString is updated with a CVSS 4 vector string" do
    cve_review = create(:cve_review, :curation_state_open, cvss_vectorString: "CVSS:3.1/AV:N/AC:H/PR:L/UI:N/S:U/C:H/I:N/A:N")

    put("/cve_reviews/#{cve_review.ghsa_id}",
      headers: { "X-Okta-Username" => create(:user).email },
      params: { cve_review: { cvss_vectorString: "CVSS:4.0/AV:A/AC:H/AT:N/PR:L/UI:N/VC:L/VI:H/VA:H/SC:H/SI:L/SA:H" } },
      as: :json)

    cve_review.reload
    assert_equal cve_review.cvss_v4, cve_review.cvss_vectorString
  end
end

class CVEReviewsControllerPublishMITREUpdateTest < ActionDispatch::IntegrationTest
  setup do
    AdvisoryDB::Features.stubs(:enabled?).returns(false)
  end

  test "a CVE Review that does not exist should present a Not Found page" do
    put "/cve_reviews/#{generate(:ghsa_id)}/publish", headers: { "X-Okta-Username" => create(:user).email }

    assert_response :not_found
  end

  test "an incomplete CVE Review presents an Unprocessable Entity error" do
    cve_review = create(:cve_review, :curation_state_open_update, vendor_name: "")

    put "/cve_reviews/#{cve_review.ghsa_id}/publish", headers: { "X-Okta-Username" => create(:user).email }

    assert_response :unprocessable_entity
  end

  test "calls the external MITRE API endpoint to update the CVE record" do
    CheckSuiteRunner.stubs(run_checks: true)
    CheckSuiteRunner.stubs(checks_passed?: true)
    cve_review = create(:cve_review, :curation_state_open_update, :all_fields_populated)
    assert_equal "open_update", cve_review.state
    CVEAPI::Client.any_instance.expects(:update_cve).once.with(
      cve_review.assigned_cve_id,
      JSON.generate("cnaContainer" => JSON.parse(cve_review.cve_json_builder.to_json)["containers"]["cna"]),
    )

    put "/cve_reviews/#{cve_review.ghsa_id}/publish", headers: { "X-Okta-Username" => create(:user).email, "Accept" => "text/html" }, params: { pull_request_url: "api" }, as: :json
  end
end

class CVEReviewsControllerReopenTest < ActionDispatch::IntegrationTest
  setup do
    AdvisoryDB::Features.stubs(:enabled?).returns(false)
  end

  test "a CVE Review that does not exist should present a Not Found page" do
    put "/cve_reviews/#{generate(:ghsa_id)}/reopen", headers: { "X-Okta-Username" => create(:user).email }

    assert_response :not_found
  end

  test "a published CVE Review changes state from submitted to open_update, redirects to its show page" do
    cve_review = create(:cve_review, :curation_state_published)
    assert_equal "submitted", cve_review.state

    put "/cve_reviews/#{cve_review.ghsa_id}/reopen", headers: { "X-Okta-Username" => create(:user).email }

    assert_equal "open_update", cve_review.reload.state
    assert_redirected_to "/cve_reviews/#{cve_review.ghsa_id}"
  end

  test "a non-published CVE Review does not change its state, renders with Unprocessable Entity error" do
    [:curation_state_in_triage, :curation_state_waiting, :curation_state_open, :curation_state_open_update, :curation_state_closed].each do |curation_state_trait|
      cve_review = create(:cve_review, curation_state_trait)
      initial_state = cve_review.state

      put "/cve_reviews/#{cve_review.ghsa_id}/reopen", headers: { "X-Okta-Username" => create(:user).email }

      assert_equal initial_state, cve_review.reload.state
      assert_response :unprocessable_entity
    end
  end
end
