# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module RequestLimits
      AUTHENTICATION_FINGERPRINT_BY_PATH_MAX         = 900
      ENTERPRISE_SCIM_BY_ENDPOINT_MAX                = 900 # matching the default value of AUTHENTICATION_FINGERPRINT_BY_PATH_MAX
      GRAPHQL_AUTHENTICATION_FINGERPRINT_MAX         = 2_000
      TWIRP_AUTHENTICATION_FINGERPRINT_BY_PATH_MAX   = 10_000
      ELAPSED_TIME_BY_AUTHENTICATION_FINGERPRINT_MAX = 90_000 # milliseconds per minute
      ELAPSED_AUTHENTICATED_TIME_BY_PATH_GRAPHQL_MAX = 60_000 # milliseconds per minute
      TWIRP_ELAPSED_TIME_BY_CLIENT_MAX               = 300_000 # milliseconds per minute
      SEARCH_ELAPSED_TIME_MAX                        = 4_000 # milliseconds
      SEARCH_ELAPSED_TIME_STAFF_MAX                  = 7_500 # milliseconds
      SEARCH_TIMED_OUT_ACTOR_MAX                     = 2  # Total timed out elasticsearch queries per minute
      SEARCH_TIMED_OUT_TTL                           = 60 # seconds
      SEARCH_ELAPSED_TIME_TTL                        = 60 # seconds
      CONCURRENT_AUTHENTICATION_FINGERPRINT_MAX      = 100 # requests per ttl
      CONCURRENT_AUTHENTICATION_FINGERPRINT_TTL      = 60
      SEARCH_IP_ADDRESS_MAX                          = 1_000 # requests per ttl
      SEARCH_IP_ADDRESS_TTL                          = 60
      REQUESTS_BY_PAT_MAX                            = 20_000 # requests per minute
      GRAPHQL_EXCESSIVE_DB_COUNT_MAX                 = 5000 # db queries per ttl
      GRAPHQL_EXCESSIVE_DB_COUNT_THRESHOLD           = 250 # db queries threshold to start recording to cache
      GRAPHQL_EXCESSIVE_DB_COUNT_TTL                 = 60 # seconds
      GRAPHQL_REPEATED_TIMEOUT_MAX                   = 6 # allowed timeouts per ttl
      GRAPHQL_REPEATED_TIMEOUT_TTL                   = 300 # seconds
      INTERNAL_IP_LESS_AUTHENTICATION_FINGERPRINT_BY_PATH_MAX = 2_500
      INTERNAL_IP_LESS_ELAPSED_TIME_BY_AUTHENTICATION_FINGERPRINT_MAX = 250_000 # milliseconds per minute
      INTERNAL_IP_LESS_CONCURRENT_AUTHENTICATION_FINGERPRINT_MAX = 600 # requests per ttl
      INTERNAL_IP_LESS_CONCURRENT_AUTHENTICATION_FINGERPRINT_TTL = 60
      INTERNAL_IP_LESS_ELAPSED_AUTHENTICATED_TIME_BY_PATH_GRAPHQL_MAX = 100_000 # milliseconds per minute
      INTERNAL_IP_LESS_GRAPHQL_AUTHENTICATION_FINGERPRINT_MAX = 23_000
      INTERNAL_IP_LESS_GRAPHQL_EXCESSIVE_DB_COUNT_MAX = 12_000 # db queries per ttl

      # API request limit for requests allowed in a minute for SCIM endpoints
      #
      # Returns integer representing requests per minute
      def enterprise_scim_by_endpoint_max
        @enterprise_scim_by_endpoint_max || ENTERPRISE_SCIM_BY_ENDPOINT_MAX
      end
      attr_writer :enterprise_scim_by_endpoint_max

      # API request limit for requests allowed in a minute
      #
      # Returns integer representing requests per minute
      def authentication_fingerprint_by_path_max
        @authentication_fingerprint_by_path_max || AUTHENTICATION_FINGERPRINT_BY_PATH_MAX
      end
      attr_writer :authentication_fingerprint_by_path_max

      # GraphQL request limit for read/write requests allowed in a minute.
      #
      # Returns integer representing requests per minute
      def graphql_authentication_fingerprint_max
        @graphql_authentication_fingerprint_max || GRAPHQL_AUTHENTICATION_FINGERPRINT_MAX
      end
      attr_writer :graphql_authentication_fingerprint_max

      # Twirp request limit for requests allowed in a minute.
      #
      # Returns integer representing requests per minute
      def twirp_elapsed_time_by_client_max
        @twirp_elapsed_time_by_client_max || TWIRP_ELAPSED_TIME_BY_CLIENT_MAX
      end
      attr_writer :twirp_elapsed_time_by_client_max

      # Twirp request limit for requests allowed in a minute.
      #
      # Returns integer representing requests per minute
      def twirp_authentication_fingerprint_by_path_max
        @twirp_authentication_fingerprint_by_path_max || TWIRP_AUTHENTICATION_FINGERPRINT_BY_PATH_MAX
      end
      attr_writer :twirp_authentication_fingerprint_by_path_max

      # API request limit for cpu time allowed to be consumed by requests
      #
      # Returns integer representing milliseconds of cpu time
      def elapsed_time_by_authentication_fingerprint_max
        @elapsed_time_by_authentication_fingerprint_max || ELAPSED_TIME_BY_AUTHENTICATION_FINGERPRINT_MAX
      end
      attr_writer :elapsed_time_by_authentication_fingerprint_max

      # API request limit for cpu time allowed to be consumed by graphql requests
      #
      # Returns integer representing milliseconds of cpu time
      def elapsed_authenticated_time_by_path_graphql_max
        @elapsed_authenticated_time_by_path_graphql_max || ELAPSED_AUTHENTICATED_TIME_BY_PATH_GRAPHQL_MAX
      end
      attr_writer :elapsed_authenticated_time_by_path_graphql_max

      # API request limit for cpu time used by searches
      #
      # Returns integer representing milliseconds of cpu time
      def search_elapsed_time_max
        @search_elapsed_time_max || SEARCH_ELAPSED_TIME_MAX
      end
      attr_writer :search_elapsed_time_max

      # API request limit for cpu time used by searches
      #
      # Returns integer representing milliseconds of cpu time
      def search_elapsed_time_staff_max
        @search_elapsed_time_staff_max || SEARCH_ELAPSED_TIME_STAFF_MAX
      end
      attr_writer :search_elapsed_time_staff_max

      # API request limit ttl for cpu time used by searches
      #
      # Returns integer representing ttl in seconds
      def search_elapsed_time_ttl
        @search_elapsed_time_ttl || SEARCH_ELAPSED_TIME_TTL
      end
      attr_writer :search_elapsed_time_ttl

      # Returns an integer representing the maximum number of times
      # an actor can generate timed-out elasticsearch searches within the default TTL.
      def search_timed_out_actor_max
        @search_timed_out_actor_max || SEARCH_TIMED_OUT_ACTOR_MAX
      end
      attr_writer :search_timed_out_actor_max

      # Returns an integer representing the TTL for the search timed out limiter,
      # in units of seconds.
      def search_timed_out_ttl
        @search_timed_out_ttl || SEARCH_TIMED_OUT_TTL
      end
      attr_writer :search_timed_out_ttl

      # API request limit for concurrent authentication requests
      #
      # Returns integer representing request count
      def concurrent_authentication_fingerprint_max
        @concurrent_authentication_fingerprint_max || CONCURRENT_AUTHENTICATION_FINGERPRINT_MAX
      end
      attr_writer :concurrent_authentication_fingerprint_max

      # API request limit ttl for concurrent authentication requests
      #
      # Returns integer representing ttl in seconds
      def concurrent_authentication_fingerprint_ttl
        @concurrent_authentication_fingerprint_ttl || CONCURRENT_AUTHENTICATION_FINGERPRINT_TTL
      end
      attr_writer :concurrent_authentication_fingerprint_ttl

      # API request limit for searches from an ip address
      #
      # Returns integer representing request count
      def search_ip_address_max
        @search_ip_address_max || SEARCH_IP_ADDRESS_MAX
      end
      attr_writer :search_ip_address_max

      # API request limit ttl for searches from an ip address
      #
      # Returns integer representing ttl in seconds
      def search_ip_address_ttl
        @search_ip_address_ttl || SEARCH_IP_ADDRESS_TTL
      end
      attr_writer :search_ip_address_ttl

      # API request limit for requests for PAT requests
      #
      # Returns integer representing request count
      def requests_by_pat_max
        @requests_by_pat_max || REQUESTS_BY_PAT_MAX
      end
      attr_writer :requests_by_pat_max

      def graphql_excessive_db_count_max
        @graphql_excessive_db_count_max || GRAPHQL_EXCESSIVE_DB_COUNT_MAX
      end
      attr_writer :graphql_excessive_db_count_max

      def graphql_excessive_db_count_threshold
        @graphql_excessive_db_count_threshold || GRAPHQL_EXCESSIVE_DB_COUNT_THRESHOLD
      end
      attr_writer :graphql_excessive_db_count_threshold

      def graphql_excessive_db_count_ttl
        @graphql_excessive_db_count_ttl || GRAPHQL_EXCESSIVE_DB_COUNT_TTL
      end
      attr_writer :graphql_excessive_db_count_ttl

      def graphql_repeated_timeout_max
        @graphql_repeated_timeout_max || GRAPHQL_REPEATED_TIMEOUT_MAX
      end
      attr_writer :graphql_repeated_timeout_max

      def graphql_repeated_timeout_ttl
        @graphql_repeated_timeout_ttl || GRAPHQL_REPEATED_TIMEOUT_TTL
      end
      attr_writer :graphql_repeated_timeout_ttl

      # API request limit for internal requests allowed in a minute
      #
      # Returns integer representing requests per minute
      def internal_ip_less_authentication_fingerprint_by_path_max
        @internal_ip_less_authentication_fingerprint_by_path_max || INTERNAL_IP_LESS_AUTHENTICATION_FINGERPRINT_BY_PATH_MAX
      end
      attr_writer :internal_ip_less_authentication_fingerprint_by_path_max

      # API request limit for cpu time allowed to be consumed by internal requests
      #
      # Returns integer representing milliseconds of cpu time
      def internal_ip_less_elapsed_time_by_authentication_fingerprint_max
        @internal_ip_less_elapsed_time_by_authentication_fingerprint_max || INTERNAL_IP_LESS_ELAPSED_TIME_BY_AUTHENTICATION_FINGERPRINT_MAX
      end
      attr_writer :internal_ip_less_elapsed_time_by_authentication_fingerprint_max

      # API request limit for concurrent internal authentication requests
      #
      # Returns integer representing request count
      def internal_ip_less_concurrent_authentication_fingerprint_max
        @internal_ip_less_concurrent_authentication_fingerprint_max || INTERNAL_IP_LESS_CONCURRENT_AUTHENTICATION_FINGERPRINT_MAX
      end
      attr_writer :internal_ip_less_concurrent_authentication_fingerprint_max

      # API request limit ttl for concurrent internal authentication requests
      #
      # Returns integer representing ttl in seconds
      def internal_ip_less_concurrent_authentication_fingerprint_ttl
        @internal_ip_less_concurrent_authentication_fingerprint_ttl || INTERNAL_IP_LESS_CONCURRENT_AUTHENTICATION_FINGERPRINT_TTL
      end
      attr_writer :internal_ip_less_concurrent_authentication_fingerprint_ttl

      # API request limit for cpu time allowed to be consumed by internal graphql requests in Proxima
      # Returns integer representing milliseconds of cpu time
      def internal_ip_less_elapsed_authenticated_time_by_path_graphql_max
        @internal_ip_less_elapsed_authenticated_time_by_path_graphql_max || INTERNAL_IP_LESS_ELAPSED_AUTHENTICATED_TIME_BY_PATH_GRAPHQL_MAX
      end
      attr_writer :internal_ip_less_elapsed_authenticated_time_by_path_graphql_max

      # Internal GraphQL request limit for read/write requests allowed in a minute.
      #
      # Returns integer representing requests per minute
      def internal_ip_less_graphql_authentication_fingerprint_max
        @internal_ip_less_graphql_authentication_fingerprint_max || INTERNAL_IP_LESS_GRAPHQL_AUTHENTICATION_FINGERPRINT_MAX
      end
      attr_writer :internal_ip_less_graphql_authentication_fingerprint_max

      # Internal GraphQL request limit for db queries allowed in a minute.
      #
      # Returns integer representing db queries per minute
      def internal_ip_less_graphql_excessive_db_count_max
        @internal_ip_less_graphql_excessive_db_count_max || INTERNAL_IP_LESS_GRAPHQL_EXCESSIVE_DB_COUNT_MAX
      end
      attr_writer :internal_ip_less_graphql_excessive_db_count_max

      # Internal GraphQL request limit for db queries threshold to start recording to cache.
      #
      # Returns integer representing db queries threshold
      def internal_ip_less_graphql_excessive_db_count_threshold
        @internal_ip_less_graphql_excessive_db_count_threshold || GRAPHQL_EXCESSIVE_DB_COUNT_THRESHOLD
      end
      attr_writer :internal_ip_less_graphql_excessive_db_count_threshold

      # Internal GraphQL request limit ttl for db queries.
      #
      # Returns integer representing ttl in seconds
      def internal_ip_less_graphql_excessive_db_count_ttl
        @internal_ip_less_graphql_excessive_db_count_ttl || GRAPHQL_EXCESSIVE_DB_COUNT_TTL
      end
      attr_writer :internal_ip_less_graphql_excessive_db_count_ttl

      # Internal GraphQL request limit for repeated timeouts allowed in a minute.
      #
      # Returns integer representing repeated timeouts within the TTL window.
      def internal_graphql_repeated_timeout_max
        @internal_graphql_repeated_timeout_max || GRAPHQL_REPEATED_TIMEOUT_MAX
      end
      attr_writer :internal_graphql_repeated_timeout_max

      # Internal GraphQL request limit ttl for repeated timeouts.
      #
      # Returns integer representing ttl in seconds
      def internal_graphql_repeated_timeout_ttl
        @internal_graphql_repeated_timeout_ttl || GRAPHQL_REPEATED_TIMEOUT_TTL
      end
      attr_writer :internal_graphql_repeated_timeout_ttl
    end
  end

  extend Config::RequestLimits
end
