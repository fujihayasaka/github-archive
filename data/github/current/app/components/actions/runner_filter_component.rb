# typed: true
# frozen_string_literal: true

module Actions
  class RunnerFilterComponent < ApplicationComponent
    include Actions::LargerRunnersHelper
    include ActionsHelper
    renders_one :description

    def initialize(
      owner:,
      owner_settings:,
      hosted_runner_group: nil,
      runners: [],
      search_action: "runners",
      inherited_groups: [],
      has_business: false,
      viewer: owner,
      can_create_runners: true,
      can_manage_runners: true,
      filter_level: nil,
      filter_query: nil,
      runner_group: nil
    )
      @owner = owner
      @viewer = viewer
      @owner_settings = owner_settings
      @runners = runners
      @hosted_runner_group = hosted_runner_group
      @search_action = search_action
      @has_business = has_business
      @can_create_runners = can_create_runners
      @can_manage_runners = can_manage_runners
      @filter_level = filter_level
      @filter_query = filter_query
      @runner_group = runner_group
    end

    def hosted_runner_group
      @hosted_runner_group
    end

    def viewing_from_a_repository?
      @owner_settings.settings_owner_type == "repository"
    end

    def viewing_from_runner_group?
      @search_action != "runners"
    end

    def filter_value_for_level(level)
      array = []
      if level.present?
        array.push([:level, level])
      end
      if @filter_query.present?
        array.push(@filter_query)
      end
      Search::ParsedQuery.stringify(array)
    end

    def should_show_runner_level_filter?
      true if @has_business
    end

    def larger_runner_button_properties

      if @owner.can_use_larger_runners? || @owner.is_eligible_to_onboard_larger_runners?
        {
          enabled: true,
          href: @owner_settings.add_larger_runner_path(runner_group_id: @runner_group&.id),
          hint: nil
        }
      elsif is_trial_billing_plan_for_entity?(@owner)
        {
          enabled: false,
          href: nil,
          hint: "Not available on Trial plans"
        }
      else
        {
          enabled: false,
          href: nil,
          hint: "Only available on paid Team or Enterprise plans"
        }
      end
    end
  end
end
