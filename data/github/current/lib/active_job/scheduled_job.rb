# typed: false
# frozen_string_literal: true

module ActiveJob
  module ScheduledJob
    extend ActiveSupport::Concern

    class InvalidScopeError < ArgumentError; end
    class InvalidIntervalError < ArgumentError; end

    # Valid TimerDaemon scopes. See .schedule
    VALID_SCOPES = %i(global host process).freeze

    included do
      class_attribute :_scheduled_interval
      class_attribute :_scheduled_scope
      class_attribute :_scheduled_condition
      class_attribute :_schedule_enabled
    end

    module ClassMethods
      def schedule(interval:, scope: :global, condition: nil)
        raise InvalidScopeError.new "scope must be one of #{VALID_SCOPES}" unless VALID_SCOPES.include?(scope)
        raise InvalidIntervalError.new "interval must be greater than 0" unless interval.to_i > 0

        # We convert the interval to an integer because TimerDaemon::GlobalTimer
        # does as well and we want to match that functionality to make sure any
        # validation we're doing is correct.
        self._scheduled_interval = interval.to_i
        self._scheduled_scope = scope
        self._scheduled_condition = condition
        self._schedule_enabled = condition.nil? || condition.call
      end

      def schedule_options
        return if _scheduled_interval.blank? || _scheduled_scope.blank?

        {
          interval: _scheduled_interval,
          scope: _scheduled_scope,
        }
      end

      def enabled?
        self._schedule_enabled
      end
    end
  end
end
