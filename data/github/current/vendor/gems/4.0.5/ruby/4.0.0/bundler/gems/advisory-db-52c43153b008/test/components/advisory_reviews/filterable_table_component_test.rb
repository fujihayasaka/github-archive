# frozen_string_literal: true

require "test_helper"

class AdvisoryReviewsFilterableTableComponentTest < ViewComponent::TestCase
  test "lists default advisory reviews" do
    component = AdvisoryReviews::FilterableTableComponent.new(sort: nil, sort_by: nil, state: nil, curator: nil, source: nil, ecosystem: nil, page: nil, query: nil, label_ids: nil, severity: nil)
    assert_equal 0, component.advisory_reviews.length

    # pending reviews to be rendered
    open_review_1 = create(:advisory_review, :open)
    open_review_2 = create(:advisory_review, :curation_state_open)
    # reviews not to be rendered
    create(:advisory_review, :curation_state_closed)
    create(:advisory_review, :curation_state_published)
    create(:advisory_review, :curation_state_withdrawn)
    create(:campaign, review_count: 5)

    component = AdvisoryReviews::FilterableTableComponent.new(sort: nil, sort_by: nil, state: nil, curator: nil, source: nil, ecosystem: nil, page: nil, query: nil, label_ids: nil, severity: nil)

    assert_equal 2, component.advisory_reviews.length
    assert_includes component.advisory_reviews, open_review_1
    assert_includes component.advisory_reviews, open_review_2
  end

  test "sorts advisory reviews by date" do
    create(:advisory_review, :curation_state_open, review_requested_at: 2.days.ago, cve_id: "CVE-2021-0001")
    create(:advisory_review, :curation_state_open, review_requested_at: 1.day.ago, cve_id: "CVE-2021-0002")

    component = AdvisoryReviews::FilterableTableComponent.new(sort: nil, sort_by: nil, state: nil, curator: nil, source: nil, ecosystem: nil, page: nil, query: nil, label_ids: nil, severity: nil)
    # default when not provided is "date asc"
    assert_equal "CVE-2021-0001", component.advisory_reviews.first.cve_id
    assert_equal "CVE-2021-0002", component.advisory_reviews.last.cve_id

    component = AdvisoryReviews::FilterableTableComponent.new(sort: "desc", sort_by: "date", state: nil, curator: nil, source: nil, ecosystem: nil, page: nil, query: nil, label_ids: nil, severity: nil)
    assert_equal "CVE-2021-0002", component.advisory_reviews.first.cve_id
    assert_equal "CVE-2021-0001", component.advisory_reviews.last.cve_id
  end

  test "sorts advisory reviews by severity" do
    create(:advisory_review, advisory_payload: build(:advisory_payload, severity: "low", cvss_v3: ""))
    create(:advisory_review, advisory_payload: build(:advisory_payload, severity: "moderate", cvss_v3: ""))
    create(:advisory_review, advisory_payload: build(:advisory_payload, severity: "high", cvss_v3: ""))
    create(:advisory_review, advisory_payload: build(:advisory_payload, severity: "critical", cvss_v3: ""))

    component = AdvisoryReviews::FilterableTableComponent.new(sort: nil, sort_by: "severity", state: nil, curator: nil, source: nil, ecosystem: nil, page: nil, query: nil, label_ids: nil, severity: nil)
    # default when not provided is "asc"
    assert_equal "critical", component.advisory_reviews[0].severity
    assert_equal "high", component.advisory_reviews[1].severity
    assert_equal "moderate", component.advisory_reviews[2].severity
    assert_equal "low", component.advisory_reviews[3].severity

    component = AdvisoryReviews::FilterableTableComponent.new(sort: "desc", sort_by: "severity", state: nil, curator: nil, source: nil, ecosystem: nil, page: nil, query: nil, label_ids: nil, severity: nil)
    assert_equal "low", component.advisory_reviews[0].severity
    assert_equal "moderate", component.advisory_reviews[1].severity
    assert_equal "high", component.advisory_reviews[2].severity
    assert_equal "critical", component.advisory_reviews[3].severity
  end

  test "filters advisory reviews" do
    create(:advisory_review, :curation_state_open,   feed_entry_type: :repository_advisory_feed_entry)
    create(:advisory_review, :curation_state_open,   feed_entry_type: :repository_advisory_feed_entry)
    create(:advisory_review, :curation_state_open,   feed_entry_type: :cve_feed_entry)
    create(:advisory_review, :curation_state_closed, feed_entry_type: :repository_advisory_feed_entry)
    create(:advisory_review, :curation_state_closed, feed_entry_type: :cve_feed_entry)
    create(:advisory_review, :curation_state_closed, feed_entry_type: :cve_feed_entry)
    create(:advisory_review, :curation_state_open,   feed_entry_type: :cve_feed_entry, default_ecosystem: "npm")
    create(:advisory_review, :curation_state_open,   feed_entry_type: :cve_feed_entry, default_ecosystem: "npm")
    create(:advisory_review, :curation_state_open,   feed_entry_type: :cve_feed_entry, default_ecosystem: "pip")
    create(:advisory_review, :curation_state_open,   feed_entry_type: :repository_advisory_feed_entry, default_ecosystem: "npm")
    assigned_advisory_review = create(:advisory_review, :curation_state_open, assign_curator: true)
    include_label = create(:label)
    exclude_label = create(:label)
    include_label.advisory_reviews = AdvisoryReview.first(5)
    exclude_label.advisory_reviews = AdvisoryReview.first(2)

    component = AdvisoryReviews::FilterableTableComponent.new(sort: nil, sort_by: nil, state: nil, curator: nil, source: "repository_advisories", ecosystem: nil, page: nil, query: nil, label_ids: nil, severity: nil)
    assert_equal 3, component.advisory_reviews.length

    component = AdvisoryReviews::FilterableTableComponent.new(sort: nil, sort_by: nil, state: "closed", curator: nil, source: nil, ecosystem: nil, page: nil, query: nil, label_ids: nil, severity: nil)
    assert_equal 3, component.advisory_reviews.length

    component = AdvisoryReviews::FilterableTableComponent.new(sort: nil, sort_by: nil, state: "closed", curator: nil, source: "repository_advisories", ecosystem: nil, page: nil, query: nil, label_ids: nil, severity: nil)
    assert_equal 1, component.advisory_reviews.length

    component = AdvisoryReviews::FilterableTableComponent.new(sort: nil, sort_by: nil, state: nil, curator: nil, source: nil, ecosystem: "npm", page: nil, query: nil, label_ids: nil, severity: nil)
    assert_equal 3, component.advisory_reviews.length

    component = AdvisoryReviews::FilterableTableComponent.new(sort: nil, sort_by: nil, state: nil, curator: nil, source: "repository_advisories", ecosystem: "npm", page: nil, query: nil, label_ids: nil, severity: nil)
    assert_equal 1, component.advisory_reviews.length

    component = AdvisoryReviews::FilterableTableComponent.new(sort: nil, sort_by: nil, state: nil, curator: assigned_advisory_review.approvals.first.user.login, source: nil, ecosystem: nil, page: nil, query: nil, label_ids: nil, severity: nil)
    assert_equal 1, component.advisory_reviews.length

    component = AdvisoryReviews::FilterableTableComponent.new(sort: nil, sort_by: nil, state: nil, curator: nil, source: nil, ecosystem: nil, page: nil, query: nil, label_ids: "#{include_label.id},-#{exclude_label.id}", severity: nil)
    assert_equal 3, component.advisory_reviews.length
  end

  test "paginates advisory reviews" do
    create_list(:advisory_review, 35, :curation_state_open)

    component = AdvisoryReviews::FilterableTableComponent.new(sort: nil, sort_by: nil, state: nil, curator: nil, source: nil, ecosystem: nil, page: nil, query: nil, label_ids: nil, severity: nil)
    assert_equal 30, component.advisory_reviews.length

    component = AdvisoryReviews::FilterableTableComponent.new(sort: nil, sort_by: nil, state: nil, curator: nil, source: nil, ecosystem: nil, page: 2, query: nil, label_ids: nil, severity: nil)
    assert_equal 5, component.advisory_reviews.length
  end

  test "searches advisory reviews" do
    review_1 = create(:advisory_review, :curation_state_open, cve_id: "CVE-1234-1232")
    review_2 = create(:advisory_review, :curation_state_open, cve_id: "CVE-4321-1232")
    create(:advisory_review, :curation_state_open, cve_id: "CVE-1234-1212")

    component = AdvisoryReviews::FilterableTableComponent.new(sort: nil, sort_by: nil, state: nil, curator: nil, source: nil, ecosystem: nil, page: nil, query: "CVE-1234-12", label_ids: nil, severity: nil)
    assert_equal 2, component.advisory_reviews.length

    component = AdvisoryReviews::FilterableTableComponent.new(sort: nil, sort_by: nil, state: nil, curator: nil, source: nil, ecosystem: nil, page: nil, query: "CVE-1234-1232+cve-4321", label_ids: nil, severity: nil)
    assert_equal 2, component.advisory_reviews.length

    component = AdvisoryReviews::FilterableTableComponent.new(sort: nil, sort_by: nil, state: nil, curator: nil, source: nil, ecosystem: nil, page: nil, query: review_1.ghsa_id, label_ids: nil, severity: nil)
    assert_equal 1, component.advisory_reviews.length

    component = AdvisoryReviews::FilterableTableComponent.new(sort: nil, sort_by: nil, state: nil, curator: nil, source: nil, ecosystem: nil, page: nil, query: "#{review_1.ghsa_id}+#{review_2.ghsa_id[0..12]}", label_ids: nil, severity: nil)
    assert_equal 2, component.advisory_reviews.length

    component = AdvisoryReviews::FilterableTableComponent.new(sort: nil, sort_by: nil, state: nil, curator: nil, source: nil, ecosystem: nil, page: nil, query: "cve-1234-1232+#{review_2.ghsa_id[0..12]}", label_ids: nil, severity: nil)
    assert_equal 2, component.advisory_reviews.length
  end

  test "sorts advisory reviews in a campaign" do
    campaign = create(:campaign, review_count: 2)
    review_1 = campaign.advisory_reviews.first
    review_2 = campaign.advisory_reviews.last
    review_1.cve_id = "CVE-2022-0001"
    review_2.cve_id = "CVE-2022-0002"
    review_1.review_requested_at = 2.days.ago
    review_2.review_requested_at = 1.day.ago
    review_1.save
    review_2.save

    component = AdvisoryReviews::FilterableTableComponent.new(sort: nil, sort_by: nil, state: nil, curator: nil, source: nil, ecosystem: nil, page: nil, query: nil, campaign: campaign, label_ids: nil, severity: nil)
    assert_equal "CVE-2022-0001", component.advisory_reviews.first.cve_id
    assert_equal "CVE-2022-0002", component.advisory_reviews.last.cve_id

    component = AdvisoryReviews::FilterableTableComponent.new(sort: "desc", sort_by: nil, state: nil, curator: nil, source: nil, ecosystem: nil, page: nil, query: nil, campaign: campaign, label_ids: nil, severity: nil)
    assert_equal "CVE-2022-0002", component.advisory_reviews.first.cve_id
    assert_equal "CVE-2022-0001", component.advisory_reviews.last.cve_id
  end

  test "filters advisory reviews by state in campaign" do
    campaign = create(:campaign, review_count: 3)
    campaign.advisory_reviews[1].update(state: "closed")
    campaign.advisory_reviews[2].update(state: "closed")

    component = AdvisoryReviews::FilterableTableComponent.new(sort: nil, sort_by: nil, state: "closed", curator: nil, source: nil, ecosystem: nil, page: nil, query: nil, campaign: campaign, label_ids: nil, severity: nil)
    assert_equal 2, component.advisory_reviews.length
  end

  test "filters advisory reviews by ecosystem in campaign" do
    advisory_review = create(:advisory_review, :curation_state_open, default_ecosystem: "npm")
    advisory_review_2 = create(:advisory_review, :curation_state_open, default_ecosystem: "pip")
    campaign = create(:campaign, advisory_reviews: [advisory_review, advisory_review_2])
    component = AdvisoryReviews::FilterableTableComponent.new(sort: nil, sort_by: nil, state: nil, curator: nil, source: nil, ecosystem: "npm", page: nil, query: nil, campaign: campaign, label_ids: nil, severity: nil)
    assert_equal 1, component.advisory_reviews.length
  end

  test "filters advisory reviews by feed entry type in campaign" do
    advisory_review = create(:advisory_review, :curation_state_open, feed_entry_type: :repository_advisory_feed_entry)
    advisory_review_2 = create(:advisory_review, :curation_state_open, feed_entry_type: :cve_feed_entry)
    campaign = create(:campaign, advisory_reviews: [advisory_review, advisory_review_2])
    component = AdvisoryReviews::FilterableTableComponent.new(sort: nil, sort_by: nil, state: nil, curator: nil, source: "repository_advisories", ecosystem: nil, page: nil, query: nil, campaign: campaign, label_ids: nil, severity: nil)
    assert_equal 1, component.advisory_reviews.length
  end

  test "filters advisory reviews by assigned curator in campaign" do
    advisory_review = create(:advisory_review, :curation_state_open, assign_curator: true)
    advisory_review_2 = create(:advisory_review, :curation_state_open)
    campaign = create(:campaign, advisory_reviews: [advisory_review, advisory_review_2])
    component = AdvisoryReviews::FilterableTableComponent.new(sort: nil, sort_by: nil, state: nil, curator: campaign.advisory_reviews[0].approvals.first.user.login, source: nil, ecosystem: nil, page: nil, query: nil, campaign: campaign, label_ids: nil, severity: nil)
    assert_equal 1, component.advisory_reviews.length
  end

  test "filters advisory reviews by labels in campaign" do
    campaign = create(:campaign, review_count: 10)
    include_label = create(:label)
    exclude_label = create(:label)
    include_label.advisory_reviews = campaign.advisory_reviews.first(5)
    exclude_label.advisory_reviews = campaign.advisory_reviews.first(2)

    component = AdvisoryReviews::FilterableTableComponent.new(sort: nil, sort_by: nil, state: nil, curator: nil, source: nil, ecosystem: nil, page: nil, query: nil, label_ids: "#{include_label.id},-#{exclude_label.id}", severity: nil, campaign: campaign)
    assert_equal 3, component.advisory_reviews.length
  end

  test "filters advisory reviews by severity" do
    create(:advisory_review, advisory_payload: build(:advisory_payload, severity: "low"))
    create(:advisory_review, advisory_payload: build(:advisory_payload, severity: "moderate"))
    create(:advisory_review, advisory_payload: build(:advisory_payload, severity: "high"))
    create(:advisory_review, advisory_payload: build(:advisory_payload, severity: "critical"))
    severity_filter = "low"
    component = AdvisoryReviews::FilterableTableComponent.new(sort: nil, sort_by: nil, state: nil, curator: nil, source: nil, ecosystem: nil, page: nil, query: nil, campaign: nil, label_ids: nil, severity: severity_filter)
    assert_equal 1, component.advisory_reviews.length
    assert_equal severity_filter, component.advisory_reviews.first.severity
  end

  test "filters advisory reviews by campaign review state" do
    campaign = create(:campaign, review_count: 3)
    campaign.advisory_reviews.first.record_curation_decision(type: "advisory_review", decision: "close", curator: "monalisa")

    component = AdvisoryReviews::FilterableTableComponent.new(sort: nil, sort_by: nil, state: nil, curator: nil, source: nil, ecosystem: nil, page: nil, query: nil, campaign: campaign, campaign_review_state: nil, label_ids: nil, severity: nil)
    assert_equal 3, component.advisory_reviews.length

    component = AdvisoryReviews::FilterableTableComponent.new(sort: nil, sort_by: nil, state: nil, curator: nil, source: nil, ecosystem: nil, page: nil, query: nil, campaign: campaign, campaign_review_state: "pending", label_ids: nil, severity: nil)
    assert_equal 2, component.advisory_reviews.length

    component = AdvisoryReviews::FilterableTableComponent.new(sort: nil, sort_by: nil, state: nil, curator: nil, source: nil, ecosystem: nil, page: nil, query: nil, campaign: campaign, campaign_review_state: "complete", label_ids: nil, severity: nil)
    assert_equal 1, component.advisory_reviews.length
  end

  test "paginates advisory reviews in campaign" do
    campaign = create(:campaign, review_count: 32)

    component = AdvisoryReviews::FilterableTableComponent.new(sort: nil, sort_by: nil, state: nil, curator: nil, source: nil, ecosystem: nil, page: nil, query: nil, campaign: campaign, label_ids: nil, severity: nil)
    assert_equal 30, component.advisory_reviews.length

    component = AdvisoryReviews::FilterableTableComponent.new(sort: nil, sort_by: nil, state: nil, curator: nil, source: nil, ecosystem: nil, page: 2, query: nil, campaign: campaign, label_ids: nil, severity: nil)
    assert_equal 2, component.advisory_reviews.length
  end

  test "searches advisory reviews in campaign" do
    campaign = create(:campaign, review_count: 2)
    review_1 = campaign.advisory_reviews.first
    review_1.cve_id = "CVE-0000-0000"
    review_2 = campaign.advisory_reviews.second
    review_2.cve_id = "CVE-1111-1111"
    review_1.save
    review_2.save

    component = AdvisoryReviews::FilterableTableComponent.new(sort: nil, sort_by: nil, state: nil, curator: nil, source: nil, ecosystem: nil, page: nil, query: "CVE-0000-00", campaign: campaign, label_ids: nil, severity: nil)
    assert_equal 1, component.advisory_reviews.length

    component = AdvisoryReviews::FilterableTableComponent.new(sort: nil, sort_by: nil, state: nil, curator: nil, source: nil, ecosystem: nil, page: nil, query: "CVE-0000-0000+cve-1111", campaign: campaign, label_ids: nil, severity: nil)
    assert_equal 2, component.advisory_reviews.length

    component = AdvisoryReviews::FilterableTableComponent.new(sort: nil, sort_by: nil, state: nil, curator: nil, source: nil, ecosystem: nil, page: nil, query: review_1.ghsa_id, campaign: campaign, label_ids: nil, severity: nil)
    assert_equal 1, component.advisory_reviews.length

    component = AdvisoryReviews::FilterableTableComponent.new(sort: nil, sort_by: nil, state: nil, curator: nil, source: nil, ecosystem: nil, page: nil, query: "#{review_1.ghsa_id}+#{review_2.ghsa_id[0..12]}", campaign: campaign, label_ids: nil, severity: nil)
    assert_equal 2, component.advisory_reviews.length

    component = AdvisoryReviews::FilterableTableComponent.new(sort: nil, sort_by: nil, state: nil, curator: nil, source: nil, ecosystem: nil, page: nil, query: "cve-0000-0000+#{review_2.ghsa_id[0..12]}", campaign: campaign, label_ids: nil, severity: nil)
    assert_equal 2, component.advisory_reviews.length
  end
end
