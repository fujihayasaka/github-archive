# typed: true
# frozen_string_literal: true

class AutomaticAppInstallation
  module Handlers
    # All handlers should inherit from this class to get generic
    # instrumentation, logging and validation.
    #
    # The following callbacks are available for handlers and should be
    # implemented as class methods:
    #
    # class MyHandler < BaseHandler
    #   # Called when an installation is triggered but the App is already
    #   # installed on the target.
    #   def self.integration_already_installed(integration:, installation:, target:, installer:, repositories:, options:{})
    #     # ... your code here
    #   end
    #
    #   # Called after an App is successfully installed on the target for the
    #   first time.
    #   def self.after_integration_installed(integration:, installation:, target:, installer:, repositories:, options:{})
    #     # ... your code here
    #   end
    # end
    class BaseHandler

      class Result
        def self.success(installation_result: nil)
          new(result: :success, installation_result:)
        end

        def self.failure(reason:, installation_result: nil)
          new(result: :failure, reason: reason, installation_result:)
        end

        attr_reader :result, :reason, :installation_result

        def initialize(result:, reason: nil, installation_result: nil)
          @result = result
          @reason = reason
          @installation_result = installation_result
        end

        def success?
          result == :success
        end
      end

      attr_reader :install_triggers, :originator, :actor

      def initialize(install_triggers:, originator:, actor:)
        @install_triggers = install_triggers
        @originator = originator
        @actor = actor
      end

      def validate
        if actor.nil?
          return Result.failure(reason: :actor_not_supplied)
        end

        if originator.nil?
          return Result.failure(reason: :originator_not_supplied)
        end

        if install_triggers.empty?
          return Result.failure(reason: :install_triggers_not_supplied)
        end

        Result.success
      end

    end
  end
end
