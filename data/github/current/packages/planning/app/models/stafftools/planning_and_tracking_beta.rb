# typed: true
# frozen_string_literal: true

module Stafftools
  class PlanningAndTrackingBeta
    attr_reader :feature_slug, :feature_name, :waitlist, :onboard_job

    def initialize
      @feature_slug = "plan_and_track_v2"
      @feature_name = "Plan and Track 2.0 Beta"
      @waitlist = EarlyAccessMembership.plan_and_track_v2_waitlist
      @onboard_job = ::PlanningBetaOnboardMemberJob
    end
  end
end
