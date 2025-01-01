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
      return :attention if runner_action_needed?(runner)
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

    def runner_status_text(runner)
      return "Shutdown" if runner.status&.match("^Shutdown")
      return "Action needed" if runner_action_needed?(runner)
      runner.status.capitalize
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

    def runner_action_needed?(runner)
      return false unless runner.is_a?(Actions::LargerRunner)
      runner.error_code.present?
    end

    def runner_support_dashboard_url(runner)
      return nil unless runner.is_a?(Actions::LargerRunner)
      return nil unless owner_host_id
      dashboard_id = "28cccc39-3380-41e9-97d8-e978d4d3c012"
      dashboard_page_id = "95e01f39-09ea-4b9a-bb32-b7f9bba210bd"
      params = {
        "p-Kusto Cluster": "githubactions.eastus2",
        "p-_startTime": "24hours",
        "p-_endTime": "now",
        "p-_hostId": owner_host_id,
        "p-_poolId": runner.id,
      }
      "https://dataexplorer.azure.com/dashboards/#{dashboard_id}?#{params.to_query}##{dashboard_page_id}"
    end

    memoize def owner_host_id
      begin
        return nil unless @business.is_larger_runners_onboarded?

        resp = Launch::Twirp::larger_runners_client.get_tenant_info(@business)
        return nil unless resp.call_succeeded?
        return nil unless resp.value
        resp.value.tenant_id
      end
    end
  end
end
