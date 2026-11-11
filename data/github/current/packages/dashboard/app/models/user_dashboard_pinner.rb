# typed: true
# frozen_string_literal: true

# Pins and unpins items to the user's dashboard (https://github.com)
class UserDashboardPinner
  PINNABLE_TYPES = %w(Repository SearchShortcut).freeze
  # Public: Removes the given items from user's dashboard.
  #
  # items_to_unpin - one or more Repositories or Gists to unpin from the user's dashboard
  # user - a User
  # viewer - the User who is doing the unpinning
  #
  # Returns nothing.
  def self.unpin(*items_to_unpin, user:, viewer:)
    items = user.remove_unpinned_items_from_list(*items_to_unpin, viewer: viewer)

    self.pin(*items, user: user, viewer: viewer)
  end

  # Public: Adds the given items to a user's dashboard.
  #
  # items_to_pin - one or more Repositories or Gists to pin to the user's dashboard
  # user - a User
  # viewer - the User who is doing the unpinning
  #
  # Returns nothing.
  def self.pin(*items_to_pin, user:, viewer:)
    user.pin_items_to_dashboard(items_to_pin, viewer: viewer)
  end

  # Accepts an array of concatenated id-type values, parses them,
  # evaluates `find` calls for corresponding ActiveRecord models (such as Repository or Gist),
  # and returns ActiveRecord entities.
  #
  # Given ["1-Repository", "2-Repository"]
  # Returns #<Repository id: 2 ...>, <Repository id: 1 ...>
  def self.get_pinned_items_from_id_and_type(pinned_items_id_and_type)
    pinned_items = []

    return pinned_items unless pinned_items_id_and_type.present?

    order = []
    pinned_items_hash = {}
    hash_of_ids_by_type = pinned_items_id_and_type.each_with_object({}) do |str, hash|
      id, name = str.split("-")
      next unless PINNABLE_TYPES.include?(name)
      hash[name] ||= []
      hash[name] << id.to_i
      order << name
    end

    hash_of_ids_by_type.each do |type, ids_for_type|
      pinned_items_hash[type] = type.constantize.find(ids_for_type)
    end

    order.each do |item_type|
      pinned_items.push(pinned_items_hash[item_type].shift)
    end

    pinned_items
  end
end
