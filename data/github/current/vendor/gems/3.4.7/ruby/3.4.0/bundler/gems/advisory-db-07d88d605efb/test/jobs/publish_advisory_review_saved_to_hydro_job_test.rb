# frozen_string_literal: true

require "test_helper"

class PublishAdvisoryReviewSavedToHydroJobTest < ActiveJob::TestCase
  test "publishes an AdvisoryReviewSaved message to Hydro with old and new state" do
    advisory_review = nil
    Timecop.freeze(2023, 1, 23) do
      advisory_review = create :advisory_review
      hydro_messages.clear

      assert_changes -> { hydro_messages.count }, from: 0, to: 1 do
        my_payload = advisory_review.advisory_payload.clone
        my_payload["description"] = "Some sample new description"
        advisory_review.advisory_payload = my_payload
        advisory_review.save!
        perform_enqueued_jobs(only: [PublishAdvisoryReviewSavedToHydroJob]) do
          advisory_review.notify_user_saved_event(User.new(login: "testuser"))
        end
      end
    end

    message = hydro_messages.last
    assert_equal ["advisory_payload"], message[:changed_attributes]
    assert_equal "testuser", message[:saved_by]
    refute_nil message[:old_delta][:advisory_payload]
    refute_nil message[:new_delta][:advisory_payload]
    refute_equal message[:old_delta][:advisory_payload], message[:new_delta][:advisory_payload]
    refute_equal "Some sample new description", message[:old_delta][:advisory_payload][:description]
    assert_equal "Some sample new description", message[:new_delta][:advisory_payload][:description]

    # Point test a few parts of our advisory_review. We can't test translated output because there is more formatting done by the hydro receiver.
    assert_equal advisory_review.id, message[:advisory_review][:id]
    assert_equal advisory_review.state, message[:advisory_review][:state]
    assert_equal advisory_review.advisory_payload["description"], message[:advisory_review][:advisory_payload][:description]
  end

  test "increments dogstat if result returns an error" do
    expect_hydro_publish_error_stat_for(PublishAdvisoryReviewSavedToHydroJob)

    advisory_review = create :advisory_review

    my_payload = advisory_review.advisory_payload.clone
    my_payload["description"] = "Some sample new description"
    advisory_review.advisory_payload = my_payload
    advisory_review.save!

    perform_enqueued_jobs(only: [PublishAdvisoryReviewSavedToHydroJob]) do
      advisory_review.notify_user_saved_event(User.new(login: "testuser"))
    end
  end
end
