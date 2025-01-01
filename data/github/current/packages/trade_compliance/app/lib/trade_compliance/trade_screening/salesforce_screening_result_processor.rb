# typed: true
# frozen_string_literal: true

module TradeCompliance::TradeScreening
  class SalesforceScreeningResultProcessor < GitHub::StreamProcessors::BaseProcessor
    class ProcessingError < StandardError; end
    class UpsertError < StandardError; end

    DEFAULT_GROUP_ID = "github-#{Rails.env}-salesforce_screening_result_processor"
    DEFAULT_SUBSCRIBE_TO = /github\.trade_screening\.v0\.SalesforceScreeningResult\Z/

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
    end

    # Public: Process a single Hydro message
    #
    # message - The Hydro message to process
    #
    # Returns nothing
    def process_message(message)
      account_ids = message.value[:enterprise_account_ids]
      screening_status = message.value[:status]
      request_time = message.value[:request_time]

      return if account_ids.empty?
      return if screening_status.blank?
      return if request_time.nil?

      screening_status = screening_status.parameterize.underscore
      unless AccountScreeningProfile::VALID_SDN_STATUSES.include?(screening_status.to_sym)
        Failbot.report(ProcessingError.new("Invalid screening status #{screening_status} for account #{account_ids.to_sentence}"))
        return
      end

      request_time = Time.at(request_time[:seconds], request_time[:nanos], :nanosecond)

      account_ids.each do |account_id|
        enterprise_account = Business.find_by(id: account_id)
        next unless enterprise_account

        screening_record = enterprise_account.trade_screening_record
        if screening_record.last_trade_screen_date &&
          screening_record.last_trade_screen_date >= request_time
          next
        end

        attrs_to_update = { last_trade_screen_date: request_time, msft_trade_screening_status: screening_status }
        unless screening_record.persisted?
          attrs_to_update = attrs_to_update.merge({
            city: "",
            country_code: "",
            address1: "",
            address2: "",
            postal_code: "",
            region: "",
          })
        end

        with_write do
          unless screening_record.update(attrs_to_update)
            Failbot.report(
              UpsertError.new(
                "Failed to save trade screening record for account #{account_id}. "\
                "Error: #{screening_record.errors.full_messages.to_sentence}"
              )
            )
          end
        end
      end
    end
  end
end
