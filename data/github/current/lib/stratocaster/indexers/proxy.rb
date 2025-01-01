# typed: true
# frozen_string_literal: true

module Stratocaster::Indexers

  # Stratocaster::Service, uses its indexer to store and retrive the ids
  # of the events that conform any timeline. This is done by invoking operations
  # such as `insert(*timelines)`, `purge(*timelines)` and `ids(timeline)`.
  #
  # Initially, the indexer was implementing using a redis backend to store those
  # timelines, however, we now need more flexibility, and the ability to store
  # and retrieve some of those timelines from different backends (eg. Memcache and
  # MySQL)
  #
  # From the perspective of its clients (mainly the `Stratocaster::Dispatcher`,
  # and `Stratocaster::Service`) the proxy handles all the operations transparently
  # as if it was any other indexer, dealing with the logic for storing/retriving
  # data for different timelines into/from different terminal indexers
  #
  # Per operation, the timeline pattern will determine the target indexer.
  #
  # See the docs on initialize a usage example.
  #
  class Proxy

    attr_reader :indexers, :partitioner

    # default number of timelines that can be written to the logs at once
    DEFAULT_BATCH_SIZE = 20

    # Initializes a new Proxy
    #
    # Receives:
    # - indexers    - Hash<Symbol, Indexer> The terminal indexers used by this proxy.
    # - partitioner - a block containing the logic to partition a set of keys accross
    #  the different indexers. The block takes two arguments:
    #    - partitions - the hash containing the partitions that are going to be populated
    #    by the block.
    #    - timelines - a hash containing the strings corresponding to the different timelines an operation may refer to
    #    grouped by type as defined by `TimelineTypes.group`, for instance:
    #
    #         {
    #         "global"          => ["public"],
    #         "homepage_public" => ["user:1:public", "user:2:public"],
    #         "org_members"     => ["user:3:org:1"],
    #         }
    #
    # Example: Create a proxy to manage the global timeline with MemcacheD and
    # the rest with redis. We provide the `redis` and `mc` indexers and a block
    # that will partition the keys, in a way that those that are of type Stratocaster::TimelineTypes::GLOBAL
    # will be targeted to the `mc` indexer, and the rest to the `redis indexer`.
    #
    # ```
    #   indexer = Proxy.new(redis: redis_indexer, mc: memcache_indexer) do |partitions, timelines|
    #     partitions[:mc]    = timelines.slice(Stratocaster::TimelineTypes::GLOBAL)
    #     partitions[:redis] = timelines.except(Stratocaster::TimelineTypes::GLOBAL)
    #   end
    # ```
    #
    # Given the above, then this operation:
    #
    # ```
    #   event = GitHub.stratocaster.store.get(345)
    #   indexer.with(event) do |idx|
    #     idx.insert("stratocaster:public", "actor:123:public", "actor:234")
    #   end
    # ```
    #
    # Will call:
    #
    # ```
    #   memcache_indexer.with(event) |idx|
    #     memcache_indexer.insert("stratocaster_public")
    #   end
    #   redis_indexer.with(event) |idx|
    #     idx.insert("actor:123:public", "actor:234")
    #   end
    # ```
    #
    def initialize(indexers = {}, &partitioner)
      @indexers = indexers
      @partitioner = partitioner || proc { |_partitions, _timelines| nil }
    end

    # Creates a proxy with the default configuration. As it's going to be used
    # by `GitHub.stratocaster` service in production.
    #
    # See StratocasterTestOverrides#stratocaster_indexer for the test environment
    # override.
    #
    def self.default
      global_indexer = if GitHub.public_event_timeline_delayed?
        DelayedGlobalIndexer.create
      else
        GlobalIndexer.create
      end

      indexers = { org_all: MysqlIndexer.create(max: Stratocaster::OrgAllTimeline::INDEX_LENGTH),
                  global: global_indexer,
                  rest: MysqlIndexer.create  }

      Proxy.new(indexers) do |partitions, timelines|
        partitions[:org_all] = timelines.slice(Stratocaster::TimelineTypes::ORG_ALL)
        partitions[:global]  = timelines.slice(Stratocaster::TimelineTypes::GLOBAL)
        partitions[:rest]    = timelines.except(Stratocaster::TimelineTypes::GLOBAL, Stratocaster::TimelineTypes::ORG_ALL)
      end
    end

    # Public
    #
    # Inserts the implicit event, in the given timelines
    #
    # Returns nothing
    def insert(*timelines)
      each_partition(timelines) do |indexer, timelines|
        indexer.with(event) do |idx|
          flattened = flatten_values(timelines)

          flattened.each_slice(DEFAULT_BATCH_SIZE) do |keys|
            GitHub.logger.info({
              "gh.stratocaster.keys" => keys,
              "gh.stratocaster.event_time" => Time.now.to_f.to_s,
            })
          end

          if stratocaster_hydro_enabled? && indexer.supports_hydro?
            publish_to_hydro(flattened) if flattened.length > 0
          else
            idx.insert(*flattened) if flattened.length > 0
          end

          metrics.push(:insert, timelines)
        end
      end
    ensure
      metrics.flush
    end

    # Public
    #
    # Receives batches from StratocasterTimelineUpdatesProcessor in the format
    # of { index_key => [array of event_ids], ...}. The arrays of IDs need to
    # be added onto the beginning of each `index_key`. However because a batch
    # could fail in the middle and retry we need to make sure we're not inserting
    # any IDs that already exist.
    #
    # Returns nothing
    def bulk_insert(batches)
      each_partition(batches.keys) do |indexer, timelines|
        flattened = flatten_values(timelines)
        updates = batches.slice(*flattened)
        indexer.bulk_insert(updates)
        metrics.push(:bulk_insert, timelines)
      end
    ensure
      metrics.flush
    end

    # Public
    #
    # Removes the implicit event from the each of the given timelines
    #
    # Returns nothing
    def purge(*timelines)
      each_partition(timelines) do |indexer, timelines|
        indexer.with(event) do |idx|
          idx.purge(*flatten_values(timelines))
          metrics.push(:purge, timelines)
        end
      end
    ensure
      metrics.flush
    end

    # Public
    #
    # Deletes the given timelines
    #
    # Returns nothing
    def drop(*timelines)
      each_partition(timelines) do |indexer, timelines|
        indexer.drop(*flatten_values(timelines))
        metrics.push(:drop, timelines)
      end
    ensure
      metrics.flush
    end

    # Public
    #
    # Returns [String] the list of ids for the given timeline
    #
    def ids(timeline)
      ids = nil
      indexer, timeline_type = first_partition_for(timeline)

      if indexer && timeline_type && timeline
        ids = indexer.ids(timeline)
        metrics.pass_through(:ids, timeline_type, 1)
      end

      ids || []
    end

    # Public
    #
    # Creates a context based on the given event, that will be provided
    # to the terminal indexers, for performing the operations, using each indexer's
    # `with` method.
    #
    # The event is a `stratocaster_events` record, which id
    # is the one being inserted, or purged when opearations such as
    # `insert` or `purged` are called inside this method's given block:
    #
    # Example:
    #
    # ```
    #   event = GitHub.stratocaster.store.get(345)
    #   # => #<Stratocaster::Event id: 345, type: CreateEvent, sender: miguelff, repo: miguelff/foo>
    #   with(event) do |idx|
    #    # will add id: 345 to "actor:2:public" and "public" timelines
    #    idx.insert("actor:2:public", "public")
    #   end
    # ```
    #
    # Returns nothing
    def with(event)
      @event = event
      yield self
    ensure
      @event = nil
    end

    private

    # Private
    #
    # Applies a transformation to the given Hash<Symbol, [String]>, returning a
    # a single list with all the values.
    #
    # Return [String]
    #
    def flatten_values(timelines)
      timelines.values.flatten
    end

    # Private
    #
    # A given timeline can be targeted at different indexers, take as an example:
    #
    # dual_proxy = Proxy.new(mc: memcache_indexer, redis: redis_indexer) do |partitions, timelines|
    #   partitions[:mc]    = timelines
    #   partitions[:redis] = timelines
    # end
    #
    # Any write operation on a timeline needs to be applied to every indexer, however
    # if we assume the partitions are consistent, we only need to read from a single
    # partition.
    #
    # Return Array: the first partition for a given timeline, in the form
    # of a tuple [indexer, timeline_type]
    #
    def first_partition_for(timeline)
      indexer, timelines = each_partition(Array(timeline)).first
      timeline_type = timelines && timelines.keys.first
      [indexer, timeline_type]
    end

    # Private
    #
    # Distributes the timelines accross the target indexers, using the partitioner
    # given on `initialize`. To do it, it yields 0..n tuples (indexer, timelines) each
    # of which corresponds to the timelines targeted at a particular indexer.
    #
    # Returns enumerator, the partitions yielded
    #
    def each_partition(timelines)
      partitions = []

      partitions(timelines).each do |indexer_name, timelines|
        indexer = indexers.fetch(indexer_name)
        if timelines && timelines.any?
          yield(indexer, timelines) if block_given?
          partitions << [indexer, timelines]
        end
      end

      partitions.each
    end

    # Private
    #
    # Returns Hash<Symbol, Hash<String,[String]> the partitions in which the timelines
    # are distributed by the partitioner block. Each key is a symbol denoting a
    # particular indexer, each value, the timelines grouped by type.
    #
    # See TimelineTypes for how the type of a key is determined.
    #
    # Example:
    # Given the following proxy
    # ```
    #  proxy = Proxy.new(redis: redis_indexer, mc: memcache_indexer) do |partitions, timelines|
    #     partitions[:mc]    = timelines.slice(Stratocaster::TimelineTypes::GLOBAL)
    #     partitions[:redis] = timelines.except(Stratocaster::TimelineTypes::GLOBAL)
    #   end
    # ```
    # The return value for this call to #partitions, will be:
    # ```
    # proxy.partitions(["public", "user:1:public", "user:2:public", "user:3:org:1"])
    #```
    #
    # => { :mc => {"global" => ["public"]},
    #      :redis => {"homepage_public" => ["user:1:public", "user:2:public"],
    #                 "org_members"     => ["user:3:org:1"]}
    #    }
    #
    def partitions(timelines)
      partitions = {}
      timelines_by_type = Stratocaster::TimelineTypes.group(timelines)
      partitioner.call(partitions, timelines_by_type)
      partitions
    end

    # Private
    #
    # Copies individual updates to Hydro for batch processing
    #
    def publish_to_hydro(index_keys)
      index_keys.each do |index_key|
        GlobalInstrumenter.instrument(
          "stratocaster.timeline_update",
          {
            index_key: index_key,
            event_id: event.id,
          },
        )
      end

      if FeatureFlag.vexi.enabled?(:conduit_publishing, default: false)
        GlobalInstrumenter.instrument(
          "conduit.timeline_update",
          {
            actor_id: event.sender_id
          }
        )
      end
    end

    # Private
    #
    def stratocaster_hydro_enabled?
      !GitHub.enterprise? && GitHub.hydro_enabled? && Rails.env.production?
    end

    # Private
    #
    # Returns Stratocaster::Event the event set as context when calling `with`
    #
    def event
      @event
    end

    def metrics
      @metrics_buffer ||= MetricsBuffer.new
    end

    class MetricsBuffer
      attr_reader :buffer

      def initialize
        @buffer = {}
      end

      def push(operation, timelines)
        timelines.each do |timeline_type, timelines|
          buffer[operation] ||= {}
          buffer[operation][timeline_type] ||= 0
          buffer[operation][timeline_type] += timelines.size
        end
      end

      def pass_through(operation, timeline_type, count)
        GitHub.dogstats.count("stratocaster.proxy_operations", count, tags: ["operation:#{operation}", "timeline_type:#{timeline_type}"])
      end

      def flush
        buffer.each do |operation, timeline_type_counts|
          timeline_type_counts.each do |timeline_type, count|
            GitHub.dogstats.count("stratocaster.proxy_operations", count, tags: ["operation:#{operation}", "timeline_type:#{timeline_type}"])
          end
        end
        buffer.clear
      end
    end
  end
end
