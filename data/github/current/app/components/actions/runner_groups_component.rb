# typed: true
# frozen_string_literal: true

module Actions
  class RunnerGroupsComponent < ApplicationComponent
    renders_one :description

    include NetworkConfigurationsHelper

    def initialize(
      owner:,
      owner_settings:,
      runner_groups: [],
      restricted_plan: false,
      has_business: false,
      viewer: owner,
      can_create_runners: true,
      can_create_groups: true,
      can_update_groups: true,
      can_manage_runners: true,
      groups_inheritance: "direct", # for test selector
      disabled_runner_group_ids: [],
      disabled_owner_runner_group_ids: []
    )
      @owner = owner
      @viewer = viewer
      @owner_settings = owner_settings
      @runner_groups = runner_groups.sort
      @restricted_plan = restricted_plan
      @has_business = has_business

      @can_create_runners = can_create_runners
      @can_create_groups = can_create_groups
      @can_update_groups = can_update_groups
      @can_manage_runners = can_manage_runners

      # this text will be exclusively used in runner groups list test selector to distinguish between 2 lists
      @groups_inheritance = groups_inheritance
      @disabled_runner_group_ids = disabled_runner_group_ids
      @disabled_owner_runner_group_ids = disabled_owner_runner_group_ids
    end

    def edit_path(runner_group)
      if @owner.is_a?(Business)
        settings_actions_runner_group_enterprise_path(@owner, id: runner_group.id)
      else
        settings_org_actions_runner_group_path(@owner, id: runner_group.id)
      end
    end

    def new_path
      if @owner.is_a?(Business)
        settings_actions_add_runner_group_enterprise_path(@owner)
      else
        settings_org_actions_add_runner_group_path(@owner)
      end
    end

    def show_public_visibility_warning?
      return false unless can_create_groups?
      @runner_groups.any? { |g| g.computed_allow_public }
    end

    def visibility_for(runner_group)
      return "" if viewing_from_repository?

      visibility = Actions::RunnerGroup.visibility_for(runner_group)

      target = @viewer.organization? ? "repositories" : "organizations"
      string = [
        Launch::Twirp::RunnerGroupsClient::TO_VISIBILITY_MAP[visibility].upcase_first,
        target,
      ].join(" ")

      if visibility == Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_SELECTED
        selected_targets_count = runner_group.selected_targets.count do |t|
          t.is_a?(Organization) ||
          (runner_group.computed_allow_public || !t.public?)
        end
        string << " (#{selected_targets_count})"
      end

      if runner_group.computed_allow_public
        string << ", including public repositories"
      else
        string << ", excluding public repositories"
      end

      string
    end

    def can_create_runners?
      @can_create_runners
    end

    def can_create_groups?
      @can_create_groups
    end

    def can_update_groups?
      @can_update_groups
    end

    def can_manage_runners?
      @can_manage_runners
    end

    def viewing_from_repository?
      @viewer.is_a? Repository
    end

    def is_network_configuration_disabled?(runner_group)
      if runner_group.inherited?
        @disabled_owner_runner_group_ids && @disabled_owner_runner_group_ids.include?(runner_group.owner_group_id.to_s)
      else
        @disabled_runner_group_ids && @disabled_runner_group_ids.include?(runner_group.id.to_s)
      end
    end

    def network_configuration_visible?(runner_group)
      can_view_network_configuration?(@owner)
    end

    def group_title
      if @viewer != @owner
        viewer = viewing_from_repository? ?  "repository" : "organization"
        # Disable rubocop here because viewer is a string, not a user object
        "Runners shared with this #{viewer}" # rubocop:disable GitHub/DoNotAllowLogin
      else
        "Runner groups"
      end
    end

    def precreated_runner_groups_count
      @runner_groups.count { |x| x.precreated? }
    end
  end
end
