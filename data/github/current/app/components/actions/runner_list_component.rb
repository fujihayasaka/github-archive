# typed: true
# frozen_string_literal: true

module Actions
  class RunnerListComponent < ApplicationComponent

    def initialize(runners: [], owner_settings: nil, can_manage_runners: true, hosted_runner_group: nil, viewing_from_a_repository: false, viewing_from_runner_group: false, filter_query: nil)
      @runners = runners
      @owner_settings = owner_settings
      @can_manage_runners = can_manage_runners
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

    def can_manage_runners?
      @can_manage_runners && @owner_settings.can_manage_runners?
    end

    def can_manage_runner?(runner)
      can_manage_runners? && @owner_settings.runner_scoped_to_view?(runner)
    end

    def can_delete_runner?(runner)
      if runner.is_a?(Actions::LargerRunner)
        return false if runner.is_in_deleting_state?
      end

      if runner.is_a?(Actions::RunnerScaleSet)
        return false
      end

      can_manage_runner?(runner)
    end

    def can_edit_runner?(runner)
      return false unless can_manage_runner?(runner)

      runner.is_a?(Actions::LargerRunner) && runner.is_in_editable_state?
    end

    def delete_path(runner)
      @owner_settings.delete_runner_path(id: runner.id, os: runner.os)
    end

    def details_path(runner)
      if runner.is_a?(Actions::LargerRunner)
        return @owner_settings.larger_runner_details_path(id: runner.id, viewing_from_runner_group: @viewing_from_runner_group)
      elsif runner.is_a?(Actions::RunnerScaleSet)
        return @owner_settings.runner_scale_set_details_path(id: runner.id)
      end
      @owner_settings.runner_details_path(id: runner.id)
    end

    def runner_group_path(runner)
      if @owner_settings&.settings_owner.is_a?(Organization) && inherited_from_enterprise?(runner) && !runner.is_a?(Actions::LargerRunner) && !runner.is_a?(Actions::RunnerScaleSet)
        group_id = runner.scoped_runner_group_id
      else
        group_id = runner.runner_group_id
      end
      @owner_settings.update_runner_group_path(id: group_id)
    end

    def can_navigate_to_runner?(runner)
      if @owner_settings&.settings_owner.is_a?(Business)
        # Only allow enterprise owners to navigate to enterprise runners.
        return @owner_settings&.settings_owner&.owner?(current_user)
      end
      # Only allow a user to navigate to runners created at the same level as the view (i.e. only org-level runners from org view, only repo-level runners from repo view)
      @owner_settings.runner_scoped_to_view?(runner)
    end

    def can_search_with_labels?
      !viewing_from_a_repository?
    end

    def viewing_from_a_repository?
      @viewing_from_a_repository
    end

    def filter_value(key, value)
      array = []
      if value.present?
        array.push([key, value])
      end
      if @filter_query.present?
        array.push(@filter_query)
      end
      Search::ParsedQuery.stringify(array)
    end

    # Custom hosted runners can be created at the org and enterprise level, but not at repo level.
    # From enterprise level they can be shared with orgs. From org level they can be shared with repos.
    # Self-hosted runners can be created at any level and shared.
    # Only runners created at the enterprise level and shared with orgs and repos are `inherited`. Org level runners shared with repos are not `inherited`.
    # This property is set in the backend and used when we create a custom hosted runner from a gRPC response. See `larger_runner.rb` and `runner.rb`

    def inherited_from_enterprise?(runner)
      runner.inherited?
    end

    def inherited_from_org?(runner)
      viewing_from_a_repository? && !inherited_from_enterprise?(runner) && !@owner_settings.runner_scoped_to_view?(runner)
    end

    def public_ip_state(runner)
      runner.is_public_ip_enabled ? "enabled" : "disabled"
    end

    def runner_action_needed?(runner)
      return false unless runner.is_a?(Actions::LargerRunner)
      runner.error_code.present?
    end
  end
end
