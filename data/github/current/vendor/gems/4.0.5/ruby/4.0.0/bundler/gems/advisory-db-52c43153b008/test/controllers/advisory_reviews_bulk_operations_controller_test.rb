# frozen_string_literal: true

require "test_helper"

class AdvisoryReviewsControllerTest < ActionDispatch::IntegrationTest
  test "bulk close: rejects advisory reviews that do not have a published advisory" do
    create_list(:advisory_review, 10, :curation_state_open)
    user = create(:user)
    ghsa_ids = AdvisoryReview.all.map(&:ghsa_id)

    post "/advisory_reviews/bulk_close",
      params: { ghsaIds: ghsa_ids.join(",") },
      as: :json,
      headers: { "X-Okta-Username" => user.email }

    assert_request_no_errors
    AdvisoryReview.all.each { |ar| assert_equal "rejected", ar.state }
  end

  test "bulk close: reverts advisory reviews that have a published advisory" do
    create_list(:advisory_review, 10, :curation_state_open_update)
    user = create(:user)
    ghsa_ids = AdvisoryReview.all.map(&:ghsa_id)

    post "/advisory_reviews/bulk_close",
      params: { ghsaIds: ghsa_ids.join(",") },
      as: :json,
      headers: { "X-Okta-Username" => user.email }

    assert_request_no_errors
    AdvisoryReview.all.each { |ar| assert_equal "accepted", ar.state }
  end

  test "bulk close: if one advisory can't be closed, it is reported in the error hash" do
    create_list(:advisory_review, 2, :curation_state_open)
    user = create(:user)

    advisory_review_accepted = AdvisoryReview.first
    advisory_review_accepted.accept
    advisory_review_accepted.save!

    ghsa_ids = AdvisoryReview.all.map(&:ghsa_id)

    post "/advisory_reviews/bulk_close",
      params: { ghsaIds: ghsa_ids.join(",") },
      as: :json,
      headers: { "X-Okta-Username" => user.email }

    assert_response :ok
    result = response.parsed_body
    assert result.key? "errorHash"
    assert_equal 1, result["errorHash"].keys.count
    assert_equal advisory_review_accepted.ghsa_id, result["errorHash"].keys.first
  end

  test "bulk curator assignment: correctly assigns all advisories in a happy path test" do
    create_list(:advisory_review, 10, :curation_state_open)
    user = create(:user, login: "test_user")
    ghsa_ids = AdvisoryReview.all.map(&:ghsa_id)

    post "/advisory_reviews/bulk_assignment",
      params: { ghsaIds: ghsa_ids.join(","), assignTo: user.login, assignToSlot: "1" },
      as: :json,
      headers: { "X-Okta-Username" => user.email }

    assert_request_no_errors
    AdvisoryReview.includes(:approvals).all.each do |review|
      assert_equal 1, review.approvals.count
      assert_equal user.id, review.approvals.first.user_id
    end
  end

  test "bulk curator assignment: assigns then clears all advisories by submitting null for assignTo" do
    create_list(:advisory_review, 10, assign_curator: true)
    user = create(:user, login: "test_user")
    AdvisoryReview.includes(:approvals).all.each do |review|
      assert_equal 1, review.approvals.count
    end

    ghsa_ids = AdvisoryReview.all.map(&:ghsa_id)
    post "/advisory_reviews/bulk_assignment",
      params: { ghsaIds: ghsa_ids.join(","), assignToSlot: "1" },
      as: :json,
      headers: { "X-Okta-Username" => user.email }

    assert_request_no_errors
    AdvisoryReview.includes(:approvals).all.each do |review|
      assert_equal 0, review.approvals.count
    end
  end

  test "bulk curator assignment: assigns over any reviewers previously assigned" do
    create_list(:advisory_review, 10, assign_curator: true)
    user = create(:user, login: "test_user")
    AdvisoryReview.includes(:approvals).all.each do |review|
      assert_equal 1, review.approvals.count
    end

    ghsa_ids = AdvisoryReview.all.map(&:ghsa_id)
    post "/advisory_reviews/bulk_assignment",
      params: { ghsaIds: ghsa_ids.join(","), assignTo: user.login, assignToSlot: "1" },
      as: :json,
      headers: { "X-Okta-Username" => user.email }

    assert_request_no_errors
    AdvisoryReview.includes(:approvals).all.each do |review|
      assert_equal 1, review.approvals.count
      assert_equal user.id, review.approvals.first.user_id
    end
  end

  test "bulk curator assignment: assigns curators to both slots" do
    create_list(:advisory_review, 10)
    user = create(:user, login: "test_user")
    second_user = create(:user, login: "second_test_user")

    ghsa_ids = AdvisoryReview.all.map(&:ghsa_id)
    post "/advisory_reviews/bulk_assignment",
      params: { ghsaIds: ghsa_ids.join(","), assignTo: user.login, assignToSlot: "1" },
      as: :json,
      headers: { "X-Okta-Username" => user.email }

    post "/advisory_reviews/bulk_assignment",
      params: { ghsaIds: ghsa_ids.join(","), assignTo: second_user.login, assignToSlot: "2" },
      as: :json,
      headers: { "X-Okta-Username" => user.email }

    assert_request_no_errors
    AdvisoryReview.includes(:approvals).all.each do |review|
      assert_equal 2, review.approvals.count
      assert_equal user.id, review.approvals.first.user_id
      assert_equal second_user.id, review.approvals.second.user_id
    end
  end

  test "bulk curator assignment: unassign works" do
    create_list(:advisory_review, 10, assign_curator: true)
    user = create(:user, login: "test_user")
    AdvisoryReview.includes(:approvals).all.each do |review|
      assert_equal 1, review.approvals.count
    end

    ghsa_ids = AdvisoryReview.all.map(&:ghsa_id)
    post "/advisory_reviews/bulk_assignment",
      params: { ghsaIds: ghsa_ids.join(","), assignTo: nil, assignToSlot: "1" },
      as: :json,
      headers: { "X-Okta-Username" => user.email }

    assert_request_no_errors
    AdvisoryReview.includes(:approvals).all.each do |review|
      assert_equal 0, review.approvals.count
    end
  end

  test "bulk ecosystem assignment: setting ecosystem without package name works" do
    create_list(:advisory_review, 10, advisory_payload: { vulnerabilities: {} })
    user = create(:user, login: "test_user")
    ghsa_ids = AdvisoryReview.all.map(&:ghsa_id)
    post "/advisory_reviews/bulk_ecosystem_and_package_name",
      params: { ghsaIds: ghsa_ids.join(","), ecosystem: "npm" },
      as: :json,
      headers: { "X-Okta-Username" => user.email }

    assert_request_no_errors
    AdvisoryReview.all.each do |review|
      assert_equal 1, review.vulnerabilities.count
      assert_equal "npm", review.vulnerabilities.values.first["ecosystem"]
    end

    # Show a second assignment works
    post "/advisory_reviews/bulk_ecosystem_and_package_name",
      params: { ghsaIds: ghsa_ids.join(","), ecosystem: "go" },
      as: :json,
      headers: { "X-Okta-Username" => user.email }

    assert_request_no_errors
    AdvisoryReview.all.each do |review|
      assert_equal 2, review.vulnerabilities.count
      assert_equal ["go", "npm"], review.vulnerabilities.values.map { |v| v["ecosystem"] }.sort
    end
  end

  test "bulk ecosystem assignment: setting ecosystem with package name works" do
    create_list(:advisory_review, 10, advisory_payload: { vulnerabilities: {} })
    user = create(:user, login: "test_user")
    ghsa_ids = AdvisoryReview.all.map(&:ghsa_id)
    post "/advisory_reviews/bulk_ecosystem_and_package_name",
      params: { ghsaIds: ghsa_ids.join(","), ecosystem: "npm", packageName: "lodash" },
      as: :json,
      headers: { "X-Okta-Username" => user.email }

    assert_request_no_errors
    AdvisoryReview.all.each do |review|
      assert_equal 1, review.vulnerabilities.count
      assert_equal "npm", review.vulnerabilities.values.first["ecosystem"]
      assert_equal "lodash", review.vulnerabilities.values.first["package_name"]
    end
  end

  test "bulk ecosystem assignment: setting package name after an ecosystem set reuses existing ecosystem entry" do
    create_list(:advisory_review, 10, advisory_payload: { vulnerabilities: {} })
    user = create(:user, login: "test_user")
    ghsa_ids = AdvisoryReview.all.map(&:ghsa_id)
    post "/advisory_reviews/bulk_ecosystem_and_package_name",
      params: { ghsaIds: ghsa_ids.join(","), ecosystem: "npm" },
      as: :json,
      headers: { "X-Okta-Username" => user.email }

    assert_request_no_errors
    post "/advisory_reviews/bulk_ecosystem_and_package_name",
      params: { ghsaIds: ghsa_ids.join(","), ecosystem: "npm", packageName: "lodash" },
      as: :json,
      headers: { "X-Okta-Username" => user.email }

    AdvisoryReview.all.each do |review|
      assert_equal 1, review.vulnerabilities.count
      assert_equal "npm", review.vulnerabilities.values.first["ecosystem"]
      assert_equal "lodash", review.vulnerabilities.values.first["package_name"]
    end
  end

  test "bulk ecosystem assignment: setting package name without ecosystem 400s" do
    create_list(:advisory_review, 10, advisory_payload: { vulnerabilities: {} })
    user = create(:user, login: "test_user")
    ghsa_ids = AdvisoryReview.all.map(&:ghsa_id)
    post "/advisory_reviews/bulk_ecosystem_and_package_name",
      params: { ghsaIds: ghsa_ids.join(","), packageName: "lodash" },
      as: :json,
      headers: { "X-Okta-Username" => user.email }

    assert_response :bad_request
    AdvisoryReview.all.each do |review|
      assert_equal 0, review.vulnerabilities.count
    end
  end

  test "bulk label options pre-selects labels that all reviews share" do
    user = create(:user)
    advisory_reviews = create_list(:advisory_review, 10)
    label_1 = create(:label)
    label_1.advisory_reviews = advisory_reviews[0...3]
    label_2 = create(:label)
    label_2.advisory_reviews = advisory_reviews[0...5]

    post "/advisory_reviews/bulk_label_options",
      params: { ghsaIds: advisory_reviews[0...4].map(&:ghsa_id).join(",") },
      as: :json,
      headers: { "X-Okta-Username" => user.email, "Accept" => "text/html" }

    assert_response :ok
    assert_select "input[checked][value=#{label_1.id}]", 0
    assert_select "input[checked][value=#{label_2.id}]", 1
  end

  test "bulk label: sets labels if they are missing from the reviews" do
    user = create(:user)
    advisory_reviews = create_list(:advisory_review, 10)
    label_1 = create(:label) # All reviews mising label
    label_2 = create(:label) # Some reviews missing label
    label_2.advisory_reviews = advisory_reviews[0...3]

    post "/advisory_reviews/bulk_labels",
      params: { ghsaIds: advisory_reviews[0...5].map(&:ghsa_id).join(","), labelIds: [label_1.id, label_2.id] },
      as: :json,
      headers: { "X-Okta-Username" => user.email }

    assert_request_no_errors
    assert_equal 5, label_1.reload.advisory_reviews.length
    assert(advisory_reviews[0...5].all? { |review| label_1.advisory_reviews.include?(review) })
    assert_equal 5, label_2.reload.advisory_reviews.length
    assert(advisory_reviews[0...5].all? { |review| label_2.advisory_reviews.include?(review) })
  end

  test "bulk label: removes labels shared by all reviews" do
    user = create(:user)
    advisory_reviews = create_list(:advisory_review, 10)
    label_1 = create(:label) # All reviews have label
    label_1.advisory_reviews = advisory_reviews
    label_2 = create(:label) # Some reviews have label
    label_2.advisory_reviews = advisory_reviews[0...3]

    post "/advisory_reviews/bulk_labels",
      params: { ghsaIds: advisory_reviews[0...5].map(&:ghsa_id).join(","), labelIds: [] },
      as: :json,
      headers: { "X-Okta-Username" => user.email }

    assert_request_no_errors
    assert_equal 5, label_1.reload.advisory_reviews.length
    assert(advisory_reviews[5...10].all? { |review| label_1.advisory_reviews.include?(review) })
    assert_equal 3, label_2.reload.advisory_reviews.length
    assert(advisory_reviews[0...3].all? { |review| label_2.advisory_reviews.include?(review) })
  end

  def assert_request_no_errors
    assert_response :ok
    result = response.parsed_body
    assert result.key? "errorHash"
    assert_equal 0, result["errorHash"].keys.count
  end
end
