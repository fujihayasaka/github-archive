# typed: true
# frozen_string_literal: true

class Orgs::Teams::ToolbarActionsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :organization, :selected_teams, :adminable_by_user, :destroy_teams_path, :is_child_team

  def show_remove_button?
    !!adminable_by_user
  end

  def show_change_visibility_button?
    !!adminable_by_user && !child_team?
  end

  private

  def child_team?
    !!is_child_team
  end
end
