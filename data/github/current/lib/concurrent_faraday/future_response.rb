# typed: true
# frozen_string_literal: true
module ConcurrentFaraday
  class FutureResponse < ::Promise
    extend T::Generic

    Value = type_member

    extend Forwardable
    attr_accessor :instrument_event

    def initialize(response = nil)
      @response = response
      @ready = false
      super()
    end
    def_delegators :@response, :finished?, :apply_request, :marshal_dump, :marshal_load, :success?, :to_hash, :env, :[]

    def status
      sync if @ready && pending?
      @response.status
    end

    def reason_phrase
      sync if @ready && pending?
      @response.reason_phrase
    end

    def headers
      sync if @ready && pending?
      @response.headers
    end

    def body
      sync if @ready && pending?
      @response.body
    end

    def on_complete(&block)
      @response.on_complete(&block)
      self
    end

    def finish(env)
      @response.finish(env)
      self
    end

    def ready!
      @ready = true
      self
    end
  end
end
