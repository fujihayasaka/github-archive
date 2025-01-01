# typed: true
# frozen_string_literal: true

require "active_support/core_ext/object/blank"

module GitHub
  module Config
    # This helper class wraps an environment with accessors that will try
    # first a site specific, then region specific and finally global.
    # These variables look like for example CP1_IAD_MEMCACHED_SERVERS, or
    # VA3_CP1_MEMCACHED_SERVERS for site specific ones. Regional versions
    # would look like IAD_REDIS_URL.
    class PrefixEnvironment

      BOOLEAN_CASTS = { "" => nil, "1" => true, "0" => false, "true" => true, "false" => false }

      # Initialize a PrefixEnvironment helper instance.
      #
      # environment - The environment Hash to wrap. Defaults to ENV.
      # region      - The region to use for key prefixes. Defaults to GitHub.server_region
      # site        - The site to use for key prefixes. Defaults to GitHub.server_site
      def initialize(environment: ENV, region: GitHub.server_region, site: GitHub.server_site)
        @environment = environment
        @region = region
        @site = site
      end

      # Public: Retrieve the given key from the environment.
      #
      # This checks the environment for a prefixed key first, then
      # falls back to the un-prefixed key.
      #
      # Returns nil if the key wasn't found.
      def [](key)
        fetch key, nil
      end

      # Public: fetch the given key from the environment.
      #
      # key     - the String key to fetch
      # default - the optional value to return if the key isn't found.
      # &block  - If the key wasn't found, return the value of this block.
      #
      # This has the same semantics and variable arguments as Hash#fetch. It
      # checks for prefixed keys first then falls back to the
      # un-prefixed key.
      def fetch(*args, &block)
        # rb_check_arity equivalent
        if args.size == 0 || args.size > 2
          raise ArgumentError, "wrong number of arguments (#{args.size} for 1..2)"
        end

        key = args[0]
        default = args[1]
        site_key = "#{site_prefix}#{key}"
        region_key = "#{region_prefix}#{key}"

        value = @environment.fetch(site_key, nil)
        return value if value.present?
        value = @environment.fetch(region_key, nil)
        return value if value.present?
        value = @environment.fetch(key, nil)
        return value if value.present?

        if args.size == 1 && !block_given?
          raise KeyError, "key not found: \"#{key}\""
        end

        block_given? ? block.call : default
      end

      def fetch_boolean(env_var, default)
        value = fetch(env_var, default)

        if BOOLEAN_CASTS.key?(value)
          BOOLEAN_CASTS[value]
        else
          value
        end
      end

      private

      # Internal: the site prefix. Uppercase version of the configured
      # site, e.g. "cp1_iad" --> "CP1_IAD"
      def site_prefix
        @site_prefix ||= env_convert(@site)
      end

      # Internal: the site prefix. Uppercase version of the configured
      # site, e.g. "iad" --> "IAD"
      def region_prefix
        @region_prefix ||= env_convert(@region)
      end

      def env_convert(str)
        return nil unless str
        "#{str.gsub("-", "_").upcase}_"
      end
    end
  end
end
