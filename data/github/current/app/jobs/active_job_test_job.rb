# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class ActiveJobTestJob < ApplicationJob
  queue_as :test

  RetryableError = Class.new(RuntimeError)
  DiscardableError = Class.new(RuntimeError)
  UnhandledError = Class.new(RuntimeError)

  retry_on RetryableError, wait: 1.second, attempts: 3
  discard_on DiscardableError

  def perform(duration: 1.0, retries: 1, error: :none)
    sleep duration

    case error
    when :none
      # do nothing
    when :retry
      raise RetryableError if executions <= retries
    when :discard
      raise DiscardableError
    when :unhandled
      raise UnhandledError
    end
  end
end
