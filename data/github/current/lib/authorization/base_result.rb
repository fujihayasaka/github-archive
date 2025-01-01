# typed: false
# frozen_string_literal: true

module Authorization
  class BaseResult
    def self.decorate(default_value = nil, &block)
      raise "Must be implemented in children classes"
    end

    def self.wrap_result(result)
      ok = result.success?
      error = ok ? nil : result.error

      result.value.tap do |v|
        class << v
          def __ok?
            ok
          end

          def __error
            error
          end
        end
      end
    end

    # Internal: All exceptions that could make abilities unavailable due to
    # timeouts, network errors or mysql failures.
    UnavailableExceptions = [
      ActiveRecord::ConnectionNotEstablished, # don't believe we'll ever hit this
      SystemCallError,                        # Errno::ECONNREFUSED, Errno::ECONNRESET and friends
    ]

    attr_reader :value
    attr_reader :error

    def success?
      @success
    end
  end
end
