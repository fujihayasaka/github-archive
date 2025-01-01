# typed: true
# frozen_string_literal: true

module Platform
  module Tracing
    module Helpers
      class NPlusOneQueries
        def self.get(mysql_calls)
          return [] unless mysql_calls

          grouped_queries = mysql_calls.group_by do |query|
            [query.backtrace.join(""), query.digested_sql]
          end.values.select { |values| values.size > 1 }
        end
      end
    end
  end
end
