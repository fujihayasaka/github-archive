# frozen_string_literal: true

require "test_helper"

class AdvisoryReviewAssignmentTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user)
  end

  test "an advisory review can be assigned to a Curator while open" do
    advisory_review = create(:advisory_review, :open)

    post "/advisory_review_approvals",
      headers: { "X-Okta-Username" => "#{@user.login}@github.com" },
      params: { curator: @user.login, ghsa_id: advisory_review.ghsa_id }

    assert_equal 1, advisory_review.approvals.size
    assert_equal @user.id, advisory_review.approvals.first.user_id
    assert_nil advisory_review.approvals.first.approved_at
  end

  test "an advisory review can be assigned to a Curator during review" do
    advisory_review = create(:advisory_review, :in_review)

    post "/advisory_review_approvals",
      headers: { "X-Okta-Username" => "#{@user.login}@github.com" },
      params: { curator: @user.login, ghsa_id: advisory_review.ghsa_id }

    assert_redirected_to advisory_review_path(advisory_review)
    follow_redirect! headers: { "X-Okta-Username" => @user.email }
    assert_response :ok

    assert_equal 1, advisory_review.approvals.size
    assert_equal @user.id, advisory_review.approvals.first.user_id
    assert_nil advisory_review.approvals.first.approved_at
  end

  test "a second approval record is created when one Curator is already assigned" do
    advisory_review = create(:advisory_review, :in_review, assign_curator: true)

    post "/advisory_review_approvals",
      headers: { "X-Okta-Username" => "#{@user.login}@github.com" },
      params: { curator: @user.login, ghsa_id: advisory_review.ghsa_id }

    assert_redirected_to advisory_review_path(advisory_review)
    follow_redirect! headers: { "X-Okta-Username" => @user.email }
    assert_response :ok

    assert_equal 2, advisory_review.approvals.size
    assert_equal @user.id, advisory_review.approvals.second.user_id
    assert_nil advisory_review.approvals.first.approved_at
  end

  test "an assigned advisory review can be re-assigned to a different Curator during review" do
    advisory_review = create(:advisory_review, :in_review, assign_curator: true)
    new_curator = create(:user)

    put "/advisory_review_approvals/#{advisory_review.approvals.first.id}",
      headers: { "X-Okta-Username" => "#{new_curator.login}@github.com" },
      params: { curator: new_curator.login, ghsa_id: advisory_review.ghsa_id },
      as: :json

    assert_redirected_to advisory_review_path(advisory_review)
    follow_redirect! headers: { "X-Okta-Username" => new_curator.email }
    assert_response :ok

    assert_equal 1, advisory_review.approvals.size
    assert_equal new_curator.id, advisory_review.approvals.first.user_id
  end

  test "an assignee can be removed from an advisory review during review" do
    advisory_review = create(:advisory_review, :in_review, assign_curator: true)

    put "/advisory_review_approvals/#{advisory_review.approvals.first.id}",
      headers: { "X-Okta-Username" => "#{@user.login}@github.com" },
      params: { curator: "", ghsa_id: advisory_review.ghsa_id },
      as: :json

    assert_redirected_to advisory_review_path(advisory_review)
    follow_redirect! headers: { "X-Okta-Username" => @user.email }
    assert_response :ok

    assert_equal 0, advisory_review.approvals.size
  end

  test "errors are caught when something goes wrong while assigning a Curator to an advisory review" do
    advisory_review = create(:advisory_review, :in_review)

    post "/advisory_review_approvals",
      headers: { "X-Okta-Username" => "#{@user.login}@github.com" },
      params: { curator: "user_does_not_exist", ghsa_id: advisory_review.ghsa_id }

    assert_response :unprocessable_entity
    assert_equal 0, advisory_review.approvals.size
  end

  test "an advisory review update can be assigned to a separate curator" do
    advisory_review = create(:advisory_review, :curation_state_open_update, approval_count: 2)

    post "/advisory_review_approvals",
      headers: { "X-Okta-Username" => "#{@user.login}@github.com" },
      params: { curator: @user.login, ghsa_id: advisory_review.ghsa_id }

    assert_redirected_to advisory_review_path(advisory_review)
    follow_redirect! headers: { "X-Okta-Username" => @user.email }
    assert_response :ok

    assert_equal 3, advisory_review.approvals.size
    assert_equal @user.id, advisory_review.approvals.last.user_id
    assert_nil advisory_review.approvals.last.approved_at
  end

  test "an advisory review that is ready to publish can be assigned a new reviewer" do
    advisory_review = create(:advisory_review, :curation_state_ready_to_publish, approval_count: 1)

    post "/advisory_review_approvals",
      headers: { "X-Okta-Username" => "#{@user.login}@github.com" },
      params: { curator: @user.login, ghsa_id: advisory_review.ghsa_id }

    assert_redirected_to advisory_review_path(advisory_review)
    follow_redirect! headers: { "X-Okta-Username" => @user.email }
    assert_response :ok

    assert_equal 2, advisory_review.approvals.size
    assert_equal @user.id, advisory_review.approvals.last.user_id
    assert_nil advisory_review.approvals.last.approved_at
  end

  test "an advisory review that is ready to withdraw can be assigned a new reviewer" do
    advisory_review = create(:advisory_review, :curation_state_ready_to_withdraw, approval_count: 1)

    post "/advisory_review_approvals",
      headers: { "X-Okta-Username" => "#{@user.login}@github.com" },
      params: { curator: @user.login, ghsa_id: advisory_review.ghsa_id }

    assert_redirected_to advisory_review_path(advisory_review)
    follow_redirect! headers: { "X-Okta-Username" => @user.email }
    assert_response :ok

    assert_equal 2, advisory_review.approvals.size
    assert_equal @user.id, advisory_review.approvals.last.user_id
    assert_nil advisory_review.approvals.last.approved_at
  end
end
