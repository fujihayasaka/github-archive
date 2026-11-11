# typed: true
# frozen_string_literal: true

module Authorization
  # Abstract operation to implement async Commands and Queries in the Authorization
  # Service.
  #
  # Check commands/*, and queries/*.rb to see how it's used.
  #
  class AsyncOperation
    include Helpers

    # Any operation when executed will check a set of preconditions and return the default value in case they
    # are not met. If the preconditions are met, it will run the `execute_implementation`,
    # decorating the result with two additonal methods __ok? and __error. This methods are useful to check
    # resiliency aspects.
    #
    # Each child class:
    #  * MUST implement `execute_implementation` returning a promise for the service
    # method exepected result.
    #  * MIGHT override `default_result` in case the expected result is not an
    # scalar. For instance, a default result for a query returning an array should
    # return [].
    #  * MIGHT override `validation_errors` to return an array of error messages for
    # those preconditions the query arguments don't met.
    #
    def async_execute
      Authorization::AsyncResult.decorate(default_result) do
        validate!
        execute_implementation
      end
    end

    private

    def execute_implementation
      raise "Must be implemented in children classes"
    end

    def default_result
      nil
    end

    def validate!
      if (errors = validation_errors).any?
        raise Authorization::Errors::InvalidQuery.new(errors.join("\n"))
      end
    end

    def validation_errors
      []
    end
  end
end
