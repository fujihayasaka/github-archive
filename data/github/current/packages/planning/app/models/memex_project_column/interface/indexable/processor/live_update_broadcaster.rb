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
