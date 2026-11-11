# frozen_string_literal: true

# A processor meant to be used in GitHub Enterprise Server, where we use a
# single consumer process to listen to all topics.
# This class gets a mapping of topic regex -> handler class, which other
# consumer classes subscribe themselves to via
# `ApplicationProcessor#subscribe_to`, it then uses `.topics` to subscribe a
# consumer to all of those topics in a dedicated enterprise hydro startup
# script.
class MultiTopicProcessor < ApplicationProcessor
  group_name "enterprise"

  def self.subscriptions
    @subscriptions ||= {}
  end

  def self.multi_subscribe(topic, klass)
    subscriptions[topic] ||= Set.new
    subscriptions[topic] << klass
  end

  def self.handlers_for(topic)
    # we `#subscribe_to` a regex pattern, find the entries that match and grab
    # the value (find returns an array with [key, value])
    subscriptions.filter { |key, _| key.match?(topic) }.flat_map { |_, v| v.to_a }
  end

  def dead_letter_errors(topic)
    handlers = self.class.handlers_for(topic)
    custom_errors = {}
    handlers.map do |handler|
      errors = handler.respond_to?(:dead_letter_errors) ? handler.dead_letter_errors : {}
      custom_errors.merge!(errors)
    end.uniq

    DEAD_LETTER_ERRORS.merge(custom_errors)
  end

  def topics
    self.class.subscriptions.keys
  end

  def process_message(message)
    topic = message.topic
    handlers = self.class.handlers_for(topic)
    return Dependabot::Logger.warn("No handler registered for #{topic}, ignoring this message") if handlers.blank?

    MetricsClient.increment("consumer.process_message.started", tags: tags(message))

    handlers.each { |h| h.run(message) }

    MetricsClient.increment("consumer.process_message.completed", tags: tags(message))
  end
end
