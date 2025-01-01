# typed: true
# frozen_string_literal: true

module GitHub

  # Public: Objects matching this interface can be used to rate limit Rack
  # requests with GitHub::Limiters::Middleware. Inherit this for a head start.
  class Limiter

    # Public: Limiter#start() must return an object matching this interface.
    class State
      def initialize(limited:, duration: nil, glb: false)
        @limited  = !!limited
        @duration = duration
        @glb = glb
        freeze
      end

      def limited?
        @limited
      end

      # Indicates that requested limit should be applied at the GLB level.  This gets propagated via
      # the X-GLB-Rate-Limit response header.
      # https://github.com/github/glb/blob/95ad5e77c2cc9fad2904492a6ca4125833bf7e8b/docs/enabling_rate_limiting.md
      def upstream_to_glb?
        @glb
      end

      # Public: The time left for this state.
      attr_reader :duration
    end

    # Public: Limiters can return this state to deny a request.
    LIMITED = State.new(limited: true)

    # Public: Limiters can return this state to allow a request.
    OK = State.new(limited: false)

    # Internal: A Graphite-friendly pattern for limiter names.
    NAME = /\A[a-z][-a-z]*\Z/

    # Public: The String name of this limiter.
    attr_reader :name

    # Public: Create a new named instance.
    def initialize(name)
      raise ArgumentError, "Bad name: a-z and '-' only" if NAME !~ name
      @name = name
    end

    # Public: Called when a request begins.
    #
    # Return Limiter::LIMITED to deny the request or Limiter::OK to allow it.
    # The return value is passed to finish() when the request is complete.
    # This method must not raise an exception.
    #
    # request - a Rack::Request instance
    #
    # Returns a State.
    def start(request)
      OK
    end

    # Public: Called when request limiting has been canceled.
    #
    # This is called only if this limiter's start() method was called. A limiter
    # can be canceled either if another limiter active in a limiter middleware
    # limits a request or if request limiting is disabled globally by the
    # application during a request.
    #
    # request - a Rack::Request instance
    #
    # Returns nothing.
    def cancel(request)
    end

    # Public: Called when a request completes.
    #
    # This is called but only if this limiter's start() method was called.
    # This method must not raise an exception.
    #
    # env - a Rack::Request instance
    #
    # Returns nothing.
    def finish(request)
    end

    # Internal: Called when a timeout is encountered during the request cycle.
    #
    # env - a Rack request environment
    #
    # Returns nothing.
    def timeout(env)
    end

    # Public: Used to list extra tags to be attached to metrics sent to DataDog.
    # The returned value can be a single tag String or an Array of tag Strings.
    # A tag String takes the form of "name:value".
    def tags(request)
    end

    # Public: Used to list extra KVPs to be attached to logs sent to Splunk.
    # The returned value should be a hash with stringified keys.
    def logging_info(request)
    end

    # Public: Used to list extra KVPs to be attached to logs sent to Hydro.
    # The returned value should be a hash that conforms to the
    # hydro.schemas.github.v1.entities.SecondaryRateLimit hydro schema.
    def hydro_info(request)
    end

    # Public: Used to determine whether the request should be ignored
    #
    # This is the first method called on a limiter, to determine whether it
    # should even be used for the request in question. If the method returns
    # true, then no other methods are called on that limiter for that request.
    #
    # request - a Rack::Request instance
    #
    # Returns a Boolean.
    def ignored?(request)
      false
    end
  end
end
