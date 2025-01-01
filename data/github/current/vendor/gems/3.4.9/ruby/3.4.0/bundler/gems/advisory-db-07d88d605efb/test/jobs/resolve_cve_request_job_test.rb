# frozen_string_literal: true

require "test_helper"

class ResolveCVERequestJobTest < ActiveJob::TestCase
  test "Creates a CVEReview for CVE Requests where no previous CVE Review exists for the GHSA" do
    cve_request = create(:cve_request,
      advisory_permalink: "https://github.com/SomeOrg/SomeApp/security/advisories/GHSA-2222-2222-2222",
      cvss_v3: "CVSS:3.1/AV:A/AC:H/PR:L/UI:R/S:U/C:L/I:H/A:N")

    assert_difference("CVEReview.count", 1) do
      ResolveCVERequestJob.new.perform(cve_request.id)
    end

    new_cve_review = CVEReview.last

    # some attributes of CVE Review are initialized to static defaults
    assert new_cve_review.cve_requests.include?(cve_request)
    assert_equal new_cve_review.state, "open"
    assert_equal new_cve_review.decision, "undecided"
    assert_nil new_cve_review.assigned_cve_id
    assert_nil new_cve_review.comment
    assert_equal [], new_cve_review.misc_references
    assert_equal [], new_cve_review.problemtype_values
    assert_equal [], new_cve_review.version_values

    # some attributes are initialized based on the CVE Request
    assert_equal cve_request.ghsa_id, new_cve_review.ghsa_id
    assert_equal cve_request.title, new_cve_review.title
    assert_equal cve_request.description, new_cve_review.description
    assert_equal cve_request.advisory_permalink, new_cve_review.confirm_reference
    assert_equal cve_request.cvss_v3, new_cve_review.cvss_vectorString
    assert_equal "SomeOrg", new_cve_review.vendor_name
    assert_equal "SomeApp", new_cve_review.product
  end

  test "Attaches a CVEReview to an existing not_assigned and notified cve request if one exists, state becomes open & decision becomes undecided" do
    existing_cve_review = create :not_assigned_cve_review, state: "notified"
    cve_request = create :cve_request, ghsa_id: existing_cve_review.ghsa_id

    assert_no_difference("CVEReview.count") do
      ResolveCVERequestJob.new.perform(cve_request.id)
    end

    existing_cve_review.reload

    assert existing_cve_review.cve_requests.include?(cve_request)
    assert_equal existing_cve_review.ghsa_id, cve_request.ghsa_id
    assert_equal existing_cve_review.state, "open"
    assert_equal existing_cve_review.decision, "undecided"
    assert_nil existing_cve_review.assigned_cve_id
    assert existing_cve_review.comment.present?
  end

  test "Attaches a CVEReview to an existing undecided and open cve request if one exists, state stays open & decision stays undecided" do
    existing_cve_review = create :undecided_cve_review
    cve_request = create :cve_request, ghsa_id: existing_cve_review.ghsa_id

    assert_no_difference("CVEReview.count") do
      ResolveCVERequestJob.new.perform(cve_request.id)
    end

    existing_cve_review.reload

    assert existing_cve_review.cve_requests.include?(cve_request)
    assert_equal existing_cve_review.ghsa_id, cve_request.ghsa_id
    assert_equal existing_cve_review.state, "open"
    assert_equal existing_cve_review.decision, "undecided"
    assert_nil existing_cve_review.assigned_cve_id
    refute existing_cve_review.comment.present?
  end
end
