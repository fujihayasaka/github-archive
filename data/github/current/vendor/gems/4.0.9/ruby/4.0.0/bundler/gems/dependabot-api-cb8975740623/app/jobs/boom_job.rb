# typed: strict
# frozen_string_literal: true

# Goes Boom! to test exception handling
class BoomJob < ApplicationJob
  extend T::Sig

  queue_as :default
  default_retries_for_idempotent_jobs

  class TickError < StandardError; end
  retry_on TickError, attempts: 4

  class SilentButDeadlyError < StandardError; end
  discard_on SilentButDeadlyError

  sig { params(mode: Symbol, custom_error_class_name: T.nilable(String)).void }
  def perform(mode: :unhandled, custom_error_class_name: nil)
    raise custom_error_class_name.constantize if custom_error_class_name

    raise TickError, (3 - executions + 1).to_s if executions <= 3

    case mode
    when :retry_stopped
      raise TickError, "Boom!"
    when :discard
      raise SilentButDeadlyError, "Psst!"
    else
      raise "Boom!"
    end
  end
end
