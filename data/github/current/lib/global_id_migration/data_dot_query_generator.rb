# typed: true
# frozen_string_literal: true

module GlobalIdMigration
  class DataDotQueryGenerator
    def initialize(node_implementors)
      @node_implementors = node_implementors
    end

    def self.run(node_implementors)
      new(node_implementors).tap(&:run)
    end

    def run
      puts prefix
      puts nodes
      puts suffix
    end

    private

    def nodes
      nodes = ""
      @node_implementors.each_with_index do |implementor, i|
        nodes += @node_implementors[i] == @node_implementors[-1] ? "('#{implementor.graphql_name}', 0))" : "('#{implementor.graphql_name}', 0),"
      end

      nodes
    end

    def prefix
      "SELECT object_type, sum(usage) as usage_count FROM (WITH types AS (SELECT * FROM (VALUES"
    end

    def suffix
      suffix = <<~SQL
      AS types (object_type, usage))

      SELECT object_type, usage FROM types

      UNION

      SELECT field.type, count(1) from hive_hydro.hydro.graphql_query_analytics_v1_analyzed_query
      CROSS JOIN UNNEST(fields) AS field
      WHERE date(day) > (CURRENT_DATE - interval '15' DAY)
      AND date(day) < (CURRENT_DATE - interval '7' DAY)
      AND target = 'PUBLIC_SCHEMA'
      AND field.type IN (SELECT object_type FROM types)
      GROUP by 1)
      GROUP by 1 ORDER BY 2,1 ASC
      SQL

      suffix
    end
  end
end
