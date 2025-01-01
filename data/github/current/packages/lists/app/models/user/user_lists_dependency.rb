# typed: false
# frozen_string_literal: true

module User::UserListsDependency
  extend ActiveSupport::Concern

  included do
    has_many :lists, class_name: "UserList", dependent: :destroy
  end

  def has_list_with_item?(item)
    lists.with_item(item).any?
  end

  def count_lists_with_item(item)
    lists.with_item(item).size
  end

  def can_modify_list?(list)
    list.owned_by?(self)
  end

  def can_create_lists?
    lists.size < UserList::MAX_PER_USER
  end

  def has_created_lists?
    UserList.has_created_lists?(id)
  end
end
