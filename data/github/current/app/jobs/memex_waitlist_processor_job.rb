# typed: true
# frozen_string_literal: true

# This job will process the waitlist for the hierarchy_and_roadmap feature slug on a schedule and convert all pending
# records into specific projects_tasklist waitlists, depending on what the user submitted
# at the time to PlanningTrackingSurveyResult (backed by GitHub.kv).
#
# This is a temporary job to manage multiple features associated with a single signup page, which we'd do differently
# given more time and co-ordination between teams.
#
class MemexWaitlistProcessorJob < ApplicationJob
  queue_as :memex_waitlist_processor

  retry_on_dirty_exit

  # run this work periodically so that we'll process new requests
  schedule interval: 1.hour, condition: -> { !GitHub.enterprise? }

  # ensure only one instance of this job is running at a time
  locked_by timeout: 1.hour, key: DEFAULT_LOCK_PROC

  TASKLIST_FEATURE_SLUG = "projects_tasklist"

  def perform
    return unless GitHub.flipper[:memex_waitlist_circuit_breaker].enabled?

    memberships = EarlyAccessMembership.hierarchy_and_roadmap_waitlist.where(feature_enabled: false)

    memberships.each do |membership|
      member_id = membership.member_id
      actor_id  = membership.actor_id
      survey_id = membership.survey_id

      results = PlanningTrackingSurveyResult.get_survey_results(membership)

      on_tasklist_waitlist = EarlyAccessMembership.exists?(feature_slug: TASKLIST_FEATURE_SLUG, member_id: member_id)

      if results[:tasklist_feature_requested] && !on_tasklist_waitlist
        with_write do
          EarlyAccessMembership.new(
            member_id: member_id,
            actor_id: actor_id,
            feature_slug: TASKLIST_FEATURE_SLUG,
            survey_id: survey_id,
          ).save
        end
      end

      with_write do
        membership.update(feature_enabled: true)

        GitHub.logger.info(
          "Successfully processed waitlist entry for hierarchy",
          {
            "code.namespace": "MemexWaitlistProcessorJob",
            "code.function": "perform",
            "gh.job.result": "success",
            "gh.membership.id": membership.id,
            "gh.membership.member.id": member_id,
            "gh.memex.tasklist_waitlist": on_tasklist_waitlist,
          }
        )

        PlanningTrackingSurveyResult.clear_survey_result(membership)
      end
    end
  end
end
