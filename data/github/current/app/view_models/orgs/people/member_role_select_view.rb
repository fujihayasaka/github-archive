# typed: true
# frozen_string_literal: true

class Orgs::People::MemberRoleSelectView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :organization
  attr_reader :selected_members

  # Public: Is the selected person an Owner of the org?
  #
  # Returns a boolean.
  def admin_selected?
    selected_members.all? { |member| organization.adminable_by?(member) }
  end

  # Public: Is the selected person just a regular Member of the org?
  #
  # Returns a boolean.
  def member_selected?
    selected_members.all? { |member| organization.direct_member?(member) && !organization.adminable_by?(member) }
  end

  # Public: Get all the selected members who aren't on any teams.
  #
  # Returns an array of users.
  def teamless_selected_members
    @teamless_selected_members ||= selected_members.select do |member|
      organization.teams_for(member).empty?
    end
  end

  # Get all the IDs of the selected members joined together by commas.
  #
  # Returns a String.
  def selected_members_query_value
    @selected_members_query_value ||= selected_members.map(&:id).sort.join(",")
  end
end
