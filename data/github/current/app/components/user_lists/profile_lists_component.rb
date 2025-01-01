# typed: true
# frozen_string_literal: true

class UserLists::ProfileListsComponent < ApplicationComponent
  attr_reader :user_lists

  HIDE_AFTER = 8

  def initialize(user_lists:)
    @user_lists = user_lists
  end

  private

  delegate :cap_filter, to: :helpers

  memoize def item_counts
    UserList.visible_item_counts(
      viewer: current_user,
      list_ids: user_lists.map(&:id),
      cap_filter: cap_filter,
    )
  end

  def has_more_lists?
    user_lists.count > HIDE_AFTER
  end
end
