# typed: true
# frozen_string_literal: true

class Orgs::Teams::ChangeTeamsVisibilityDialogView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :organization, :selected_teams

  def teams_to_change_visibility
    selected_teams.reject(&:cant_change_visibility?)
  end

  def cant_change_visibility_for_all_teams?
    selected_teams.any?(&:cant_change_visibility?)
  end
end
