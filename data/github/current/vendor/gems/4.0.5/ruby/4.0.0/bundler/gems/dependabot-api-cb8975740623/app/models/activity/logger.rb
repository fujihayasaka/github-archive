# frozen_string_literal: true

# Activity::Logger is a utility class which centralises the logging and notification
# of key transactions for defined context.
#
# An Activity::Logger should be instantiated with a context name and any values
# which should be attached to all events recorded by this instance.
#
# activity_log = Activity::Logger.new(
#   context_name: "repository",
#   context: {
#     account_id: account.id,
#     account_github_id: account.github_id,
#     repository_id: id,
#     repository_github_id: github_id,
#     nwo: nwo,
#   }
# )
#
# activity_log.record_event("my-event-name", tags: { event-info: "foo" })
#
# See our general guidelines on Logging at GitHub for more information:
# => https://thehub.github.com/epd/engineering/dev-practicals/observability/logging/
#
module Activity
  class Logger
    DEFAULT_CONTEXT = "system"

    attr_reader :context_name, :context

    def initialize(context_name: DEFAULT_CONTEXT, context: {})
      @context_name = context_name.parameterize.dasherize
      @context = context
    end

    # When recording an event, consider:
    # - Should the event should be noticed before any logic that could error?
    # - Does any downstream logic rely on Activity::PauseManager updating the
    #   Repository for your event beforehand?
    #
    # As a general rule of thumb:
    # - record first for user-triggered events so we always see what they tried to
    #   do even if it fails.
    # - record last for dependabot-triggered events so we do only see events where
    #   we succeeded. Prefer to log failures explicitly instead.
    def record_event(name, tags: {})
      validate_tags(tags)

      event_name = full_event_name(name)

      Dependabot::Logger.log_context(context_tags) do
        Dependabot::Logger.info(
          {
            activity_log_event: event_name,
          }.merge(tags)
        )
      end

      # Let the pause manager know
      Activity::PauseManager.handle_activity_log_event(event_name, context_tags.merge(tags))
    rescue StandardError => e
      # If we are in production, notice the error but don't block execution
      raise unless Rails.env.production?

      Dependabot::Exceptions.report!(e)
    end

    private

    # Permit nested event names by avoiding clobbering "."
    # e.g. name = comment.rebase-request
    def full_event_name(name)
      [
        context_name,
        name.split(".").map do |str|
          str.parameterize.dasherize
        end,
      ].join(".")
    end

    def context_tags
      { context: context_name }.merge(context)
    end

    def validate_tags(tags)
      common_keys = tags.keys.map(&:to_s) & reserved_tags.map(&:to_s)

      raise ArgumentError, tag_error_message(common_keys) if common_keys.any?
    end

    def reserved_tags
      context_tags.keys + [:activity_log_event]
    end

    def tag_error_message(illegal_tags)
      "The #{'tag'.pluralize(illegal_tags.count)} '#{illegal_tags.join(', ')}' would overwrite defaults"
    end
  end
end
