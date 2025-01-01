# frozen_string_literal: true
require "failbot"

# Inspired heavily from gh/gh ( lib/github/failbot_logger.rb )
module DependencyGraph
  # This is hardcoded to match Failbot::MAXIMUM_CAUSE_DEPTH from later versions of failbot.
  MAXIMUM_CAUSE_DEPTH = 2
  # Helper to log the exceptions to Splunk with full, unredacted context
  # before it gets filtered to be sent to Sentry
  class FailbotLogger
    def log_exception(data, exception)
      DependencyGraph.logger.info(adjusted_data(data, exception))
    end

    # TODO: fix this method so it uses OTEL conventions when logging
    def adjusted_data(data, exception)
      # Ensure failbot_dg_id is always inserted in the new hash first.  Ruby
      # iterates over hashes in insertion order and we want to make sure
      # failbot_dg_id is always first, incase the message is truncated.
      adjusted_data = {}
      adjusted_data["failbot_dg_id"] = data.delete("failbot_dg_id") if data.has_key?("failbot_dg_id")

      # app at this point represents the haystack bucket / sentry project being reported too
      # GitHub::Logger has a different app that represents that app logging, ie github
      # so we need make it have a different key
      # TODO may as well rename this key to something that isn't overloaded?
      adjusted_data["failbot_app"] = data.delete("app") if data.has_key?("app")

      # Remove the stacktrace, but save off the type and value.  The stack trace
      # is generally huge and not very readable in the logs and should always be
      # in Sentry.
      data.delete("exception_detail")
      adjusted_data["exception_type"] = exception.class.name.to_s.gsub("\n", "\\n")
      adjusted_data["exception_value"] = exception.message.to_s.gsub("\n", "\\n")
      if (cause = exception.cause)
        causes = []
        depth = 0
        loop do
          causes.unshift(
            "type" => cause.class.name.to_s.gsub("\n", "\\n"),
            "value" => cause.message.to_s.gsub("\n", "\\n")
          )
          depth += 1
          break unless (cause = cause.cause)
          break if depth > MAXIMUM_CAUSE_DEPTH
        end
        adjusted_data["causes"] = causes
      end

      # Each line of a logged data to syslog is treated as its own event.
      # Therefore, we need to make sure to escape newlines and remove quotes
      # Otherwise, each line will be its own event, and be missing the rest of the context
      # This impacts backtrace values the most
      data.each do |key, value|
        adjusted_data[key] = data[key].to_s.gsub("\n", "\\n")
      end

      adjusted_data
    end
  end
end
