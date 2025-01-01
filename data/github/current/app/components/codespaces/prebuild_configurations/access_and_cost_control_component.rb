# typed: true
# frozen_string_literal: true

class Codespaces::PrebuildConfigurations::AccessAndCostControlComponent < ApplicationComponent
  def initialize(
    form:,
    repo:,
    selected_locations: [],
    all_locations_selected: true,
    vscs_target_options:,
    selected_target_name: nil,
    vscs_target_url: nil,
    delivery_days:,
    delivery_times:,
    time_zone_name:,
    trigger:,
    maximum_template_versions:,
    runner_group_options:
  )
    @form = form
    @repo = repo
    @selected_locations = selected_locations
    @all_locations_selected = all_locations_selected
    @vscs_target_options = vscs_target_options
    @selected_target_name = selected_target_name
    @vscs_target_url = vscs_target_url
    @delivery_days = delivery_days
    @delivery_times = delivery_times
    @time_zone_name = time_zone_name
    @trigger = trigger
    @maximum_template_versions = maximum_template_versions
    @runner_group_options = runner_group_options
  end

  private

  attr_reader :form, :repo, :selected_locations, :all_locations_selected,
    :vscs_target_options, :selected_target_name, :vscs_target_url, :delivery_days,
    :delivery_times, :time_zone_name, :trigger, :maximum_template_versions,
    :runner_group_options
end
