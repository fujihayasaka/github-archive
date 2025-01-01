# typed: false
# frozen_string_literal: true

# Public: Service object to replace the user lists to which an item belongs.
class UserLists::ReplaceItemUserLists
  # Public: Invoke the service.
  #
  # inputs - Hash containing attributes.
  # inputs[:user] - Currently authenticated user.
  # inputs[:item] - The item to be added and removed from UserLists. Item can currently only be a Repository. The
  #   user must already be verified to have at least read access.
  # inputs[:requested_list_ids] - Array of UserList IDs to which the chosen item should belong. Some entries may be
  #   empty, not visible to the current user, or invalid.
  # inputs[:requested_list_names] - Array of String UserList names to which the chosen item should belong. If the :user
  #   already owns a UserList with a slug colliding with a chosen name, that UserList will be used, otherwise a new
  #   UserList with the specified name (and no description) will be created.
  # inputs[:context] - String describing the request context used to mark how the item was starred in Hydro events.
  #   Must be one of Star::STARRABLE_CONTEXTS.
  #
  # Returns a UserLists::ReplaceItemUserLists::Result indicating overall operation success or failure and whether or not
  # starring was performed.
  def self.call(**inputs)
    new(**inputs).call
  end

  def initialize(user:, item:, requested_list_ids: [], requested_list_names: [], context:)
    @user = user
    @item = item
    @requested_list_ids = requested_list_ids
    @requested_list_names = requested_list_names
    @context = context

    @did_star = false
    @did_create = false
  end

  def call
    if verified_list_ids.any?
      return Result.failure(did_create: @did_create) if !ensure_item_is_starred
    end

    UserList.replace_all(user_id: user.id, repository_id: item.id, list_ids: verified_list_ids)
    Result.success(did_star: @did_star, did_create: @did_create)
  end

  private

  attr_reader :user, :item, :context

  # Private: Returns the subset of requested list IDs that correspond to valid UserLists owned by the requesting
  # user.
  #
  # Returns an Array of UserList IDs that are a subset of the requested list IDs.
  def verified_list_ids
    @verified_list_ids ||= begin
      list_ids = Set.new
      nonempty_ids = @requested_list_ids.reject(&:blank?)
      nonempty_names = @requested_list_names.reject(&:blank?)

      # Model validations from the .save call below will trigger N+1 queries - a COUNT() query from
      # #ensure_user_has_less_than_max_lists, a KV query from #user_created_list_kv, an existence query from the
      # uniqueness constraint on #slug. N is expected to be small (<= 3) so we opt for simplicity here.
      #
      # If performance becomes a problem, we can create an efficient batch-creation method on UserList and use it
      # here instead.
      list_ids += nonempty_names.flat_map do |name|
        created_list = user.lists.build(name: name)
        if created_list.save
          @did_create = true
          [created_list.id]
        elsif created_list.errors.of_kind?(:name, :taken)
          user.lists.with_colliding_name(name).pluck(:id)
        else
          []
        end
      end

      if nonempty_ids.any?
        list_ids += user.lists.where(id: nonempty_ids).pluck(:id)
      end

      list_ids.to_a
    end
  end

  # Private: Return true if the current user has already starred the item.
  def has_starred_item?
    return @has_starred if defined?(@has_starred)
    @has_starred = item.starred_by?(user)
  end

  # Private: Return true if the current user has permission to star the item.
  def can_star_item?
    return @can_star if defined?(@can_star)
    @can_star = user.can_star?(item, is_readable: true, is_starred: has_starred_item?)
  end

  # Private: Attempt to star the item if we are about to add it to at least one UserList, if it is not already
  # starred, and if the current user has permission to do so. As a side effect, sets `@did_star` to true if starring
  # occurred.
  #
  # Returns false if we need to star the item but don't have permissions to do so. Returns true if we won't even try
  # to star or if starring succeeded.
  def ensure_item_is_starred
    return true if has_starred_item?
    return false if !can_star_item?

    @did_star = user.star(item, context: context)
  end

  class Result
    def initialize(success:, did_star:, did_create:)
      @success = success
      @did_star = did_star
      @did_create = did_create
    end

    def success?
      @success
    end

    def did_star?
      @did_star
    end

    def did_create?
      @did_create
    end

    def self.success(did_star:, did_create:)
      new(success: true, did_star: did_star, did_create: did_create)
    end

    def self.failure(did_create:)
      new(success: false, did_star: false, did_create: did_create)
    end
  end
end
