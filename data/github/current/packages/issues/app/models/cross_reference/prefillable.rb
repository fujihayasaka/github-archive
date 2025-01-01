# typed: true
# frozen_string_literal: true

module CrossReference::Prefillable
  extend ActiveSupport::Concern

  class_methods do
    include GitHub::Tracing

    trace_method :prefill_associations
    def prefill_associations(cross_references, current_user: nil, exclude_prefills: [], available_records: [])
      GitHub::PrefillAssociations.prefill_associations(cross_references, [:source, :target, :actor], available_records: available_records) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      issues = (cross_references.map(&:source) + cross_references.map(&:target)).compact.uniq
      IssuePrefiller.optimized_prefill(
        issues,
        exclude_prefills: exclude_prefills,
        current_user: current_user,
        available_records: cross_references.map(&:actor).uniq
      ) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      Reaction::Summary.prefill(issues) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      Repository.prefill_associations(issues.map(&:repository).uniq, internal: true) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end
  end
end
