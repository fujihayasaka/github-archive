# typed: strict
# frozen_string_literal: true

# These are just constants that hold instrumentation strings
module Copilot
  module Metrics
    extend T::Sig

    sig do
      type_parameters(:A).params(
        name: String,
        tags: T::Hash[Symbol, String],
        block: T.proc.returns(T.type_parameter(:A)),
      ).returns(T.type_parameter(:A))
    end
    def collect_metrics(name, **tags, &block)
      tagger = Copilot::StatsTagger.new(copilot_object: self, **tags)

      GitHub.tracer.in_span(name, attributes: tagger.all_tags, kind: :internal) do |_span|
        begin
          GitHub.dogstats.distribution_time("#{name}.latency", tags: tagger.datadog_tags) do
            yield
          end
        rescue => e # rubocop:todo Lint/GenericRescue
          GitHub.dogstats.increment "#{name}.errors"
          Kernel.raise e
        end
      end
    end
  end
end
