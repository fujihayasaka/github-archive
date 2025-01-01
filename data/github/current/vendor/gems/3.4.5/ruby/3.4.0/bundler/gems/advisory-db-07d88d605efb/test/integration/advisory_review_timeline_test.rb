# frozen_string_literal: true

require "test_helper"

class AdvisoryReviewTimelineTest < ActionDispatch::IntegrationTest
  def setup
    @user = create(:user)
    @advisory_review = create(:advisory_review, :open, {
      feed_entry_type: :cve_feed_entry,
      advisory_payload: generate_advisory_payload(severity: "moderate"),
    })
    @selector_root = "timeline-item-advisory-review"
    @expected_timeline_items = ["open"]
  end

  def generate_advisory_payload(severity:)
    advisory_payload ||= create(:advisory_payload, vulnerability_count: 1)
    advisory_payload.deep_dup.tap do |payload|
      payload["severity"] = severity
      payload["cvss_v3"] = ""
    end
  end

  def advisory_payload_params(severity:)
    generate_advisory_payload(severity: severity).deep_dup.tap do |payload|
      payload["withdrawn"] ||= nil
      payload["vulnerabilities"].each_value do |vulnerability_payload|
        vulnerability_payload["withdrawn"] ||= nil
      end
    end
  end

  def assert_rendered_timeline_items
    get timeline_advisory_review_path(@advisory_review),
      headers: { "X-Okta-Username" => @user.email }
    assert_response :ok

    # Assert the content of the fully populated timeline.
    count = @expected_timeline_items.size
    assert_select "[data-test-selector^=#{@selector_root}]", count: count do |items|
      # Assert the content of the fully populated timeline.
      @expected_timeline_items.each_with_index do |event, index|
        assert_equal "#{@selector_root}-#{event}", items[index]["data-test-selector"]
      end
    end
  end

  # Ensure that events don't happen too close together to be rolled up into a
  # single timeline event
  def ensure_no_timeline_rollups
    Timecop.travel(Time.now.utc + 1.second)
  end

  def add_expected_timeline_items(*events)
    @expected_timeline_items += events
    ensure_no_timeline_rollups
  end

  test "the advisory review timeline renders its important activity" do
    Timecop.freeze do
      # Get the timeline before all the interesting stuff happens!
      assert_rendered_timeline_items

      # Now we'll make a series of changes to the advisory review to produce an
      # interesting timeline that we can make new assertions on.

      # Close the review
      @advisory_review.close!
      @advisory_review.reload
      assert_equal "closed", @advisory_review.state
      add_expected_timeline_items "close"

      # Reopen the review
      @advisory_review.reopen!
      @advisory_review.reload
      assert_equal "open", @advisory_review.state
      add_expected_timeline_items "reopen"

      # Update the severity from "moderate" to "high"
      payload_params = advisory_payload_params(severity: "high")
      advisory_payload = AdvisoryPayload.new(data: payload_params)
      @advisory_review.update!(advisory_payload: advisory_payload.data)
      @advisory_review.reload
      assert_equal "high", @advisory_review.severity
      add_expected_timeline_items "update"

      # Assign the advisory review to a Curator
      @advisory_review.approvals.create!(user_id: @user.id)
      @advisory_review.reload
      assert_equal 1, @advisory_review.approvals.size
      add_expected_timeline_items "assign"

      # Approve the advisory review for publictaion
      @advisory_review.record_approval(@user.id)
      @advisory_review.approve_to_publish!
      @advisory_review.reload
      assert_equal "approved_to_publish", @advisory_review.state
      add_expected_timeline_items "approve"

      # Publish the advisory with second approval
      @advisory_review.record_approval(@user.id)
      Publisher.new(@advisory_review).publish
      @advisory_review.reload
      assert_equal "accepted", @advisory_review.state
      assert_equal "published_reviewed", @advisory_review.curation_state
      add_expected_timeline_items "approve", "publish"

      # Reopen the advisory review
      @advisory_review.revisit!
      @advisory_review.reload
      assert_equal "in_review", @advisory_review.state
      add_expected_timeline_items "reopen"

      # Update the severity from "high" to "critical"
      payload_params = advisory_payload_params(severity: "critical")
      advisory_payload = AdvisoryPayload.new(data: payload_params)
      @advisory_review.update!(advisory_payload: advisory_payload.data)
      @advisory_review.reload
      assert_equal "critical", @advisory_review.severity
      add_expected_timeline_items "update"

      # Update the published advisory with approval
      @advisory_review.record_approval(@user.id)
      Publisher.new(@advisory_review).publish
      @advisory_review.reload
      assert_equal "accepted", @advisory_review.state
      assert_equal "published_reviewed", @advisory_review.curation_state
      add_expected_timeline_items "approve", "publish"

      # Reopen the advisory review
      @advisory_review.revisit!
      @advisory_review.reload
      assert_equal "in_review", @advisory_review.state
      add_expected_timeline_items "reopen"

      # Update the severity from "critical" to "low"
      payload_params = advisory_payload_params(severity: "low")
      advisory_payload = AdvisoryPayload.new(data: payload_params)
      @advisory_review.update!(advisory_payload: advisory_payload.data)
      @advisory_review.reload
      assert_equal "low", @advisory_review.severity
      add_expected_timeline_items "update"

      # Revert the advisory review to reflect the published advisory
      @advisory_review.revert!
      @advisory_review.reload
      assert_equal "critical", @advisory_review.severity
      assert_equal "accepted", @advisory_review.state
      assert_equal "published_reviewed", @advisory_review.curation_state
      add_expected_timeline_items "revert"

      # Reopen the advisory review
      @advisory_review.revisit!
      @advisory_review.reload
      assert_equal "in_review", @advisory_review.state
      add_expected_timeline_items "reopen"

      # Revert the advisory review without any changes
      @advisory_review.revert!
      @advisory_review.reload
      assert_equal "accepted", @advisory_review.state
      assert_equal "published_reviewed", @advisory_review.curation_state
      add_expected_timeline_items "revert"

      # Reopen the advisory review
      @advisory_review.revisit!
      @advisory_review.reload
      assert_equal "in_review", @advisory_review.state
      add_expected_timeline_items "reopen"

      # Approve the advisory review for withdrawal
      @advisory_review.approvals.each do |approval|
        approval.update!(approved_at: nil)
      end
      @advisory_review.record_approval(@user.id)
      @advisory_review.approve_to_withdraw!
      @advisory_review.reload
      assert_equal "ready_to_withdraw", @advisory_review.curation_state
      add_expected_timeline_items "approve"

      # Withdraw the advisory with second approval
      @advisory_review.record_approval(@user.id)
      @advisory_review.withdraw!
      Publisher.new(@advisory_review).publish
      @advisory_review.reload
      assert_equal "withdrawn", @advisory_review.curation_state
      add_expected_timeline_items "approve", "withdraw"

      # All done! Now it's time to get the timeline again and see what we find.
      assert_rendered_timeline_items
    end
  end
end
