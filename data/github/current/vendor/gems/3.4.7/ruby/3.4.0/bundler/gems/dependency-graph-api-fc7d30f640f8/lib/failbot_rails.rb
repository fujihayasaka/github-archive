require "failbot"
require "rollup"
require "failbot/middleware"

require "rails"
require "rails/railtie"
require "active_support/concern"
require "active_support/parameter_filter"
require_relative "./dependency_graph/active_record_rollup.rb"
require_relative "./dependency_graph/failbot_logger.rb"
require_relative "./dependency_graph/failbot_key_tagger.rb"
require_relative "./dependency_graph/failbot_key_filter.rb"

# This is a monkey patch against the Failbot gem to add the "in_app" key to the backtrace frame.
# This is something that could probably be added to the Failbot gem itself, but since I don't know
# how well/if this will work yet, it is here for now.
module Failbot
  class Backtrace
    class Frame
      def self.new_frame_hash(path, line_number, method)
        {
          "filename" => path,
          "abs_path" => path,
          "lineno"   => line_number,
          "function" => method,
          "in_app"   => Rollup.significant?(path)
        }
      end
    end
  end
end

module FailbotRails
  class RailsRootPrefixProcessor
    def self.call(frame)
      if Rails.root
        @prefix ||= File.join(Rails.root, "")
        frame.delete_prefix(@prefix)
      end
    end
  end

  def self.setup(app_name, default_context = {})
    if _setup
      fail "FailbotRails already setup"
    end

    if !app_name.respond_to?(:to_str) || app_name.to_str.empty?
      raise ArgumentError, "app_name argument is required"
    end

    settings = ENV.to_hash

    if Rails.env.development? || Rails.env.test?
      settings["FAILBOT_BACKEND"] ||= "memory"
    end

    settings["FAILBOT_EXCEPTION_FORMAT"] ||= DependencyGraphAPI.enterprise? ? :haystack : :structured

    failbot_logger = DependencyGraph::FailbotLogger.new
    should_enable_tagger = Rails.env.production? && !DependencyGraphAPI.enterprise?
    failbot_key_tagger = DependencyGraph::FailbotKeyTagger.new(enabled: should_enable_tagger)
    failbot_key_filter = DependencyGraph::FailbotKeyFilter.new

    Failbot.setup(settings, default_context.merge({ app: app_name.to_str })) do |config|
      config.register_frame_processing_pipeline([RailsRootPrefixProcessor])
    end
    install_unhandled_exception_hook!

    # Override the default denylist for Rollup's first_significant_frame function
    # Properly refined, this will allow us to group exceptions by where they actually occur in our own code
    Rollup.denylist = [
      # Ruby bundled libraries, if we're using rbenv
      ".rbenv/",
      "/usr/share/rbenv/",

      # Ignore anything that isn't ours
      "vendor/",
    ]

    Failbot.rollup do |exception, context|
      if exception.is_a?(Rack::Timeout::RequestTimeoutException) && context.include?("rpc.method")
        # This is a specific case where we want to rollup on the rpc.method to group all the timeouts together,
        # since Rack::Timeout will timeout anywhere in the request stack.
        slug = "#{exception.class.name}|#{context["rpc_method"]}"
        Digest::SHA256.hexdigest(slug)
      elsif DependencyGraph::ActiveRecordRollup.should_rollup?(exception)
        DependencyGraph::ActiveRecordRollup.rollup(exception, context)
      else
        Rollup.generate(exception, scrub_root_path: Rails.root.to_s)
      end
    end

    # Unabashedly ripped off from gh/gh ( lib/github/config/failbot.rb )
    # Things removed:
    #   The concept of redaction (AFAIK we don't care about it, could bring it back tho)
    #   More complex logging around region / kube stuff. It's unclear how much is common across Moda or just gh config.
    Failbot.before_report do |exception, context, thread|
      log_data = {}

      # Generate a failbot_dg_id so we can search for it in splunk
      # Why not "failbot_id", you ask? Because there is a hacky filter that directs all
      # splunk events with the field "failbot_id" into a specific, incorrect index (prod-dotcom-exceptions)
      log_data["failbot_dg_id"] = SecureRandom.uuid

      if DependencyGraph::ActiveRecordRollup.should_rollup?(exception)
        log_data["first_significant_frame"] = DependencyGraph::ActiveRecordRollup.rollup_significant_frame(exception)
      else
        log_data["first_significant_frame"] = Rollup.first_significant_frame(exception.backtrace, scrub_root_path: Rails.root.to_s)
      end

      # We log before cleaning stuff up too much, splunk is OK for us to log sensitive things to.
      # We squash context in here, to get the most detailed logging message
      failbot_logger.log_exception(Failbot.squash_contexts(context, log_data), exception)

      # This looks really unintuitive (modifying something for a side effect)
      # Failbot itself will re-merge the context, requiring us to clean it up here.
      failbot_key_filter.call(context)
      failbot_key_tagger.convert_keys!(context)

      # Include a URL to search splunk. Do it after logging though, so it doesn't get logged to Splunk
      now = Time.now
      context["splunk_url"] = "https://splunk.githubapp.com/app/gh_reference_app/search?earliest=#{(now - 3600).to_i}&latest=#{(now + 3600).to_i}&q=search%20index%3Ddependency-graph-api%20failbot_dg_id%3D#{log_data["failbot_dg_id"]}"

      # We return log_data here (without squashing) because the caller will turn around
      # and squash the context and log_data together. That's why we're cleaning up context above.
      log_data
    end

    @_setup = true
  end

  # This is taken from https://github.com/github/failbot/blob/master/lib/failbot/exit_hook.rb
  # In lieu of waiting to merge https://github.com/github/failbot/pull/117 and publishing a new version
  # we add an exception to SignalException here.
  @unhandled_exception_hook_installed = false
  def self.install_unhandled_exception_hook!
    # only install the hook once, even when called from multiple locations
    return if @unhandled_exception_hook_installed

    # the $! is set when the interpreter is exiting due to an exception
    at_exit do
      boom = $!
      if boom && !@raise_errors && !boom.is_a?(SystemExit) && !boom.is_a?(SignalException)
        Failbot.report(boom, "argv" => ([$0]+ARGV).join(" "), "halting" => true)
      end
    end

    @unhandled_exception_hook_installed = true
  end

  class << self
    attr_reader :_setup
  end

  class Engine < Rails::Railtie
    initializer "failbot_rails.assert_setup" do |app|
      app.config.before_initialize do
        if !::FailbotRails._setup
          fail "FailbotRails must be setup like so: FailbotRails.setup(\"my_app\")"
        end
      end
    end

    initializer "failbot_rails.install_middleware" do |app|
      app.middleware.insert_after \
        ::ActionDispatch::DebugExceptions,
        ::FailbotRails::Middleware

      # Intentionally insert our UnknownHttpMethod middleware after failbot.
      #  This will stop failbot from handling the exception "too early" and logging an error.
      app.middleware.insert_after \
        ::FailbotRails::Middleware,
        ::FailbotRails::UnknownHttpMethodMiddleware
    end

    initializer "failbot_rails.install_action_controller_utilities" do |app|
      app.config.to_prepare do
        ActiveSupport.on_load(:action_controller) do
          include ::FailbotRails::ActionControllerUtilities
        end
      end
    end
  end

  class Middleware < ::Failbot::Rescuer
    def initialize(app)
      @app = app
      @other = {}
    end

    def self.context(env)
      ::FailbotRails._failbot_safe_context(super)
    end
  end

  # Defined here in failbot because the behavior / timing is very failbot oriented.
  # The real trick is making sure we log and suppress the exception before picked up
  #  by any other logger.
  # Reports unexpected methods to the Failbot user bucket for dg-api.
  # This intentionally AVOIDS calling wrapped middleware when a disallowed method is used,
  #  since much of the rails framework (and other libs) uses .request_method on request,
  #  which throws unexpectedly in middleware execution.
  class UnknownHttpMethodMiddleware
    ALLOWED_METHODS = ["OPTIONS", "GET", "HEAD", "POST", "PUT", "DELETE", "PATCH"]
    def initialize(app)
      @app = app
    end

    def call(env)
      attempted_method = env["REQUEST_METHOD"].upcase
      if ALLOWED_METHODS.include? attempted_method
        @status, @headers, @response = @app.call(env)
        [@status, @headers, @response]
      else
        error = ActionController::UnknownHttpMethod.new "#{attempted_method}, accepted HTTP methods are #{ALLOWED_METHODS.join(', ')}"
        ::FailbotRails.report_user_error(error)
        [405, { "Content-Type" => "text/plain" }, ["Method Not Allowed: #{error}"]]
      end
    end
  end

  def self.report_user_error(e, context = {})
    # This might look a little strange, but using a different app is how dotcom partitions "user" errors and
    # more operational / service health errors. This makes sure the requests still end up in some bucket, but not
    # the one we alert on. From: https://github.com/github/github/blob/master/config/initializers/failbot.rb
    Failbot.report(e, context.merge(app: "dependency-graph-api-user-error").merge(::FailbotRails._failbot_safe_context(context)))
  end

  def self._failbot_safe_context(context)
    new_context = {}.merge(context)
    filters = Rails.application.config.filter_parameters
    filter = ActiveSupport::ParameterFilter.new(filters)

    if new_context.key?(:params)
      new_context[:params] = filter.filter(new_context[:params])
    end

    new_context
  end

  module ActionControllerUtilities
    extend ActiveSupport::Concern

    included do
      # reset context before populating it with rails-specific info
      before_action :_failbot_rails
    end

    private

    def failbot(e, context = {})
      if e.kind_of?(ActionView::TemplateError) && e.respond_to?(:original_exception)
        # exceptions raised from views are wrapped in TemplateError. This is the
        # most annoying thing ever.
        e = e.original_exception
      end

      if e.respond_to?(:info) && e.info.is_a?(Hash)
        context = e.info.merge(context || {})
      end

      Failbot.report(e, ::FailbotRails._failbot_safe_context(context))
    end

    def _failbot_rails
      context = {
        controller: params[:controller],
        action: params[:action],
      }

      # allow overriding context by defining ApplicationController#failbot_context
      if respond_to?(:failbot_context) && failbot_context.respond_to?(:to_hash)
        context.merge!(failbot_context.to_hash)
      end

      Failbot.push(::FailbotRails._failbot_safe_context(context))
    end
  end
end
