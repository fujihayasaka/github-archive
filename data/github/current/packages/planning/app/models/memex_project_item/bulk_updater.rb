# typed: true
# frozen_string_literal: true

# Public: Service model to perform many changes at once to different items in a Memex project.
class MemexProjectItem::BulkUpdater
  include GitHub::Memoizer

  PROGRESS_MESSAGE_TYPE = "project_items_bulk_update_progress"
  COMPLETION_MESSAGE_TYPE = "project_items_bulk_update_complete"

  # Encapsulates instructions for how to update the value of a particular field.
  class FieldValueUpdate < T::Struct
    # Either the database ID (e.g. 123) or the synthetic ID (e.g. "Assignees") of a `MemexProjectColumn` object
    const :field_id, T.any(String, Integer)

    # The new value to set for the field. The specific type used here at runtime depends on the field data type.
    const :value, T.untyped # rubocop:disable Sorbet/ForbidUntypedStructProps

    # The `MemexProjectColumn::Field::Base` object that corresponds to the `field_id` above.
    # This value is typically initialized as `nil` and then populated internally by `BulkUpdater#hydrate_requests!`.
    prop :field, T.nilable(MemexProjectColumn::Field::Base)
  end

  # Encapsulates a request to update a set of field values for a particular item.
  class UpdateRequest < T::Struct
    # Database ID of a `MemexProjectItem` object.
    const :item_id, Integer

    # A list of updates to apply to the item.
    const :field_value_updates, T::Array[FieldValueUpdate]

    # The `MemexProjectItem` object that corresponds to the `item_id` above.
    # This value is typically initialized as `nil` and then populated internally by `BulkUpdater#hydrate_requests!.
    prop :item, T.nilable(MemexProjectItem)

    # Constructs an `UpdateRequest` from a loosely-typed Hash of parameters.
    #
    # @param params - A Hash shaped like:
    #
    #   {
    #     id: ,
    #     memex_project_column_values: [
    #       {
    #         memex_project_column_id: ,
    #         value:
    #       },
    #       ...
    #     ]
    #   }
    sig { params(params: T.any(ActionController::Parameters, T::Hash[Symbol, T.untyped])).returns(UpdateRequest) }
    def self.build(params)
      new(
        item_id: params[:id],
        field_value_updates: params[:memex_project_column_values].map do |update|
          MemexProjectItem::BulkUpdater::FieldValueUpdate.new(
            field_id: update[:memex_project_column_id],
            value: update[:value]
          )
        end
      )
    end
  end

  # Public: Update many items in a Memex project.
  #
  # requests - A list of updates that should all be applied by the `perform` method.
  # memex_project - the MemexProject the items belong to
  # user - the User making the changes
  # notify_channel - Boolean indicating whether a websocket message should be sent after the bulk update is complete
  #
  # Returns a Result object.
  sig do
    params(requests: T::Array[UpdateRequest], memex_project: MemexProject, user: User, notify_channel: T::Boolean)
    .returns(Result)
  end
  def self.perform(requests:, memex_project:, user:, notify_channel: true)
    new(
      requests:,
      memex_project:,
      user:,
      notify_channel:,
    ).perform
  end

  class Error
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
    sig do
      params(
        items: T::Array[MemexProjectItem],
        success: T::Boolean,
        errors: T::Array[Error],
        total_updated_items: Integer,
        elasticsearch_result: T.nilable(MemexProjectColumn::Interface::Writeable::PartialResult),
      ).void
    end
    def initialize(items:, success:, errors:, total_updated_items:, elasticsearch_result:)
      @items = items
      @success = success
      @errors = errors
      @total_updated_items = total_updated_items
      @elasticsearch_result = elasticsearch_result
    end

    sig { returns(T::Array[MemexProjectItem]) }
    attr_reader :items

    # Public: How many items in the Memex project were successfully updated.
    sig { returns(Integer) }
    attr_reader :total_updated_items

    sig { returns(T.nilable(MemexProjectColumn::Interface::Writeable::PartialResult)) }
    attr_reader :elasticsearch_result

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
      requests: T::Array[UpdateRequest],
      memex_project: MemexProject,
      user: User,
      notify_channel: T::Boolean
    ).void
  end
  def initialize(requests:, memex_project:, user:, notify_channel:)
    @requests = requests
    @memex_project = memex_project
    @user = user
    @notify_channel = notify_channel

    hydrate_requests!
  end

  sig { returns(Result) }
  def perform
    GitHub.dogstats.time("memex.update_bulk") do
      total_updated_items, errors = update_project_items_in_mysql!
      elasticsearch_result = update_project_items_in_elasticsearch!

      result = Result.new(
        items: @requests.map(&:item).compact,
        success: errors.empty?,
        errors:,
        total_updated_items:,
        elasticsearch_result:,
      )

      notify_clients_of_completion!(result) if @notify_channel

      result
    end
  end

  private

  sig { returns([Integer, T::Array[Error]]) }
  def update_project_items_in_mysql!
    updated = 0
    errors = T.let([], T::Array[Error])

    @requests.each do |request|
      next unless request.item
      item = T.must(request.item)

      request.field_value_updates.each do |update|
        next unless update.field

        MemexProjectItem.throttle_writes_with_retry do
          if item.set_column_value(update.field, update.value, @user)
            updated += 1
          else
            errors << Error.new(
              memex_project_item_id: request.item_id,
              message: item.errors.full_messages.to_sentence
            )
          end
        end
      end

      # Arbitrarily, we say that updates to MySQL represent 80% of the total progress of the bulk update;
      # the remaining 20% comes from updates to Elasticsearch.
      #
      # This intentionally ignores requests that we short-circuit because we couldn't retrieve the associated item
      # from the database: those should be rare, and the progress they represent is negligible.
      progress = ((updated + errors.length).to_f / @requests.length * 80).round

      notify_clients_of_progress!(progress) if @notify_channel
    end

    [updated, errors]
  end

  sig { returns(T.nilable(MemexProjectColumn::Interface::Writeable::PartialResult)) }
  def update_project_items_in_elasticsearch!
    bulk_update_actions = @requests.each_with_object([]) do |request, acc|
      item = T.must(request.item)
      next unless item.errors.blank?
      request.field_value_updates.each do |u|
        action = T.must(u.field).elasticsearch_bulk_update_action(item)
        acc << action if action
      end
    end

    result = MemexProjectItem.bulk_update_elasticsearch(bulk_update_actions)

    # We consider the bulk update complete once we've attempted a write to Elasticsearch
    # (and regardless of the outcome).
    notify_clients_of_progress!(100) if @notify_channel

    result
  end

  # @param percentage Percentage completion of the bulk update as an integer between 0 and 100 inclusive.
  sig { params(percentage: Integer).void }
  def notify_clients_of_progress!(percentage)
    @memex_project.notify_memex_channel({
      # Keep in sync with `isValidBulkUpdateProgressEvent()` in ui/packages/memex/src/client/helpers/alive.ts
      # See also allowed fields in SocketMessageData in ui/packages/memex/src/client/api/SocketMessage/contracts.ts
      type: PROGRESS_MESSAGE_TYPE,
      requestId: GitHub.context[:request_id],
      actor: { id: @user.id },
      percentage:
    })
  end

  sig { params(result: Result).void }
  def notify_clients_of_completion!(result)
    @memex_project.notify_memex_channel({
      # Keep in sync with `isValidBulkUpdateCompleteEvent()` in ui/packages/memex/src/client/helpers/alive.ts
      # See also allowed fields in SocketMessageData in ui/packages/memex/src/client/api/SocketMessage/contracts.ts
      type: COMPLETION_MESSAGE_TYPE,
      requestId: GitHub.context[:request_id],
      actor: { id: @user.id },
      bulkUpdateSuccess: result.success?,
      bulkUpdateErrors: result.errors.map(&:to_h),
      invalidateQueryCache: result.elasticsearch_result.try(:succeeded?),
    })
  end

  def hydrate_requests!
    item_by_id = ActiveRecord::Base.connected_to(role: :reading) do
      @memex_project
        .memex_project_items
        .includes(:content, :memex_project_column_values)
        .where(id: @requests.map(&:item_id))
        .index_by(&:id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    fields_by_id = ActiveRecord::Base.connected_to(role: :reading) do
      @requests.flat_map { |r| r.field_value_updates.map(&:field_id) }.each_with_object({}) do |field_id, result|
        column = @memex_project.find_column_by_name_or_id(field_id)
        next unless column
        field = column.to_field
        GitHub::PrefillAssociations.prefill_associations(field, :memex_project, available_records: [@memex_project])
        result[field_id] = field
      end
    end

    @requests.each do |request|
      request.item = item_by_id[request.item_id]
      request.field_value_updates.each do |update|
        update.field = fields_by_id[update.field_id]
      end
    end
  end
end
