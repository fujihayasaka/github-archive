# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class Issue < Connections::Base
      TOTAL_COUNT_MAX_RETRIES = 2
      TOTAL_COUNT_MAX_EXECUTION_TIME_MS = 2000

      description "The connection type for Issue."
      total_count_field

      def total_count
        return super unless @object.respond_to?(:total_count_scope)
        return super unless FeatureFlag.vexi.enabled?(:retry_issues_total_count, retry_issues_total_count_actors, default: false)

        attempts_counter = 0
        begin
          attempts_counter += 1
          result = @object.total_count_scope.limit_execution_time(limit_ms: TOTAL_COUNT_MAX_EXECUTION_TIME_MS).count

          result
        rescue ActiveRecord::StatementTimeout => _exception
          retry if attempts_counter < TOTAL_COUNT_MAX_RETRIES

          raise Platform::Errors::Internal, "Unable to generate response at this time"
        end
      end

      private

      def retry_issues_total_count_actors
        actors = []
        actors << @context[:viewer] if @context[:viewer]
        actors << @object if @object.is_a?(Repository)
        actors
      end
    end
  end
end
