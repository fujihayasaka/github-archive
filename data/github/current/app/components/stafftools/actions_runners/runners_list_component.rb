# typed: true
# frozen_string_literal: true

module Stafftools
  class ActionsRunners::RunnersListComponent < ApplicationComponent

    # Component and UI largely copied over from Actions::RunnerListComponent, separate so that stafftools and user facing UI is separate

    def initialize(runners: [], business: nil, can_manage_runners: true, hosted_runner_group: nil, viewing_from_a_repository: false, viewing_from_runner_group: false, filter_query: nil)
      @runners = runners
      @business = business
      @hosted_runner_group = hosted_runner_group
      @viewing_from_a_repository = viewing_from_a_repository
      @viewing_from_runner_group = viewing_from_runner_group
      @filter_query = filter_query
    end

    def hosted_runner_group
      @hosted_runner_group
    end

    def hosted_job_count
      @hosted_runner_group&.runners&.count { |runner| runner.current_parallelism == 1 } || 0
    end

    def runner_status_color(runner)
      case runner.status
      when Actions::Runner::IDLE then :success
      when :Ready then :success
      when Actions::RunnerScaleSet::ONLINE then :success
      when Actions::Runner::ACTIVE then :attention
      when Actions::Runner::DISABLED, Actions::RunnerScaleSet::DISABLED then :attention
      when :Provisioning then :attention
      when :ShutdownBilling, :ShutdownSpammy, :ShutdownNetwork then :danger
      else :muted
      end
    end

    def runner_icon(runner)
      if runner.is_a?(Actions::LargerRunner)
        "mark-github"
      else
        :server
      end
    end

    # Custom hosted runners can be created at the org and enterprise level, but not at repo level.
    # From enterprise level they can be shared with orgs. From org level they can be shared with repos.
    # Self-hosted runners can be created at any level and shared.
    # Only runners created at the enterprise level and shared with orgs and repos are `inherited`. Org level runners shared with repos are not `inherited`.
    # This property is set in the backend and used when we create a custom hosted runner from a gRPC response. See `larger_runner.rb` and `runner.rb`

    def inherited_from_enterprise?(runner)
      runner.inherited?
    end

    def public_ip_state(runner)
      runner.is_public_ip_enabled ? "enabled" : "disabled"
    end
  end
end
