# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Turboghas
      # The summary processor takes the nightly committer metrics emitted by Turboghas and emits
      # a ratio of active committers to purchased committers.
      # This allows us to identify customers whos committer counts are dropping away from the amount they purchased
      # unexpectedly.
      class SummaryProcessor < BaseProcessor
        DEFAULT_GROUP_ID = "turboghas_summary_processor"
        DEFAULT_SUBSCRIBE_TO = /turboghas\.v0\.Summary\Z/

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

        # Public: Configure the Hydro processor
        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
        end

        def batching?
          true
        end

        # Public: Process a single Hydro message
        #
        # message - The Hydro message to process
        #
        # Returns nothing
        def process_message(message)
          summary = Hydro::Schemas::Turboghas::V0::Summary.new(**message.value)

          return unless %w(User Business).include?(summary.entity_type)

          entity = summary.entity_type.constantize.find_by(id: summary.entity_id)

          return if entity.nil?
          return unless entity.advanced_security_purchased?
          return if entity.advanced_security_metered_for_entity?

          license = entity.advanced_security_license

          return if license.unlimited_seats?

          ratio = summary.active_committers.to_f / license.seats.to_f

          GitHub.logger.info("emitting advanced security usage", {
            "entity_id": summary.entity_id,
            "entity_type": summary.entity_type,
            "ratio": ratio.truncate(2),
            "active_committers": summary.active_committers,
            "maximum_committers": summary.maximum_committers,
            "seats": license.seats,
          })

          GitHub.dogstats.distribution("advanced_security.usage", ratio)
        end
      end
    end
  end
end
