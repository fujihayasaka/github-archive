# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Title < MemexProjectColumn::Field
  extend T::Sig
  include SpecialFieldHelpers

  TermQuery = Elastomer::Interfaces::Api::Search::Request::TermQuery
  WildcardQuery = Elastomer::Interfaces::Api::Search::Request::WildcardQuery

  sig { override.returns(T::Array[String]) }
  def self.register_processors
    [
      "MemexProjectColumn::Indexable::Processor::IssueTitleValueUpdate",
      "MemexProjectColumn::Indexable::Processor::DraftIssueTitleUpdate",
    ]
  end

  sig { override.returns(Elastomer::Interfaces::Mapping::FieldDataType) }
  def self.elasticsearch_mapping
    Elastomer::Interfaces::Mapping::FieldDataTypes::KeywordMultiField.new(copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS)
  end

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_elasticsearch_document_data(items)
    preload_content_tree(items)
  end

  sig do
    override
      .params(item: MemexProjectItem)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::TitleValue)
  end
  def elasticsearch_document(item)
    if issue_or_pull_request?(item) && item.content.repository.nil?
      raise CanonicalDataMissingError, "repository for item_id: #{item.id} does not exist"
    end
    item.denormalized_title_value&.dig(:title, :raw)
  end

  sig do
    override
      .params(context: Elastomer::Interfaces::Document::MemexProjectItem::SeedContext)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::TitleValue)
  end
  def seed_elasticsearch_document(context)
    # Populate the title for the first item in a batch deterministically.
    # This gives us a string that we know will return hits in a properly constructed search query.
    return "O Romeo, Romeo! Wherefore art thou Romeo?" if context.first_item?

    case rand(1..6)
    when 1
      Faker::GreekPhilosophers.quote
    when 2
      Faker::Movies::BackToTheFuture.quote
    when 3
      Faker::Movies::PrincessBride.quote
    when 4
      Faker::Movies::HitchhikersGuideToTheGalaxy.quote
    when 5
      Faker::Quotes::Shakespeare.romeo_and_juliet_quote
    else
      Faker::TvShows::DrWho.quote
    end
  end

  sig { params(item: MemexProjectItem).returns(T::Boolean) }
  private def issue_or_pull_request?(item)
    item.issue? || item.pull_request?
  end

  sig do
    override
      .params(direction: String)
      .returns(T::Hash[T.untyped, T.untyped])
  end
  def sort_fragment(direction:)
    build_version_compatible_sort_fragment(
      direction: direction,
      sort_by: "field_values.#{MemexProjectColumn::Title.value_name}.keyword",
    )
  end

  sig do
    override
      .params(values: T::Array[String], is_negated: T::Boolean, context: Search::Memex::Context)
      .returns(T::Hash[T.untyped, T.untyped])
  end
  def query_fragment(values:, is_negated:, context:)
    should_clauses = values.map do |value|
      {
        nested: {
          path: "field_values",
          query: {
            bool: {
              must: [
                {
                  term: {
                    "field_values.field_id": { value: id },
                  }
                },
                wildcard_query(value)&.to_hash || term_query(value).to_hash
              ]
            }
          }
        }
      }
    end

    wrap_query_fragment(should_clauses:, is_negated:)
  end

  sig { params(value: String).returns(T.nilable(WildcardQuery)) }
  private def wildcard_query(value)
    return nil unless value.include?("*")

    WildcardQuery.new(
      field_path: "field_values.#{self.class.value_name}",
      value: WildcardQuery::Value.new(value),
      case_insensitive: true,
    )
  end

  sig { params(value: String).returns(TermQuery) }
  private def term_query(value)
    TermQuery.new(
      field_path: "field_values.#{self.class.value_name}.keyword",
      value:,
      case_insensitive: true
    )
  end
end
