# frozen_string_literal: true

require "test_helper"

class CampaignsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    user = create(:user)
    get "/campaigns",
      headers: { "X-Okta-Username" => user.email }

    assert_response :ok
  end

  test "show displays a list of advisory reviews associated with campaign" do
    user = create(:user)
    campaign = create(:campaign)
    get "/campaigns/#{campaign.id}",
      headers: { "X-Okta-Username" => user.email }
    assert_response :ok
    assert_select "[data-test-selector=progress-bar]"
    assert_select "[data-test-selector=advisory-review-row]", count: 5
  end

  test "new displays an empty campign form" do
    user = create(:user)

    get "/campaigns/new", headers: { "X-Okta-Username" => user.email }

    assert_response :ok
    assert_select "[data-test-selector=campaign-title]", text: "Create a review campaign"
    assert_select "[data-test-selector=campaign-form]", count: 1
    assert_select "[data-test-selector=campaign-submit-button]", count: 1
  end

  test "create successfully" do
    user = create(:user)
    create(:advisory_review) # excluded
    cve_advisory_review = create(:advisory_review)
    ghsa_advisory_review = create(:advisory_review)

    post campaigns_path,
      headers: { "X-Okta-Username" => user.email },
      params: {
        campaign: {
          name: "JPMC",
        },
        cve_or_ghsa_ids: "#{cve_advisory_review.cve_id}\n#{ghsa_advisory_review.ghsa_id}",
      }

    assert_response :found
    assert_includes "Review campaign JPMC was created successfully!", flash[:notice]
    campaign = Campaign.last
    assert_equal "JPMC", campaign.name
    assert_equal [cve_advisory_review, ghsa_advisory_review], campaign.advisory_reviews
  end

  test "create accepts multiple seaprators in id param" do
    user = create(:user)
    advisory_reviews = create_list(:advisory_review, 5)

    post campaigns_path,
      headers: { "X-Okta-Username" => user.email },
      params: {
        campaign: {
          name: "NuGet Backfill",
        },
        cve_or_ghsa_ids: "#{advisory_reviews[0].cve_id}\n#{advisory_reviews[1].ghsa_id} #{advisory_reviews[2].ghsa_id},#{advisory_reviews[3].cve_id}, #{advisory_reviews[4].ghsa_id}",
      }

    assert_response :found
    assert_includes "Review campaign NuGet Backfill was created successfully!", flash[:notice]
    campaign = Campaign.last
    assert_equal advisory_reviews, campaign.advisory_reviews
  end

  test "create reports when id param doesn't match actual reviews" do
    user = create(:user)
    advisory_review = create(:advisory_review)

    post campaigns_path,
      headers: { "X-Okta-Username" => user.email },
      params: {
        campaign: {
          name: "Re-review these",
        },
        cve_or_ghsa_ids: "CVE-0000-0000 #{advisory_review.cve_id}",
      }

    assert_response :unprocessable_entity
    assert_includes "Review campaign Re-review these could not be created because it contains the following unknown ids: CVE-0000-0000!", flash[:alert]
  end

  test "create opens non-approved reviews for re-review" do
    user = create(:user)
    reviews = [
      create(:advisory_review, :open),
      create(:advisory_review, :curation_state_open),
      create(:advisory_review, :curation_state_ready_to_publish),
      create(:advisory_review, :curation_state_published),
      create(:advisory_review, :curation_state_closed),
      create(:advisory_review, :closed),
    ]

    post campaigns_path,
      headers: { "X-Okta-Username" => user.email },
      params: {
        campaign: {
          name: "JPMC",
        },
        cve_or_ghsa_ids: reviews.map(&:ghsa_id).join(", "),
      }

    assert_response :found
    assert_includes "Review campaign JPMC was created successfully!", flash[:notice]
    assert(reviews.all? { |review| review.reload.in_review? || review.approved_to_publish? })
  end

  test "destroy deletes the campaign and the review associations" do
    user = create(:user)
    campaign = create(:campaign, name: "NuGet Backfill", review_count: 3)
    id = campaign.id

    assert Campaign.find(id)
    assert_equal 3, AdvisoryReviewsCampaign.where(campaign_id: id).count

    delete "/campaigns/#{id}",
      headers: { "X-Okta-Username" => user.email }

    assert_response :found
    assert_includes "Review campaign NuGet Backfill was deleted successfully!", flash[:notice]
    assert_raises(ActiveRecord::RecordNotFound) do
      Campaign.find(id)
    end
    assert_equal 0, AdvisoryReviewsCampaign.where(campaign_id: id).count
  end
end
