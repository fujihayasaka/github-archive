module HealthService
  module V1
    class Handler < TracedHandler
      def ping(*args)
        {
          response: "Pong!"
        }
      end

      def boom(*args)
        return Twirp::Error.not_found("Couldn't find the resource!") if args[0].issue400

        sleep args[0].sleep_seconds if args[0].sleep_seconds > 0

        return Twirp::Error.internal("Boom!")
      end
    end
  end
end
