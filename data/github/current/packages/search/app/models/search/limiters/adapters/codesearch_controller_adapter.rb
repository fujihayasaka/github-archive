# typed: true
# frozen_string_literal: true

module Search::Limiters
  module Adapters
    # This is the adapter for CodesearchController and its subclasses.
    module CodesearchControllerAdapter
      extend T::Helpers
      extend Search::RateLimitRegistry

      abstract!

      requires_ancestor { CodesearchController }

      def search_type
        queries.search_type
      end

      def anonymous_actor_identifier
        T.bind(self, ApplicationController)
        request.env.fetch(Search::RateLimitRegistry::JA3_HASH_HEADER, request.remote_ip)
      end

      def rate_limit_timed_out_searches?
        FeatureFlag.vexi.enabled_or_raise?(:rate_limit_timed_out_codesearch_controller_searches) || ( # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
          logged_in? && T.must(current_user).feature_flag_enabled_or_raise?(:rate_limit_timed_out_codesearch_controller_searches) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        )
      end

      def self.included(other)
        # The controller itself already defines a `rate_limit_request` block for standard per-request limiting
        # by user. So, we only define this extra, secondary limit here.
        other.register_search_rate_limiter(
          Search::Limiters::SearchTimedOut.new(
            name: "search-timed-out",
            limit: GitHub.search_timed_out_actor_max,
            ttl: GitHub.search_timed_out_ttl,
            context: :web,
          ),
          if: :rate_limit_timed_out_searches?,
          only: :index
        )

        other.around_action(:search_rate_limiters_around, if: :search_rate_limiters_enabled?)
      end
    end
  end
end
