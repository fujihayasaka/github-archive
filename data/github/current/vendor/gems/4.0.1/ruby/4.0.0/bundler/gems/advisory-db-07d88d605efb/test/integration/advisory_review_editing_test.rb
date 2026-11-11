# frozen_string_literal: true

require "test_helper"

class AdvisoryReviewEditingTest < ActionDispatch::IntegrationTest
  test "the advisory review edit form renders current attributes" do
    user = create(:user)
    advisory_payload = create(:advisory_payload, {
      source_code_location: "https://github.com/github/advisory-db",
      vulnerabilities: {
        0 => {
          ecosystem: "rubygems",
          package_name: "rails",
          vulnerable_version_range: ">= 5.2.0, < 5.2.4.5",
          first_patched_version: "5.2.4.5",
          withdrawn: false,
        },
        # Withdrawn, shouldn't show up in test verification
        1 => {
          ecosystem: "rubygems",
          package_name: "rails",
          vulnerable_version_range: ">= 6.0.0, < 6.0.3.5",
          first_patched_version: "6.0.3.5",
          withdrawn: true,
        },
        2 => {
          ecosystem: "rubygems",
          package_name: "rails",
          vulnerable_version_range: ">= 6.1.0, < 6.1.3",
          first_patched_version: "6.1.3",
          withdrawn: false,
        },
        3 => {
          ecosystem: "npm",
          package_name: "@rails/actioncable",
          vulnerable_version_range: ">= 6.1.0, < 6.1.3",
          first_patched_version: "6.1.3",
          withdrawn: false,
        },
      },
      severity: "moderate",
      cvss_v3: "CVSS:3.1/AV:A/AC:H/PR:L/UI:R/S:C/C:L/I:H/A:L",
      cwe_ids: [
        cwe_id_1 = create(:cwe).cwe_id,
        cwe_id_2 = create(:cwe).cwe_id,
      ],
      references: [
        "https://example.com/one",
        "https://example.com/two",
      ],
      summary: "This is a test",
      description: "This is _only_ a test.",
      withdrawn: false,
    })
    advisory_review = create(:advisory_review, {
      advisory_payload: advisory_payload,
      review_notes: "Notes left by a Curator.",
      cve_id: "CVE-2022-1234",
    })

    get advisory_review_path(advisory_review),
      headers: { "X-Okta-Username" => user.email }

    assert_response :ok

    assert_select "[data-test-selector='review-title']", text: "This is a test"

    assert_select "[data-test-selector='advisory-review-form']", count: 1 do |(form)|
      # Assert the visible, populated form data.

      assert_form_field "[data-test-selector='advisory-review-cve-id']", value: "CVE-2022-1234"
      assert_form_field "[data-test-selector='source-code-location']", value: "https://github.com/github/advisory-db"

      assert_select "[data-test-selector='vulnerability-form-row']", count: 3 do |(row_1, row_2, row_3)|
        assert_form_field row_1, "[data-test-selector='ecosystem']", value: "RubyGems"
        assert_form_field row_1, "[data-test-selector='package-name']", value: "rails"
        assert_form_field row_1, "[data-test-selector='vulnerable-version-range']", value: ">= 5.2.0, < 5.2.4.5"
        assert_form_field row_1, "[data-test-selector='first-patched-version']", value: "5.2.4.5"

        assert_form_field row_2, "[data-test-selector='ecosystem']", value: "RubyGems"
        assert_form_field row_2, "[data-test-selector='package-name']", value: "rails"
        assert_form_field row_2, "[data-test-selector='vulnerable-version-range']", value: ">= 6.1.0, < 6.1.3"
        assert_form_field row_2, "[data-test-selector='first-patched-version']", value: "6.1.3"

        assert_form_field row_3, "[data-test-selector='ecosystem']", value: "npm"
        assert_form_field row_3, "[data-test-selector='package-name']", value: "@rails/actioncable"
        assert_form_field row_3, "[data-test-selector='vulnerable-version-range']", value: ">= 6.1.0, < 6.1.3"
        assert_form_field row_3, "[data-test-selector='first-patched-version']", value: "6.1.3"
      end

      assert_form_field "[data-test-selector='severity']", value: "Moderate"
      assert_form_field "[data-test-selector='cvss-v3']", value: "CVSS:3.1/AV:A/AC:H/PR:L/UI:R/S:C/C:L/I:H/A:L"

      assert_select "[data-test-selector='cwe-form-row']", count: 2 do |(row_1, row_2)|
        assert_select row_1, "[data-test-selector='cwe-id']", text: cwe_id_1
        assert_select row_2, "[data-test-selector='cwe-id']", text: cwe_id_2
      end

      assert_select "[data-test-selector='reference-form-row']", count: 2 do |(row_1, row_2)|
        assert_form_field row_1, "[data-test-selector='url']", value: "https://example.com/one"
        assert_form_field row_2, "[data-test-selector='url']", value: "https://example.com/two"
      end

      assert_form_field "[data-test-selector='summary']", value: "This is a test"
      assert_form_field "[data-test-selector='description']", value: "This is _only_ a test."
      assert_form_field "[data-test-selector='advisory-review-notes']", value: "Notes left by a Curator."

      # Assert the underlying form data as it will be submitted.

      data = form_data_for(form)
      advisory_payload_params = data.dig("advisory_review", "advisory_payload")
      assert_equal(
        {
          "source_code_location" => "https://github.com/github/advisory-db",
          "vulnerabilities" => {
            "0" => {
              "ecosystem" => "rubygems",
              "package_name" => "rails",
              "vulnerable_version_range" => ">= 5.2.0, < 5.2.4.5",
              "first_patched_version" => "5.2.4.5",
            },
            "1" => {
              "ecosystem" => "rubygems",
              "package_name" => "rails",
              "vulnerable_version_range" => ">= 6.0.0, < 6.0.3.5",
              "first_patched_version" => "6.0.3.5",
              "withdrawn" => "true",
            },
            "2" => {
              "ecosystem" => "rubygems",
              "package_name" => "rails",
              "vulnerable_version_range" => ">= 6.1.0, < 6.1.3",
              "first_patched_version" => "6.1.3",
            },
            "3" => {
              "ecosystem" => "npm",
              "package_name" => "@rails/actioncable",
              "vulnerable_version_range" => ">= 6.1.0, < 6.1.3",
              "first_patched_version" => "6.1.3",
            },
          },
          "severity" => "moderate",
          "cvss_v3" => "CVSS:3.1/AV:A/AC:H/PR:L/UI:R/S:C/C:L/I:H/A:L",
          "cvss_v4" => "",
          "cwe_ids" => [
            cwe_id_1,
            cwe_id_2,
          ],
          "problemtype_values" => [
            "#{cwe_id_1}: Name of #{cwe_id_1}",
            "#{cwe_id_2}: Name of #{cwe_id_2}",
          ],
          "references" => [
            "https://example.com/one",
            "https://example.com/two",
          ],
          "summary" => "This is a test",
          "description" => "\nThis is _only_ a test.", # Textareas prepend a newline.
          "withdrawn" => "false", # This is set in a hidden field
        },
        advisory_payload_params,
      )
    end
  end

  test "updates the advisory review" do
    user = create(:user)
    advisory_review = create(:advisory_review, review_notes: "Notes left by a Curator.")

    patch advisory_review_path(advisory_review),
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
      params: {
        "advisory_review" => {
          "advisory_payload" => {
            "source_code_location" => "https://github.com/github/github",
            "vulnerabilities" => {
              "0" => {
                "ecosystem" => "rubygems",
                "package_name" => "rails",
                "vulnerable_version_range" => ">= 5.2.0, < 5.2.4.5",
                "first_patched_version" => "5.2.4.5",
              },
              "1" => {
                "ecosystem" => "npm",
                "package_name" => "@rails/actioncable",
                "vulnerable_version_range" => ">= 6.1.0, < 6.1.3",
                "first_patched_version" => "6.1.3",
              },
            },
            "severity" => "moderate",
            "cvss_v3" => "CVSS:3.1/AV:A/AC:H/PR:L/UI:R/S:C/C:L/I:H/A:L",
            "cwe_ids" => [
              cwe_id_1 = create(:cwe).cwe_id,
              cwe_id_2 = create(:cwe).cwe_id,
            ],
            "references" => [
              "https://example.com/one",
              "https://example.com/two",
            ],
            "summary" => "This is a test",
            "description" => "This is _only_ a test.",
            "withdrawn" => "false",
          },
          "review_notes" => "Updated notes from Curator. 👍🏻",
          "cve_id" => "CVE-2022-5678",
        },
      },
      as: :json

    assert_redirected_to advisory_review_path(advisory_review)
    follow_redirect! headers: { "X-Okta-Username" => user.email }
    assert_response :ok

    advisory_review.reload
    assert_equal user.login, advisory_review.paper_trail.originator

    assert_select "[data-test-selector='flash-notice']"
    assert_select "[data-test-selector='review-title']", text: "This is a test"

    assert_select "[data-test-selector='advisory-review-form']" do
      assert_form_field "[data-test-selector='advisory-review-cve-id']", value: "CVE-2022-5678"
      assert_form_field "[data-test-selector='source-code-location']", value: "https://github.com/github/github"

      assert_select "[data-test-selector='vulnerability-form-row']", count: 2 do |(row_1, row_2)|
        assert_form_field row_1, "[data-test-selector='ecosystem']", value: "RubyGems"
        assert_form_field row_1, "[data-test-selector='package-name']", value: "rails"
        assert_form_field row_1, "[data-test-selector='vulnerable-version-range']", value: ">= 5.2.0, < 5.2.4.5"
        assert_form_field row_1, "[data-test-selector='first-patched-version']", value: "5.2.4.5"

        assert_form_field row_2, "[data-test-selector='ecosystem']", value: "npm"
        assert_form_field row_2, "[data-test-selector='package-name']", value: "@rails/actioncable"
        assert_form_field row_2, "[data-test-selector='vulnerable-version-range']", value: ">= 6.1.0, < 6.1.3"
        assert_form_field row_2, "[data-test-selector='first-patched-version']", value: "6.1.3"
      end

      assert_form_field "[data-test-selector='severity']", value: "Moderate"
      assert_form_field "[data-test-selector='cvss-v3']", value: "CVSS:3.1/AV:A/AC:H/PR:L/UI:R/S:C/C:L/I:H/A:L"

      assert_select "[data-test-selector='cwe-form-row']", count: 2 do |(row_1, row_2)|
        assert_select row_1, "[data-test-selector='cwe-id']", text: cwe_id_1
        assert_select row_2, "[data-test-selector='cwe-id']", text: cwe_id_2
      end

      assert_select "[data-test-selector='reference-form-row']", count: 2 do |(row_1, row_2)|
        assert_form_field row_1, "[data-test-selector='url']", value: "https://example.com/one"
        assert_form_field row_2, "[data-test-selector='url']", value: "https://example.com/two"
      end

      assert_form_field "[data-test-selector='summary']", value: "This is a test"
      assert_form_field "[data-test-selector='description']", value: "This is _only_ a test."
      assert_form_field "[data-test-selector='withdrawn']", value: "false"
      assert_form_field "[data-test-selector='advisory-review-notes']", value: "Updated notes from Curator. 👍🏻" # Be sure emoji is supported too

      # Be sure editing doesn't inadvertently withdraw the advisory review.
      assert_equal false, advisory_review.advisory_payload["withdrawn"]
    end
  end

  test "changes the advisory review's state to in-review" do
    user = create(:user)
    advisory_review = create(:advisory_review, :open)

    patch advisory_review_path(advisory_review),
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
      params: {
        "advisory_review" => {
          "advisory_payload" => {
            "severity" => "high",
          },
        },
      },
      as: :json

    assert_redirected_to advisory_review_path(advisory_review)
    assert_predicate advisory_review.reload, :in_review?
  end

  test "renders validation errors when update fails" do
    user = create(:user)
    advisory_review = create(:advisory_review, {
      summary: "The original summary",
      review_notes: "Notes left by a Curator.",
    })

    patch advisory_review_path(advisory_review),
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
      params: {
        "advisory_review" => {
          "advisory_payload" => {
            "vulnerabilities" => {
              "0" => {
                "ecosystem" => "rubygems",
                "package_name" => "rails",
                "vulnerable_version_range" => "5.2.0+", # Invalid
                "first_patched_version" => "5.2.4.5",
              },
              "1" => {
                "ecosystem" => "npm",
                "package_name" => "@rails/actioncable",
                "vulnerable_version_range" => ">= 6.1.0, < 6.1.3",
                "first_patched_version" => ">= 6.1.3", # Invalid
              },
            },
            "severity" => "moderate",
            "cvss_v3" => "CVSS:3.1/AV:A/AC:H/PR:L/UI:R/S:C/C:L/I:H/A:X", # Invalid
            "cwe_ids" => [
              cwe_id_1 = generate(:cwe_id), # Invalid
              cwe_id_2 = create(:cwe).cwe_id,
            ],
            "references" => [
              "https://example.com/one",
              "ftp://example.com/two", # Invalid
            ],
            "summary" => "This is a test",
            "description" => "This is _only_ a test.",
          },
          "review_notes" => "Updated notes from Curator.",
          "cve_id" => "invalid",
        },
      },
      as: :json

    assert_response :unprocessable_entity

    assert_select "[data-test-selector='flash-error']"
    assert_select "[data-test-selector='review-title']", text: "The original summary"

    assert_select "[data-test-selector='advisory-review-form']" do
      assert_form_field "[data-test-selector='advisory-review-cve-id']", value: "invalid", error: true
      assert_select "[data-test-selector='vulnerability-form-row']", count: 2 do |(row_1, row_2)|
        assert_form_field row_1, "[data-test-selector='ecosystem']", value: "RubyGems"
        assert_form_field row_1, "[data-test-selector='package-name']", value: "rails"
        assert_form_field row_1, "[data-test-selector='vulnerable-version-range']", value: "5.2.0+", error: true
        assert_form_field row_1, "[data-test-selector='first-patched-version']", value: "5.2.4.5"

        assert_form_field row_2, "[data-test-selector='ecosystem']", value: "npm"
        assert_form_field row_2, "[data-test-selector='package-name']", value: "@rails/actioncable"
        assert_form_field row_2, "[data-test-selector='vulnerable-version-range']", value: ">= 6.1.0, < 6.1.3"
        assert_form_field row_2, "[data-test-selector='first-patched-version']", value: ">= 6.1.3", error: true
      end

      assert_form_field "[data-test-selector='severity']", value: "Moderate"
      assert_form_field "[data-test-selector='cvss-v3']", value: "CVSS:3.1/AV:A/AC:H/PR:L/UI:R/S:C/C:L/I:H/A:X", error: true

      assert_select "[data-test-selector='cwe-form-row']", count: 2 do |(row_1, row_2)|
        assert_select row_1, "[data-test-selector='unknown-cwe-id']", text: cwe_id_1
        assert_select row_2, "[data-test-selector='cwe-id']", text: cwe_id_2
      end

      assert_select "[data-test-selector='reference-form-row']", count: 2 do |(row_1, row_2)|
        assert_form_field row_1, "[data-test-selector='url']", value: "https://example.com/one"
        assert_form_field row_2, "[data-test-selector='url']", value: "ftp://example.com/two", error: true
      end

      assert_form_field "[data-test-selector='summary']", value: "This is a test"
      assert_form_field "[data-test-selector='description']", value: "This is _only_ a test."
      assert_form_field "[data-test-selector='advisory-review-notes']", value: "Updated notes from Curator."
    end
  end

  test "shows a warning if the advisory review overlaps other reviews" do
    user = create(:user)
    advisory_review = create(:overlapping_advisory_review)

    get advisory_review_path(advisory_review),
      headers: { "X-Okta-Username" => user.email }

    assert_response :ok
    assert_select "[data-test-selector='flash-warning']", text: /overlap/
  end
end
