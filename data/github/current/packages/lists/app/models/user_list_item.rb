# typed: false
# frozen_string_literal: true

class UserListItem < ApplicationRecord::Collab
  belongs_to :user_list
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain

  after_commit :update_user_list, on: [:create, :destroy]
  after_commit :instrument_create, on: :create
  after_commit :instrument_delete, on: :destroy

  scope :owned_by, ->(user_or_id) { joins(:user_list).merge(UserList.owned_by(user_or_id)) }

  scope :for_repository, ->(repo_or_id) { where(repository: repo_or_id) }

  scope :in_list, ->(list_or_id) { where(user_list: list_or_id) }

  scope :not_in_list, ->(list_or_id) { where.not(user_list: list_or_id) }

  validate :user_can_view_repository

  # Public: Ensure a repository is in all the given lists that are owned by a particular user.
  #
  # user_id - ID of the User who owns the lists specified in `list_ids`
  # repository_id - ID of the Repository to add to the lists
  # list_ids - Enumerable of UserList IDs to ensure the repository belongs to
  #
  # Returns an Array of UserList IDs that the repository was added to.
  def self.bulk_insert(user_id:, repository_id:, list_ids:)
    return [] if list_ids.empty?

    existing_list_item_ids = owned_by(user_id).in_list(list_ids).for_repository(repository_id).pluck(:id)

    now = Time.zone.now
    item_attrs = list_ids.map do |list_id|
      {
        repository_id: repository_id,
        user_list_id: list_id,
        created_at: now,
        updated_at: now,
      }
    end

    # Bulk-insert new UserListItems. The unique index ensures that existing items are preserved as-is.
    insert_all(item_attrs)

    new_list_items = owned_by(user_id).in_list(list_ids).for_repository(repository_id)
      .where.not(id: existing_list_item_ids).includes(:repository)
    new_list_items.map(&:instrument_create)

    list_ids_repo_added_to = new_list_items.map(&:user_list_id)
    list_ids_repo_added_to
  end

  # Public: Ensure a repository does not belong to any the given lists that are owned by a particular user.
  #
  # user_id - ID of the User who owns the lists specified in `list_ids`
  # repository_id - ID of the Repository to remove from the lists
  # list_ids_to_keep - Enumerable of UserList IDs that the repository should be kept in; any UserList not in this list
  #                    will have the repository removed
  #
  # Returns an Array of the UserList IDs the repository was removed from.
  def self.bulk_delete(user_id:, repository_id:, list_ids_to_keep:)
    list_items_to_delete = owned_by(user_id).for_repository(repository_id).not_in_list(list_ids_to_keep)
    list_items_to_delete.map(&:instrument_delete)
    list_ids_repo_removed_from = list_items_to_delete.map(&:user_list_id)

    # Bulk-delete items to remove this repository from any lists not in the provided collection.
    list_items_to_delete.delete_all

    list_ids_repo_removed_from
  end

  def list_owner
    user_list.user
  end

  # Public: Emit a Hydro event about the creation of this list item. Happens automatically when a UserListItem
  # is created by itself.
  #
  # Returns nothing.
  def instrument_create
    # Hydro
    GlobalInstrumenter.instrument("user_list.add_item", user_list_item: self, user_list: user_list,
      repository: repository)
  end

  # Public: Emit a Hydro event about the deletion of this list item. Happens automatically when a UserListItem
  # is destroyed by itself.
  #
  # Returns nothing.
  def instrument_delete
    # Hydro
    GlobalInstrumenter.instrument("user_list.remove_item", user_list_item: self, user_list: user_list,
      repository: repository)
  end

  def target_for_conditional_access
    async_target_for_conditional_access.sync
  end

  def async_target_for_conditional_access
    async_repository.then do |repository|
      if repository.nil?
        :no_target_for_conditional_access
      else
        repository.async_target_for_conditional_access
      end
    end
  end

  private

  def user_can_view_repository
    if !repository.readable_by?(list_owner)
      errors.add(:repository, :not_found, message: "not found for list owner.")
    end
  end

  def update_user_list
    return unless user_list&.persisted?
    user_list.update_item_count
    user_list.touch(:last_added_at)
  end
end
