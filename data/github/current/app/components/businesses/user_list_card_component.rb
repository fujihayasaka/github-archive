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
    :owner_actor

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
    owner_actor: true
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
  end

  memoize def is_first_emu_owner?
    return true if user.is_a?(BusinessUserAccount) && user&.user&.is_first_emu_owner?
    return true if user.is_a?(User) && user.is_first_emu_owner?
    false
  end
end
