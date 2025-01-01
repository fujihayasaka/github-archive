# typed: true
# frozen_string_literal: true

module Search::Limiters
  module Adapters
    # This adapter configures a few different secondary rate limiters for Api::Search.
    module SearchApiAdapter
      extend T::Helpers
      extend Search::RateLimitRegistry

      requires_ancestor { Api::Search }

      abstract!

      def anonymous_actor_identifier
        fingerprint = Api::RequestAuthenticationFingerprint.new(request.env)
        fingerprint.to_s
      end

      def self.included(other)
        # All users are subject to a max number of timed-out eleasticsearch requests per minute.
        # Most users never issue a timed out search; of those that do, few do it more than once in a
        # short time frame. Those that do are typically exhibiting abusive patterns and should be throttled.
        other.register_search_rate_limiter(
          Search::Limiters::SearchTimedOut.new(
            name: "search-timed-out",
            limit: GitHub.search_timed_out_actor_max,
            ttl: GitHub.search_timed_out_ttl,
            context: :api,
          ),
          if: :rate_limit_timed_out_searches?,
        )

        # This limits the total amount of query time a user can consume in a given time period;
        # this means that users who issue very slow queries can't issue too many in a given period.
        other.register_search_rate_limiter(
          Search::Limiters::SearchElapsedTime.new(
            name: "search-elapsed-time-shared-grouped",
            limit: GitHub.search_elapsed_time_max,
            ttl: GitHub.search_elapsed_time_ttl,
            strategy: :grouped,
            context: :api,
          ),
          if: :limit_search_elapsed_time_user?,
        )

        # Same as above, but with a more relaxed limit for staff users.
        other.register_search_rate_limiter(
          Search::Limiters::SearchElapsedTime.new(
            name: "search-elapsed-time-shared-grouped-staff",
            limit: GitHub.search_elapsed_time_staff_max,
            ttl: GitHub.search_elapsed_time_ttl,
            strategy: :grouped,
            context: :api,
          ),
          if: :limit_search_elapsed_time_staff?
        )

        other.before do
          search_rate_limiters_start if search_rate_limiters_enabled?
        end

        other.after do
          T.bind(self, Api::Search)  # Rebind because :after runs in an instance-based context
          search_rate_limiters_finish if search_rate_limiters_enabled?
        end
      end

      def limit_search_elapsed_time_user?
        !search_elapsed_time_user_is_staff? && limit_search_elapsed_time?
      end

      def limit_search_elapsed_time_staff?
        search_elapsed_time_user_is_staff? && limit_search_elapsed_time?
      end

      def search_elapsed_time_user_is_staff?
        logged_in? && T.must(current_user).employee?
      end

      def limit_search_elapsed_time?
        # Some users are exempt from rate limiting
        return false if logged_in? && T.must(current_user).rate_limit_exempt_user?
        params[:q] && params[:q].to_s.dup.force_encoding("UTF-8").valid_encoding?
      end

      def rate_limit_timed_out_searches?
        return false if request.path.end_with?("/count")
        GitHub.flipper[:rate_limit_timed_out_search_api_searches].enabled? || (
          logged_in? && T.must(current_user).feature_enabled?(:rate_limit_timed_out_search_api_searches)
        )
      end
    end
  end
end
