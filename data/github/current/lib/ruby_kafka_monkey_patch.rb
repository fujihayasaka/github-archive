# typed: false
# frozen_string_literal: true

# This monkey patch configures the ruby-kafka logger to log messages but skip
# the message: "There are no partitions to fetch from, sleeping for #{backoff}s" when running
# in an enterprise environment.
# TODO: Remove this monkey patch when the ruby-kafka library is replaced
module RubyKafkaLoggingMonkeyPatch
  def info(message, *tags)
    super(message, *tags) unless message.include?("There are no partitions to fetch from") && GitHub.enterprise?
  end
end

class Kafka::TaggedLogger
  prepend RubyKafkaLoggingMonkeyPatch
end
