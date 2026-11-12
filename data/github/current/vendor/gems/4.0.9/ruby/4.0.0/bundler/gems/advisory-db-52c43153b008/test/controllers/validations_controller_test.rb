# frozen_string_literal: true

require "test_helper"

class ValidationsControllerTest < ActionDispatch::IntegrationTest
  test "cve_id returns 200 if the CVE ID is valid and unique" do
    user = create(:user)

    post cve_id_validations_path,
      headers: { "X-Okta-Username" => user.email },
      params: { value: "CVE-2021-1234" }

    assert_response :ok
  end

  test "cve_id returns 422 if the CVE ID is invalid" do
    user = create(:user)

    post cve_id_validations_path,
      headers: { "X-Okta-Username" => user.email },
      params: { value: "GHSA-4444-4444-4444" }

    assert_response :unprocessable_entity
  end

  test "cve_id returns 422 if the CVE ID is not unique" do
    user = create(:user)
    cve_review = create(:assigned_cve_review)

    post cve_id_validations_path,
      headers: { "X-Okta-Username" => user.email },
      params: { value: cve_review.assigned_cve_id }

    assert_response :unprocessable_entity
  end

  test "replaced_by_cve_id returns 200 if the CVE ID is valid and unique" do
    user = create(:user)

    post replaced_by_cve_id_validations_path,
      headers: { "X-Okta-Username" => user.email },
      params: { value: "CVE-2021-1234" }

    assert_response :ok
  end

  test "replaced_by_cve_id returns 422 if the CVE ID is invalid" do
    user = create(:user)

    post replaced_by_cve_id_validations_path,
      headers: { "X-Okta-Username" => user.email },
      params: { value: "GHSA-4444-4444-4444" }

    assert_response :unprocessable_entity
  end

  test "replaced_by_cve_id returns 200 if the CVE ID is not unique" do
    user = create(:user)
    cve_review = create(:assigned_cve_review)

    post replaced_by_cve_id_validations_path,
      headers: { "X-Okta-Username" => user.email },
      params: { value: cve_review.assigned_cve_id }

    assert_response :ok
  end
end
