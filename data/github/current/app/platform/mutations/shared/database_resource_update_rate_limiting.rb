# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    module Shared
      module DatabaseResourceUpdateRateLimiting
        extend T::Helpers

        include GitHub::RateLimitable

        # Check and enforce rate limiting for same-resource updates in GraphQL mutations. This is to protect
        # database resources from runaway transaction queueing that could lead to performance issues or downtime.
        #
        # See https://github.com/github/issues/issues/17441 for more context.
        #
        # @param resource [ActiveRecord::Base, nil] The resource being updated (issue, pull request, comment, etc.)
        # @param max_tries [Integer] Maximum number of tries allowed (default: 30)
        # @param ttl [ActiveSupport::Duration] Time window for rate limiting (default: 10 seconds)
        # @param current_user [User, nil] The current user for user-level feature flag check (optional)
        #
        # @raise [Platform::Errors::RateLimited] Raises rate limit exceeded error if limit is reached
        # @return [void]
        sig do
          params(
            resource: T.nilable(ActiveRecord::Base),
            max_tries: Integer,
            ttl: T.any(ActiveSupport::Duration, Integer),
            current_user: T.nilable(User)
          ).void
        end
        def check_database_resource_update_rate_limit!(
          resource: nil,
          max_tries: 30,
          ttl: 10.seconds,
          current_user: nil
        )
          return unless resource

          rate_limit_enabled = false

          if current_user
            rate_limit_enabled ||= current_user.feature_flag_enabled?(:issues_pulls_update_graphql_api_rate_limit, default: false)
          end

          rate_limit_enabled ||= FeatureFlag.vexi.enabled?(:issues_pulls_update_graphql_api_rate_limit, default: false)

          return unless rate_limit_enabled

          resource_type = resource.model_name.name.underscore
          cluster_name = resource.class.respond_to?(:cluster_name) ? T.unsafe(resource.class).cluster_name : "default"
          limit_key = "db_update_rate_limit/#{cluster_name}/#{resource_type}/#{resource.id}"

          # Uses the same rate limiting method as the REST API (see: app/api/database_resource_update_rate_limiting.rb)
          if rate_limit_increment(limit_key, { max_tries: max_tries, ttl: ttl }).at_limit?
            raise Platform::Errors::RateLimited.new("Too many requests")
          end
        end
      end
    end
  end
end
