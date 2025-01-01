# typed: true
# frozen_string_literal: true

# setup Failbot for exceptions reporting.
require "github"
require "failbot/exit_hook"
require "rollup"
# require 'securerandom' for UUID generation
require "securerandom"

# require 'github/logger' for reporting redacted exceptions to Splunk
require "github/logger"

require "sensitive_data"
require "github/failbot_backtrace"
require "github/sql/digester"
require "github/exceptions/cause_catalog_service_finder"
require "github/exceptions/basic_rollup"

# failbot settings from environment override GitHub::Config
settings = ENV.to_hash.keep_if { |k, _v| k.start_with?("FAILBOT_") }
settings = GitHub.failbot.merge(settings)

default_context = {
  "gh.deployment.sha" => GitHub.current_sha,
  "gh.deployment.ref" => GitHub.current_ref,
  "app" => "github",
  "ruby.version" => RUBY_DESCRIPTION,
  "host.name" => ENV["KUBE_NODE_HOSTNAME"],
  "deployment.environment" => GitHub.failbot_deployed_to,
  "k8s.namespace.name" => GitHub.kubernetes_namespace,
  # the fields below are needed by failbotg, see https://github.com/github/failbotg/blob/main/docs/api.md
  "release" => GitHub.current_sha,
  "deployed_to" => GitHub.failbot_deployed_to,
}

TIMEOUT_FAILBOT_APP = "github-timeout"

# We need to set the instrumenter for Failbot _before_ calling
# Failbot.setup because the instrumenter is used to configure
# the HTTP backend
Failbot.instrumenter = ActiveSupport::Notifications
Failbot.setup(settings, default_context) do |config|
  config.register_frame_processing_pipeline([
    GitHub::FailbotBacktrace::GitRPCFrameProcessor,
    GitHub::FailbotBacktrace::RailsRootPrefixProcessor,
  ])
end

# Enforce allowable key list before sending to Sentry.
failbot_key_filter = GitHub::FailbotKeyFilter.new(raise_on_filter: GitHub.raise_on_failbot_filter?)
failbot_key_tagger = GitHub::FailbotKeyTagger.new(enabled: GitHub.enable_failbot_tags?)
failbot_scrubber = GitHub::FailbotScrubber.new(enabled: GitHub.enable_failbot_scrubbing?)

# Make adjustments to Failbot context before it gets reported
#
# @params exception the exception object being reported
# @params context the combined Failbot context Hash so far, including defaults, everything Failbot.push'd, and message,
#         class and backtrace extracted from the exception. Failbot#squash_context ensures the keys are strings, not symbols
#
# Note: The full environment may not be available here if run from hooks, etc.  Vanilla Ruby only.

