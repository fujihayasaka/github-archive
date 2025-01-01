# typed: true
# frozen_string_literal: true

class Settings::Organization::TeamsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :organization

  def team_discussions_setting_policy?
    organization.team_discussions_policy?
  end

  def team_discussions_allowed_text
    organization.team_discussions_allowed? ? "enabled" : "disabled"
  end

  def team_discussions_label_class
    return "color-fg-muted" if team_discussions_setting_policy?
  end
end
