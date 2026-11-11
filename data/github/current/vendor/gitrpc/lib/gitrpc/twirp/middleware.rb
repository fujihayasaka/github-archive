# typed: true
# frozen_string_literal: true

require "timeout"
require "json"

module GitRPC
  module Twirp
    module Middleware
      # Instantiates the backend for the path (or /tmp if not given) and options
      # from the Git-Path and GitRPC-Options header fields respectively.
      class BackendMiddleware
        def initialize(app)
          @app = app
        end

        def call(env)
          path = env.fetch("HTTP_X_GIT_PATH", nil)
          path = "/tmp" if path.nil?

          # Parse the options from the header and symbolize only the top-level
          # keys.
          options_str = env.fetch("HTTP_X_GITRPC_OPTIONS", "{}")
          options = JSON.parse(options_str).map do |k, v|
            [k.to_sym, v]
          end.to_h

          env[:backend] = GitRPC::Backend.new(path, options)
          @app.call(env)
        end
      end

      class GitmonMiddleware
        def initialize(app)
          @app = app
        end

        def call(env)
          backend = env[:backend]
          method = env["PATH_INFO"].split("/")[-1]
          GitmonClient.track(backend, method) do
            @app.call(env)
          end
        end
      end

      class TimeoutMiddleware
        def initialize(app)
          @app = app
        end

        def call(env)
          backend = env[:backend]
          # Provide the exception class manually so it can be caught by the
          # Twirp code.
          ::Timeout.timeout(backend.message_timeout, Timer::Error) do
            @app.call(env)
          end
        end
      end

      # Install our hooks for this service
      def self.setup_for(svc, require_repo: true)
        # This relies on the twirp code overwriting the exception with whatever
        # comes out of here which may be a bit brittle.
        svc.exception_raised do |ex, env|
          if ex.is_a?(Timer::Error)
            error = GitRPC::Timeout.new("#{env[:rpc_method]} - #{ex.message}")
            error.set_backtrace(ex.backtrace)
            raise error
          end

          if ex.is_a?(Rugged::InvalidError)
            error = GitRPC::BadRepositoryState.new("#{env[:rpc_method]} - #{ex.message}")
            error.set_backtrace(ex.backtrace)
            raise error
          end
        end

        svc.on_error do |twerr, env|
          if twerr.cause.is_a?(StandardError)
            ex = twerr.cause
            twerr.meta["message"] = ex.message
            twerr.meta["backtrace"] = ex.backtrace.join("\n")
          end
        end

        svc.before do |rack_env, env|
          backend = rack_env[:backend]
          env[:backend] = backend

          # Raise here so we can catch it in on_error
          if require_repo
            path = backend.path
            raise InvalidRepository.new(path) unless Dir.exist?(path)
          end
        end
      end
    end
  end
end
