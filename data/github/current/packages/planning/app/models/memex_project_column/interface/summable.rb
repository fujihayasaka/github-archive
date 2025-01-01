# typed: strict
# frozen_string_literal: true

# This abstract module encapsulates behavior to sum data on Memex field values supported in GitHub Projects in Elasticsearch.
#
# This is intended to be included in the specific MemexProjectColumn::Field::Base subclasses that support this behavior.
module MemexProjectColumn::Interface::Summable
  extend T::Helpers
  abstract!

  requires_ancestor { MemexProjectColumn::Field::Base }

  module ClassMethods
    extend T::Helpers
    abstract!

    sig { abstract.returns(T::Boolean) }
    def summable?; end
  end

  mixes_in_class_methods(ClassMethods)

  SUM_SLUG = :sum

  # Abbreviation to improve readability of types in this module.
  ElasticsearchRequest = Elastomer::Interfaces::Api::Search::Request

  sig { overridable.returns(String) }
  def sum_by_value_path
    ""
  end

  sig(:final) { returns(ElasticsearchRequest::Aggregation::Filter) }
  def sum_by_aggregation
    ElasticsearchRequest::Aggregation::Filter.new(
      slug: self.id.to_s.to_sym,
      filter: elasticsearch_field_value_term_filter,
    ).add_subaggregation(
      ElasticsearchRequest::Aggregation::Sum.new(
        slug: SUM_SLUG,
        field: self.sum_by_value_path,
      )
    )
  end

  sig(:final) do
    params(sum_by_agg_result: T.nilable(T::Hash[String, T.untyped]))
    .returns(Float)
  end
  def get_sum_value(sum_by_agg_result)
    sum_by_agg_result&.dig(
      self.id.to_s,
      SUM_SLUG.to_s,
      "value"
    ) || 0.0
  end
end
