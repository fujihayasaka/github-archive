# typed: true
# frozen_string_literal: true

class Orgs::Teams::DeleteTeamsDialogView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :organization, :selected_teams, :destroy_teams_path

  def delete_teams_text
    if contains_parent_teams?
      "Deleting teams will delete all their child teams. Once deleted, it can’t be undone."
    else
      "Once deleted, it can’t be undone."
    end
  end

  def contains_parent_teams?
    !!selected_teams.any? { |team| team.descendants.any? }
  end
end
