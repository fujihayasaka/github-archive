# frozen_string_literal: true

require "failbot"
require "failbot/middleware"
require "./lib/dependabot/exceptions"

# Add custom failbot rack middleware to replace FailbotRails::Middleware

# Re-implementing failbot middleware from:
# https://github.com/github/failbot/blob/b2e01b3f3257041d90ac406f0bc21a0dd87f8d03/lib/failbot/middleware.rb
module Middleware
  class Failbot < ::Failbot::Rescuer
    # Re-implement ::Failbot::Rescuer#call with transaction rollup

    def call(env)
      ::Dependabot::Exceptions.reset!
      ctx = @other.merge(self.class.context(env))

      ::Dependabot::Exceptions.push(ctx) do
        handle_request(env, ctx)
      end
    end

    def handle_request(env, ctx)
      start = Time.now.in_time_zone
      @app.call(env)
    rescue Object => e
      elapsed = Time.now.in_time_zone - start
      extra = { "http.server.request.duration": elapsed.to_s }

      unless extra.key?(:rollup)
        # Transaction is set to the route class in coach Middlewares::Failbot
        rollup = setup_transaction_rollup(ctx, e)
        extra[:rollup] = rollup if rollup
      end

      ::Dependabot::Exceptions.report(e, extra)
      raise
    end

    def setup_transaction_rollup(ctx, exception)
      transaction = ctx[:transaction] || self.class.context_find(:transaction)
      existing_rollup = ctx[:rollup] || self.class.context_find(:rollup)

      return unless transaction && !existing_rollup

      Digest::MD5.hexdigest("#{exception.class}#{transaction}")
    end

    def self.context(env)
      failbot_safe_context(super)
    end

    # Copied from failbot_rails
    def self.failbot_safe_context(context)
      new_context = {}.merge(context)
      filters = Rails.application.config.filter_parameters
      filter = ActiveSupport::ParameterFilter.new(filters)

      new_context[:params] = filter.filter(new_context[:params]) if new_context.key?(:params)

      new_context
    end

    # Find Failbot.push context by key
    def self.context_find(key)
      ::Dependabot::Exceptions.context.find { |ctx| ctx.try(:key?, key) }.try(:[], key)
    end
  end

  module ActionControllerUtilities
    extend ActiveSupport::Concern

    included do
      # temporarily disable/replace until we upgrade to a thread-safe version of Failbot
      skip_before_action :_failbot_rails
      before_action :setup_exception_context
    end

    private

    def setup_exception_context
      context = {
        "code.namespace": params[:controller],
        "code.function": params[:action],
      }

      Dependabot::Exceptions.push(context)
    end
  end
end
