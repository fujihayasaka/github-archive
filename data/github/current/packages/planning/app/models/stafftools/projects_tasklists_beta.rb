# typed: true
# frozen_string_literal: true

module Stafftools
  class ProjectsTasklistsBeta
    attr_reader :feature_slug, :feature_name, :waitlist, :onboard_job

    def initialize
      @feature_slug = "hierarchy_tasklist"
      @feature_name = "Projects Tasklists Beta"
      @waitlist = EarlyAccessMembership.projects_tasklist_waitlist
      @onboard_job = ::Projects::TasklistBetaOnboardMemberJob
    end
  end
end
