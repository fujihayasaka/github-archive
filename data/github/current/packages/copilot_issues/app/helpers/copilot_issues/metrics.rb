# typed: true
# frozen_string_literal: true

module CopilotIssues
  module Metrics
    sig do
      type_parameters(:U).params(
        name: String,
        tags: T.untyped, # rubocop:disable Sorbet/ForbidTUntyped
        block: T.proc.returns(T.type_parameter(:U)),
      ).returns(T.type_parameter(:U))
    end
    def collect_metrics(name, **tags, &block)
      tags_array = tags.map { |k, v| "#{k}:#{v}" }
      GitHub.tracer.in_span(name, kind: :internal) do |_span|
        begin
          yield
        rescue => e # rubocop:todo Lint/RescueException
          GitHub.dogstats.increment("#{name}.errors", tags: tags_array)
          Kernel.raise e
        end
      end
    end
  end
end
