# typed: true
# frozen_string_literal: true

class Businesses::UserListCardComponent < ApplicationComponent
  include BusinessesHelper

  attr_reader \
    :primary_name,
    :user,
    :octicon,
    :user_link,
    :user_link_data_options,
    :secondary_name,
    :subtitle,
    :spammy,
    :display_login,
    :bulk_action_enabled,
    :bulk_attribute,
    :bulk_id,
    :bulk_action_prevent_selection,
    :owner_actor,
    :classes

  def initialize(
    primary_name:,
    user: nil,
    octicon: nil,
    user_link: nil,
    user_link_data_options: {},
    secondary_name: nil,
    subtitle: nil,
    spammy: false,
    display_login: nil,
    bulk_action_enabled: nil,
    bulk_attribute: nil,
    bulk_id: nil,
    bulk_action_prevent_selection: false,
    owner_actor: true,
    classes: ""
  )
    @primary_name = primary_name
    @user = user
    @octicon = octicon
    @user_link = user_link
    @user_link_data_options = user_link_data_options
    @secondary_name = secondary_name
    @subtitle = subtitle
    @spammy = spammy
    @display_login = display_login
    @bulk_action_enabled = bulk_action_enabled
    @bulk_attribute = bulk_attribute
    @bulk_id = bulk_id
    @bulk_action_prevent_selection = bulk_action_prevent_selection
    @owner_actor = owner_actor
    @classes = classes
  end

  memoize def is_first_emu_owner?
    if user.is_a?(BusinessUserAccount) && user.association(:user).loaded?
      return true if user.user.is_first_emu_owner?
    elsif user.is_a?(Admin::IBusinessUserAccount)
      resolved_user = T.cast(Users.domain.by_id(user.user_id), T.nilable(User))
      return true if resolved_user&.is_first_emu_owner?
    end
    return true if user.is_a?(User) && user.is_first_emu_owner?
    false
  end

  # Public: Generate an accessible label for the member checkbox
  #
  # Returns a String that describes the member for screen readers
  def accessible_member_label
    if display_login.present?
      "Member #{display_login}"
    else
      "Member #{primary_name}"
    end
  end
end
