# typed: true
# frozen_string_literal: true

class Orgs::People::ToolbarActionsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :organization
  attr_reader :selected_members

  # Get all the IDs of the selected members joined together by commas.
  #
  # Returns a String.
  def selected_member_ids
    selected_members.map(&:id).sort.join(",")
  end

  # Public: Should we show the "Hide memberships" button?
  #
  # Returns a boolean.
  def show_hide_membership_button?
    return @show_hide_membership_button if defined?(@show_hide_membership_button)
    return unless logged_in?
    return unless selected_members.present?

    @show_membership_button = (selected_members.map(&:id) & organization.public_members.pluck(:id)).any?
  end

  # Public: Should we show the "Remove from organization" button?
  #
  # Returns a boolean.
  def show_remove_button?
    return unless logged_in?
    organization.adminable_by?(current_user)
  end

  # Public: Should we show the role switcher?
  #
  # Returns a boolean.
  def show_role_switcher?
    return unless logged_in?
    return unless selected_members.present?

    if selected_members.include?(current_user)
      role = Organization::Role.new(organization, current_user)
      role.can_be_modified_by?(current_user)
    else
      organization.adminable_by?(current_user)
    end
  end
end
