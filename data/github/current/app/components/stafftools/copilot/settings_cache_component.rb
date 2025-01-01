# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::SettingsCacheComponent < ApplicationComponent

  sig { returns(Copilot::Organization) }
  attr_reader :copilot_organization

  sig { params(copilot_organization: Copilot::Organization).void.checked(:always).on_failure(:raise) }
  def initialize(copilot_organization)
    @copilot_organization = copilot_organization
  end
end
