# typed: true
# frozen_string_literal: true

require "lz4-ruby"
require "msgpack"

module Stratocaster::Indexers
  class MysqlIndexer
    autoload :Store, "stratocaster/indexers/mysql_indexer/store"

    class NotPipelining < StandardError
    end

    # Creates an instance of the indexer using the default the
    # default MysqlIndexer::Store
    def self.create(options = {})
      new(Store.create, options)
    end

    # default number of timelines that can be written to at once
    DEFAULT_BATCH_SIZE = 10

    SERIALIZER = Coders.compose(MessagePack, Coders::LZ4, default: [], errors: LZ4Internal::Error) do |e, value|
      # We can't do anything with bad data except report it
      # and wait for it to be overwritten in future.
      Failbot.report(e, app: "github-non-user-facing", value: value)
    end

    attr_reader :store

    def initialize(store, options = {})
      @store      = store
      @per_page   = options[:per_page]   || Stratocaster::DEFAULT_PAGE_SIZE
      @max        = options[:max]        || Stratocaster::DEFAULT_INDEX_SIZE
      @batch_size = options[:batch_size] || DEFAULT_BATCH_SIZE
      @id_field   = options[:id]         || :id
    end

    # Public
    #
    # Returns the ids stored in the value. Raises an error
    #
    def ids(key)
      res = current_values([key]).first
    end

    # Public
    #
    # Inserts the implicit @event_id in the given keys in batches of @batch_size.
    # Raises NotPipelining if this is not called inside a `with` block (i.e.
    # there's no @event_id contextualizing the operation)
    #
    def insert(*keys)
      if pipelining?
        keys.each_slice(@batch_size) do |batch|
          updated_values = current_values(batch).map do |values|
            SERIALIZER.dump(values.unshift(@current_id).slice(0, @max))
          end

          throttle do
            @store.mset(batch.zip(updated_values))
          end
        end
      else
        raise NotPipelining.new("pipelining should always be applied")
      end
    end

    # Public
    #
    # Receives a batch of updates in the format of:
    # { index_key: [event_ids], ....}
    # Loads the index_key's and merges [event_ids] onto the front of each feed.
    # Each feed is checked for duplicates and if no changes are made it's
    # ejected from the batch and not updated in the database.
    #
    def bulk_insert(updates)
      updates.keys.each_slice(@batch_size) do |keys|
        GitHub.dogstats.count("stratocaster_timeline_updates_processor.batches_count", keys.length)

        # The list of updated feeds should be in the format of:
        # [[index_key, feed], [index_key, feed]]
        updated_feeds = []
        throttle do
          current_values(keys).each_with_index do |feed, index|
            index_key = keys[index]
            index_updates = updates[index_key]

            GitHub.logger.info({
              "gh.stratocaster.processor.index" => index_key,
              "gh.stratocaster.processor.index_updates" => index_updates,
            })

            GitHub.dogstats.count("stratocaster_timeline_updates_processor.index_updates_count", index_updates.length)

            feed = merge_updates(index_key, feed, index_updates)
            updated_feeds.push([index_key, SERIALIZER.dump(feed.slice(0, @max))])
          end

          @store.mset(updated_feeds)
        end
      end
    end

    def merge_updates(index_key, feed, updates)
      to_be_added = updates - feed
      GitHub.dogstats.increment("stratocaster.mysql_indexer.merge_updates", tags: ["results:#{to_be_added.empty? ? "not_found" : "found"}"])

      unless to_be_added.empty?
        GitHub.logger.info({
          "gh.stratocaster.processor.index" => index_key,
          "gh.stratocaster.update_differences" => to_be_added,
          "gh.stratocaster.processor.updates" => updates,
        })
      end

      feed.unshift(*to_be_added)
    end

    # Public
    #
    # Deletes the given keys in batches of @batch_size.
    #
    def drop(*keys)
      keys.each_slice(@batch_size) do |batch|
        throttle do
          @store.mdel(batch)
        end
      end
    end

    # Public
    #
    # Removes the implicit @event_id in the given keys in batches of @batch_size.
    # Raises NotPipelining if this is not called inside a `with` block (i.e.
    # there's no @event_id contextualizing the operation)
    #
    def purge(*keys)
      if pipelining?
        keys.each_slice(@batch_size) do |batch|
          updated_values = current_values(batch).map do |values|
            values.delete(@current_id)
            SERIALIZER.dump(values)
          end

          throttle do
            @store.mset(batch.zip(updated_values))
          end
        end
      else
        raise NotPipelining.new("pipelining should always be applied")
      end
    end

    # Public
    #
    # Sets the current record as a context for pipelined write operation
    #
    def with(record)
      @current_id = record.send(@id_field)
      yield self
    ensure
      @current_id = nil
    end

    # Public
    #
    # Indicates if this indexer is setup to handle batches received from
    # the Hydro consumer
    #
    def supports_hydro?
      true
    end


    private

    def throttle
      throttler.throttle do
        yield
      end
    end

    def throttler
      ApplicationRecord::Mysql5.throttler
    end

    # Private
    #
    # Returns [[Any]] the values for the given keys, in the same order
    # For an inexisting key, the corresponding value is an empty array.
    #
    def current_values(keys)
      @store.mget(keys).value!.map do |values|
        Failbot.push(stratocaster_keys: keys, stratocaster_values: values, stratocaster_encoding: values.try(:encoding))

        SERIALIZER.load(values).slice(0, @max)
      end
    end

    # Private
    #
    # Returns whether a context exist to pipeline write operations
    #
    def pipelining?
      @current_id
    end
  end
end
