# typed: false
# frozen_string_literal: true

module Profile::PinsDependency
  extend ActiveSupport::Concern

  included do
    has_many :profile_pins, -> { ordered_by_position }, dependent: :destroy
    has_many :pinned_repositories, through: :profile_pins, source: :pinned_item,
       source_type: "Repository", disable_joins: true
  end

  # Public: Given a list of repositories and gists, will delete any pins for
  # repositories and gists not included in that list. Will also create pins
  # for repositories and gists in the list that are not already pinned.
  #
  # internal_view - Whether the pins should be created in the member-only view or public view
  def pin_items(repos_and_gists, internal_view: false)
    repos = repos_and_gists.select { |item| item.is_a?(Repository) }
    gists = repos_and_gists.select { |item| item.is_a?(Gist) }
    pins_to_keep = profile_pins.for_repository(repos).where(internal_view: internal_view).includes(:pinned_item) +
      profile_pins.for_gist(gists).includes(:pinned_item)
    new_items_to_pin = repos_and_gists - pins_to_keep.map(&:pinned_item)

    max_position = if pins_to_keep.count > 0
      pins_to_keep.pluck(:position).max
    else
      # No pins we're keeping, so start fresh:
      0
    end

    # Remove old pins we no longer want:
    delete_old_profile_pins(pins_to_keep, internal_view: internal_view)

    # Create new pins for repos and gists we didn't have pinned before:
    pin_new_items(new_items_to_pin, max_position, internal_view: internal_view)

    # Make sure the pinned items are in the order we were given:
    reorder_pinned_items(repos_and_gists, internal_view: internal_view)
  end

  def create_profile_pin(pinned_item_id:, pinned_item_type:, position:, internal_view: false)
    return false unless persisted?

    existing_pin = profile_pins.
      where(pinned_item_id: pinned_item_id,
            pinned_item_type: ProfilePin.pinned_item_types[pinned_item_type]).first
    other_pins = profile_pins.where(internal_view: internal_view)
    if existing_pin
      other_pins = other_pins.where("id <> ?", existing_pin.id)
    end
    return false if other_pins.count >= ProfilePin::LIMIT_PER_PROFILE

    pins_query = <<-SQL
      INSERT INTO profile_pins
      (profile_id, pinned_item_type, pinned_item_id, position, internal_view)
      VALUES
      (:profile_id, :pinned_item_type, :pinned_item_id, :position, :internal_view)
      ON DUPLICATE KEY
      UPDATE id = id, position = VALUES(position)
    SQL
    ProfilePin.connection.insert(Arel.sql(pins_query, profile_id: id, position: position,
                    pinned_item_type: ProfilePin.pinned_item_types[pinned_item_type],
                    pinned_item_id: pinned_item_id, internal_view: internal_view))

    ProfilePin.instrument_create(user, pinned_item_type: pinned_item_type,
                                 pinned_item_id: pinned_item_id, position: position, internal_view: internal_view)

    true
  end

  # Public: Returns true when the given list of repositories and gists is the same as
  # the repositories and gists this profile has pinned, regardless of order.
  def has_pins_for_all_items?(items, internal_view: false)
    get_item_key = ->(item) { "#{item.class.name}:#{item.id}" }
    item_keys = items.map { |item| get_item_key.call(item) }
    pinned_item_keys = profile_pins.where(internal_view: internal_view).includes(:pinned_item).map do |pin|
      get_item_key.call(pin.pinned_item)
    end
    Set.new(item_keys) == Set.new(pinned_item_keys)
  end

  # Public: Given a list of repositories and gists, will rearrange the existing
  # pins so that they're in the same order as the given list.
  def reorder_pinned_items(ordered_items, internal_view: false)
    return unless has_pins_for_all_items?(ordered_items, internal_view: internal_view)

    existing_pins = profile_pins.where(internal_view: internal_view).includes(:pinned_item)
    return if ordered_items == existing_pins.map(&:pinned_item)

    # Update the position on repositories and gists we already had pinned:
    existing_pins.each do |pin|
      position = ordered_items.index(pin.pinned_item) + 1 # 1-based index
      pin.update_attribute(:position, position) unless pin.position == position
    end
  end

  private

  def pin_new_items(new_items_to_pin, max_position, internal_view: false)
    valid_new_items_to_pin = get_valid_new_items_to_pin(new_items_to_pin, internal_view: internal_view)
    valid_new_items_to_pin.each_with_index do |item, i|
      create_profile_pin(pinned_item_type: item.class.name.to_sym, pinned_item_id: item.id,
                         position: i + max_position + 1, internal_view: internal_view)
    end
  end

  def delete_old_profile_pins(pins_to_keep, internal_view: false)
    pins_to_delete = profile_pins.where(internal_view: internal_view) - pins_to_keep
    pins_to_delete.each do |pin|
      profile_pins.delete(pin)
    end
  end

  def pinnable_repo_scope(internal_view: false)
    internal_view ? Repository.active.is_not_disabled : Repository.active.public_scope.is_not_disabled
  end

  def pinnable_gist_scope
    Gist.are_public.is_not_disabled
  end

  def get_valid_new_items_to_pin(new_items_to_pin, internal_view: false)
    new_repos = new_items_to_pin.select { |item| item.is_a?(Repository) }
    valid_repo_ids = pinnable_repo_scope(internal_view: internal_view).where(id: new_repos.map(&:id)).pluck(:id)
    valid_repos = new_repos.select { |repo| valid_repo_ids.include?(repo.id) }

    new_gists = new_items_to_pin.select { |item| item.is_a?(Gist) }
    valid_gist_ids = pinnable_gist_scope.where(id: new_gists.map(&:id)).pluck(:id)
    valid_gists = new_gists.select { |gist| valid_gist_ids.include?(gist.id) }

    (valid_repos + valid_gists).sort_by { |item| new_items_to_pin.index(item) }
  end
end
