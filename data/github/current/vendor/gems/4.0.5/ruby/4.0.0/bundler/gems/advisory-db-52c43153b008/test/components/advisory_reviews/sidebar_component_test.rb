# frozen_string_literal: true

require "test_helper"

class AdvisoryReviewsSidebarComponentTest < ViewComponent::TestCase
  setup do
    AdvisoryDB::Features.stubs(:enabled?).returns(false)
  end

  test "shows grouped publish buttons if FF is enabled and advisory can be marked ready to review" do
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_advisory_review_grouped_buttons").at_least_once.returns(true)
    advisory_review = create(:advisory_review)
    render_inline AdvisoryReviews::SidebarComponent.new(advisory_review: advisory_review)
    assert_selector "[data-test-selector='two-stage-publish-approval']", count: 1
  end

  test "shows grouped publish buttons if FF is enabled and advisory can be published" do
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_advisory_review_grouped_buttons").at_least_once.returns(true)
    advisory_review = create(:advisory_review, :curation_state_ready_to_publish)
    render_inline AdvisoryReviews::SidebarComponent.new(advisory_review: advisory_review)
    assert_selector "[data-test-selector='two-stage-publish-approval']", count: 1
  end

  test "does not show grouped publish buttons if FF is disabled" do
    advisory_review = create(:advisory_review)
    render_inline AdvisoryReviews::SidebarComponent.new(advisory_review: advisory_review)
    refute_selector "[data-test-selector='two-stage-publish-approval']"
  end

  test "shows grouped withdrawal buttons if FF is enabled and advisory can be marked ready to withdraw" do
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_advisory_review_grouped_buttons").at_least_once.returns(true)
    published_advisory_review = create(:advisory_review, :curation_state_published)
    published_advisory_review.revisit!
    render_inline AdvisoryReviews::SidebarComponent.new(advisory_review: published_advisory_review)
    assert_selector "[data-test-selector='two-stage-withdraw-approval']", count: 1
  end

  test "shows grouped withdrawal buttons if FF is enabled and advisory can be withdrawn" do
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_advisory_review_grouped_buttons").at_least_once.returns(true)
    published_advisory_review = create(:advisory_review, :curation_state_ready_to_withdraw)
    render_inline AdvisoryReviews::SidebarComponent.new(advisory_review: published_advisory_review)
    assert_selector "[data-test-selector='two-stage-withdraw-approval']", count: 1
  end

  test "does not show grouped withdrawal buttons if FF is disabled" do
    published_advisory_review = create(:advisory_review, :curation_state_published)
    published_advisory_review.revisit!
    render_inline AdvisoryReviews::SidebarComponent.new(advisory_review: published_advisory_review)
    refute_selector "[data-test-selector='two-stage-withdraw-approval']"
  end

  test "makes approved to publish button inactive if advisory has failing checks" do
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_advisory_review_grouped_buttons").at_least_once.returns(true)
    advisory_review = create(:advisory_review)
    CheckSuiteRunner.expects(:checks_passed?).with(review: advisory_review).at_least_once.returns(false)
    render_inline AdvisoryReviews::SidebarComponent.new(advisory_review: advisory_review)
    assert_selector "[data-test-selector='advisory-review-sidebar-ready-to-publish-button'][aria-disabled]", count: 1
  end

  test "makes approved to publish button inactive if advisory is already approved to publish" do
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_advisory_review_grouped_buttons").at_least_once.returns(true)
    advisory_review = create(:advisory_review, :curation_state_ready_to_publish)
    render_inline AdvisoryReviews::SidebarComponent.new(advisory_review: advisory_review)
    assert_selector "[data-test-selector='advisory-review-sidebar-ready-to-publish-button'][aria-disabled]", count: 1
  end

  test "makes publish button inactive if advisory has failing checks" do
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_advisory_review_grouped_buttons").at_least_once.returns(true)
    advisory_review = create(:advisory_review, :curation_state_ready_to_publish)
    CheckSuiteRunner.expects(:checks_passed?).with(review: advisory_review).at_least_once.returns(false)
    render_inline AdvisoryReviews::SidebarComponent.new(advisory_review: advisory_review)
    assert_selector "[data-test-selector='advisory-review-sidebar-publish-button'][aria-disabled]", count: 1
  end

  test "makes publish button inactive if advisory has not been approved to publish" do
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_advisory_review_grouped_buttons").at_least_once.returns(true)
    advisory_review = create(:advisory_review)
    render_inline AdvisoryReviews::SidebarComponent.new(advisory_review: advisory_review)
    assert_selector "[data-test-selector='advisory-review-sidebar-publish-button'][aria-disabled]", count: 1
  end

  test "makes approved to withdraw button inactive if advisory has failing checks" do
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_advisory_review_grouped_buttons").at_least_once.returns(true)
    published_advisory_review = create(:advisory_review, :curation_state_published)
    published_advisory_review.revisit!
    CheckSuiteRunner.expects(:checks_passed?).with(review: published_advisory_review).at_least_once.returns(false)
    render_inline AdvisoryReviews::SidebarComponent.new(advisory_review: published_advisory_review)
    assert_selector "[data-test-selector='advisory-review-sidebar-ready-to-withdraw-button'][aria-disabled]", count: 1
  end

  test "makes approved to withdraw button inactive if advisory is already approved to withdraw" do
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_advisory_review_grouped_buttons").at_least_once.returns(true)
    published_advisory_review = create(:advisory_review, :curation_state_ready_to_withdraw)
    render_inline AdvisoryReviews::SidebarComponent.new(advisory_review: published_advisory_review)
    assert_selector "[data-test-selector='advisory-review-sidebar-ready-to-withdraw-button'][aria-disabled]", count: 1
  end

  test "makes withdraw button inactive if advisory has failing checks" do
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_advisory_review_grouped_buttons").at_least_once.returns(true)
    published_advisory_review = create(:advisory_review, :curation_state_ready_to_withdraw)
    CheckSuiteRunner.expects(:checks_passed?).with(review: published_advisory_review).at_least_once.returns(false)
    render_inline AdvisoryReviews::SidebarComponent.new(advisory_review: published_advisory_review)
    assert_selector "[data-test-selector='advisory-review-sidebar-withdraw-button'][aria-disabled]", count: 1
  end

  test "makes withdraw button inactive if advisory has not been approved to withdraw" do
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_advisory_review_grouped_buttons").at_least_once.returns(true)
    published_advisory_review = create(:advisory_review, :curation_state_published)
    published_advisory_review.revisit!
    render_inline AdvisoryReviews::SidebarComponent.new(advisory_review: published_advisory_review)
    assert_selector "[data-test-selector='advisory-review-sidebar-withdraw-button'][aria-disabled]", count: 1
  end
end
