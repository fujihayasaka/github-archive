# typed: true
# frozen_string_literal: true

# A subscriber object intended to be used with ActiveSupport::Notifications.subscribe.
# It passes the SQL queries to specified checker.
#
module Instrumentation
  class QuerySubscriber
    def initialize(checkers: [])
      @checkers = checkers
    end

    def call(event, start, ending, notifier_id, payload)
      return unless @checkers.size > 0

      return if payload[:sql].blank?

      connection = payload.fetch(:connection)
      connection_class = connection.connection_class

      @checkers.each do |checker|
        checker.check(queries: [payload[:sql]], connection_class: connection_class)
      end
    end
  end
end
