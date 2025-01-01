# typed: true
# frozen_string_literal: true

# Public: Service model to perform many changes at once to different items in a Memex project.
class MemexProjectItem::BulkUpdater
  extend T::Sig
  include GitHub::Memoizer

  # Public: Update many items in a Memex project.
  #
  # item_ids - the database IDs of MemexProjectItem records to change
  # item_params - an Array of change Hashes, each with the following keys:
  #   :id - the MemexProjectItem ID this change applies to
  #   :memex_project_column_values - an Array of Hashes with the following keys:
  #     :memex_project_column_id - String or Integer identifier for the column to change, e.g., "Title" or the
  #                                database ID of a user-defined column
  #     :value - a String or Hash that describes the new value the specified item should get for this column, e.g.,
  #              `{ title: "New title" }` for the "Title" column or `"some string"` for a text column
  # memex_project - the MemexProject the items belong to
  # user - the User making the changes
  # notify_channel - Boolean indicating whether a websocket message should be sent after the bulk update is complete
  #
  # Returns a Result object.
  sig do
    params(
      item_ids: T::Array[T.any(String, Integer)],
      item_params: T::Array[T::Hash[T.any(String, Symbol), T.untyped]],
      memex_project: MemexProject,
      user: User,
      notify_channel: T::Boolean
    ).returns(Result)
  end
  def self.perform(item_ids:, item_params:, memex_project:, user:, notify_channel: true)
    new(
      item_ids: item_ids,
      item_params: item_params,
      memex_project: memex_project,
      user: user,
      notify_channel: notify_channel,
    ).perform
  end

  class Error
    extend T::Sig

    sig { params(message: String, memex_project_item_id: Integer).void }
    def initialize(message:, memex_project_item_id:)
      @message = message
      @memex_project_item_id = memex_project_item_id
    end

    sig { returns(String) }
    attr_reader :message

    sig { returns(Integer) }
    attr_reader :memex_project_item_id

    def to_h
      # Keep in sync with `BulkUpdateError` in ui/packages/memex/src/client/api/memex-items/contracts.ts
      { memexProjectItemId: memex_project_item_id, message: message }
    end

    def as_json(*)
      to_h
    end
  end

  class Result
    extend T::Sig

    sig do
      params(
        items: T::Array[MemexProjectItem],
        success: T::Boolean,
        errors: T::Array[Error],
        total_updated_items: Integer
      ).void
    end
    def initialize(items:, success:, errors:, total_updated_items:)
      @items = items
      @success = success
      @errors = errors
      @total_updated_items = total_updated_items
    end

    sig { returns(T::Array[MemexProjectItem]) }
    attr_reader :items

    # Public: How many items in the Memex project were successfully updated.
    sig { returns(Integer) }
    attr_reader :total_updated_items

    # Public: Were all the updates made successfully?
    sig { returns(T::Boolean) }
    def success?
      @success
    end

    # Public: A which Memex project items failed to update, if any, and the human-readable error message about why
    # the update failed.
    sig { returns(T::Array[Error]) }
    attr_reader :errors

    def total_failed_items
      errors.uniq(&:memex_project_item_id).size
    end
  end

  sig do
    params(
      item_ids: T::Array[T.any(String, Integer)],
      item_params: T::Array[T::Hash[T.any(String, Symbol), T.untyped]],
      memex_project: MemexProject,
      user: User,
      notify_channel: T::Boolean
    ).void
  end
  def initialize(item_ids:, item_params:, memex_project:, user:, notify_channel:)
    @item_ids = item_ids
    @item_params = item_params
    @memex_project = memex_project
    @user = user
    @notify_channel = notify_channel
    @success = T.let(true, T::Boolean)
    @errors = T.let([], T::Array[Error])
    @total_updated = 0
  end

  sig { returns(Result) }
  def perform
    GitHub.dogstats.time("memex.update_bulk") do
      items.each { |item| update_memex_project_item(item) }
      notify_memex_channel if notify_channel?
      Result.new(items: items, success: success?, errors: errors, total_updated_items: total_updated)
    end
  end

  private

  sig { returns(T::Array[T.any(String, Integer)]) }
  attr_reader :item_ids

  sig { returns(T::Array[T::Hash[T.any(String, Symbol), T.untyped]]) }
  attr_reader :item_params

  sig { returns(MemexProject) }
  attr_reader :memex_project

  sig { returns(User) }
  attr_reader :user

  sig { returns(T::Array[Error]) }
  attr_reader :errors

  sig { returns(Integer) }
  attr_reader :total_updated

  sig { returns(T::Boolean) }
  def notify_channel?
    @notify_channel
  end

  sig { returns(T::Boolean) }
  def success?
    @success
  end

  sig { params(item: MemexProjectItem).void }
  def update_memex_project_item(item)
    column_values_by_item_id[item.id].each do |update|
      value = update[:value]
      column = memex_project.find_column_by_name_or_id(update[:memex_project_column_id])

      MemexProjectItem.throttle_writes_with_retry do
        if item.set_column_value(column, value, user)
          @total_updated += 1
        else
          errors << Error.new(memex_project_item_id: T.must(item.id), message: item.errors.full_messages.to_sentence)
          @success = false
        end
      end
    end
  end

  sig { void }
  def notify_memex_channel
    # Keep in sync with `isValidBulkUpdateEventShape()` in ui/packages/memex/src/client/helpers/alive.ts
    # See also allowed fields in SocketMessageData in ui/packages/memex/src/client/api/SocketMessage/contracts.ts
    data = {
      bulkUpdateSuccess: success?,
      actor: { id: user.id },
      bulkUpdateErrors: errors.map(&:to_h),
    }

    memex_project.notify_memex_channel(data)
  end

  memoize def items
    ActiveRecord::Base.connected_to(role: :reading) do
      memex_project.memex_project_items.includes(:content, :memex_project_column_values).where(id: item_ids)
        .order(id: :asc).to_a
    end
  end

  memoize def column_values_by_item_id
    item_params.each_with_object(Hash.new { |h, k| h[k] = [] }) do |item_params, hash|
      key = item_params[:id]
      value = item_params[:memex_project_column_values] || []
      hash[key] = value
    end
  end
end
