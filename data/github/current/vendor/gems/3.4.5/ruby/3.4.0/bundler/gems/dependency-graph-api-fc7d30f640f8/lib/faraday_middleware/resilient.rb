# typed: true
# frozen_string_literal: true

module DependencyGraph
  module FaradayMiddleware
    # Copped from github/github, naturally
    # https://github.com/github/github/blob/e05140afcd19b2e351eaa092eeaac70af4c2041a/lib/github/faraday_middleware/resilient.rb#L5
    class Resilient < Faraday::Middleware
      def self.tripped?(res)
        res.status == 502 && res.headers[:resilient] == "yes"
      end

      def initialize(app, options)
        super(app)
        @name = options[:name]
        @options = options[:options]
        @registry = options[:registry]
      end

      def circuit_breaker
        ::Resilient::CircuitBreaker.get(@name, @options, @registry)
      end

      def call(env)
        env.clear_body if env.needs_body?

        circuit = circuit_breaker
        if circuit.allow_request?
          call_request(env, circuit)
        else
          tripped_request(env, circuit)
        end
      end

      def call_request(env, circuit)
        @app.call(env).on_complete do |response_env|
          status = response_env[:status]
          if status < 200 || status > 499
            circuit.failure
          else
            circuit.success
          end
        end
      rescue
        circuit.failure
        raise
      end

      def tripped_request(env, circuit)
        env[:resilient_circuit] = circuit
        env.status = 502
        env.response_headers = ::Faraday::Utils::Headers.new
        env.response_headers["Resilient"] = "yes"
        env.response = ::Faraday::Response.new.tap do |res|
          res.finish(env) unless env.parallel?
        end
      end
    end
  end
end
