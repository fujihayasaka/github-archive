# frozen_string_literal: true

class PublishCurationDecisionToHydroJob < ApplicationJob
  queue_as :low

  def perform(type:, decision:, curator:, ghsa_id:, time_to_decision:, sources: [])
    result = AdvisoryDB.hydro_publisher.publish(
      {
        type: type,
        decision: decision,
        curator_login: curator,
        ghsa_id: ghsa_id,
        sources: sources,
        time_to_decision_seconds: time_to_decision.to_i,
      },
      schema: "advisory_db.v0.CurationDecision",
    )

    AdvisoryDB.send_hydro_publish_error_stat(self.class) unless result.success?

    result
  end
end
