# typed: true
# frozen_string_literal: true

require "github/sql/readonly"
require "github/stream_processors/memex/message"
require "github/stream_processors/memex/title_message"
require "github/stream_processors/memex/milestone_message"
require "github/stream_processors/memex/issue_update_milestone_message"
require "github/stream_processors/memex/milestone_update_message"
require "github/stream_processors/memex/milestone_delete_message"

module GitHub
  module StreamProcessors
    # Note: If your Hydro processor is nested within a module, you may need to
    # adjust the generated code since it is unlikely that the module name is
    # defined inside of GitHub::StreamProcessors.
    class MemexEventsProcessor < BaseProcessor
      include GitHub::Tracing

      trace_method(
        :process_column_specific_message,
        span_name: "memex_events_processor/process_column_specific_message",
        span_attribute_extractor: ->(_processor, *args, **_kwargs) do
          message = args[0]

          # Use `to_s` and `to_i` methods to convert any potential `nil` values
          # to an acceptable type for the tracing library.
          attributes = {
            "gh.hydro.msg.topic" => message.topic.to_s,
            "gh.hydro.msg.partition" => message.partition.to_s,
            "gh.hydro.msg.offset" => message.offset.to_i,
          }

          message_type = case message
          when GitHub::StreamProcessors::Memex::TitleMessage
            { "gh.memex.event_processor.message.type" => "title" }
          when GitHub::StreamProcessors::Memex::IssueUpdateMilestoneMessage
            { "gh.memex.event_processor.message.type" => "issue_update_milestone" }
          when GitHub::StreamProcessors::Memex::MilestoneUpdateMessage
            { "gh.memex.event_processor.message.type" => "milestone_update"  }
          when GitHub::StreamProcessors::Memex::MilestoneDeleteMessage
            { "gh.memex.event_processor.message.type" => "milestone_delete" }
          else
            {}
          end

          attributes.merge(message_type)
        end,
        span_annotator: -> (_processor, span, _context, result) do
          span.add_attributes({ "gh.memex.event_processor.fanout_size" => result })
        end
      )

      trace_method(
        :instrument_milestone_update_events,
        span_name: "memex_events_processor/instrument_milestone_update_events",
      )

      include TransientErrorResiliency

      DEFAULT_GROUP_ID = "memex_events_processor"

      DEFAULT_SUBSCRIBE_TO = \
        GitHub::StreamProcessors::Memex::Message::TITLE_COLUMN_TOPICS +
        GitHub::StreamProcessors::Memex::Message::MILESTONE_COLUMN_TOPICS

      # Where should dead letter messages be published when processing fails?
      DEAD_LETTER_TOPIC = "memex.v0.TitleColumnUpdate.DeadLetter"

      # Stats naming
      STATS_PREFIX = "memex.#{DEFAULT_GROUP_ID}"
      METRIC_SKIPPED_MESSAGE = "#{STATS_PREFIX}.message_skipped"
      METRIC_PROCESS_TIME = "#{STATS_PREFIX}.process_time"
      METRIC_CODE_EXECUTION_TIME = "#{STATS_PREFIX}.code_execution_time"

      UPDATE_BATCH_SIZE = 100

      # This is the timeout used for determining if a given Kafka consumer has
      # failed or quit due to e.g. a deploy. Setting it to a lower value is NOT
      # recommended if your Hydro processor interacts with the database, since
      # Freno may wait up to 30 seconds when throttling writes. Processors that
      # do not interact with a database may lower this value to allow faster
      # consumer group rebalancing during deploys and processor failures.
      #
      # See https://kafka.apache.org/documentation/#session.timeout.ms
      options[:session_timeout] = 60.seconds

      # This value must be greater than "session_timeout"
      #
      # See https://github.com/zendesk/ruby-kafka#understanding-timeouts
      options[:socket_timeout] = 65.seconds

      # When the processor starts consuming from a partition for the first time and has no committed offsets,
      # `start_from_beginning` determines if should start from the beginning of the log (i.e. the oldest available messages)
      # or the end of the log (i.e. the newest available messages).
      #
      # This is the equivalent of the java client `auto.offset.reset` consumer config.
      # See: https://kafka.apache.org/documentation/#consumerconfigs_auto.offset.reset
      options[:start_from_beginning] = false

      # Other options you may want to set...
      #
      # This will cause the Kafka consumer to wait until there is at least a
      # given number of bytes available to fetch; but the consumer will wait
      # no longer than "max_wait_time" (described below). This allows the
      # processor to wait for a large enough batch of data. The default is
      # 1 byte, meaning data will be fetched as soon as it's available. Value
      # below is for example purposes only and not a recommendation; the default
      # value of 1 should be suitable for most cases.
      # See https://kafka.apache.org/documentation/#fetch.min.bytes
      # options[:min_bytes] = 1.kilobyte
      #
      # This is the maximum amount of time the Kafka consumer will wait to
      # fetch data. The default is 500ms (0.5.seconds). Value below is for
      # example purposes only and not a recommendation; the default value of
      # 500ms should be suitable for most cases.
      # options[:max_wait_time] = 1.second
      #
      # This is the maximum amount of data that will be fetched at a time. This
      # value is specified in bytes, so the number of distinct Hydro messages
      # fetched depends on the size of those messages. The default is 1MB. You
      # may want to consider lowering this if processing each batch of messages
      # is taking more than 60 seconds in order to ensure that your processor
      # shuts down in a timely manner during deploys.
      # See https://kafka.apache.org/documentation/#max.partition.fetch.bytes
      # options[:max_bytes_per_partition] = 100.kilobytes

      # Public: Configure the Hydro processor
      def setup(**kwargs)
        options[:group_id] ||= DEFAULT_GROUP_ID
        options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

        self.dead_letter_topic = DEAD_LETTER_TOPIC
      end

      # Public: Process a single Hydro message
      #
      # consumer_message - Object<HydroConsumerMessage>
      #
      # Returns message methods as defined in GitHub::StreamProcessors::BaseProcessor
      def process_message(consumer_message)
        message = GitHub::StreamProcessors::Memex::Message.from_consumer_message(consumer_message)
        return skip(message, message.reason_to_ignore) if message.ignore?
        code_execution_start_time = GitHub::Dogstats.monotonic_time

        # Wait to make sure read replicas are up to date before fetching the
        # data that we'll use to update denormalized stores.
        wait_for_replication!(message)

        rows_affected = process_column_specific_message(message)

        return skip(message, "no matching items") if rows_affected == 0

        log_results(
          "process_message",
          message,
          rows_affected,
          code_execution_start_time: code_execution_start_time
        )
        message.success

      rescue => error # rubocop:todo Lint/GenericRescue
        log_results(
          "process_message",
          message,
          rows_affected,
          error: error,
          code_execution_start_time: code_execution_start_time
        )
        # Re-raise the error so that processing wrappers -- currently
        # TransientErrorResiliency retries and then BaseProcessor dead letter
        # publishing -- will handle the logic from here.
        raise
      end

      private

      # Propagates changes from a given message back to memex datastores, and then returns the
      # number of memex items that were actually updated.
      #
      # This intentionally does not delegate processing to the message subclasses themselves so as
      # not to force a `Memex::Message` class to understand how to handle database connection and
      # issue queries. A better alternative might be to break this class up into different
      # Processor classes altogether, but we chose not to do this as of yet to limit scope. If we
      # again expand the set of messages that this Processor consumers, then we should consider
      # making that refactor instead of expanding the cases in the switch statement below.
      #
      # Returns Integer representing number of memex items that were updated due to this message.
      def process_column_specific_message(message)
        case message
        when GitHub::StreamProcessors::Memex::TitleMessage
          process_title_message(message)
        when GitHub::StreamProcessors::Memex::IssueUpdateMilestoneMessage
          process_issue_update_milestone_message(message)
        when GitHub::StreamProcessors::Memex::MilestoneUpdateMessage
          process_milestone_update_message(message)
        when GitHub::StreamProcessors::Memex::MilestoneDeleteMessage
          process_milestone_delete_message(message)
        else
          0
        end
      end

      def process_title_message(message)
        matching_items = memex_project_items(message.repository_id, message.content_id, message.content_type)

        issue = matching_items&.first&.issue # domain-isolation-query-violation:ignore:packages/issues (SELECT)

        matching_items.each do |item|
          safe_trigger_heartbeat

          title_column, title_json = with_read do
            [item.memex_project.columns.find(&:title?), item.denormalized_title_value]
          end

          with_write do
            item.cache_title_column_value(
              title_column,
              title_json,
              message.actor,
              disable_webhook_instrumentation: message.state_change?
            )
          end

          if issue && item.issue_id == issue.id
            with_write do
              item.update( # domain-isolation-query-violation:ignore:packages/issues (SELECT)
                issue_closed_at: issue.closed_at,
                issue_created_at: issue.created_at,
                state: issue.state,
                state_reason: issue.state_reason
              )
            end
          end
        end

        matching_items.length
      end

      def process_issue_update_milestone_message(message)
        matching_items = memex_project_items(message.repository_id, message.content_id, message.content_type)

        matching_items.each do |item|
          safe_trigger_heartbeat

          milestone_column, milestone_json = with_read do
            [item.memex_project.columns.find(&:milestone?), item.denormalized_milestone_value]
          end

          # Because MemexProjectItem#set_json_value has the ability to "find or create" a new record
          # we need to make this call more resilient so that it doesn't immediately raise a
          # ActiveRecord::RecordNotUnique error which leads to a message being added to the dead letter
          # queue.
          #
          # Rather than use an upsert here this first attempt is to specifically handle the ActiveRecord::RecordNotUnique
          # error if encountered and retry the operation, hopefully mitigating the problem in a more targeted way.
          ActiveRecord::Base.connected_to(role: :writing) do
            MemexProjectColumnValue.retry_on_find_or_create_error(max_retry_count: 3) do
              item.cache_milestone_column_value(milestone_column, milestone_json, message.actor)
            end
          end
        end

        matching_items.length
      end

      def process_milestone_update_message(message)
        milestone = with_read { Milestone.find_by(id: message.milestone_id) }
        return 0 unless milestone
        return 0 unless milestone_has_references?(milestone.id)

        rows_updated = 0

        with_read do
          MemexProjectColumnValue
            .includes({ memex_project_column: :memex_project }, :memex_project_item)
            .milestone_values(milestone.id)
            .find_in_batches(batch_size: UPDATE_BATCH_SIZE) do |value_objects|

            safe_trigger_heartbeat

            ids = value_objects.map(&:id)
            previous_json_value = value_objects.first&.json_value

            denormalized_json = milestone.memex_denormalized_value

            rows_updated += with_write do
              updates = MemexProjectColumnValue.where(id: ids).update_all(json_value: denormalized_json)
              instrument_milestone_update_events(value_objects, previous_json_value)
              updates
            end
          end
        end

        rows_updated
      end

      def instrument_milestone_update_events(value_objects, previous_json_value)
        value_objects.each do |v|
          v.previous_json_value = previous_json_value
          v.disable_webhook_event_instrumentation = true
          v.instrument_update_event
        end
      end

      def process_milestone_delete_message(message)
        return 0 unless milestone_has_references?(message.milestone_id)

        rows_deleted = 0

        with_read do
          MemexProjectColumnValue
            .milestone_values(message.milestone_id)
            .in_batches(of: UPDATE_BATCH_SIZE) do |deletion_scope|

            safe_trigger_heartbeat

            rows_deleted += with_write { deletion_scope.destroy_all.length }
          end
        end

        rows_deleted
      end

      # Simple wrapper for connecting to read pool for read operations only.
      def with_read
        ActiveRecord::Base.connected_to(role: :reading) do
          yield
        end
      end

      # Simple wrapper for connecting to write for write operations only.
      def with_write
        ActiveRecord::Base.connected_to(role: :writing) do
          MemexProjectColumnValue.throttle do
            yield
          end
        end
      end

      # Fetch matching Memex project items for the id and class/content type
      # that came in via the Hydro message payload. These will be the
      # candidates for update.
      #
      # Note that we are including memex_project_columns because we know we
      # will need to access the title column and pass it into the update
      # method.
      #
      # content_id - Integer - The Issue or PullRequest id
      # content_type - String - "Issue" | "PullRequest"
      #
      # Returns Array<MemexProjectItem>
      def memex_project_items(repository_id, content_id, content_type)
        with_read do
          MemexProjectItem
            .includes(:content, memex_project: :memex_project_columns)
            .where(repository_id: repository_id, content_id: content_id, content_type: content_type)
            .select { |item| item.content.present? } # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        end
      end

      def milestone_has_references?(milestone_id)
        with_read { MemexProjectColumnValue.milestone_values(milestone_id).exists? }
      end

      # Check that read replicas are up to date and wait for them if they're
      # not. If we end up needing to wait for more than `max_wait_seconds`
      # a DataUnavailable error will be raised, and our message will be
      # published to DeadLetter.
      #
      # message - GitHub::StreamProcessors::Memex::Message object
      #
      # Raises `DataUnavailable` | Returns Integer representing number of seconds waited
      def wait_for_replication!(message)
        WaitForReplication.new(
          format_time_for_replication(message.timestamp),
          store_name: Issue.cluster_name,
          max_wait_seconds: 8
        ).wait!
      end

      # WaitForReplication expects a specific Timestamp format. This first
      # converts Rational to time, and then passes it into
      # the method that converts it into the format WaitForReplication is
      # expecting.
      #
      # timestamp - Rational - The consumer message.timestamp
      #
      # Returns Time
      def format_time_for_replication(timestamp)
        Timestamp.from_time(Time.at(timestamp))
      end

      # Provide standard tags that we want to capture from every message,
      # regardless of the metric.
      #
      # message - Object<HydroConsumerMessage>
      #
      # Returns Array
      def stats_tags_default(message)
        [
          "topic:#{message.topic}",
          "partition:#{message.partition}",
          "replay:#{replaying?}"
        ]
      end

      # Encapsulate the various logging/stats logic that we want to execute
      # anytime a message is skipped. NOTE: Since reason will be converted to tags,
      # its value should always be static in order to prevent cardinality explosions.
      # See https://git.io/J3Ej8 for more.
      #
      # message - Object<HydroConsumerMessage>
      # reason - String
      #
      # Returns nothing (of interest)
      def skip(message, reason)
        tags = ["reason:#{reason}"] + stats_tags_default(message)
        GitHub.dogstats.increment(METRIC_SKIPPED_MESSAGE, tags: tags)
        message.skip(reason)
      end

      # Handle all logging logic for message processing
      #
      # fn_name - String
      # message - Object<HydroConsumerMessage>
      # rows_affected - Integer
      # error - Object<Exception>
      #
      # Returns nothing.
      def log_results(fn_name, message, rows_affected, error: nil, code_execution_start_time: nil)
        begin
          # Do processing time instrumentation first to make sure it's as
          # accurate as possible, and wrap it in exception handling so that if
          # an error is raised we can continue with basic logging.
          unless replaying?
            instrument_processing_time(
              message,
              rows_affected,
              error: error,
              code_execution_start_time: code_execution_start_time
            )
          end
        ensure
          log_hash = {
            "code.namespace": "GitHub::StreamProcessors::MemexEventsProcessor",
            "code.function": fn_name,
            "gh.actor.id": message.actor_id,
            "gh.hydro.msg.topic": message.topic,
            "gh.repo.id": message.repository_id,
            "gh.repo.name": message.repository_name,
            "gh.issue.id": message.issue_id,
            "gh.hydro.msg.timestamp": message.timestamp,
            "gh.hydro.consumer.replay": replaying?
          }
          if error
            Failbot.report(error, **log_hash)
            GitHub.logger.error(error, **log_hash)
          else
            GitHub.logger.info(
              "#{log_hash["code.function"]} successfully processed #{rows_affected} items",
              **log_hash
            )
          end
        end
      end

      # Log how long it took for a message to process all the way through to
      # success or error and send to stats service with relevant tags.
      #
      # message - Object<HydroConsumerMessage>
      # rows_affected - Integer
      # error - Object<Exception>
      #
      # Returns nothing.
      def instrument_processing_time(message, rows_affected, error: nil, code_execution_start_time: nil)
        start_time = Time.at(message.timestamp)
        result = error ? "error" : "success"
        tags = stats_tags_default(message) << "result:#{result}"
        tags << "fanout:#{fanout_size(rows_affected)}" if rows_affected
        tags << "error:#{error.class.name.demodulize.underscore}" if error
        GitHub.dogstats.timing_since(METRIC_PROCESS_TIME, start_time, tags: tags)

        if code_execution_start_time
          GitHub.dogstats.timing_since(METRIC_CODE_EXECUTION_TIME, code_execution_start_time, tags: tags)
        end
      end

      # Return fanout tag parameters associated with how many project items
      # were matched for a given message. This will help contextualize
      # processing time and other metrics.
      #
      # count - Integer
      #
      # Return String
      def fanout_size(count)
        case
        when count < 5
          "small"
        when count >= 10
          "large"
        else
          "medium"
        end
      end

      # Publish a dead letter message when an error is encountered if
      # a dead letter topic is configured. See source in BaseProcessor.rb
      #
      # This will publish a `github.v1.DeadLetter` message to the configured
      # topic whenever we return message.error from #process_message.
      #
      # message - The Hydro::Source::Message that could not be processed
      # error   - The error that was raised
      #
      # Returns nothing
      def publish_dead_letter_message(message, error)
        return unless dead_letter_topic
        message = GitHub::StreamProcessors::Memex::Message.new(message)

        payload = {
          envelope: message.envelope,
          payload: JSON.dump(message.value),
          retries: message.retries + 1,
          error_class: error.class.name,
          error_message: error.message,
        }

        # Get a publication key for future identification of outdated messages
        # eligible for skipping during times of lag.
        key = publication_key(message)

        Hydro::PublishRetrier.publish(
          payload,
          schema: "github.v1.DeadLetter",
          topic: dead_letter_topic,
          key: key,
        )

        log_dead_letter(message, error, message.retries + 1)
      end

      # Get a unique key for identifying "duplicate" messages in Kafka so that
      # older ones can be discarded in favor of newer ones. Note that this does
      # not need to be truly unique per topic/event type because every time we
      # process a message for a given issue or pr we refresh with the latest
      # data from canonical data stores.
      #
      # message - The Hydro::Consumer::Message being processed
      #
      # Returns string | nil
      def publication_key(message)
        if message.content_type && message.content_id
          "#{message.content_type}:#{message.content_id}"
        else
          nil
        end
      end

      # Log the dead letter publication. There are stats and hydro logs
      # already, but logging to Splunk lets us see this in context of other
      # messages, run some of our own ad hoc queries/stats against it, etc.
      #
      # message - The Hydro::Consumer::Message being processed
      # error - Object<Exception> The error thrown that induced dead letter
      # processing
      # retries - Integer - The number of times this message has been put back
      # onto the dead letter topic
      def log_dead_letter(message, error, retries)
        log_hash = {
          "code.namespace": "GitHub::StreamProcessors::MemexEventsProcessor",
          "code.function": "publish_dead_letter_message",
          "error.class": error.class.name,
          "gh.actor.id": message.actor_id,
          "gh.hydro.msg.topic": message.topic,
          "gh.repo.id": message.repository_id,
          "gh.repo.name": message.repository_name,
          "gh.issue.id": message.issue_id,
          "gh.hydro.msg.timestamp": message.timestamp,
          "gh.hydro.consumer.retries": retries
        }
        GitHub.logger.info(
          "Message added to #{self.dead_letter_topic} because of error: #{error.message})",
          **log_hash
        )
      end
    end
  end
end
