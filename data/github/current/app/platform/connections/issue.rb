# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class Issue < Connections::Base
      TOTAL_COUNT_MAX_RETRIES = 2
      TOTAL_COUNT_MAX_EXECUTION_TIME_MS = 5000

      description "The connection type for Issue."
      total_count_field

      def total_count
        return super unless @object.respond_to?(:total_count_scope)
        return super unless FeatureFlag.vexi.enabled?(:retry_issues_total_count, retry_issues_total_count_actors, default: false)

        attempts_counter = 0
        begin
          GitHub.logger.info("retrying issues total_count", logger_tags, attempts_counter: attempts_counter) if attempts_counter > 0

          attempts_counter += 1
          result = @object.total_count_scope.limit_execution_time(limit_ms: TOTAL_COUNT_MAX_EXECUTION_TIME_MS).count

          result
        rescue ActiveRecord::StatementTimeout => _exception
          retry if attempts_counter < TOTAL_COUNT_MAX_RETRIES

          GitHub.logger.error("failed to generate issues total_count", logger_tags, attempts_counter: attempts_counter)
          raise Platform::Errors::Internal, "Unable to generate response at this time"
        end
      end

      private

      def logger_tags
        {
          "gh.code.namespace" => "Platform::Connections::Issue",
          "gh.code.function" => "total_count",
        }
      end

      def retry_issues_total_count_actors
        actors = []
        actors << @context[:viewer] if @context[:viewer]
        actors << @object if @object.is_a?(Repository)
        actors
      end
    end
  end
end