Failbot.before_report do |exception, context, sensitive_context, thread|
  result = {}

  # Populate the datacenter lazily, in order to avoid a circular dependency.
  # See https://github.com/github/github/commit/9bea1bfef0 for details.
  result[:"gh.infra.datacenter.name"] = GitHub.datacenter
  result[:"gh.infra.site"] = GitHub.server_site
  result[:"gh.infra.cloud.region"] = GitHub.server_region

  result["#yjit_enabled"] = defined?(RubyVM::YJIT.enabled?) && RubyVM::YJIT.enabled?

  # Exceptions raised from an ActiveRecord adapter contain a connection pool that we can reference for DB info.
  if (pool = exception.connection_pool if exception.respond_to?(:connection_pool))
    result["#gh.db.connection.pool.name"] = pool.connection_class.name.split("::").last
    result["gh.db.connection.pool.role"] = pool.role.to_s
  end

  if app = app_for(exception, context)
    result[:app] = app
  end

  # Attributing the service that caused a timeout isn't straightforward.
  # To avoid confusion, don't tag timeout issues with a cause catalog service.
  finder = GitHub::Exceptions::CauseCatalogServiceFinder.new(exception, context: context)
  if app != TIMEOUT_FAILBOT_APP && finder.service_owner
    result["#cause_catalog_service"] = finder.service_owner
    result["cause_catalog_service_frame"] = finder.relevant_backtrace_line
  end

  # Ensure that critical exceptions are tagged as critical, and that exceptions
  # that are not caught and cause the process to exit are tagged as critical.
  critical, gh_critical, halting = Failbot.squash_contexts(context, result).values_at("critical", "gh.exception.is_critical", "halting")
  result["#critical"] = result["critical"] = critical || gh_critical || halting || false

  if GitHub::Exceptions::BasicRollup.should_rollup?(exception)
    result["rollup_significant_frame"] = "N/A (BasicRollup)"
  elsif GitHub::Exceptions::ActiveRecordRollup.should_rollup?(exception)
    result["rollup_significant_frame"] = GitHub::Exceptions::ActiveRecordRollup.rollup_significant_frame(exception)
  else
    result["rollup_significant_frame"] = Rollup.first_significant_frame(exception.backtrace, scrub_root_path: GitHub::AppEnvironment.root.to_s + "/")
  end

  # Append any enabled feature flags captured by the feature flag data collector
  if defined?(FlipperSubscriber)
    result[:enabled_feature_flags] = FlipperSubscriber.enabled_tested_features.to_s
  end

  # generate a failbot_id so we can search for it in splunk
  result["failbot_id"] = SecureRandom.uuid

  context_keys_before_redaction = context.keys.dup

  failbot_key_filter.call(context, sensitive_context)
  failbot_key_tagger.convert_keys!(context)
  failbot_scrubber.call(context, sensitive_context, thread)

  if exception_needs_redacting?(exception)
    if context["exception_detail"]
      context["exception_detail"].each_with_index do |payload, index|
        if payload && payload["value"]
          # This is an immutable hash that can't be modified but doesn't need to be redacted
          next if payload == Failbot::ExceptionFormat::Structured::FURTHER_CAUSES_WERE_OMITTED
          # This value may already have been populated by the scrubber. In which case we do not want to overwrite it with a scrubbed value
          sensitive_context["exception_detail.#{index}.value"] ||= payload["value"]
          context["exception_detail"][index]["value"] = redacted_message(exception)
        end
      end
    end
  end

  # Track keys sent to failbot that are not compliant with our redaction
  # requirements
  unless GitHub.enterprise?
    normalise_context_keys = lambda do |array|
      array
        .map { |k| k.to_s.delete_prefix("#") }
        .compact
        .sort
        .uniq
    end

    keys_before_redaction = normalise_context_keys.call(context_keys_before_redaction)
    keys_after_redaction  = normalise_context_keys.call(result.keys)

    redaction_undocumented_keys = keys_before_redaction.select do |k|
      !GitHub::FailbotKeyConfiguration.instance.definitions.keys.include?(k)
    end

    redaction_leaked_keys = keys_after_redaction.select do |k|
      !GitHub::FailbotKeyConfiguration.key_allowed?(k)
    end

    result[:"redaction_undocumented_keys"]          = redaction_undocumented_keys
    result[:"#redaction_undocumented_keys_present"] = redaction_undocumented_keys.present?
    result[:"redaction_leaked_keys"]                = redaction_leaked_keys
    result[:"#redaction_leaked_keys_present"]       = redaction_leaked_keys.present?
  end

  [result, sensitive_context]
end

# ExceptionRedacting defines a base implementation of #needs_redacting? and
# #with_redacting! for all Exception subclasses.
#
# If you have an exception instance that needs redacting at runtime (for
# example, when rescuing StandardError from a source you can't control or don't
# know), call #with_redacting!.
#
# For exception classes you control that should always be redacted, defining
# #needs_redacting? on the class is better.
module ExceptionRedacting
  # Returns true if this exception should be redacted in Sentry. Default: false
  def needs_redacting?
    @needs_redacting ||= false
  end

  # Set needs_redacting? to true. Returns the exception for chaining.
  #
  # Example:
  #
  #   Failbot.report(exception.with_redacting!)
  def with_redacting!
    @needs_redacting = true
    self
  end
end
Exception.include(ExceptionRedacting)

FAILBOT_ERRORS_NEEDING_REDACTING = [
  # wraps message from Trilogy::ProtocolError
  "Trilogy::ProtocolError",
  # leaks information about duplicate key entry: trilogy_query_recv: 1062 Duplicate entry 'user@example.com' for key 'index_user_licenses_on_business_id_and_email'
  "ActiveRecord::RecordNotUnique",
  # leaks information about user and repo names
  "ActionController::UrlGenerationError",
  # leak full SQL queries with values when used through Vitess
  "ActiveRecord::StatementTimeout",
  "ActiveRecord::QueryCanceled",
  # leaks full SQL queries
  "ActiveRecord::ReadOnlyError",
  # Elastomer::Error subclasses leak PII
  # - ElastomerClient::Client::Error includes information about the query performed
  "Elastomer::Error",
  "ElastomerClient::Error",
  # leak information about the URI being parsed
  "URI::InvalidURIError",
  "Addressable::URI::InvalidURIError",
  # leaks GitHub::Cache values that have invalid encoding
  "EncodingFixer::InvalidEncodingError",
  # leak information about the parsed string
  "JSON::ParserError",
  "Yajl::ParseError",
  # 3rd party error without insurance of not leaking PII
  "MessagePack::UnpackError",
  "Zlib::Error",
  # Potential to leak PII
  "Net::SMTPError"
]

