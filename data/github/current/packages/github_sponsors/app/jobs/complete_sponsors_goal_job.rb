# typed: true
# frozen_string_literal: true

class CompleteSponsorsGoalJob < ApplicationJob
  retry_on_dirty_exit
  queue_as :complete_sponsors_goal

  locked_by timeout: 1.hour, key: ->(job) { job.arguments[0].id }

  def perform(goal)
    return unless GitHub.sponsors_enabled?
    return unless goal.can_complete?

    SponsorsGoal.throttle_writes_with_retry { goal.complete! }

    return if opted_out_of_goal_email?(goal)

    SponsorsPrimerMailer.goal_completed(goal: goal).deliver_later
  end

  def opted_out_of_goal_email?(goal)
    sponsorable = goal.sponsorable

    listing = sponsorable.sponsors_listing
    email_settings = listing.email_opt_outs
    email_settings.opted_out_of_all? || email_settings.opted_out_of_goal_completed?
  end
end
