# frozen_string_literal: true

# Helpers for working with structured logs in tests
module LoggingHelpers
  LOG_SPLIT_REGEX = /([^=]+=("[^"]+"|[^\s]+))\s?/

  def structured_log_values(log_line)
    log_line.scan(LOG_SPLIT_REGEX).map(&:first)
  end
end
