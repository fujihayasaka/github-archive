# typed: false
# frozen_string_literal: true

module Authorization
  class Result < BaseResult

    # Public
    #
    # Executes the given block and adds to methods to the block's returning object:
    # * `__ok?` Determines whether the execution was ok, or not.
    # * `__error` The error that made the result to not be OK.
    # Also if the block execution results in an error, the return value will
    # default_value
    #
    # Both methods can be used to make resiliency-aware calls to the service.
    #
    # Examples:
    #
    # * An OK value:
    #
    #   res = Result.decorate([]) do
    #     [1,2,3]
    #   end
    #
    #   res.__ok?
    #   => true
    #   res.error
    #   => nil
    #   res.inspect
    #   => "[1, 2, 3]"
    #   res.class
    #   => Array
    #
    # * A not OK value:
    #
    #   res = Result.decorate([]) do
    #     raise ActiveRecord::ConnectionNotEstablished
    #   end
    #
    #   res.__ok?
    #   => false
    #   res.error
    #   => ActiveRecord::ConnectionNotEstablished
    #   res.inspect
    #   => "[]"
    #   res.class
    #   => Array
    #
    def self.decorate(default_value = nil, &block)
      result = Result.new(default_value, &block)
      wrap_result(result)
    end

    def initialize(default_value = nil, &block)
      @success = false
      @error = nil

      @value = if block_given?
        begin
          result = yield
          @success = true
          if result.nil? && default_value
            default_value
          else
            result
          end
        rescue *UnavailableExceptions => boom
          Failbot.report(boom, app: "github-abilities")
          @error = boom
          default_value
        end
      else
        @success = true
        default_value
      end
    end
  end
end
