# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::Number < MemexProjectColumn::Field::Base
  include Helper::GenericField

  RangeQuery = Elastomer::Interfaces::Api::Search::Request::RangeQuery

  sig { override.returns(T::Array[String]) }
  def self.register_processors
    [
      "MemexProjectColumn::Interface::Indexable::Processor::NumberValueCreate",
      "MemexProjectColumn::Interface::Indexable::Processor::NumberValueDestroy",
      "MemexProjectColumn::Interface::Indexable::Processor::NumberValueUpdate"
    ]
  end

  sig { override.returns(Elastomer::Interfaces::Mapping::FieldDataType) }
  def self.elasticsearch_mapping
    Elastomer::Interfaces::Mapping::FieldDataTypes::Float.new(copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS)
  end

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_elasticsearch_document_data(items)
    GitHub::PrefillAssociations.prefill_associations(items, :memex_project_column_values)
  end

  sig do
    override
      .params(item: MemexProjectItem)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::NumberValue)
  end
  def elasticsearch_document(item)
    item.group_by_value(self, require_prefilled_associations: false)
  end

  sig do
    override
      .params(values: T::Array[String], is_negated: T::Boolean, context: Search::Memex::Context)
      .returns(T::Hash[T.untyped, T.untyped])
  end
  def query_fragment(values:, is_negated:, context:)
    should_clauses = values.map do |value|
      query_strategy = range_query(value)&.to_hash || match_query(value)
      {
        nested: {
          path: "field_values",
          query: {
            bool: {
              must: [
                {
                  term: {
                    "field_values.field_id": id,
                  }
                },
                query_strategy
              ]
            }
          }
        }
      }
    end

    wrap_query_fragment(should_clauses:, is_negated:)
  end

  sig { override.returns(T::Hash[T.untyped, T.untyped]) }
  def existence_fragment
    {
      nested: {
        path: "field_values",
        query: {
          bool: {
            filter: [
              {
                term: {
                  "field_values.field_id": id,
                }
              },
              exists: {
                field: "field_values.#{self.class.value_name}"
              },
            ]
          }
        }
      }
    }
  end

  sig do
    override
      .params(direction: String)
      .returns(T::Hash[T.untyped, T.untyped])
  end
  def sort_fragment(direction:)
    build_version_compatible_sort_fragment(
      direction: direction,
      sort_by: "field_values.#{self.class.value_name}",
    )
  end

  sig do
    override
      .params(context: Elastomer::Interfaces::Document::MemexProjectItem::SeedContext)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::NumberValue)
  end
  def seed_elasticsearch_document(context)
    context.set_value? ? Faker::Number.digit : nil
  end

  sig { override.returns(String) }
  def group_by_value_path
    "field_values.#{self.class.value_name}"
  end
  [:chart_by_value_path, :slice_by_value_path].each { |method| alias_method method, :group_by_value_path }

  sig { params(value: String).returns(T::Hash[T.untyped, T.untyped]) }
  private def match_query(value)
    {
      match: {
        "field_values.#{self.class.value_name}": value
      }
    }
  end

  sig do returns(
    T::Hash[
      Regexp,
      T.proc.params(match: MatchData).returns(RangeQuery::Operators)
    ])
  end
  private def range_patterns
    {
      # Range query, inclusive. For example: 1..10
      /\A(\d+)\.\.(\d+)\z/ => ->(match) { RangeQuery::Operators.new(gte: match[1], lte: match[2]) },
      # Greater than or equal to. For example: >=1
      /\A>=(\d+)\z/        => ->(match) { RangeQuery::Operators.new(gte: match[1]) },
      # Greater than or equal to, using range syntax. For example: 10..*
      /\A(\d+)\.\.\*\z/    => ->(match) { RangeQuery::Operators.new(gte: match[1]) },
      # Less than or equal to. For example: <=10
      /\A<=(\d+)\z/        => ->(match) { RangeQuery::Operators.new(lte: match[1]) },
      # Less than or equal to, using range syntax. For example: *..10
      /\A\*\.\.(\d+)\z/    => ->(match) { RangeQuery::Operators.new(lte: match[1]) },
      # Greater than. For example: >1
      /\A>(\d+)\z/         => ->(match) { RangeQuery::Operators.new(gt: match[1]) },
      # Less than. For example: <10
      /\A<(\d+)\z/         => ->(match) { RangeQuery::Operators.new(lt: match[1]) },
    }
  end

  sig { params(value: String).returns(T.nilable(RangeQuery)) }
  private def range_query(value)
    range_clause = range_patterns.filter_map do |pattern, clause_converter|
      if match = value.match(pattern)
        clause_converter.call(match)
      end
    end

    return nil if range_clause.empty?

    RangeQuery.new(
      field_path: "field_values.#{self.class.value_name}",
      operators: T.must(range_clause.first)
    )
  end

  sig { override.params(group_by_value: T.nilable(String)).returns(T.nilable(Float)) }
  def graphql_value(group_by_value)
    # Calling super helps cleanse potential _noValue values
    super(group_by_value)&.to_f
  end

  sig { override.params(group_by_value: T.nilable(String)).returns(String) }
  def graphql_title(group_by_value)
    ActiveSupport::NumberHelper.number_to_rounded(
      graphql_value(group_by_value),
      precision: MemexProjectColumnValue::NUMBER_VALUE_PRECISION,
      strip_insignificant_zeros: true
    ) || super(group_by_value)
  end

  sig { override.returns(T::Boolean) }
  def self.writeable? = true
end
