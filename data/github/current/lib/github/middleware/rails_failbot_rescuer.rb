# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    # This is very similar to Failbot::Rescuer, except that it does not reset or
    # push a new Failbot context.
    #
    # We need this because we have Failbot::Rescuer early in the middleware
    # stack (so that it will report errors from the API, and from other
    # middleware). But the Rails app also has ActionDispatch::ShowExceptions
    # (which rescues errors and renders an error page) and we need a
    # `Failbot::Rescuer` after that too otherwise errors that reach it will go
    # unreported.
    #
    # We can't have two `Failbot::Rescuer` middlewares, since they would wipe
    # out each other's context, so instead we have this inner one that reports
    # but does not reset the context. We end up with a stack that looks like:
    #
    # ...
    # use Failbot::Rescuer (reports errors from the API and from other early middleware)
    # ...
    # use GitHub::Routers::Api (Sinatra)
    # ...
    # use ActionDispatch::ShowExceptions (rescues errors and shows an error page)
    # use ActionDispatch::DebugExceptions (rescues errors and shows debug pages in development)
    # use GitHub::Middleware::RailsFailbotRescuer (reports errors before they get rescued by ShowExceptions/DebugExceptions)
    # ...
    # run GitHub::Application.routes (Rails app)
    #
    class RailsFailbotRescuer
      def initialize(app)
        @app   = app
      end

      def call(env)
        start = Time.now
        @app.call(env)
      rescue Object => boom
        raise if ignore?(boom)
        elapsed = T.let(Time.now, T.untyped) - start
        Failbot.report(boom, time: elapsed.to_s)
        raise
      end

      # These errors are frequent and not actionable (bad requests sent by the
      # user), so don't bother reporting them. They all get handled by the Rails
      # ShowExceptions middleware and turned into the appropriate 4xx response.
      IGNORED_ERRORS = [
        "ActionController::RoutingError",
        "ActionController::BadRequest",
        "ActionDispatch::Http::MimeNegotiation::InvalidType",
        "Rack::QueryParser::ParameterTypeError",
      ].freeze

      def ignore?(boom)
        IGNORED_ERRORS.include?(boom.class.name)
      end
    end
  end
end
