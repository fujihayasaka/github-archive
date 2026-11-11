# frozen_string_literal: true

require "test_helper"

class CVEReviewEditingTest < ActionDispatch::IntegrationTest
  test "the CVE review edit form renders current editable attributes" do
    user = create(:user)
    cwe_id_1 = create(:cwe).cwe_id
    cwe_id_2 = create(:cwe).cwe_id
    cve_review = create(
      :cve_review,
      confirm_reference: "https://github.com",
      cvss_vectorString: "CVSS:3.1/AV:L/AC:H/PR:L/UI:N/S:U/C:L/I:L/A:L",
      description: "description here",
      misc_references: [
        "https://example.com/one",
        "https://example.com/two",
      ],
      problemtype_values: [
        "#{cwe_id_1}: Name of #{cwe_id_1}",
        "#{cwe_id_2}: Name of #{cwe_id_2}",
      ],
      product: "the_product",
      review_notes: "review notes here",
      title: "this is a test",
      vendor_name: "the_vendor",
      version_values: ["< 1.0", "> 1.2, < 1.5"],
    )

    get cve_review_path(cve_review),
      headers: { "X-Okta-Username" => user.email }

    assert_response :ok

    assert_select "[data-test-selector='review-title']", text: "this is a test"

    assert_select "[data-test-selector='cve-review-form']", count: 1 do
      assert_select "[data-test-selector='cve-review-version-values-row']", count: 2 do |(row_1, row_2)|
        assert_form_field row_1, "[data-test-selector='cve-review-version-values']", value: "< 1.0"
        assert_form_field row_2, "[data-test-selector='cve-review-version-values']", value: "> 1.2, < 1.5"
      end

      assert_form_field "[data-test-selector='cvss-vector-string']", value: "CVSS:3.1/AV:L/AC:H/PR:L/UI:N/S:U/C:L/I:L/A:L"

      assert_select "[data-test-selector='cwe-form-row']", count: 2 do |(row_1, row_2)|
        assert_select row_1, "[data-test-selector='cwe-id']", text: cwe_id_1
        assert_select row_2, "[data-test-selector='cwe-id']", text: cwe_id_2
      end

      assert_select "[data-test-selector='cve-review-misc-references-row']", count: 2 do |(row_1, row_2)|
        assert_form_field row_1, "[data-test-selector='cve-review-misc-references']", value: "https://example.com/one"
        assert_form_field row_2, "[data-test-selector='cve-review-misc-references']", value: "https://example.com/two"
      end

      assert_form_field "[data-test-selector='title']", value: "this is a test"
      assert_form_field "[data-test-selector='description']", value: "description here"
      assert_form_field "[data-test-selector='cve-review-notes']", value: "review notes here"
    end
  end

  test "the CVE review edit form saves and renderes current valid attributes" do
    user = create(:user)
    cwe_id_1 = create(:cwe).cwe_id
    cwe_id_2 = create(:cwe).cwe_id
    cve_review = create(
      :assigned_cve_review,
      :notified,
      :all_fields_populated,
    )

    patch cve_review_path(cve_review),
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
      params: {
        cve_review: {
          cvss_vectorString: "CVSS:3.1/AV:A/AC:H/PR:L/UI:R/S:C/C:L/I:H/A:H",
          title: "test title",
          description: "description",
          misc_references: ["https://github.com", "https://example.com"],
          version_values: ["< 1.0", "> 1.2, < 1.5"],
          problemtype_values: [
            "#{cwe_id_1}: Name of #{cwe_id_1}",
            "#{cwe_id_2}: Name of #{cwe_id_2}",
          ],
          review_notes: "review notes here",
        },
      },
      as: :json

    assert_redirected_to cve_review_path(cve_review)
    follow_redirect! headers: { "X-Okta-Username" => user.email }
    assert_response :ok

    cve_review.reload
    assert_equal user.login, cve_review.paper_trail.originator

    assert_select "[data-test-selector='flash-notice']"
    assert_select "[data-test-selector='review-title']", text: "test title"

    assert_select "[data-test-selector='cve-review-form']", count: 1 do
      assert_select "[data-test-selector='cve-review-version-values-row']", count: 2 do |(row_1, row_2)|
        assert_form_field row_1, "[data-test-selector='cve-review-version-values']", value: "< 1.0"
        assert_form_field row_2, "[data-test-selector='cve-review-version-values']", value: "> 1.2, < 1.5"
      end

      assert_form_field "[data-test-selector='cvss-vector-string']", value: "CVSS:3.1/AV:A/AC:H/PR:L/UI:R/S:C/C:L/I:H/A:H"

      assert_select "[data-test-selector='cwe-form-row']", count: 2 do |(row_1, row_2)|
        assert_select row_1, "[data-test-selector='cwe-id']", text: cwe_id_1
        assert_select row_2, "[data-test-selector='cwe-id']", text: cwe_id_2
      end

      assert_select "[data-test-selector='cve-review-misc-references-row']", count: 2 do |(row_1, row_2)|
        assert_form_field row_1, "[data-test-selector='cve-review-misc-references']", value: "https://example.com"
        assert_form_field row_2, "[data-test-selector='cve-review-misc-references']", value: "https://github.com"
      end

      assert_form_field "[data-test-selector='title']", value: "test title"
      assert_form_field "[data-test-selector='description']", value: "description"
      assert_form_field "[data-test-selector='cve-review-notes']", value: "review notes here"
    end
  end

  test "the CVE review edit form returns validation error when invalid values" do
    user = create(:user)
    cve_review = create(
      :assigned_cve_review,
      :notified,
      title: "this is a test",
    )

    patch cve_review_path(cve_review),
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
      params: {
        cve_review: {
          cvss_vectorString: "CVSS:3.1/AV:A/AC:H/PR:L/UI:R/S:C/C:L/I:H/A:X", # Invalid,
          title: "test",
          description: "desc",
          misc_references: ["https://github.com"],
          version_values: ["< 123"],
          problemtype_values: ["CWE-123: Hello"],
        },
      },
      as: :json

    assert_response :unprocessable_entity

    assert_select "[data-test-selector='flash-alert']"
    assert_select "[data-test-selector='review-title']", text: "test"

    assert_select "[data-test-selector='cve-review-form']", count: 1 do
      assert_form_field "[data-test-selector='cvss-vector-string']", value: "CVSS:3.1/AV:A/AC:H/PR:L/UI:R/S:C/C:L/I:H/A:X", error: true
    end
  end
end
