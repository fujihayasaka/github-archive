# typed: strict
# frozen_string_literal: true

# This concern implements custom rate limiting to protect the Dependency Graph service from runaway integrations
# causing service degradation.
#
# It implements both a proactive rate limit on accesses per actor per interval and a reactive rate limit that is
# applied when a single actor causes too many exceptions in an interval.
#
# This approach was based on precedent set by:
# - Platform::Mutations::Shared::DatabaseResourceUpdateRateLimiting - proactively rate limits writes
# - Platform::Objects::Blame - reactively re-raises SpokesAPI::ResourceExhausted as Platform::Errors::RateLimited
#
module Platform
  module Objects
    module Concerns
      module DependencyGraphRateLimiting
        extend T::Helpers
        extend ActiveSupport::Concern

        include GitHub::RateLimitable

        # Rate limiting rationale
        #
        # See:
        # - https://docs.github.com/en/graphql/overview/rate-limits-and-query-limits-for-the-graphql-api
        #
        # A GitHub App on GHEC has a maximum rate limit of 12,500 'points' per hour (~3.5 points per second).
        #
        # A Dependency Graph for a repository is unbounded across two dimensions:
        # - A repository may have X manifests
        # - Each manifest may have Y dependencies
        #
        # These dimensions are multiplicative and we cannot easily ascertain the size of X * Y until after we've
        # processed a significant amount of the request, which is prone to timeout on our largest repositories.
        #
        # This component is designed to set Dependency Graph access at a cost of 5 points.
        #
        # The rate limits are applied to the viewer which will be either a User or an Installation.
        #
        # NOTE: Feature Flag enablement is applied at the Installation level for ease of use
        #
        # Maximum number of dependency graph API accesses per actor within the TTL window.
        ACCESS_MAX = 7 # 5 points * 7 = 35 points
        ACCESS_TTL = T.let(10.seconds, ActiveSupport::Duration) # 35 points / 10 = 3.5 points per second.
        ACCESS_FEATURE_FLAG = :dependency_graph_graphql_custom_rate_limit

        # Error clamping rationale
        #
        # If an Integration is using a query schema that tries to request too broad a dependency set
        # at once, it is very likely to cause excessive timeouts which can impact our service SLO and
        # occupy too many resources.
        #
        # In order to protect service stability, error clamping is applied to the GitHub App (integration)
        # and will start to restrict access with a rate limit as Dependency Graph errors exceed one error
        # every two seconds.
        #
        # Maximum number of errors (timeouts/failures) per actor before cutting off access.
        ERROR_MAX = 5 # We will tolerate 1 error every 2 seconds
        ERROR_TTL = T.let(10.seconds, ActiveSupport::Duration)
        ERROR_FEATURE_FLAG = :dependency_graph_graphql_error_clamping

        # Check proactive and reactive rate limits for dependency graph access.
        # Raises Platform::Errors::RateLimited if the actor has exceeded either limit.
        #
        # @param repository [Repository] The repository being queried
        # @param context [GraphQL::Query::Context] The GraphQL context
        # @param resource [String] The resource being accessed (e.g. "manifests", "dependencies")
        sig { params(repository: ::Repository, context: T.untyped, resource: String).void }
        def check_dependency_graph_rate_limit!(repository, context, resource:)
          # Errors are cumulative across both manifest and dependencies resource paths.
          # Error clamping is scoped to the integration for broader protection.
          check_dependency_graph_error_limit!(repository, context)
          # Accesses count independently for manifest and dependencies resource paths to minimise double-counting.
          # Access limiting is scoped to the installation for per-installation granularity.
          check_dependency_graph_access_limit!(repository, context, resource: resource)
        end

        # Record that a dependency graph error occurred for this actor.
        # Called when the dependency graph service returns a timeout or unavailable error.
        #
        # @param repository [Repository] The repository being queried
        # @param context [GraphQL::Query::Context] The GraphQL context
        sig { params(repository: ::Repository, context: T.untyped).void }
        def record_dependency_graph_error!(repository, context)
          flag_actor = dependency_graph_flag_actor(context)
          return unless flag_actor
          return unless FeatureFlag.vexi.enabled?(ERROR_FEATURE_FLAG, flag_actor, default: false)

          actor_key = error_clamp_actor_key(context)
          rate_limit_increment(
            dependency_graph_error_key(actor_key),
            { max_tries: ERROR_MAX, ttl: ERROR_TTL }
          )
          GitHub.dogstats.increment(
            "dependency_graph.graphql.error_recorded",
            tags: ["actor_type:#{actor_type(context)}"]
          )
          GitHub.logger.info("dependency_graph_rate_limit: error recorded")
        end

        private

        # Reactive check: if this integration/user has caused too many errors, block them.
        sig { params(repository: ::Repository, context: T.untyped).void }
        def check_dependency_graph_error_limit!(repository, context)
          flag_actor = dependency_graph_flag_actor(context)
          return unless flag_actor
          return unless FeatureFlag.vexi.enabled?(ERROR_FEATURE_FLAG, flag_actor, default: false)

          actor_key = error_clamp_actor_key(context)
          actor_type = actor_type(context)
          GitHub.dogstats.increment(
            "dependency_graph.graphql.error_limit_checked",
            tags: ["actor_type:#{actor_type}"]
          )
          GitHub.logger.info("dependency_graph_rate_limit: error limit checked")

          error_result = rate_limit_check(
            dependency_graph_error_key(actor_key),
            { max_tries: ERROR_MAX, ttl: ERROR_TTL }
          )
          if error_result.at_limit?
            retry_after = retry_after_seconds(error_result)
            set_retry_after_header(context, retry_after)
            GitHub.dogstats.increment(
              "dependency_graph.graphql.rate_limited",
              tags: ["reason:errors", "actor_type:#{actor_type}"]
            )
            GitHub.logger.info("dependency_graph_rate_limit: rate limited by errors", retry_after: retry_after)
            raise Platform::Errors::RateLimited.new(
              "You have made too many failing requests to dependency graph. Please retry after #{retry_after} seconds."
            )
          end
        end

        # Proactive check: if this actor has accessed DG too many times, throttle them.
        sig { params(repository: ::Repository, context: T.untyped, resource: String).void }
        def check_dependency_graph_access_limit!(repository, context, resource:)
          flag_actor = dependency_graph_flag_actor(context)
          return unless flag_actor
          return unless FeatureFlag.vexi.enabled?(ACCESS_FEATURE_FLAG, flag_actor, default: false)

          actor_key = rate_limit_actor_key(context)
          actor_type = actor_type(context)
          GitHub.dogstats.increment(
            "dependency_graph.graphql.access_limit_checked",
            tags: ["resource:#{resource}", "actor_type:#{actor_type}"]
          )
          GitHub.logger.info("dependency_graph_rate_limit: access limit checked", resource: resource)

          access_key = "dependency_graph/access/#{resource}/#{actor_key}"
          access_result = rate_limit_increment(access_key, { max_tries: ACCESS_MAX, ttl: ACCESS_TTL })
          if access_result.at_limit?
            retry_after = retry_after_seconds(access_result)
            set_retry_after_header(context, retry_after)
            GitHub.dogstats.increment(
              "dependency_graph.graphql.rate_limited",
              tags: ["reason:access", "resource:#{resource}", "actor_type:#{actor_type}"]
            )
            GitHub.logger.info("dependency_graph_rate_limit: rate limited by access", retry_after: retry_after)
            raise Platform::Errors::RateLimited.new(
              "You have exceeded the dependency graph access rate limit. Please retry after #{retry_after} seconds."
            )
          end
        end

        # Resolve the actor for feature flag evaluation.
        # For installation-authenticated requests, returns the parent integration.
        # Falls back to the viewer for user-authenticated requests.
        sig { params(context: T.untyped).returns(T.untyped) }
        def dependency_graph_flag_actor(context)
          installation = context[:installation]
          if installation
            installation.integration
          else
            context[:viewer]
          end
        end

        # Low-cardinality actor type for metric tags.
        sig { params(context: T.untyped).returns(String) }
        def actor_type(context)
          context[:installation] ? "app" : "user"
        end

        # Build the rate limit key for access limiting.
        # Scoped to the installation for app-authenticated requests, or the user.
        sig { params(context: T.untyped).returns(String) }
        def rate_limit_actor_key(context)
          installation = context[:installation]
          if installation
            "installation:#{installation.id}"
          else
            "user:#{context[:viewer].id}"
          end
        end

        # Build the rate limit key for error clamping.
        # Scoped to the integration for app-authenticated requests, or the user.
        sig { params(context: T.untyped).returns(String) }
        def error_clamp_actor_key(context)
          installation = context[:installation]
          if installation
            "integration:#{installation.integration.id}"
          else
            "user:#{context[:viewer].id}"
          end
        end

        sig { params(actor_key: String).returns(String) }
        def dependency_graph_error_key(actor_key)
          "dependency_graph/errors/#{actor_key}"
        end

        sig { params(context: T.untyped, retry_after: Integer).void }
        def set_retry_after_header(context, retry_after)
          response = context[:response]
          response.headers["Retry-After"] = retry_after.to_s if response
        end

        # Compute the number of seconds until the rate limit window resets.
        sig { params(result: T.untyped).returns(Integer) }
        def retry_after_seconds(result)
          [result.expires_at.to_i - Time.now.to_i, 1].max
        end
      end
    end
  end
end
