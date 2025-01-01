# typed: true
# frozen_string_literal: true

# A subscriber object intended to be used with ActiveSupport::Notifications.subscribe.
# It passes the SQL queries to specified checker.
#
module Instrumentation
  class QuerySubscriber
    REMOVE_QUOTED_VALUES_REGEX = /(?<![\\])'(?:[^']|(?<=[\\])')*'/m.freeze

    def initialize(checkers: [])
      @checkers = checkers
    end

    def call(event, start, ending, notifier_id, payload)
      return unless @checkers.size > 0
      queries = remove_quoted_values_from_sql([payload[:sql].to_s])

      connection = payload.fetch(:connection)
      connection_class = connection.connection_class

      @checkers.each do |checker|
        checker.check(queries: queries, connection_class: connection_class)
      end
    end

    private

    # Replace substrings between single-quotes ('), allowing for escaped single quotes
    def remove_quoted_values_from_sql(queries)
      queries.map do |query|
        query.gsub(REMOVE_QUOTED_VALUES_REGEX, "'...'")
      end
    end
  end
end
