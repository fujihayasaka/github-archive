# typed: true
# frozen_string_literal: true

module RuleEngine
  module Timing

    # Helper method for timing a block of code.
    # Logs to both datadog metrics and APM
    sig do
      type_parameters(:R)
      .params(
        resource: String,
        tags: T::Array[String],
        span_attributes: T::Hash[String, String],
        blk: T.proc.params(span: T.untyped).returns(T.type_parameter(:R))
      ).returns(T.type_parameter(:R))
    end
    def trace_time(resource, tags: [], span_attributes: {}, &blk)
      context_tags = ["from:#{GitHub.context[:from]}", "method:#{GitHub.context[:method] || GitHub.context[:request_method]}"]
      GitHub.dogstats.distribution_time("repository_rules_engine.#{resource}.duration", tags: tags + context_tags) do
        GitHub.tracer.in_span("repository_rules_engine.#{resource}", kind: :internal, attributes: span_attributes) do |span|
          yield span
        end
      end
    end
  end
end
