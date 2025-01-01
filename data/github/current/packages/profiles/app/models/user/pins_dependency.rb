# typed: false
# frozen_string_literal: true

module User::PinsDependency
  # Public: Given a record, will pin that record to the user's dashboard in the last position if
  # the user has any spots left for pinning.
  #
  # item_to_pin - a Repository, Gist, Issue, Project, PullRequest, User, Organization, or Team
  # viewer - the current User or nil
  #
  # Returns Boolean indicating if the item was pinned or not.
  def pin_item_to_dashboard(item_to_pin, viewer: nil)
    return false unless valid_dashboard_pin_item?(item: item_to_pin, viewer: viewer)
    max_position = dashboard_pins.maximum(:position) || 0
    create_user_dashboard_pin(pinned_item_id: item_to_pin.id,
                              pinned_item_type: item_to_pin.class.name, position: max_position + 1)
  end

  # Public: Given a record, will unpin that record from the user's dashboard.
  #
  # item_to_unpin - a Repository, Gist, Issue, Project, PullRequest, User, Organization, or Team
  #
  # Returns nil if the item wasn't pinned, or a Boolean indicating if it was unpinned successfully.
  def unpin_item_from_dashboard(item_to_unpin)
    pin = dashboard_pins.for_item(item_to_unpin.id, item_to_unpin.class.name).first
    pin&.destroy
  end

  # Public: Given a list of items, will delete any pins for items
  # not included in that list. Will also create pins for items in the list
  # that are not already pinned.
  def pin_items_to_dashboard(items_to_pin, viewer: nil)
    items_to_pin.compact!

    # Identify already pinned items that exist that are being repinned
    pins_to_keep = dashboard_pins.where(pinned_item: items_to_pin)
                                 .reorder(nil)
                                 .select(&:pinned_item) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

    # Identify items that have not already been pinned that are being pinned
    new_items_to_pin = items_to_pin - pins_to_keep.map(&:pinned_item)

    max_position = pins_to_keep.map(&:position).max || 0

    # Remove old pins we no longer want:
    delete_old_user_dashboard_pins(pins_to_keep)

    # Create new pins for items we didn't have pinned before:
    pin_new_dashboard_items(new_items_to_pin, max_position, viewer: viewer)

    # Make sure the pinned items are in the order we were given:
    reorder_dashboard_pinned_items(items_to_pin)
  end

  # Public: Given a list of items to unpin from the dashboard it will return
  # a list of the pinned items that should remain pinned to the dashboard
  def remove_unpinned_items_from_list(*items_to_unpin, viewer: nil)
    items = ActiveRecord::Base.connected_to(role: :reading) { self.dashboard_pinned_items(viewer: viewer) }

    items_to_unpin.each do |item|
      items.delete(item)
    end

    items
  end

  def async_pinned_items(viewer: nil, types: ProfilePin.pinned_item_types.keys, internal_view: false)
    if organization?
      async_business.then do
        pinned_items(viewer: viewer, types: types, internal_view: internal_view)
      end
    else
      Promise.resolve(pinned_items(viewer: viewer, types: types, internal_view: internal_view))
    end
  end

  # Public: Get a list of pinned gists and repositories on this user's profile page.
  #
  # viewer - the User who is viewing the pinned items
  # types - list of pinned item types to include, defaults to including all possible types;
  #         valid values include "Repository" and "Gist"
  # internal_view - determines whether to grab pins from public or member-only view
  #
  # Returns an Array of Gist and Repository records.
  def pinned_items(viewer: nil, types: ProfilePin.pinned_item_types.keys, internal_view: false)
    pins = profile_pins.where(pinned_item_type: types).where(internal_view: internal_view).preload(:pinned_item)

    if organization?
      pinned_repos_ids = Repository.where(
        id: pins.select(&:repository?).map(&:pinned_item_id),
      ).filter_spam_and_disabled_for(viewer).active.pluck(:id)
      visible_pinned_repo_ids =
        self.visible_repositories_for(viewer, org_pinned_repo_ids: pinned_repos_ids, limit_visible_internal_repos_to_org: true).ids &
        pinned_repos_ids
    else
      visible_pinned_repo_ids = Repository.where(
        id: pins.select(&:repository?).map(&:pinned_item_id),
      ).filter_spam_and_disabled_for(viewer).public_scope.active.pluck(:id)
    end

    visible_pinned_gist_ids = Gist.where(
      id: pins.select(&:gist?).map(&:pinned_item_id),
    ).filter_spam_and_disabled_for(viewer).are_public.pluck(:id)

    pins.select do |pin|
      (
        pin.repository? && visible_pinned_repo_ids.include?(pin.pinned_item_id)
      ) || (
        pin.gist? && visible_pinned_gist_ids.include?(pin.pinned_item_id)
      )
    end.map(&:pinned_item)
  end

  def any_dashboard_pinned_items?(viewer: self, types: UserDashboardPin.pinned_item_types.keys, excluded_account_ids: [], preload_scope: :pinned_item)
    dashboard_pinned_items(
      viewer: self,
      types: types,
      excluded_account_ids: excluded_account_ids,
      preload_scope: preload_scope)
    .any?
  end

  # Public: Get a list of pinned items on this user's dashboard (e.g. https://github.com).
  #
  # viewer - the User who is viewing the pinned items
  # types - list of pinned item types to include, defaults to including all possible types;
  #         valid values include "Repository", "Gist", "Issue", "Project", "PullRequest",
  #         "User" and "Organization"
  #
  # Returns an Array of dashboard pinned item records.
  def dashboard_pinned_items(viewer: self, types: UserDashboardPin.pinned_item_types.keys, excluded_account_ids: [], preload_scope: :pinned_item)
    pins = dashboard_pins.where(pinned_item_type: types).preload(preload_scope)

    pins.each_with_object([]) do |pin, pinned_items| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      if valid_dashboard_pin_item?(item: pin.pinned_item, viewer: viewer, excluded_account_ids: excluded_account_ids)
        pinned_items << pin.pinned_item
      end
    end
  end

  def create_user_dashboard_pin(pinned_item_id:, pinned_item_type:, position:)
    return false unless persisted?

    existing_pin = dashboard_pins.for_item(pinned_item_id, pinned_item_type).first
    other_pins = dashboard_pins
    if existing_pin
      other_pins = other_pins.where("id <> ?", existing_pin.id)
    end
    return false if other_pins.count >= UserDashboardPin::LIMIT_PER_USER_DASHBOARD

    pins_query = <<-SQL
      INSERT INTO user_dashboard_pins
      (user_id, pinned_item_type, pinned_item_id, position, created_at, updated_at)
      VALUES
      (:user_id, :pinned_item_type, :pinned_item_id, :position, NOW(), NOW())
      ON DUPLICATE KEY
      UPDATE id = id, position = VALUES(position), updated_at = VALUES(updated_at)
    SQL
    UserDashboardPin.connection.insert(Arel.sql(pins_query, user_id: id, position: position,
      pinned_item_type: UserDashboardPin.pinned_item_types[pinned_item_type],
      pinned_item_id: pinned_item_id))

    UserDashboardPin.instrument_create(self, pinned_item_type: pinned_item_type,
      pinned_item_id: pinned_item_id, position: position)

    true
  end

  # Public: Given a list of items, will rearrange the existing pins so that they
  # are in the same order as the given list.
  def reorder_dashboard_pinned_items(ordered_items)
    return unless has_dashboard_pins_for_all_items?(ordered_items)

    existing_pins = dashboard_pins.includes(:pinned_item)
    return if ordered_items == existing_pins.map(&:pinned_item) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

    # Update the position on items we already had pinned:
    existing_pins.each do |pin|
      position = ordered_items.index(pin.pinned_item) + 1 # 1-based index
      pin.update_attribute(:position, position) unless pin.position == position
    end
  end

  # Public: Returns true when the given list of items is the same as the items
  # this dashboard has pinned, regardless of order.
  def has_dashboard_pins_for_all_items?(items)
    get_item_key = ->(item) { "#{item.class.name}:#{item.id}" }
    item_keys = items.map { |item| get_item_key.call(item) }
    pinned_item_keys = dashboard_pins.includes(:pinned_item).map do |pin| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      get_item_key.call(pin.pinned_item)
    end
    Set.new(item_keys) == Set.new(pinned_item_keys)
  end

  # Public: Determine if the given viewer can pin items to this user's profile.
  #
  # viewer - nil or a User
  #
  # Returns a Boolean.
  def can_pin_profile_items?(viewer)
    if organization?
      adminable_by?(viewer)
    elsif user? && !self.is_enterprise_managed?
      self == viewer
    else
      false
    end
  end

  # Public: Determine if the given viewer can pin items to this dashboard.
  #
  # viewer - nil or a User
  #
  # Returns a Boolean.
  def can_pin_dashboard_items?(viewer)
    user? && self == viewer
  end

  # Public: Returns true when the given repository is pinned to this user's profile.
  def pinned_repository?(repo, internal_view: false)
    profile_pins.for_repository(repo).where(internal_view: internal_view).exists?
  end

  # Public: Returns true when the given gist is pinned to this user's profile.
  def pinned_gist?(gist)
    profile_pins.for_gist(gist).exists?
  end

  def total_pinned_repositories
    if profile
      profile.pinned_repositories.size
    else
      0
    end
  end

  def any_pinnable_items?(viewer: nil, types: ProfilePin.pinned_item_types.keys, internal_view: false)
    async_any_pinnable_items?(viewer: viewer, types: types, internal_view: internal_view).sync
  end

  def async_any_pinnable_items?(viewer: nil, types: ProfilePin.pinned_item_types.keys, internal_view: false)
    any_public_repos = types.include?("Repository") && public_repositories.any?
    any_public_gists = if types.include?("Gist")
      public_gists.any?
    else
      false
    end
    any_obvious_pinnable_items = any_public_repos || any_public_gists

    # Don't call `async_pinnable_items` for a large bot account since it
    # will load all contributions to repos within the past year, which is expensive.
    # Even for a regular user, it's faster to return early here if possible.
    if any_obvious_pinnable_items || large_bot_account?
      return Promise.resolve(any_obvious_pinnable_items)
    end

    pinner = ProfilePinner.new(user: self, viewer: viewer, viewing_as_member: internal_view)
    pinner.async_pinnable_items(types: types).then do |pinnable_items|
      pinnable_items.any?
    end
  end

  def pinned_items_remaining(internal_view: false)
    ProfilePin::LIMIT_PER_PROFILE - profile_pins.where(internal_view: internal_view).count
  end

  def dashboard_pinned_items_remaining
    UserDashboardPin::LIMIT_PER_USER_DASHBOARD - dashboard_pinned_items(viewer: self).count
  end

  private

  def delete_old_user_dashboard_pins(pins_to_keep)
    dashboard_pins.where.not(id: pins_to_keep).destroy_all
  end

  def pin_new_dashboard_items(new_items_to_pin, max_position, viewer: nil)
    valid_new_items_to_pin = get_valid_new_items_to_pin_to_dashboard(new_items_to_pin, viewer)
    valid_new_items_to_pin.each_with_index do |item, i|
      create_user_dashboard_pin(pinned_item_type: item.class.name.to_sym,
        pinned_item_id: item.id, position: i + max_position + 1)
    end
  end

  def get_valid_new_items_to_pin_to_dashboard(new_items_to_pin, viewer)
    new_items_to_pin.select do |item|
      valid_dashboard_pin_item?(item: item, viewer: viewer)
    end
  end

  def valid_dashboard_pin_item?(item:, viewer: nil, excluded_account_ids: [])
    async_valid_dashboard_pin_item?(item: item, viewer: viewer, excluded_account_ids: excluded_account_ids).sync
  end

  def async_valid_dashboard_pin_item?(item:, viewer: nil, excluded_account_ids: [])
    return Promise.resolve(false) if item&.destroyed?

    case item
    when Repository
      promises = [item.async_disabled_access_reason,
                  item.async_internal_repository,
                  item.async_owner,
                  item.async_parent]
      Promise.all(promises).then do
        item.readable_by?(viewer) && item.active? && !item.hide_from_user?(viewer) && !item.access.disabled? && !excluded_account_ids.include?(item.owner.id)
      end
    when Gist
      item.async_disabled_access_reason.then do
        item.readable_by?(viewer) && item.active? && !item.hide_from_user?(viewer) && !item.access.disabled? && !excluded_account_ids.include?(item.user_id)
      end
    when Issue, PullRequest
      item.async_repository.then do |repo|
        repo.async_owner.then do |owner|
          item.readable_by?(viewer) && !excluded_account_ids.include?(owner.id)
        end
      end
    when Project
      item.async_owner.then do |owner|
        if owner.is_a?(Repository)
          owner.async_owner.then do |repo_owner|
            item.readable_by?(viewer) && !excluded_account_ids.include?(repo_owner.id)
          end
        else
          item.readable_by?(viewer) && !excluded_account_ids.include?(owner.id)
        end
      end
    when User, Organization
      Promise.resolve(!viewer&.avoid?(item) && !excluded_account_ids.include?(item.id))
    when Team
      item.async_visible_to?(viewer).then do |visible|
        visible && !excluded_account_ids.include?(item.organization_id)
      end
    else
      Failbot.report!(ArgumentError.new("Unsupported pinned item type: #{item.class}"))
      Promise.resolve(false)
    end
  end
end