# Returns true if the exception or any of its nested causes (up to the limit
# that failbot will serialize) needs to be redacted in Sentry.
def exception_needs_redacting?(root_exception)
  return false if GitHub.bypass_failbot_filter_logic?

  depth = 0
  exception = root_exception
  loop do
    return true if exception.needs_redacting? || FAILBOT_ERRORS_NEEDING_REDACTING.any? { |c| exception_is_a?(exception, c) }
    depth += 1
    break false unless (exception = exception.cause)
    break false if depth > Failbot::MAXIMUM_CAUSE_DEPTH
  end
end

def exception_is_a?(exception, class_name)
  exception.class.ancestors.any? { |x| x.name == class_name.to_s }
end

def app_for(exception, context)
  return "github-freno" if exception_is_a?(exception, "Freno::Error")

  timeouts = [
    "Timeout::Error",
    "GitRPC::Timeout",
    "GitRPC::SpawnFailure",
  ]
  return TIMEOUT_FAILBOT_APP if timeouts.any? { |c| exception_is_a?(exception, c) }

  return "github-spokes-api-throttling" if exception_is_a?(exception, "SpokesAPI::ResourceExhausted")

  external_errors = [
    "Braintree::BraintreeError",
    "Twilio::REST::TwilioError",
    "Twilio::REST::RestError",
  ]
  return "github-external-request" if external_errors.any? { |c| exception_is_a?(exception, c) }

  zuora_errors = [
    "Zuorest::HttpError",
    "Billing::Zuora::Error",
  ]
  return "github-zuora" if zuora_errors.any? { |c| exception_is_a?(exception, c) }

  if query_interruption?(exception)
    if pages_query_in_message?(exception)
      "pages"
    elsif spokes_job?(context) || spokes_query_in_message?(exception)
      if !spokes_app_already_set?(context)
        "github-dgit"
      else
        nil
      end
    else
      "github-killed-query"
    end
  end
end

def pages_query_in_message?(exception)
  !(exception.message =~ /pages_replicas|pages_fileservers/).nil?
end

def spokes_app_already_set?(context)
  %w[github-dgit github-dgit-debug].include? context["app"]
end

def spokes_query_in_message?(exception)
  !(exception.message =~ /(network|repository|gist)_replicas|(repository|gist)_checksums|fileservers/).nil?
end

def spokes_job?(context)
  context["job"] && (context["job"].include?("DGit") || context["job"].include?("Dgit") || context["job"].include?("Spokes"))
end

def query_interruption?(exception)
  return false unless defined?(ActiveRecord)
  exception.is_a?(ActiveRecord::QueryCanceled) || exception.is_a?(ActiveRecord::StatementTimeout)
end

def redacted_message(exception)
  if GitHub::Exceptions::ActiveRecordRollup.should_rollup?(exception)
    generic_message = GitHub::Exceptions::ActiveRecordRollup.generic_message(exception)
    "[redacted] #{generic_message}(see Splunk for a detailed error message)"
  elsif exception.is_a? ActiveRecord::ReadOnlyError
    "Write query attempted while in readonly mode: [redacted]"
  else
    "[redacted]"
  end
end

Failbot.rollup do |exception, context|
  if query_interruption?(exception)
    sql = exception.message.sub(/\A.+?Query execution was interrupted: /, "")
    Digest::SHA256.hexdigest(GitHub::SQL::Digester.digest_sql(sql))
  elsif GitHub::Exceptions::ActiveRecordRollup.should_rollup?(exception)
    GitHub::Exceptions::ActiveRecordRollup.rollup(exception, context)
  elsif GitHub::Exceptions::BasicRollup.should_rollup?(exception)
    GitHub::Exceptions::BasicRollup.rollup(exception, context)
  else
    Rollup.generate(exception, scrub_root_path: GitHub::AppEnvironment.root.to_s)
  end
end

# hot fix for exception_message_from_hash failing when the exception has too many causes
Failbot::ExceptionFormat::Structured.class_eval do
  # given a hash generated by this class, return the exception message.
  def self.exception_message_from_hash(hash)
    return unless hash && hash["exception_detail"]
    detail = hash["exception_detail"].detect { |detail| detail && detail["type"] != "Notice" }
    return unless detail
    detail["value"]
  end

  # given a hash generated by this class, return the exception class name.
  def self.exception_classname_from_hash(hash)
    return unless hash && hash["exception_detail"]
    detail = hash["exception_detail"].detect { |detail| detail && detail["type"] != "Notice" }
    return unless detail
    detail["type"]
  end
end
