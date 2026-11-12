# frozen_string_literal: true

require "active_record"
require "aqueduct"
require "failbot"
require "octokit"
require "redis"
require "trilogy"

require "./lib/dependabot/sentry"
require "./lib/dependabot/telemetry"

module Dependabot
  class Exceptions
    RECOVERABLE_AQUEDUCT_EXCEPTION_CLASSES = [
      Aqueduct::Client::ClientError, Aqueduct::Client::RequestError,
    ].freeze

    # Use the translated ActiveRecord exception classes rather than raw Trilogy
    # errors. ActiveRecord's TrilogyAdapter#translate_exception converts all
    # connection-related Trilogy errors (EOFError, ConnectionClosed,
    # ConnectionRefusedError, TimeoutError, etc.) into these ActiveRecord types
    # before they reach the job layer, so this list stays in sync with upstream
    # automatically.
    RECOVERABLE_DATABASE_EXCEPTION_CLASSES = [
      ActiveRecord::ConnectionFailed,
      ActiveRecord::ConnectionNotEstablished,
      ActiveRecord::AdapterTimeout,
      ActiveRecord::StatementTimeout,
      ActiveRecord::Deadlocked,
      ActiveRecord::LockWaitTimeout,
    ].freeze

    RECOVERABLE_REDIS_EXCEPTION_CLASSES = [
      Redis::CannotConnectError,
    ].freeze

    UPDATER_FAILBOT_APP_NAME = "deltaforce"

    # Add info to be sent in the next exceptions report in the current thread,
    # should one occur.
    #
    # info  - Hash of name => value pairs to include in the exception report.
    # block - When given, the info is removed from the current context after the
    #         block is executed.
    #
    # Returns the value returned by the block when given; otherwise, returns nil.
    def self.push(info = {}, &)
      # Setting which fields are tags here to make it easier to manage.
      # Tags start with # and are indexed by Sentry.
      info = Dependabot::Sentry.tag_indexed_telemetry_attributes(info) if info.instance_of?(Hash)
      validate_exception_context!([info])
      ::Failbot.push(info, &)
    end

    # Reset the current thread's context stack to a pristine state.
    def self.reset!
      ::Failbot.reset_context
    end

    # Stack of context information to include in the next failbot report. These
    # hashes are condensed down into one and included in the next report. Don't
    # mess with this structure directly - use the #push and #reset! methods.
    def self.context
      ::Failbot.context
    end

    def self.report(err, other = {})
      if exception_satisfies?(err, :updater_error?)
        # ensure Updater errors are not reported to the API's project
        other = other.merge({ app: UPDATER_FAILBOT_APP_NAME })
      else
        instrument_reported_exception(err)
      end

      other = Dependabot::Sentry.tag_indexed_telemetry_attributes(other)

      # Each push is validated at push time, so we only need to validate
      # the `other` hash here. Failbot.context includes Failbot's own
      # default context entries which aren't in our telemetry allowlist.
      validate_exception_context!([], other)
      ::Failbot.report(err, other)
    end

    def self.report!(err, other = {})
      other = Dependabot::Sentry.tag_indexed_telemetry_attributes(other)

      validate_exception_context!([], other)
      ::Failbot.report!(err, other)

      instrument_reported_exception(err)
    end

    private_class_method def self.updater_error?(err)
      return false unless err
      return false unless err.respond_to?(:updater_error?) && err.updater_error?

      MetricsClient.increment(
        "updater_errors",
        tags: {
          exception_class: err.original_error_class,
        }
      )

      true
    end

    private_class_method def self.exception_satisfies?(err, check_method)
      check = method(check_method)
      return true if check.call(err)
      return true if err.respond_to?(:original_exception) && check.call(err.original_exception)
      return true if err.respond_to?(:cause) && check.call(err.cause)

      false
    end

    private_class_method def self.instrument_reported_exception(err)
      MetricsClient.increment("reported_exceptions",
                              tags: { exception_class: err.class.to_s })
    end

    private_class_method def self.validate_exception_context!(context, other = {})
      return if Rails.env.production?

      context.each do |attrs|
        Dependabot::Telemetry.validate_exception_attributes!(attrs)
      end
      Dependabot::Telemetry.validate_exception_attributes!(other)
    end
  end
end
