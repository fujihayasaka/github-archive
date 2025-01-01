# typed: true
# frozen_string_literal: true

module GitHub::SQLCheckers::TableParser
  # To capture and ignore the edge case of `ON DUPLICATE KEY UPDATE` where
  # there are variable lengths of whitespaces between `KEY` and `UPDATE`,
  # we unfortunately cannot use negative lookbehinds, because Ruby does not
  # support variable length lookbehinds. Instead, we will capture the
  # preceding keyword and check if it contains `KEY` in the next step.
  OLD_REGEX = /(\sFROM|\sJOIN|UPDATE|KEY\s+UPDATE|INSERT(?:\s+INTO)?)\s+`?(\w+(?:,\s*\w+)*)`?/im
  REGEX = /(\sFROM|\sJOIN|UPDATE|KEY\s+UPDATE|INSERT(?:\s+INTO)?)\s+`?(\w+(?:,\s*\w+)*)`?(?=(?:[^']|'[^']*')*$)/im

  def self.run(sql)
    regex = if Rails.env.test? || ENV["STATEMENT_CHECKS_BETTER"] == "1" # rubocop:todo GitHub/DoNotBranchOnRailsEnv
      REGEX
    else
      OLD_REGEX
    end

    tables = sql.scan(regex).flat_map do |keyword, tables|
      next if keyword.end_with?("UPDATE") && keyword.start_with?("KEY")

      if tables.include?(",")
        tables.split(/\s*,\s*/).each(&:strip!)
      else
        tables.strip!
        tables
      end
    end.compact.uniq
    tables.reject! { |t| t.start_with?("JSON_TABLE") }

    tables - cte_names(sql)
  end

  # This regex pattern uses subexpression calls to match balanced parentheses.
  # Each CTE definition is followed by either a comma or the primary SELECT
  # statement.
  #
  # (?<cte_name>[a-z0-9_]+) - Captures the CTE name
  # (?:\s+\([a-z0-9_][a-z0-9_,\s]*\))? - Matches CTE column names, if any
  # \s+AS\s+\( - Matches " AS ("
  # (?<parens> - Named capture for balanced parentheses
  #   [^()]* - Match any character except parentheses
  #   (?: - Start non-capturing group
  #     \( - Match open parenthesis
  #     \g<parens> - Recursively call the parens pattern
  #     \) - Match close parenthesis
  #     [^()]* - Match any character except parentheses again
  #   )* - End non-capturing group, repeat zero or more times
  # ) - End named capture
  # \)\s* - End "AS (...)" clause
  # (?:,\s*|SELECT) - Comma between CTEs or primary SELECT statement
  CTE_REGEX = /(?<cte_name>[a-z0-9_]+)(?:\s+\([a-z0-9_][a-z0-9_,\s]*\))?\s+AS\s+\((?<parens>[^()]*(?:\(\g<parens>\)[^()]*)*)\)\s*(?:,\s*|SELECT)/i

  # Finds CTE (Common Table Expression) names in SQL query, if any.
  #
  # @param sql [String] The SQL query to parse
  # @return [Array<String>] Names of CTEs defined in the query
  def self.cte_names(sql)
    cte_names = []

    # Find the WITH clause
    if with_clause_match = sql.match(/\bWITH\s+(?:RECURSIVE\s+)?/im)
      start_pos = with_clause_match.end(0)
      rem = sql[start_pos..-1]

      pos = 0
      while cte_name_match = CTE_REGEX.match(rem, pos) do
        cte_name = cte_name_match[:cte_name]
        unless cte_name.nil?
          cte_names << cte_name.downcase
        end
        pos = cte_name_match.end(0)
        break if pos >= rem.length || rem[pos..-1] !~ /\s*[a-z0-9_]/i
      end
    end

    cte_names.uniq
  end
end
