# typed: true
# frozen_string_literal: true

class Codespaces::PrebuildConfigurations::RegionSelectComponent < ApplicationComponent
  def initialize(form:, repo:, selected_locations: [], all_locations_selected: true)
    @form = form
    @repo = repo
    @selected_locations = selected_locations
    @all_locations_selected = all_locations_selected
  end

  private

  attr_reader :form, :repo, :selected_locations, :all_locations_selected
end
