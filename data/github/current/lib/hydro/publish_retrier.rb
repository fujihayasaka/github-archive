# frozen_string_literal: true

module Hydro
  module PublishRetrier
    DEFAULT_MAX_ATTEMPTS = 5
    DEFAULT_RETRY_DELAY = 2.seconds

    extend self

    # Public: Publish a message to a hydro publisher with delayed retry attempts
    # if the result is a buffer overflow or kafka delivery error. Reports to dogstats
    # and Failbot if all attempts are exhausted or the result was an error other
    # than a buffer overflow.
    #
    # message - A Hydro message Hash to be published
    #
    # Options
    #   publisher      - Optional Hydro::Publisher instance (default: GitHub.hydro_publisher)
    #   max_attempts   - Optional number of retries to attempt (default: 5)
    #   retry_delay    - Optional amount seconds to sleep between attempts (default: 2 seconds)
    #
    # All other keyword arguments will be passed directly to the publish method
    # of the hydro publisher.
    #
    # Returns a Hydro::Sink::Result.
    def publish(message, **kwargs)
      publisher = kwargs.delete(:publisher) || GitHub.hydro_publisher
      max_attempts = kwargs.delete(:max_attempts) || DEFAULT_MAX_ATTEMPTS
      retry_delay = kwargs.delete(:retry_delay) || DEFAULT_RETRY_DELAY

      attempts = 0

      begin
        result = publisher.publish(message, **kwargs)
        raise(result.error) unless result.success?
      rescue Hydro::Sink::Error, Kafka::DeliveryFailed => e
        attempts += 1
        if retry_publish_on?(e, attempts, max_attempts)
          report_retry(kwargs[:schema])
          sleep retry_delay
          retry
        end
      end

      report_error(result.error, kwargs[:schema]) if result.error

      result
    end

    private

    # Internal: Report retrying publishing due to buffer overflow error.
    #
    # schema - The Hydro schema for the published message
    #
    # Returns nothing
    def report_retry(schema)
      GitHub.dogstats.increment(
        "hydro.publish_retrier.publish_retry",
        tags: ["schema:#{schema}"]
      )
    end

    # Internal: Report Hydro message publishing failures.
    #
    # error  - A Hydro exception
    # schema - The Hydro schema for the published message
    #
    # Returns nothing
    def report_error(error, schema)
      GitHub.dogstats.increment(
        "hydro_client.publish_error",
        tags: [
          "schema:#{schema}",
          "error:#{error.class.name.underscore}",
        ]
      )

      GitHub.report_hydro_error(error, {
        schema: schema
      })
    end

    def retry_publish_on?(error, tries, max_attempts)
      (
        error.kind_of?(Hydro::Sink::BufferOverflow) || error.kind_of?(Kafka::DeliveryFailed)
      ) && tries < max_attempts
    end
  end
end
