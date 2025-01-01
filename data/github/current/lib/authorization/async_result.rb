# typed: true
# frozen_string_literal: true

module Authorization
  class AsyncResult < BaseResult

    # Public
    #
    # Adds a callback to the promise returned by the provided block
    # This callaback adds two methods to the object returned by the promise:
    # * `__ok?` Determines whether the execution was ok, or not.
    # * `__error` The error that made the result to not be OK.
    # Also, if the promise results in an error, the return value will be default_value
    #
    # Both methods can be used to make resiliency-aware calls to the service.
    #
    # Examples:
    #
    # * An OK value:
    #
    #   res = AsyncResult.decorate([]) do
    #     Promise.resolve([1,2,3])
    #   end
    #   res = res.sync
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
    #     Promise.new.reject(ActiveRecord::ConnectionNotEstablished)
    #   end
    #   res = res.sync
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
      AsyncResult.create_promise(default_value, &block).then do |result|
        wrap_result(result)
      end
    end

    def initialize(value, error)
      @value = value
      @error = error
      @success = error.nil?
    end

    def self.create_promise(default_value = nil, &block)
      return Promise.resolve(AsyncResult.new(default_value, nil)) unless block_given?

      promise = yield
      raise ArgumentError.new("provided block must return a promise") unless promise.is_a?(Promise)

      promise.rescue do |error|
        if UnavailableExceptions.any? { |ue| error.is_a?(ue) }
          Failbot.report(error, app: "github-abilities")
          error
        else
          raise error
        end
      end.then do |result|
        next AsyncResult.new(default_value, result) if result&.is_a?(Exception)
        next AsyncResult.new(default_value, nil) if result.nil? && default_value
        AsyncResult.new(result, nil)
      end
    end
  end
end
