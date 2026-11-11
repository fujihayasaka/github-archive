# typed: strict
# frozen_string_literal: true

# Build a unique set of memex_project_ids from the results and send a live
# update message to each of them
# The timestamp provided should represent the time at which the update was stored in the SQL store. This is used by
# the front end to determine if the update is newer than the most recent update made there, and should be fresh.
module MemexProjectColumn::Interface::Indexable::Processor
  class LiveUpdateBroadcaster
    LIVE_UPDATE_BASE_DATA = T.let(
      { type: "memex_item_denormalized_to_elasticsearch" },
      T::Hash[Symbol, String]
    )

    # Type alias for the per-project item descriptors carried in the
    # `items:` field of the websocket payload. Matches the shape produced by
    # `#item_ids_for_project` and consumed by `BroadcastDenormalizedLiveUpdateJob`.
    ItemDescriptor = T.type_alias { T::Hash[Symbol, T.any(Integer, String)] }

    sig do
      params(
        memex_project_ids: T::Array[Integer],
        timestamp: Integer,
        source_topic: T.nilable(String),
        updated_models: T.nilable(T::Array[Base::ObjectWithGlobalRelayId]),
        request_id: T.nilable(String),
      ).void
    end
    def self.call(memex_project_ids:, timestamp:, source_topic: nil, updated_models: nil, request_id: nil)
      new(memex_project_ids:, timestamp:, source_topic:, updated_models:, request_id:).call
    end

    # Scalar-only entry point used by the delayed `BroadcastDenormalizedLiveUpdateJob`.
    # `updated_models` (ActiveRecord objects) are pre-resolved by the caller into
    # `model_gids` (non-item GIDs) and `items_by_project` (per-project item id/gid
    # tuples) so that the job payload can be serialized to the queue without
    # carrying AR object references. See `BroadcastDenormalizedLiveUpdateJob` for
    # the enqueue-side companion.
    sig do
      params(
        memex_project_ids: T::Array[Integer],
        timestamp: Integer,
        source_topic: T.nilable(String),
        model_gids: T::Array[String],
        items_by_project: T::Hash[Integer, T::Array[ItemDescriptor]],
        request_id: T.nilable(String),
      ).void
    end
    def self.broadcast_resolved(memex_project_ids:, timestamp:, source_topic: nil, model_gids: [], items_by_project: {}, request_id: nil)
      ActiveRecord::Base.connected_to(role: :reading) do
        MemexProject.where(id: memex_project_ids).each do |memex_project|
          payload = if memex_project.feature_flag_enabled?(:memex_live_update_gids, default: false)
            LIVE_UPDATE_BASE_DATA.merge({
              timestamp:,
              source_type: source_topic&.sub(/\Acp1-iad.ingest./, ""),
              models: model_gids,
              items: items_by_project[memex_project.id] || [],
              request_id:,
            })
          else
            LIVE_UPDATE_BASE_DATA.merge({
              timestamp:,
              request_id:,
            })
          end
          memex_project.notify_memex_channel(payload.compact)
        end
      end
    end

    # Resolves the non-item global relay IDs from an array of `updated_models`.
    # Exposed as a class method so callers preparing a payload for the delayed
    # `BroadcastDenormalizedLiveUpdateJob` can pre-extract scalars at enqueue
    # time.
    sig { params(updated_models: T::Array[Base::ObjectWithGlobalRelayId]).returns(T::Array[String]) }
    def self.extract_model_gids(updated_models)
      updated_models.filter_map do |model|
        if !model.kind_of?(MemexProjectItem) && model.respond_to?(:global_relay_id)
          T.cast(model, GitHub::Relay::GlobalIdentification).global_relay_id
        end
      end
    end

    # Resolves an `{ memex_project_id => [{id:, gid:}, ...] }` map from an
    # array of `updated_models`. Companion to `extract_model_gids` for
    # enqueue-time serialization.
    sig do
      params(updated_models: T::Array[Base::ObjectWithGlobalRelayId])
      .returns(T::Hash[Integer, T::Array[ItemDescriptor]])
    end
    def self.extract_items_by_project(updated_models)
      result = T.let({}, T::Hash[Integer, T::Array[ItemDescriptor]])
      updated_models.each do |model|
        next unless model.kind_of?(MemexProjectItem)
        project_id = T.cast(model.memex_project_id, Integer)
        (result[project_id] ||= []) << { id: model.id, gid: model.global_relay_id }
      end
      result
    end

    sig do
      params(
        memex_project_ids: T::Array[Integer],
        timestamp: Integer,
        source_topic: T.nilable(String),
        updated_models: T.nilable(T::Array[Base::ObjectWithGlobalRelayId]),
        request_id: T.nilable(String),
      ).void
    end
    def initialize(memex_project_ids:, timestamp:, source_topic: nil, updated_models: nil, request_id: nil)
      @memex_project_ids = memex_project_ids
      @timestamp = timestamp
      @source_topic = source_topic
      @updated_models = T.let(Array.wrap(updated_models), T::Array[Base::ObjectWithGlobalRelayId])
      @request_id = request_id
    end

    sig { void }
    def call
      ActiveRecord::Base.connected_to(role: :reading) do
        MemexProject
          .where(id: @memex_project_ids)
          .each { emit_socket_message_for_memex_project(_1) }
      end
    end

    sig { params(memex_project: MemexProject).void }
    private def emit_socket_message_for_memex_project(memex_project)
      payload = if memex_project.feature_flag_enabled?(:memex_live_update_gids, default: false)
        LIVE_UPDATE_BASE_DATA.merge({
          timestamp: @timestamp,
          source_type: truncated_topic,
          models: model_gids,
          items: item_ids_for_project(memex_project),
          request_id: @request_id,
        })
      else
        LIVE_UPDATE_BASE_DATA.merge({
          timestamp: @timestamp,
          request_id: @request_id
        })
      end

      memex_project.notify_memex_channel(payload.compact)
    end

    # Remove the cp1-iad.ingest. prefix from the topic name
    sig { returns(T.nilable(String)) }
    private def truncated_topic
      @source_topic&.sub(/\Acp1-iad.ingest./, "")
    end

    # Select models from updated_moodels that are not MemexProjectItems, and convert them to GraphQL IDs.
    sig { returns(T::Array[String]) }
    private def model_gids
      @updated_models.filter_map do |model|
        if !model.kind_of?(MemexProjectItem) && model.respond_to?(:global_relay_id)
          T.cast(model, GitHub::Relay::GlobalIdentification).global_relay_id
        end
      end
    end

    # Select MemexProjectItems from updated_models that belong to the given memex_project,
    # and convert them to an Array of hashes with the item's ID and GraphQL ID. We return both kinds of IDs
    # to allow clients the maximum versatility for keeping state in sync. Many Alive messages return DB IDs.
    sig { params(memex_project: MemexProject).returns(T::Array[T::Hash[Symbol, T.any(Integer, String)]]) }
    private def item_ids_for_project(memex_project)
      @updated_models.filter_map do |model|
        if model.kind_of?(MemexProjectItem) && model.memex_project_id == memex_project.id
          { id: model.id, gid: model.global_relay_id }
        end
      end
    end
  end
end
