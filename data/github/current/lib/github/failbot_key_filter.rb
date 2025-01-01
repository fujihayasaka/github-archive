# typed: true
# frozen_string_literal: true

module GitHub
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
    def call(context, sensitive_context)
      return context if GitHub.bypass_failbot_filter_logic?

      if @raise_on_filter
        call_with_raise(context, sensitive_context)
      else
        call_without_raise(context, sensitive_context)
      end
    end

    private

    # Raises an error if keys are present that violate the allowable key policy.
    def call_with_raise(context, sensitive_context)
      original_context = context.dup
      new_context, sensitive_context = call_without_raise(context, sensitive_context)

      if sensitive_context.keys.any?
        # (indifferent_access not available everywhere)
        disallowed_keys = sensitive_context.keys + sensitive_context.keys.map(&:to_sym)
        raise "Filtered keys detected: #{original_context.slice(*disallowed_keys)}"
      end

      [new_context, sensitive_context]
    end

    # Silently removes keys that violate the allowable key list policy.
    def call_without_raise(context, sensitive_context)
      context.each do |k, v|
        if !GitHub::FailbotKeyConfiguration.key_allowed?(k.to_s.tr("#", ""))
          sensitive_context[k] = v
          context.delete(k)
        end
      end
      [context, sensitive_context]
    end

    # Before we can send additional data to Sentry, some works needs to be done to categorize
    # what type of sensitive data, if any, it can contain.
    #
    # - review https://thehub.github.com/epd/engineering/dev-practicals/observability/exception-tracking/secure-exceptions/#identifying-your-sensitive-data
    #   for knowing what is considered sensitive
    # - add your key to docs/sensitive-data.yaml with information about the key
    # - test/fast/linting/failbot_key_filter_test.rb will point you in the right direction

    RESTRICTED_CUSTOMER_PII_KEYS = %w[
      referrer
      remote_ip
      repo
      url
      migrator_config
      gh.migration_tools.gh_migrator.config
      gh.migration_tools.migration.repository.url
      gh.rate_limit.secondary.key
      gh.rate_limit.primary.key
      gh.actor.login
      gh.organization.login
    ]
  end
end
