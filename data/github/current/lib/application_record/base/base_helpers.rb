# typed: false
# frozen_string_literal: true

require "github/throttler"

class BaseHelpers
  # Internal: A set of methods delegating throttling methods to the correct throttler instance.
  #
  # This module depends on an instance method `.connection`.
  module Helpers
    # Let's add these methods to the class and instances
    def self.included(base)
      base.extend(self)
    end

    # Public: Attempts to retry the query if the record is not unique
    #
    # on_max_retry - optional proc to call when the maximum number of retries is reached
    #
    # Returns the result of the provided block.
    def retry_on_find_or_create_error(max_retry_count: 1, on_max_retry: nil)
      retry_count = 0
      begin
        yield
      rescue ActiveRecord::RecordNotUnique
        retry_count += 1
        if retry_count > max_retry_count
          if on_max_retry.respond_to? :call
            on_max_retry.call
          else
            raise
          end
        else
          retry
        end
      end
    end

    # Attempts to retry the query if deadlock occurs
    #
    # max_retry_count: - The number of times to retry before giving up
    def retry_on_deadlock(max_retry_count: 8)
      retry_count = 0
      begin
        yield
      rescue ActiveRecord::Deadlocked
        retry_count += 1
        retry_count > max_retry_count ? raise : retry
      end
    end

    # Attempts to retry the statement if statement invalid occurs
    #
    # max_retry_count: - The number of times to retry before giving up
    def retry_on_statement_invalid(max_retry_count: 5)
      retry_count = 0
      begin
        yield
      rescue ActiveRecord::StatementInvalid
        retry_count += 1
        retry_count > max_retry_count ? raise : retry
      end
    end
  end
end
