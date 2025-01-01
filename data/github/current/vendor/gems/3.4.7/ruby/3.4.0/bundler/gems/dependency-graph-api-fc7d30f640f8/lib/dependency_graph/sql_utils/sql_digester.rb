# frozen_string_literal: true

# Adapted from:
# https://github.com/github/github/blob/master/lib/github/sql/digester.rb

module DependencyGraph::SqlUtils
  class SqlDigester
    # Digest a SQL statement, removing strings and numbers.
    #
    # Returns a string.
    def self.digest_sql(sql, strings: true, numbers: true)
      # One time copy so we can use in string replacements afterwards
      sql = sql.dup
      # Remove any escaped quotes (\ followed by " or ')
      sql.gsub!(/\\["']/, "")
      # Replace quoted strings with " with ?
      sql.gsub!(/".*?"/, "?") if strings
      # Replace quoted strings with ' with ?
      sql.gsub!(/'.*?'/, "?") if strings
      # Replace numbers
      sql.gsub!(/\b[0-9+-][0-9a-f.xb+-]*/, "?") if numbers
      # Replace booleans
      sql.gsub!(/\bfalse\b|\btrue\b/i, "?")
      # Turn IN() clause into single ? for dynamic length lists
      sql.gsub!(/\bIN\s*\([\s\?,]*\)/, "IN ?")
      # Remove query comments for better grouping
      sql.gsub!(/\/\*.*?\*\//, "")
      # Remove backticks for column quoting
      sql.gsub!(/`(\w+)`/, "\\1")
      # Collapse whitespace
      sql.gsub!(/\s+/, " ")
      # Strip leading and trailing whitespace
      sql.strip!
      sql
    end
  end
end
