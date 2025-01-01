# frozen_string_literal: true

require "digest/md5"

class PublishAdvisoryToHydroJob < ApplicationJob
  queue_as :high

  # https://github.com/github/team-advisory-database/issues/4624
  retry_on ActiveJob::DeserializationError, wait: :polynomially_longer

  # The optional review_lab_ref keyword argument is never passed by any caller
  # in the code base. This argument is only meant to be passed from the console
  # when doing manual testing of advisory publication to review-lab.
  #
  # In production, only SubmitAdvisory messages with a blank review_lab_ref will
  # be consumed. In review-lab, only messages *with* a review_lab_ref will be
  # consumed, and _only_ if that review_lab_ref matches the GitHub.current_ref.
  # This allows us to consume messages from a review-lab environment but only
  # the review-lab instance we specify here.
  #
  # For example, from the console:
  #
  #   PublishAdvisoryToHydroJob.perform_later(advisory, review_lab_ref: "laserlemon/add-new-feature")
  #
  def perform(advisory, credits: [], review_lab_ref: "")
    advisory_version_id = advisory.versions.last.id

    json_serialized_payload = JSON.dump(advisory.hydro_payload)
    hydro_payload_hash = Digest::MD5.hexdigest(json_serialized_payload)
    ::GitHub::Telemetry::Logs.logger.info(
      "Right before we publish an advisory to hydro",
      "gh.advisory_inbox.publish_advisory_to_hydro.payload": json_serialized_payload,
      "gh.advisory_inbox.paper_trail_version_id": advisory_version_id,
      "gh.advisory_inbox.hydro_payload_hash": hydro_payload_hash,
    )

    result = AdvisoryDB.hydro_publisher.publish(
      {
        # This will be part of the advisory.hydro_payload method when we add credits to
        # advisory payloads (https://github.com/github/team-advisory-database/issues/2420), but
        # for now this at least lets us automatically credit advisory improvement contributors
        advisory: advisory.hydro_payload.merge({ credits: credits }),
        review_lab_ref: review_lab_ref,
        status: advisory.hydro_status,
        version_id: advisory_version_id,
        hydro_payload_hash: hydro_payload_hash, # this is technically going to be the hash before the merge above, but that's OK -- we are interested in changes before this merge.
      },
      schema: "advisory_db.v0.SubmitAdvisory", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 },
    )

    AdvisoryDB.send_hydro_publish_error_stat(self.class) unless result.success?

    result
  end
end
