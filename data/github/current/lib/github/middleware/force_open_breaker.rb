# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    class ForceOpenBreaker
      def initialize(app)
        @app = app
      end

      def call(env)
        request = Rack::Request.new(env)

        return @app.call(env) unless request.GET.has_key?("force_open_breaker")
        return @app.call(env) unless GitHub::StaffOnlyCookie.read(request.cookies) || Rails.env.development?

        key = request.GET["force_open_breaker"]

        if key.present?
          cb = Resilient::CircuitBreaker.get(key)
          cb.properties.instance_variable_set("@force_open", true)
        end
        @app.call(env)
      ensure
        cb&.properties&.instance_variable_set("@force_open", false)
      end
    end
  end
end
