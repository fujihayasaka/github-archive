# frozen_string_literal: true

class PublishCVEReviewToHydroJob < ApplicationJob
  queue_as :high

  def perform(cve_review_id:)
    cve_review = CVEReview.find(cve_review_id)
    result = AdvisoryDB.hydro_publisher.publish(
      cve_review.hydro_payload,
      schema: "advisory_db.v0.CVERequestResponse", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 },
    )

    AdvisoryDB.send_hydro_publish_error_stat(self.class) unless result.success?

    result
  end
end
