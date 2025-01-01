# frozen_string_literal: true

require "test_helper"

class CampaignTest < ActiveSupport::TestCase
  test "can by scoped by status" do
    active_campaign = create(:campaign)
    complete_campaign = create(:campaign, :complete)

    assert_includes Campaign.by_status("active"), active_campaign
    refute_includes Campaign.by_status("active"), complete_campaign
    assert_includes Campaign.by_status("complete"), complete_campaign
    refute_includes Campaign.by_status("complete"), active_campaign

    # Only some reviews are complete means the campaign is still active
    active_campaign.advisory_reviews.first.accept!
    active_campaign.advisory_reviews.last.reject!
    assert_includes Campaign.by_status("active"), active_campaign
    refute_includes Campaign.by_status("complete"), active_campaign
  end

  test "requires a name" do
    create(:advisory_review)

    assert_raises(ActiveRecord::RecordInvalid) do
      Campaign.create!(name: "", advisory_reviews: AdvisoryReview.all)
    end
  end

  test "requires advisory reviews" do
    assert_raises(ActiveRecord::RecordInvalid) do
      Campaign.create!(name: "JPMC", advisory_reviews: AdvisoryReview.none)
    end
  end

  test "#reviews_from_ids accepts CVE & GHSA IDs" do
    cve_advisory_review = create(:advisory_review)
    ghsa_advisory_review = create(:advisory_review)
    campaign = Campaign.new(name: "NuGet Backfill")
    campaign.reviews_from_ids([cve_advisory_review.cve_id, ghsa_advisory_review.ghsa_id])

    assert_includes campaign.advisory_reviews, cve_advisory_review
    assert_includes campaign.advisory_reviews, ghsa_advisory_review
  end

  test "#reviews_from_ids raises an error for ids that it cannot add" do
    advisory_review = create(:advisory_review)
    assert_raises(ArgumentError, "CVE-0000-0000") do
      Campaign.new(name: "JPMC").reviews_from_ids([advisory_review.cve_id, "CVE-0000-0000"])
    end
  end

  test "unicode works in campaign name" do
    # This test fails if DB connection is not set to connect with utf8mb4 collation with:
    # ActiveRecord::StatementInvalid: Mysql2::Error: Illegal mix of collations (utf8mb4_general_ci,IMPLICIT) and (utf8mb3_general_ci,COERCIBLE) for operation '='
    advisory_review = create(:advisory_review)
    c = Campaign.new(name: "Sample campaign 🫣")
    c.reviews_from_ids([advisory_review.cve_id])
    c.save!
    c.reload

    assert_equal "Sample campaign 🫣", c.name
  end
end
