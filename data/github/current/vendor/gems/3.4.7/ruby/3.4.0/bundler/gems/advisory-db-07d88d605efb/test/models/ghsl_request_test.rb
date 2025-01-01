# frozen_string_literal: true

require "test_helper"

class GHSLRequestTest < ActiveSupport::TestCase
  test "requires an associated CVE Review" do
    ghsl_request = build(:ghsl_request, cve_review: nil)
    refute ghsl_request.save
    assert_equal ["must exist"], ghsl_request.errors[:cve_review]
  end

  test "requires a ghsa_id" do
    ghsl_request = build(:ghsl_request, ghsa_id: "")
    refute ghsl_request.save
    assert_equal ["is invalid", "can't be blank"], ghsl_request.errors[:ghsa_id]
  end

  test "requires a non-nil ghsl_id" do
    ghsl_request = build(:ghsl_request, ghsl_id: nil)
    refute ghsl_request.save
    assert_equal ["is too short (minimum is 0 characters)"], ghsl_request.errors[:ghsl_id]
  end

  test "requires a non-nil ghsl_issue" do
    ghsl_request = build(:ghsl_request, ghsl_issue: nil)
    refute ghsl_request.save
    assert_equal ["is too short (minimum is 0 characters)"], ghsl_request.errors[:ghsl_issue]
  end

  test "associates with a cve review" do
    cve_review = create(:cve_review)
    ghsl_request = create(:ghsl_request, cve_review: cve_review)
    assert_equal cve_review, ghsl_request.cve_review
  end
end
