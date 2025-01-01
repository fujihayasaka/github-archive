# typed: true
# frozen_string_literal: true

module GitHub
  module Enterprise
    module Middleware
      def self.mount(builder)
        # The customer may use an alias for easier access (e.g. http://github/ vs.
        # http://github.foocompany.com/). We need to redirect them to the hostname
        # they configured enterprise to use.
        builder.insert_after GitHub::Routers::Api, EnsureHostname, %w[ 127.0.0.1 localhost ]

        # TamperGuard periodically reloads the enterprise license. This is to prevent any
        # injected code that might monkey patch GitHub.license to bypass seat limits or
        # expiration dates.
        # builder.use TamperGuard,
        #   :backoff  => 8.hours
      end

      class TamperGuard
        def initialize(app, options = {})
          @app = app

          @backoff    = options[:backoff]
          @reload_at  = options[:reload_at] || DateTime.now
        end

        def call(env)
          reload_license if DateTime.now > @reload_at

          @app.call(env)
        end

        def reload_license
          Enterprise.license.reload!

          @reload_at = DateTime.now + @backoff
        end
      end

      class EnsureHostname
        def initialize(app, allowlist = [])
          allowlist += [GitHub.host_name, "api.#{GitHub.host_name}", "gist.#{GitHub.host_name}"]
          allowlist += [Rack::Test::DEFAULT_HOST, "example.com", "www.example.com"] if Rails.env.test?
          if GitHub.subdomain_isolation?
            allowlist += ["raw.#{GitHub.host_name}", "pages.#{GitHub.host_name}"]
          end
          @app, @allowlist = app, allowlist
        end

        def call(env)
          request = Rack::Request.new(env)
          # Allow /status checks here for external load balancers
          if @allowlist.include?(env["SERVER_NAME"]) || request.path == "/status"
            @app.call(env)
          else
            url = request.url.sub(env["SERVER_NAME"], GitHub.host_name)
            response = Rack::Response.new
            # Avoid browser redirect caching in local development so we can
            # easily switch between dotcom and enterprise.
            # https://github.com/github/github/pull/49510
            status = Rails.env.development? ? "302" : "301"
            response.redirect(url, status)
            [response.status, response.headers, response.body]
          end
        end
      end
    end
  end
end
