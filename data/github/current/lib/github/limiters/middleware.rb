# typed: false
# frozen_string_literal: true

require "rack"
require "rack/request_logger"
require "github/timeout_middleware"

module GitHub
  module Limiters
    # Public: This middleware kills fascists.
    class Middleware
      include GitHub::Middleware::Constants

      SKIP_LIMIT_CHECKS = "github.limiters.skip".freeze
      LIMITERS_EVALUATED_KEY = "secondary_rate_limits_evaluated".freeze

      # Public: Initialize a limiter middleware.
      #
      # app      - the Rack application this middleware is wrapping.
      # group    - a graphite-safe String group name for these limiters.
      # limiters - zero or more limmiters conforming to GitHub::Limiter's
      #            interface.
      #
      # Group names are used to help determine which set of limiting middleware
      # is active, for example "app" versus "api".
      #
      # Limiter names must be unique Graphite-safe strings and should
      # also conform to the following convention of "prefix-suffix" where:
      #
      #   prefix: the noun or nouns being used to discriminate requests,
      #           e.g. "path", "path-ip", and "ua"
      #   suffix: one of:
      #           - "count" for counting things
      #           - "elapsed" for counting elapsed time
      #           - "concurrent" for tracking concurrency
      #
      sig { params(app: T.untyped, group: String, limiters: T.untyped).void }
      def initialize(app, group, *limiters)
        if Limiter::NAME !~ group
          raise ArgumentError, "Bad group name: a-z and '-' only"
        end

        @app = app
        @group = group
        @limiters = Array[limiters].flatten

        # gauge the number of api limiters being initialized
        GitHub.dogstats.gauge("limiters.initialized", @limiters.size, tags: ["group:#{@group}"])
      end

      # Public: Handle a request, returning A minimal 429 response if the
      # request is limited. Translate the 429 to a more user-friendly response
      # somewhere upstream of this middleware.
      #
      # Limited requests add `limited=<middleware-name>/<limiter-name>` to the
      # log context, try `/splunk -1h limited=app/path | top path_info`.
      def call(env)
        if @limiters.empty? || self.class.skip_limit_checks?(env) || ignored?(env)
          return @app.call(env)
        end

        all_limiters_start_pre = GitHub::Dogstats.monotonic_time

        request = Rack::Request.new(env)
        response = nil
        started = []
        group_tag = "group:#{@group}"
        method_tag = "method:#{env[REQUEST_METHOD].downcase}"
        enabled = enabled?(env)
        enabled_tag = enabled ? "enabled:true" : "enabled:false"
        limited_tag = "limited:false"

        GitHub.dogstats.increment("limited.tries", tags: [group_tag, enabled_tag])

        @limiters.each do |limiter|
          limiter_tag, tags, limiter_start_pre = nil

          begin
            limiter_tag = "limiter:#{limiter.name}"
            tags = Array(limiter.tags(request)).concat([group_tag, limiter_tag, method_tag, enabled_tag])
            limiter_start_pre = GitHub::Dogstats.monotonic_time
            GitHub.dogstats.increment("limited.per_limiter.tries", tags: tags)

            next if limiter.ignored?(request)

            state = limiter.start(request)
            started << limiter

            if state.limited?
              limited_tag = "limited:true"
              GitHub.dogstats.increment("limited.request", tags: tags)

              # Rate limited requests shed at the middleware layer don't go through the rest of our request
              # code paths. However we do potentially want the user details from the token to provide better
              # support in dealing with rate limit queries. This tries to find the user from the environment
              # credentials and will add that to the log/hydro data if it is found. Failures are ignored.
              user_being_limited = nil

              # GH owned internal services sending unauthenthicated requests from Proxima stamps to dotcom
              # will use a proxima service token to identify themselves. Service identities are extracted
              # (similar to user id/login above) for logging purposes.
              proxima_service_identity_being_limited = nil

              # Guard against rack data not being available
              creds = if env["rack.input"]
                Api::RequestCredentials.from_env(env)
              else
                nil
              end

              if creds
                api_auth = GitHub::Authentication::Attempt.new(
                  allow_integrations:         true,
                  allow_user_via_granular_actor: true,
                  from:                       :api_middleware,
                  login:                      creds.login,
                  password:                   creds.password,
                  otp:                        creds.otp,
                  token:                      creds.token,
                  request_id:                 env["HTTP_X_GITHUB_REQUEST_ID"],
                )
                if api_auth.credentials_present?
                  result = api_auth.result
                  if result.success?
                    user_being_limited = result.user
                  end
                elsif creds.proxima_service_token_present?
                  verified_token = ProximaServiceToken.verify(creds.proxima_service_token)
                  if verified_token.valid?
                    proxima_service_identity_being_limited = verified_token.identity
                  end
                end
              end

              logging_limit_message = "#{@group}/#{limiter.name}"
              if (log_data = env[Rack::RequestLogger::APPLICATION_LOG_DATA])
                log_data.merge!(Hash(limiter.logging_info(request)))
                log_data["gh.rate_limit.secondary.limit_reason"] = logging_limit_message
                log_data["gh.actor.id"] = user_being_limited.id if user_being_limited
                log_data["gh.actor.login"] = user_being_limited.login if user_being_limited
                log_data["gh.proxima_service_identity.service_name"] = proxima_service_identity_being_limited.service_name if proxima_service_identity_being_limited
                log_data["gh.proxima_service_identity.tenant_shortcode"] = proxima_service_identity_being_limited.tenant_shortcode if proxima_service_identity_being_limited
              end

              if (hydro_payload = env[GitHub::HydroMiddleware::PAYLOAD])
                hydro_payload["secondary_rate_limit_reason"] = logging_limit_message
                hydro_payload["current_user"] = user_being_limited.login if user_being_limited
                append_to_hydro_payload(env, hydro_payload)
              end

              if enabled
                headers = {
                  CONTENT_TYPE     => TEXT_PLAIN,
                  # These headers are stripped by haproxy on the way out:
                  GH_LIMITED_BY    => limiter.name,
                  GH_LIMITED_GROUP => @group,
                }
                headers[RETRY_AFTER] = state.duration.to_s if state.duration

                if state.upstream_to_glb?
                  # Propagate this rate limit up to GLB.  This will block all requests to dotcom for this IP address for
                  # the next 5 minutes.
                  # https://github.com/github/glb/blob/95ad5e77c2cc9fad2904492a6ca4125833bf7e8b/docs/enabling_rate_limiting.md
                  headers["X-GLB-Rate-Limit"] = "true"
                  headers[RETRY_AFTER] = "300"
                end

                response = [429, headers, EMPTY_BODY]
              end

              break
            end

          ensure
            unless tags.nil?
              tags = tags.dup.push(limited_tag)
              GitHub.dogstats.distribution_timing_since("limiters.per_limiter.executed.pre", limiter_start_pre, tags: tags)
            end
          end

          GitHub::TimeoutMiddleware.notify(env, limiter)
        end

        tags = [group_tag, enabled_tag, limited_tag, method_tag]

        begin
          if @group == "api"
            if (hydro_payload = env[GitHub::HydroMiddleware::PAYLOAD])
              hydro_payload[LIMITERS_EVALUATED_KEY] ||= []
              hydro_payload[LIMITERS_EVALUATED_KEY].concat(started.map do |limiter|
                limiter.hydro_info(request)
              end)
              append_to_hydro_payload(env, hydro_payload)
            end
          end

          GitHub.dogstats.distribution_timing_since("limiters.executed.pre", all_limiters_start_pre, tags: tags)
          GitHub.dogstats.distribution("limiters.evaluated", started.size, tags: tags)
          response || @app.call(env)
        ensure
          GitHub.dogstats.distribution_time("limiters.executed.post", tags: tags) do
            # If skip_limit_checks is set here, it means the app toggled the flag
            # based on information that wasn't available when this limiter
            # started. Cancel any pending limiters:
            if self.class.skip_limit_checks?(env)
              started.each { |limiter| limiter.cancel(request) }
            else
              started.each { |limiter| limiter.finish(request) }
            end
          end
        end
      end

      # Public: Mark a request to ignore request limit checks.
      #
      # This prevents any limiter middleware from running, and any limiters
      # already in-flight will be canceled.
      #
      # env - a Rack request environment
      #
      # Modifies the given environment to set a flag. Returns nothing.
      def self.skip_limit_checks(env)
        env[SKIP_LIMIT_CHECKS] = true
      end

      # Internal: should limit checks be skipped?
      #
      # env - a Rack request environment
      #
      # Returns true or false.
      def self.skip_limit_checks?(env)
        !!env[SKIP_LIMIT_CHECKS]
      end

      protected

      # Internal: Override this method in a subclass to activate limiting.
      def enabled?(env)
        false
      end

      # Internal: Override this method in a subclass to implement allowlists.
      def ignored?(env)
        false
      end

      # Internal: Override this method in a subclass to add additional context to Hydro when the request has been limited.
      def append_to_hydro_payload(env, hydro_payload)
        # no-op
      end
    end
  end
end
