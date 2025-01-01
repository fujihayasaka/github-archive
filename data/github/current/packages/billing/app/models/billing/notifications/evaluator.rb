# typed: true
# frozen_string_literal: true

module Billing
  module Notifications
    class Evaluator
      def initialize(thresholds:)
        @thresholds = thresholds.sort.reverse
        @eval_cases = []
      end

      def add_case(*tags, &proc)
        eval_cases << EvaluationCase.new(tags: tags, proc: proc)
      end

      def results(tags: [])
        evaluted_results = eval_cases.map do |eval_case|
          next if tags.present? && !eval_case.includes_tags?(tags)
          context = {}
          eval_result = eval_case.proc.call(context)
          next if eval_result.nil?
          threshold = thresholds.detect { |threshold| eval_result >= threshold }
          next if threshold.nil?
          Result.new(value: eval_result, threshold: threshold, tags: eval_case.tags, context: context)
        end.compact
        # order the results with the highest threshold first
        evaluted_results.sort_by(&:threshold).reverse
      end

      private

      attr_reader :eval_cases, :thresholds
    end
  end
end
