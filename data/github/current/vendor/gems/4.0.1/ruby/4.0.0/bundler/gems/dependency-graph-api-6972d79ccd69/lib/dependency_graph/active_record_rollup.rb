# frozen_string_literal: true

# This file is inspired by
# https://github.com/github/github/blob/72944313c53faf19755ecc688ebe09afc37cd45e/lib/github/exceptions/active_record_rollup.rb
# We do not have a Resilient wrapper for the Trilogy client, nor do we use Sorbet typing, so that has been removed.

module DependencyGraph
  # ActiveRecordRollup responds to `rollup` which our failbot configuration uses to
  # determine the fingerprint used by Sentry issue grouping. This rollup differs from
  # the default roller by not including the backtrace in the fingerprint. Instead, it
  # uses the exception class, cause class, and error code if available.
  module ActiveRecordRollup
    @_rollup_classes = Set.new
    @_rollup_classes_skip_location = Set.new

    MYSQL_ERROR_MESSAGES = {
      1040 => "Too many connections", # ER_CON_COUNT_ERROR
      1045 => "Access denied for user", # ER_ACCESS_DENIED_ERROR
      1054 => "Unknown column", # ER_BAD_FIELD_ERROR
      1064 => "You have an error in your SQL syntax", # ER_PARSE_ERROR
      1105 => "Unknown Error", # ER_UNKNOWN_ERROR
      1135 => "Can't create a new thread", # ER_CANT_CREATE_THREAD
      1153 => "Tried to send message larger than max", # ER_NET_PACKET_TOO_LARGE
      1203 => "Resource exhausted (too many connections)", # ER_TOO_MANY_USER_CONNECTIONS
      1235 => "Unsupported operation", # ER_NOT_SUPPORTED_YET
      1267 => "Illegal mix of collations", # ER_CANT_AGGREGATE_2COLLATIONS
      1270 => "Illegal mix of collations", # ER_CANT_AGGREGATE_3COLLATIONS
      1271 => "Illegal mix of collations", # ER_CANT_AGGREGATE_NCOLLATIONS
      1290 => "The MySQL server is running in the wrong mode to execute this statement", # ER_OPTION_PREVENTS_STATEMENT
      1292 => "Truncated incorrect value", # ER_TRUNCATED_WRONG_VALUE;
      1366 => "Incorrect value for column", # ER_TRUNCATED_WRONG_VALUE_FOR_FIELD
      1525 => "Incorrect value", # ER_WRONG_VALUE
      1690 => "Value is out of range", # ER_DATA_OUT_OF_RANGE;
      1907 => "Query execution was interrupted, timeout exceeded", #ER_QUERY_TIMEOUT
      2002 => "Can't connect to MySQL server", # CR_CONNECTION_ERROR
      3118 => "Access denied for user. Account is locked", # ER_ACCOUNT_HAS_BEEN_LOCKED
      3854 => "Cannot convert string", # ER_CANNOT_CONVERT_STRING
      9001 => "Max connect timeout reached", # ProxySQL error code
    }.freeze

    GENERIC_ROLLUP_SIGNIFICANT_FRAME = "N/A (ActiveRecordRollup)"

    def self.generic_message(exception)
      cause = exception.cause
      return "" if !cause

      if cause.respond_to?(:error_code) && code = cause.error_code
        "MySQL error code #{code}: #{MYSQL_ERROR_MESSAGES[code] || cause.class.name} "
      else
        "#{cause.class.name} "
      end
    end

    def self.rollup_significant_frame(exception)
      return GENERIC_ROLLUP_SIGNIFICANT_FRAME if should_skip_rollup_location_frame?(exception)

      first_significant_frame(exception)
    end

    def self.should_rollup?(exception)
      @_rollup_classes.any? { |cls| exception.is_a?(cls) }
    end

    def self.should_skip_rollup_location_frame?(exception)
      cause = exception.cause

      @_rollup_classes_skip_location.any? { |cls| exception.is_a?(cls) }
    end

    def self.rollup(exception, context)
      Digest::SHA256.hexdigest(rollup_base(exception))
    end

    def self.add_rollup_class(exception, skip_frame_location: false)
      @_rollup_classes << exception
      @_rollup_classes_skip_location << exception if skip_frame_location
    end

    def self.rollup_base(exception)
      base = "#{exception.class.name}#{generic_message(exception)}"

      return base if should_skip_rollup_location_frame?(exception)

      base << first_significant_frame(exception)

      base
    end

    def self.first_significant_frame(exception)
      Rollup.first_significant_frame(exception.backtrace, scrub_root_path: Rails.root.to_s)
    end
  end
end
