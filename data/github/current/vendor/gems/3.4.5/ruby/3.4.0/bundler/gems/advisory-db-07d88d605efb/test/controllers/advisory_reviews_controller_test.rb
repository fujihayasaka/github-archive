# frozen_string_literal: true

require "test_helper"

class AdvisoryReviewsControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Allow other feature flag checks beyond the expected calls below
    AdvisoryDB::Features.stubs(:enabled?).returns(false)
  end

  test "index displays advisory reviews" do
    create_list(:advisory_review, 10, :curation_state_open)
    user = create(:user)

    get "/advisory_reviews",
      headers: { "X-Okta-Username" => user.email }

    assert_response :ok
    assert_select "[data-test-selector=advisory-review-row]", 10
  end

  test "show displays an advisory review's details" do
    advisory_review = create(:advisory_review, :curation_state_open)
    user = create(:user)

    get "/advisory_reviews/#{advisory_review.ghsa_id}",
      headers: { "X-Okta-Username" => user.email }

    assert_response :ok
    assert_select "[data-test-selector=review-title]", text: advisory_review.title
    assert_select "[data-test-selector=review-state]", text: "Open - New"
    assert_select "[data-test-selector=read-only-badge]", count: 0
    assert_select "[data-test-selector=advisory-review-sidebar-button]", count: 3
    assert_select "[data-test-selector=advisory-review-feeds]"
  end

  test "show displays a read-only advisory review" do
    advisory_review = create(:advisory_review, :accepted)
    user = create(:user)

    get "/advisory_reviews/#{advisory_review.ghsa_id}",
      headers: { "X-Okta-Username" => user.email }

    assert_response :ok
    assert_select "[data-test-selector=review-title]", text: advisory_review.title
    assert_select "[data-test-selector=review-state]", text: "Published - Reviewed"
    assert_select "[data-test-selector=read-only-badge]", count: 1
    assert_select "[data-test-selector=advisory-review-sidebar-button]", count: 1
  end

  test "show triggers a check suite" do
    advisory_review = create(:advisory_review, :open)
    user = create(:user)

    assert_equal(0, CheckSuiteRunner.get_checks(review: advisory_review).count { |check| check["status"] })

    get "/advisory_reviews/#{advisory_review.ghsa_id}",
      headers: { "X-Okta-Username" => "#{user.login}@github.com" }

    assert CheckSuiteRunner.get_checks(review: advisory_review).count { |check| check["status"] } > 0
  end

  test "show displays an advisory review's review notes" do
    advisory_review = create(:advisory_review, :open, review_notes: "Notes left by a Curator.")
    user = create(:user)

    get "/advisory_reviews/#{advisory_review.ghsa_id}",
      headers: { "X-Okta-Username" => user.email }

    assert_response :ok
    assert_select "[data-test-selector=advisory-review-notes]", text: advisory_review.review_notes
  end

  test "show displays an advisory review's pending ai predictions" do
    AdvisoryDB::Features.expects(:enabled?).with("gpt4_prediction").at_least_once.returns(true)
    advisory_review = create(:advisory_review, :open)
    create_list(:ai_prediction, 2, advisory_review: advisory_review)
    user = create(:user)

    get "/advisory_reviews/#{advisory_review.ghsa_id}",
      headers: { "X-Okta-Username" => user.email }

    assert_response :ok
    assert_select "[data-test-selector=vulnerability-prediction-form-row]", count: 2
  end

  test "update successfully" do
    user = create(:user)

    advisory_review = create(:advisory_review, :open, review_notes: "Notes left by a Curator.")

    AdvisoryReview.any_instance.expects(:notify_user_saved_event).with(user).at_least_once

    # Edit the advisory
    patch advisory_review_path(advisory_review),
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
      params: {
        advisory_review: {
          advisory_payload: {
            severity: "critical",
          },
          review_notes: "Updated notes from a Curator.",
        },
      },
      as: :json

    assert_response :found
    assert_includes flash[:notice], "Advisory review #{advisory_review.ghsa_id} was updated successfully!"
    updated_review = AdvisoryReview.last
    assert_equal updated_review.review_notes, "Updated notes from a Curator."
    assert_equal updated_review.severity, "critical"
  end

  test "create successfully" do
    user = create(:user)

    advisory_review = AdvisoryReview.new

    AdvisoryReview.any_instance.expects(:notify_user_saved_event).with(user).at_least_once

    # Edit the advisory
    post advisory_reviews_path(advisory_review),
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
      params: {
        advisory_review: {
          advisory_payload: {
            severity: "critical",
            vulnerabilities: {
              "0": { fix_commits: ["samplecommittext", "samplecommittext2"] },
            },
          },
          review_notes: "Updated notes from a Curator.",
        },
      },
      as: :json

    assert_response :found
    assert_includes flash[:notice], "was created successfully!"
    updated_review = AdvisoryReview.last
    assert_equal updated_review.review_notes, "Updated notes from a Curator."
    assert_equal updated_review.severity, "critical"
  end

  test "creates successfully with CVSS v3" do
    user = create(:user)
    advisory_review = AdvisoryReview.new

    AdvisoryReview.any_instance.expects(:notify_user_saved_event).with(user).at_least_once

    post advisory_reviews_path(advisory_review),
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
      params: {
        advisory_review: {
          advisory_payload: {
            cvss_v3: "CVSS:3.1/AV:N/AC:H/PR:L/UI:N/S:U/C:H/I:N/A:N",
            severity: "low",
            vulnerabilities: {
              "0": { fix_commits: ["samplecommittext", "samplecommittext2"] },
            },
          },
        },
      },
      as: :json

    advisory_review = AdvisoryReview.last

    assert_response :found
    assert_includes flash[:notice], "was created successfully!"
    assert_equal "CVSS:3.1/AV:N/AC:H/PR:L/UI:N/S:U/C:H/I:N/A:N", advisory_review.advisory_payload["cvss_v3"]
    assert_equal "moderate", advisory_review.severity
  end

  test "creates successfully with CVSS v4" do
    user = create(:user)
    advisory_review = AdvisoryReview.new

    AdvisoryReview.any_instance.expects(:notify_user_saved_event).with(user).at_least_once

    post advisory_reviews_path(advisory_review),
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
      params: {
        advisory_review: {
          advisory_payload: {
            cvss_v4: "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:L/SC:H/SI:H/SA:H",
            severity: "low",
            vulnerabilities: {
              "0": { fix_commits: ["samplecommittext", "samplecommittext2"] },
            },
          },
        },
      },
      as: :json

    advisory_review = AdvisoryReview.last

    assert_response :found
    assert_includes flash[:notice], "was created successfully!"
    assert_equal "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:L/SC:H/SI:H/SA:H", advisory_review.advisory_payload["cvss_v4"]
    assert_equal "high", advisory_review.severity
  end

  test "create calculates the severity based on CVSS 4 if both v3 and v4 vector strings are present" do
    user = create(:user)
    advisory_review = AdvisoryReview.new

    AdvisoryReview.any_instance.expects(:notify_user_saved_event).with(user).at_least_once

    post advisory_reviews_path(advisory_review),
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
      params: {
        advisory_review: {
          advisory_payload: {
            cvss_v3: "CVSS:3.1/AV:N/AC:H/PR:L/UI:N/S:U/C:H/I:N/A:N", # Has a severity of "moderate"
            cvss_v4: "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:L/SC:H/SI:H/SA:H", # Has a severity of "high"
            severity: "low",
            vulnerabilities: {
              "0": { fix_commits: ["samplecommittext", "samplecommittext2"] },
            },
          },
        },
      },
      as: :json

    advisory_review = AdvisoryReview.last

    assert_response :found
    assert_includes flash[:notice], "was created successfully!"
    assert_equal "CVSS:3.1/AV:N/AC:H/PR:L/UI:N/S:U/C:H/I:N/A:N", advisory_review.advisory_payload["cvss_v3"]
    assert_equal "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:L/SC:H/SI:H/SA:H", advisory_review.advisory_payload["cvss_v4"]
    assert_equal "high", advisory_review.severity
  end

  test "create does not re-calculate the severity if no CVSS vector string is in the advisory payload" do
    user = create(:user)
    advisory_review = AdvisoryReview.new

    AdvisoryReview.any_instance.expects(:notify_user_saved_event).with(user).at_least_once

    post advisory_reviews_path(advisory_review),
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
      params: {
        advisory_review: {
          advisory_payload: {
            severity: "low",
            vulnerabilities: {
              "0": { fix_commits: ["samplecommittext", "samplecommittext2"] },
            },
          },
        },
      },
      as: :json

    advisory_review = AdvisoryReview.last

    assert_response :found
    assert_includes flash[:notice], "was created successfully!"
    assert_equal "low", advisory_review.severity
  end

  test "create does not work if an invalid CVSS vector string is in the advisory payload" do
    user = create(:user)
    advisory_review = AdvisoryReview.new

    AdvisoryReview.any_instance.expects(:notify_user_saved_event).with(user).never

    post advisory_reviews_path(advisory_review),
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
      params: {
        advisory_review: {
          advisory_payload: {
            cvss_v4: "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:L/SC:H/SI:H/SA:Z", # Invalid CVSS vector string
            severity: "low",
          },
        },
      },
      as: :json

    assert_response :unprocessable_entity
  end

  test "create doesn't work if validations fail" do
    user = create(:user)

    advisory_review = AdvisoryReview.new

    AdvisoryReview.any_instance.expects(:notify_user_saved_event).with(user).never

    # Edit the advisory
    post advisory_reviews_path(advisory_review),
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
      params: {
        advisory_review: {
          advisory_payload: {
            summary: "sometextthatislongerthan255characterssometextthatislongerthan255characterssometextthatislongerthan255characterssometextthatislongerthan255characterssometextthatislongerthan255characterssometextthatislongerthan255characterssometextthatislongerthan255characterssometextthatislongerthan255characters",
            vulnerabilities: {
              "0": { fix_commits: ["samplecommittext", "samplecommittext2"] },
            },
          },
          review_notes: "Updated notes from a Curator.",
        },
      },
      as: :json
    assert_response :unprocessable_entity
  end

  test "update commits fix_commit updates" do
    user = create(:user)

    advisory_review = create(:advisory_review, :open, review_notes: "Notes left by a Curator.")
    # Edit the advisory
    patch advisory_review_path(advisory_review),
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
      params: {
        advisory_review: {
          advisory_payload: {
            severity: "critical",
            vulnerabilities: {
              "0": { fix_commits: ["samplecommittext", "samplecommittext2"] },
            },
          },
          review_notes: "Updated notes from a Curator.",
        },
      },
      as: :json

    assert_response :found
    assert_includes flash[:notice], "Advisory review #{advisory_review.ghsa_id} was updated successfully!"
    updated_review = AdvisoryReview.last
    assert_equal updated_review["advisory_payload"]["vulnerabilities"][0]["fix_commits"], ["samplecommittext", "samplecommittext2"]
  end

  test "update adds fix commits to references" do
    user = create(:user)
    advisory_review = create(:advisory_review, :open, review_notes: "Notes left by a Curator.")

    # Edit the advisory
    patch advisory_review_path(advisory_review),
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
      params: {
        advisory_review: {
          advisory_payload: {
            severity: "critical",
            vulnerabilities: {
              "0": { fix_commits: ["samplecommittext", "samplecommittext2"] },
            },
          },
          review_notes: "Updated notes from a Curator.",
        },
      },
      as: :json
    assert_response :found
    assert_includes flash[:notice], "Advisory review #{advisory_review.ghsa_id} was updated successfully!"
    updated_review = AdvisoryReview.last
    assert_equal updated_review["advisory_payload"]["references"], ["samplecommittext", "samplecommittext2"]
  end

  test "update adds fix commits to references from different ecosystems without duplications" do
    user = create(:user)
    advisory_review = create(:advisory_review, :open, review_notes: "Notes left by a Curator.")

    # Edit the advisory
    patch advisory_review_path(advisory_review),
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
      params: {
        advisory_review: {
          advisory_payload: {
            severity: "critical",
            vulnerabilities: {
              "0": { ecosystem: "composer", fix_commits: ["samplecommittext", "samplecommittext2 "] },
              "1": { ecosystem: "go", fix_commits: ["samplecommittext", "sample123"] },
              "2": { ecosystem: "nuget", fix_commits: ["samplecommittext123 ", "samplecommittext123", "sample123"] },
            },
          },
          review_notes: "Updated multiple ecosystems.",
        },
      },
      as: :json
    assert_response :found
    assert_includes flash[:notice], "Advisory review #{advisory_review.ghsa_id} was updated successfully!"
    updated_review = AdvisoryReview.last
    assert_equal updated_review["advisory_payload"]["references"], ["sample123", "samplecommittext", "samplecommittext123", "samplecommittext2"]
  end

  test "update gracefully handles no fix commits" do
    user = create(:user)
    advisory_review = create(:advisory_review, :open, review_notes: "Notes left by a Curator.")

    # Edit the advisory
    patch advisory_review_path(advisory_review),
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
      params: {
        advisory_review: {
          advisory_payload: {
            severity: "critical",
            vulnerabilities: {
              "0": {},
            },
          },
          review_notes: "Updated notes from a Curator.",
        },
      },
      as: :json

    assert_response :found
    assert_includes flash[:notice], "Advisory review #{advisory_review.ghsa_id} was updated successfully!"
    updated_review = AdvisoryReview.last
    assert_equal updated_review["advisory_payload"]["references"], []
  end

  test "update gracefully handles empty fix commits" do
    user = create(:user)
    advisory_review = create(:advisory_review, :open, review_notes: "Notes left by a Curator.")

    # Edit the advisory
    patch advisory_review_path(advisory_review),
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
      params: {
        advisory_review: {
          advisory_payload: {
            severity: "critical",
            vulnerabilities: {
              "0": { fix_commits: [""] },
            },
          },
          review_notes: "Updated notes from a Curator.",
        },
      },
      as: :json

    assert_response :found
    assert_includes flash[:notice], "Advisory review #{advisory_review.ghsa_id} was updated successfully!"
    updated_review = AdvisoryReview.last
    assert_equal updated_review["advisory_payload"]["vulnerabilities"][0]["fix_commits"], []
    assert_equal updated_review["advisory_payload"]["references"], []
  end

  test "update re-calculates the severity based on CVSS 3 when no previous CVSS vector string was present and a v3 vector string is added" do
    user = create(:user)
    advisory_review = create(
      :advisory_review,
      :open,
      advisory_payload: build(
        :advisory_payload,
        summary: "No CVSS",
        description: "An Advisory Review with no CVSS",
        cvss_v3: nil,
        cvss_v4: nil,
        severity: "low",
      ),
    )

    # Edit the advisory
    patch advisory_review_path(advisory_review),
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
      params: { advisory_review: { advisory_payload: { cvss_v3: "CVSS:3.1/AV:N/AC:H/PR:L/UI:N/S:U/C:H/I:N/A:N" } } },
      as: :json

    updated_review = AdvisoryReview.last

    assert_response :found
    assert_includes flash[:notice], "Advisory review #{advisory_review.ghsa_id} was updated successfully!"
    assert_equal "moderate", updated_review.advisory_payload["severity"]
  end

  test "update re-calculates the severity based on CVSS 4 when no previous CVSS vector string was present and a v4 vector string is added" do
    user = create(:user)
    advisory_review = create(
      :advisory_review,
      :open,
      advisory_payload: build(
        :advisory_payload,
        summary: "No CVSS",
        description: "An Advisory Review with no CVSS",
        cvss_v3: nil,
        cvss_v4: nil,
        severity: "low",
      ),
    )

    # Edit the advisory
    patch advisory_review_path(advisory_review),
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
      params: { advisory_review: { advisory_payload: { cvss_v4: "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:L/SC:H/SI:H/SA:H" } } },
      as: :json

    updated_review = AdvisoryReview.last

    assert_response :found
    assert_includes flash[:notice], "Advisory review #{advisory_review.ghsa_id} was updated successfully!"
    assert_equal "high", updated_review.advisory_payload["severity"]
  end

  test "update re-calculates the severity based on CVSS 4 if a v3 vector string is already present and a v4 vector string is added" do
    user = create(:user)
    advisory_review = create(:advisory_review, :open, :with_cvss_v3) # Has a severity of "moderate"

    # Edit the advisory
    patch advisory_review_path(advisory_review),
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
      params: { advisory_review: { advisory_payload: { cvss_v4: "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:L/SC:H/SI:H/SA:H" } } },
      as: :json

    updated_review = AdvisoryReview.last

    assert_response :found
    assert_includes flash[:notice], "Advisory review #{advisory_review.ghsa_id} was updated successfully!"
    assert_equal "high", updated_review.advisory_payload["severity"]
  end

  test "update does not re-calculate the severity if a v4 vector string was already present and a v3 vector string is added" do
    user = create(:user)
    advisory_review = create(:advisory_review, :open, :with_cvss_v4)
    updated_advisory_payload = advisory_review.advisory_payload
    updated_advisory_payload["cvss_v3"] = "CVSS:3.1/AV:N/AC:H/PR:L/UI:N/S:U/C:H/I:N/A:N" # Add a v3 vector string for when we send the update

    # Edit the advisory
    patch advisory_review_path(advisory_review),
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
      params: { advisory_review: { advisory_payload: updated_advisory_payload } },
      as: :json

    updated_review = AdvisoryReview.last

    assert_response :found
    assert_includes flash[:notice], "Advisory review #{advisory_review.ghsa_id} was updated successfully!"
    assert_equal "high", updated_review.advisory_payload["severity"]
  end

  test "update does not re-calculate the severity if no CVSS vector string is added" do
    user = create(:user)

    advisory_review = create(
      :advisory_review,
      :open,
      advisory_payload: build(
        :advisory_payload,
        summary: "No CVSS",
        description: "An Advisory Review with no CVSS",
        cvss_v3: nil,
        cvss_v4: nil,
        severity: "low",
      ),
    )

    # Edit the advisory
    patch advisory_review_path(advisory_review),
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
      params: {
        advisory_review: { advisory_payload: advisory_review.advisory_payload },
        review_notes: "Updated notes from a Curator.",
      },
      as: :json

    updated_review = AdvisoryReview.last

    assert_response :found
    assert_includes flash[:notice], "Advisory review #{advisory_review.ghsa_id} was updated successfully!"
    assert_equal "low", updated_review.advisory_payload["severity"]
  end

  test "update does not re-calculate the severity if an invalid CVSS vector string is in the advisory payload" do
    user = create(:user)
    advisory_review = create(
      :advisory_review,
      :open,
      advisory_payload: build(
        :advisory_payload,
        summary: "Invalid CVSS",
        description: "An Advisory Review with and invalid CVSS",
        cvss_v3: nil,
        cvss_v4: nil,
        severity: "moderate",
      ),
    )

    # Attempt to edit the advisory
    patch advisory_review_path(advisory_review),
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
      params: {
        advisory_review: {
          advisory_payload: advisory_review.advisory_payload,
          cvss_v4: "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:L/SC:H/SI:H/SA:Z", # Invalid CVSS vector string,
        },
        review_notes: "Updated notes from a Curator.",
      },
      as: :json

    assert_response :found
    assert_includes flash[:notice], "Advisory review #{advisory_review.ghsa_id} was updated successfully!"
    assert_equal "moderate", advisory_review.severity
  end

  test "update does not persist an advisory review's review notes if validations fail" do
    advisory_review = create(:advisory_review, :open, review_notes: "Notes left by a Curator.")
    user = create(:user)

    # This test should not notify since the update fails.
    AdvisoryReview.any_instance.expects(:notify_user_saved_event).with(user).never

    patch advisory_review_path(advisory_review),
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
      params: {
        "advisory_review" => {
          "advisory_payload" => {
            "cvss_v3" => "CVSS:3.1/AV:A/AC:H/PR:L/UI:R/S:C/C:L/I:H/A:X", # Invalid
          },
          "review_notes" => "Updated notes from a Curator.",
        },
      },
      as: :json

    assert_response :unprocessable_entity
    assert_equal advisory_review.review_notes, "Notes left by a Curator."
  end

  test "update does not clobber edits from another user" do
    user = create(:user)

    advisory_review = create(:advisory_review, :open, review_notes: "Notes left by a Curator.")
    # Capture the current values to mimic an initial user beginning to edit the page
    body_version = advisory_review.body_version
    advisory_payload = advisory_review.advisory_payload
    # Edit the advisory to mimic a second user editing before the first user submits
    advisory_review.update!(review_notes: "First edit")
    # Edit the advisory as the first user
    patch advisory_review_path(advisory_review),
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
      params: {
        advisory_review: {
          advisory_payload: advisory_payload,
          review_notes: "Updated notes from a Curator.",
        },
        body_version: body_version,
      },
      as: :json

    assert_response :unprocessable_entity
    assert_includes flash[:alert], "The Advisory review you are editing has changed. Please copy your edits and refresh the page."
    # User edits are still present on the page
    assert_select "[data-test-selector='advisory-review-notes']", text: "Updated notes from a Curator."
    # Original edit was not clobbered
    updated_review = AdvisoryReview.last
    assert_equal updated_review.review_notes, "First edit"
  end

  test "update processes ai predictions" do
    AdvisoryDB::Features.expects(:enabled?).with("gpt4_prediction").at_least_once.returns(true)
    advisory_review = create(:advisory_review, :open)
    predictions = create_list(:ai_prediction, 4,
      advisory_review: advisory_review)
    vulnerabilities = {
      "0" => create(:vulnerability_payload),
      "1" => create(:vulnerability_payload),
    }
    advisory_payload = advisory_review.advisory_payload
    advisory_payload["vulnerabilities"] = vulnerabilities
    vulnerability_predictions_params = {
      predictions[0].id.to_s => { "decision" => "accepted", "vulnerability_index" => "999" },
      predictions[1].id.to_s => { "decision" => "accepted", "vulnerability_index" => "1" },
      predictions[2].id.to_s => { "decision" => "rejected", "vulnerability_index" => "" },
      predictions[3].id.to_s => { "decision" => "pending",  "vulnerability_index" => "" },
    }

    user = create(:user)

    patch advisory_review_path(advisory_review),
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
      params: {
        advisory_review: {
          advisory_payload: advisory_payload,
          vulnerability_predictions: vulnerability_predictions_params,
        },
      },
      as: :json

    assert_equal "accepted", predictions[0].reload.curator_decision
    assert_equal "accepted", predictions[1].reload.curator_decision
    assert_equal "rejected", predictions[2].reload.curator_decision
    assert_equal "pending",  predictions[3].reload.curator_decision
  end

  test "new displays an empty advisory review form" do
    user = create(:user)

    get "/advisory_reviews/new", headers: { "X-Okta-Username" => user.email }

    assert_response :ok
    assert_select "[data-test-selector=review-title]", text: "Create an advisory review"
    assert_select "[data-test-selector=advisory-review-form]", count: 1
    assert_select "[data-test-selector=advisory-review-sidebar-button]", count: 1
  end

  test "#show still renders the advisory review page if the advisory payload has description encoded as ASCII_8BIT" do
    advisory_review = create(
      :advisory_review,
      advisory_payload: build(
        :advisory_payload,
        description: (+"’").force_encoding(::Encoding::ASCII_8BIT),
      ),
    )

    get "/advisory_reviews/#{advisory_review.ghsa_id}", headers: { "X-Okta-Username" => create(:user).email }

    assert_response :ok
  end

  test "set_labels updates the reviews's associated labels" do
    user = create(:user)
    advisory_review = create(:advisory_review)
    label_1 = create(:label)
    label_2 = create(:label)

    # Add label
    put set_labels_advisory_review_path(advisory_review),
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
      params: {
        labels: [label_1.id],
      },
      as: :json

    assert_response :found
    assert_includes flash[:notice], "Advisory review #{advisory_review.ghsa_id} labels were set!"
    assert_equal [advisory_review], label_1.reload.advisory_reviews
    assert_equal [], label_2.reload.advisory_reviews

    # Mixed adding/removing labels
    put set_labels_advisory_review_path(advisory_review),
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
      params: {
        labels: [label_2.id],
      },
      as: :json

    assert_response :found
    assert_includes flash[:notice], "Advisory review #{advisory_review.ghsa_id} labels were set!"
    assert_equal [], label_1.reload.advisory_reviews
    assert_equal [advisory_review], label_2.reload.advisory_reviews

    # Remove label
    put set_labels_advisory_review_path(advisory_review),
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" },
      params: {
        labels: [],
      },
      as: :json

    assert_response :found
    assert_includes flash[:notice], "Advisory review #{advisory_review.ghsa_id} labels were set!"
    assert_equal [], label_1.reload.advisory_reviews
    assert_equal [], label_2.reload.advisory_reviews
  end
end
