# typed: true
# frozen_string_literal: true

# This is the base class for Search::Limiters.
#
# Search rate limiters are designed primarily to be used with
# `Search::RateLimitRegistry` and so there's no true factory pattern for each
# rate limiter to conform to, thus this base class does not implement any
# common method for checking a rate limit or incrementing it. (This also means
# there's nothing tying them directly to Search::RateLimitRegistry - they can
# be used elsewhere just as easily.) Each subclass will determine how its
# limit is stored and checked, what the units of measure are for the limit, how
# the cost of each request is calculated, and how the cost is applied to the
# limit. This provides a lot of flexibility for designing rate limits based on
# more than just the number of requests made.
module Search
  module Limiters
    class Base
      DATADOG_PREFIX_ROOT = "search.limiters"

      KEY_NAME_FILTER = /[^-\w\.]/
      KEY_NAME_REPLACEMENT = "-"

      attr_reader :name, :limit, :ttl, :context, :strategy

      # Create a new rate limit.
      #
      # name - the name of the rate limiter. Will be reported in metrics and
      #        logging.
      # limit - The maximum accrued cost that each unique actor_id can use
      #         during each TTL window.
      # ttl - The "time to live" for rate limiting. The default is 60 seconds.
      # context - Useful for reporting what context this rate limiter was
      #           applied to for a shared strategy, i.e. `web` or `api`. Will
      #           be added to metrics and logging info.
      # strategy - Useful for reporting if timing for each search type will be
      #            tracked individually or in a shared bucket. Subclasses can
      #            use this to generate appropriate keys.
      def initialize(name:, limit:, ttl: 60, context: :default, strategy: :individual)
        @name = name.freeze
        @limit = limit.freeze
        @ttl = ttl.freeze
        @context = context.freeze
        @strategy = strategy.freeze
      end

      # Trigger a dogstats increment operation for a given event which will
      # include attribute tags for the limiter instance. Other tags can be
      # passed in to be appended to the defaults.
      def stat(event, additional_metrics_tags = [])
        tags = [
          "name:#{name}",
          "limit:#{limit}",
          "ttl:#{ttl}",
          "context:#{context}",
          "strategy:#{strategy}"
        ] + additional_metrics_tags
        stat_name = "#{datadog_prefix}.#{key_safe(event)}"
        GitHub.dogstats.increment(stat_name, tags: tags)
      end

      # Publish an event notification on a rate limit event which includes
      # attributes for the limiter instance in the payload. The generated hydro
      # event will include the request context if one was present, which can be
      # used to join to other tables in the datawarehouse. You can optionally
      # provide other attributes which will be added to the payload:
      #
      # Payload options:
      #   actor - the User who triggered the rate limit event. Required, but
      #           can be nil for anonymous users.
      #   halted - whether the rate limit event halted the request. This allows
      #            for passive mode rate limiters that merely report that a rate
      #            limit was reached. Useful for testing rate limits before
      #            making them actively rate limit. Your limiters should set
      #            this to true when calling if they halted the request.
      #            Required.
      #   search_type - The search type that was detected for the query.
      #                 Optional.
      def publish(payload_options = {})
        payload = {
          name: name,
          limit: limit,
          ttl: ttl,
          context: context,
          strategy: strategy,
          actor: payload_options.fetch(:actor),
          halted: payload_options.fetch(:halted),
          search_type: payload_options.fetch(:search_type, nil)
        }
        GlobalInstrumenter.instrument("search.rate_limit", payload)
      end

      # Provides a reasonable default for generating unique search keys to track
      # limits per actor. Can be overridden or ignored by subclasses based on
      # their specific requirements.
      def key(actor_id, search_type)
        key_name = key_safe(name)
        if strategy == :grouped
          "#{key_name}:#{key_safe(actor_id)}"
        else
          "#{key_name}:#{key_safe(search_type)}:#{key_safe(actor_id)}"
        end
      end

      def datadog_prefix
        class_name = self.class.name&.demodulize.parameterize
        "#{DATADOG_PREFIX_ROOT}.#{class_name}"
      end

      private

      def key_safe(component)
        component.to_s.downcase.gsub(KEY_NAME_FILTER, KEY_NAME_REPLACEMENT)
      end
    end
  end
end
