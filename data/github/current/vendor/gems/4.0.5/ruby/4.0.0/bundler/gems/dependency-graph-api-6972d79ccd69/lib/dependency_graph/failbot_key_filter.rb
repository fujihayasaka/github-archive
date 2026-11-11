# frozen_string_literal: true

require "set"
require_relative "./failbot_key_tagger"

# Wholesale copied from gh/gh ( lib/github/failbot_key_filter.rb ).
module DependencyGraph
  # Before we can send additional data to Sentry, some works needs to be done to categorize
  # what type of sensitive data, if any, it can contain.
  #
  # - review https://thehub.github.com/engineering/development-and-ops/observability/sentry/secure-exceptions/#identifying-your-sensitive-data
  #   for knowing what is considered sensitive
  # This is fashioned after dotcom's approach, but we use our own list in dg-api
  # We add all keys in failbot_key_tagger to this set to determine what is allowed.
  ALLOWED_SENTRY_KEYS = %w[
    app
    backtrace
    class
    created_at
    exception_detail
    gh.repo.id
    hydro_offset
    hydro_key
    hydro_topic
    hydro_partition
    message
    method
    rollup
    user
    rpc.method
    rpc.service
  ]

  # Removes keys from the context if they are not present in the allowable
  # key list. Failbot context payloads are sent to an external service provider
  # at sentry.io, and we want to prevent leaking personally identifiable
  # information.
  #
  # If you need to send a new key to Sentry, and its values don't contain
  # private information, open a pull request adding it to the list of keys
  # below.
  class FailbotKeyFilter
    def initialize(raise_on_filter: false)
      @raise_on_filter = raise_on_filter
    end

    # Removes keys from the context.
    #
    # context - The Hash from which to remove keys.
    #
    # Returns the context Hash that was passed in.
    def call(context)
      return context if DependencyGraphAPI.enterprise?

      if @raise_on_filter
        call_with_raise(context)
      else
        call_without_raise(context)
      end
    end

    private

    # Raises an error if keys are present that violate the allowable key policy.
    def call_with_raise(context)
      context_keys = context.keys.map { |k| k.to_s.tr("#", "") }
      disallowed_keys = context_keys - ALLOWED_KEYS
      if disallowed_keys.any?
        # (indifferent_access not available everywhere)
        disallowed_keys = disallowed_keys + disallowed_keys.map(&:to_sym)
        raise "Filtered keys detected: #{context.slice(*disallowed_keys)}"
      end
      context
    end

    # Silently removes keys that violate the allowable key list policy.
    def call_without_raise(context)
      context.delete_if do |key, value|
        key = key.to_s.tr("#", "")
        !ALLOWED_KEYS_SET.include?(key)
      end
    end

    ALLOWED_KEYS_SET = (DependencyGraph::ALLOWED_SENTRY_KEYS + DependencyGraph::TAGGED_SENTRY_KEYS).to_set
  end
end
