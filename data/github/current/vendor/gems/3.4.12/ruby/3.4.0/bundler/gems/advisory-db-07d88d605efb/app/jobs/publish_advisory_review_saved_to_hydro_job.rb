# frozen_string_literal: true

class PublishAdvisoryReviewSavedToHydroJob < ApplicationJob
  queue_as :low

  def perform(advisory_review_hydro_payload, changed_attributes:, old_delta:, new_delta:, saved_by:)
    result = AdvisoryDB.hydro_publisher.publish(
      {
        advisory_review: advisory_review_hydro_payload,
        changed_attributes: changed_attributes,
        old_delta: old_delta,
        new_delta: new_delta,
        saved_by: saved_by,
      },
      schema: "advisory_db.v0.AdvisoryReviewSaved",
    )

    AdvisoryDB.send_hydro_publish_error_stat(self.class) unless result.success?

    result
  end
end
