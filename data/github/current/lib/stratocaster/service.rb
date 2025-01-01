# typed: false
# frozen_string_literal: true

module Stratocaster
  class Service
    attr_reader :store, :index

    HYDRO_PUBLISH_RETRIES = 5
    HYDRO_PUBLISH_RETRY_DELAY = 1.second

    # This is the public end point for outsiders to access Stratocaster.
    #
    # store - A Horcrux compatible adapter for the individual Events
    #         themselves.  See Stratocaster::ActiveRecordStore.
    # index - A Stratocaster::Indexer instance.  See
    #         Stratocaster::Indexers::MysqlIndexer.
    #
    def initialize(store, index)
      @store = store
      @index = index
      @enabled = true
    end

    # Public: Gets a list of the most recent events for a given timeline.
    #
    # timeline - A String timeline name, like "user:5"
    #
    # Returns an Array of Stratocaster::Event instances.
    def events(timeline)
      event_ids = ids(timeline)

      stratocaster_events = ids_to_events(event_ids)

      # There are events in redis older than 3 months, which is the retention policy for stratocaster_events
      mismatches = event_ids.length - stratocaster_events.length
      GitHub.dogstats.count("stratocaster_events.redis_stale_events", mismatches) if mismatches > 0
      stratocaster_events
    end

    # Public: Gets a list of the most recent event IDs for a given timeline.
    #
    # timeline - A String timeline name, like "user:5"
    #
    # Returns an Array of Stratocaster::Event Integer IDs.
    def ids(timeline)
      @index.ids(timeline)
    rescue # rubocop:todo Lint/GenericRescue
      Failbot.report($!, app: "stratocaster", timeline: timeline)
      []
    end

    # Public: Loads a single Stratocaster::Event record.
    #
    # id   - Integer Stratocaster::Event ID.
    #
    # Returns a Stratocaster::Event.
    def get(id)
      @store.get(id)
    end

    # Public: Loads Stratocaster::Event records from an Array.
    #
    # ids  - Array of Stratocaster::Event IDs.
    #
    # Returns an Array of Stratocaster::Event instances.
    def ids_to_events(ids)
      @store.get_all(*ids).tap { |e| e.compact! }
    end

    def create(event)
      @store.save event
    end

    # Public: Deletes the given Stratocaster::Events.
    #
    # events_or_ids - An Array of Stratocaster::Events or IDs.
    #
    # Returns nothing.
    def delete(events_or_ids)
      @store.delete_all *events_or_ids.map do |event_or_id|
        case event_or_id
        when Integer
          event_or_id
        when Stratocaster::Event
          event_or_id.id
        else
          raise TypeError, "Expected Integer or Stratocaster::Event, got #{event_or_id.class}"
        end
      end
    end

    # Public: drops the given timelines, deleting in batches the events they contain
    # from the stratocaster_events table.
    #
    # Stratocaster::DEFAULT_INDEX_SIZE is the amount of events we select from
    # the stratocaster_events table at once, and hence it's an initial sensible
    # amount of events to be deleted in one shot. In any case, deletions are being
    # throttled.
    #
    # Returns nothing.
    def delete_timelines(*timelines)
      ids_to_delete = timelines.inject(Set.new) do |to_delete, timeline|
        to_delete += self.ids(timeline)
      end

      ids_to_delete.sort.each_slice(Stratocaster::DEFAULT_INDEX_SIZE) do |ids|
        Stratocaster::Model.throttle do
          self.delete(ids)
        end
      end

      self.clear_timelines(*timelines)
    end

    # Public: Clears the given timelines, but does not delete the event
    # records.
    #
    # *timelines - One or more String timeline names.
    #
    # Returns nothing.
    def clear_timelines(*timelines)
      @index.drop *timelines
    end

    # Public: Initializes a new Stratocaster::Event.
    #
    # attributes - Optional Hash of attributes to set.
    #
    # Returns a Stratocaster::Event.
    def build(attributes = {})
      Stratocaster::Event.new(attributes)
    end

    # Public: Builds a Stratocaster::Dispatcher for a new Event.  Does not
    # save the event yet.
    #
    # event_type - String event name in camelcase: CreateEvent.
    # *args      - One or more arguments for the specific Event type.
    #              See the type's Stratocaster::Attributes module.
    #
    # Returns a Stratocaster::Dispatcher instance.
    def dispatcher(event_type, *args)
      Stratocaster.attributes_class_for(event_type).dispatcher(self, *args)
    end

    # Public: Creates and dispatches a new Event.
    #
    # event_type - String event name in camelcase: CreateEvent.
    # *args      - One or more arguments for the specific Event type.
    #              See the type's Stratocaster::Attributes module.
    #
    # Returns a Stratocaster::Event instance.
    def trigger(event_type, *args)
      return unless @enabled
      event = dispatcher(event_type, *args).perform

      if event.present?
        Stratocaster::Fanout.new(event: event, index: @index).perform
      end

      event
    end

    # Public: Queues a background job to trigger a new Event.
    #
    # *args - One or more arguments for the specific Event type. See the type's
    #         Stratocaster::Attributes module.
    #
    # Returns nothing.
    def queue(event_type, *args)
      return unless @enabled

      ProcessEventJob.perform_later(event_type, args)
    end

    # Public: Queues a background job to trigger a new Event at a specified wait.
    #
    # wait_s - How long to wait (in seconds) before performing this job
    # *args - One or more arguments for the specific Event type. See the type's
    #         Stratocaster::Attributes module.
    #
    # Returns nothing.
    def delayed_queue(event_type, wait_s, *args)
      return unless @enabled

      ProcessEventJob.set(wait: wait_s).perform_later(event_type, args)
    end

    def publish_to_hydro
      tries = 0
      while tries < HYDRO_PUBLISH_RETRIES
        result = yield

        break if result.success?
        break unless result.error.kind_of? Hydro::Sink::BufferOverflow

        GitHub.dogstats.increment("stratocaster.hydro_publish.buffer_overflow_wait")

        # The fanout process that generates these messages can sometimes generate
        # many thousands of messages. When this happens the buffer of messages
        # may be exhausted leading to buff overflow exceptions. This is an edge
        # case and doesn't happen often but when it does we need to give the
        # buffer a chance to clear out a bit.
        sleep HYDRO_PUBLISH_RETRY_DELAY unless Rails.env.test?

        tries += 1
      end
    end

    def enabled?
      !!@enabled
    end

    def enable
      @enabled = true
    end

    # Public: Temporarily disables all stratocaster calls.
    # Any events queued to Stratocaster while disabled will
    # be dropped on the floor.
    #
    # block - (Optional) If called with a block the enabled flag will
    #         be reset to the previous value after the block has been ran.
    #
    # Returns nothing.
    def disable
      if block_given?
        begin
          @enabled_was = @enabled
          @enabled = false
          yield
        ensure
          @enabled = @enabled_was
        end
      else
        @enabled = false
      end
    end

    def inspect
      %(#<#{self.class} (#{@enabled ? :en : :dis}abled) store=#{@store.class} index=#{@index.class}>)
    end
  end
end
