# typed: true
# frozen_string_literal: true

class UserLists::RowComponent < ApplicationComponent
  def initialize(user_list:, item_count:, classes: "")
    @user_list = user_list
    @item_count = item_count
    @classes = classes
  end

  private

  attr_reader :user_list, :item_count, :classes

  def render?
    user_list.present?
  end

  def user_list_href
    user_list_path(user_list.user, user_list.slug)
  end
end
