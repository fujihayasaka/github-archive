# typed: true
# frozen_string_literal: true

class CanceledQueryReporter
  class QueryDigester
    MAX_QUERY_LENGTH = 1000

    TRUNCATE_IN_CLAUSE_REGEX = Regexp.compile(%r{(?i)(in\s?)(\([^)]{50}[^),]*),[^)]+\)})
    TRUNCATE_IN_CLAUSE_COMMENT = "/* TRIMMED BY CANCELED_QUERY_REPORTER */"
    TRUNCATE_QUERY_COMMENT_TEMPLATE = "\n/* MIDDLE %s CHARACTERS TRIMMED BY CANCELED_QUERY_REPORTER */\n"

    DIGEST_QUERY_PREFIX = "SELECT STATEMENT_DIGEST"
    DIGEST_QUERY_TEMPLATE = "#{DIGEST_QUERY_PREFIX}(?)"

    MAX_EXECUTION_TIME_REGEX = Regexp.compile(%r{(?i)MAX_EXECUTION_TIME\((\d+)\)})

    def initialize(query, connection)
      @sql = query.sql
      @digest_query = query.digested_sql
      @connection = connection
    end

    def truncate
      raw_query_length = @sql.length
      return @sql if raw_query_length <= MAX_QUERY_LENGTH

      sql_with_truncated_in_clause = @sql.gsub(TRUNCATE_IN_CLAUSE_REGEX, "\\1\\2 #{TRUNCATE_IN_CLAUSE_COMMENT})")
      return sql_with_truncated_in_clause if sql_with_truncated_in_clause.length <= MAX_QUERY_LENGTH

      truncated_in_clause_query_length = sql_with_truncated_in_clause.length
      query_start = sql_with_truncated_in_clause[0..(MAX_QUERY_LENGTH / 2) - 1]
      query_comment = TRUNCATE_QUERY_COMMENT_TEMPLATE % (truncated_in_clause_query_length - MAX_QUERY_LENGTH)
      query_end = sql_with_truncated_in_clause[truncated_in_clause_query_length - (MAX_QUERY_LENGTH / 2)..]

      query_start + query_comment + query_end
    end

    def digest
      sanitized_sql = ActiveRecord::Base.sanitize_sql([DIGEST_QUERY_TEMPLATE, @sql])
      @connection.select_value(sanitized_sql)
    rescue ActiveRecord::ActiveRecordError => e
      nil
    end

    def max_execution_time
      match = @sql.match(MAX_EXECUTION_TIME_REGEX)
      return match.captures[0] if match
      nil
    end

    def digest_query?
      @sql.start_with?(DIGEST_QUERY_PREFIX)
    end
  end
end
