# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::Title < MemexProjectColumn::Field::Base
  include Helper::SpecialField

  TermQuery = Elastomer::Interfaces::Api::Search::Request::TermQuery
  WildcardQuery = Elastomer::Interfaces::Api::Search::Request::WildcardQuery

  sig { override.returns(T::Array[String]) }
  def self.register_processors
    [
      "MemexProjectColumn::Interface::Indexable::Processor::IssueTitleValueUpdate",
      "MemexProjectColumn::Interface::Indexable::Processor::DraftIssueTitleUpdate",
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
      sort_by: "field_values.#{MemexProjectColumn::Field::Title.value_name}.keyword",
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
      field_path: "field_values.#{self.class.value_name}.keyword",
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

  # Returns a value that can be used to sort a MemexProjectItem by a given field.
  #
  # When querying for project items outside of ElasticSearch, this method returns the sortable value
  # for a field to regenerate the same sort order as ElasticSearch. The output for these methods should match
  # what ElasticSearch returns for the sorting order. Depending on the data type and direction, fields could
  # return the max or minimum 64-bit signed integer, a String, or a representation for Infinity.
  #
  # direction   - The direction to sort by, either :asc or :desc.
  # column_data - The data for the column to be sorted, this is JSON data stored in the column record, after
  #               extracting more specific information using the column data type to query through
  #               the MemexProjectItem::ColumnDependency::COLUMN_VALUE_KEYS Hash.
  #
  sig { override.params(direction: Symbol, column_data: T.untyped).returns(T.untyped) }
  def graphql_sortable_column_value(direction:, column_data:)
    column_data
  end

  sig { override.returns(T::Boolean) }
  def self.writeable? = true

  sig { override.returns(T::Boolean) }
  def self.value_required? = true

  sig do
    override
    .params(
      item: MemexProjectItem,
      new_value: T.untyped,
      actor: User,
      suppress_hydro_events: T::Boolean)
    .returns(Interface::Writeable::PartialResult)
  end
  private def update_mysql_field_value(item:, new_value:, actor:, suppress_hydro_events:)
    if new_value&.try(:fetch, :title).blank?
      return Interface::Writeable::PartialResult.failure("Title value cannot be blank")
    end

    title_receiver = item.content.is_a?(PullRequest) ? item.content.issue : item.content
    title_receiver.modifying_user = actor if title_receiver&.respond_to?(:modifying_user=)

    unless title_receiver.update(title: new_value[:title])
      return Interface::Writeable::PartialResult.failure(title_receiver.errors.full_messages.to_sentence)
    end

    # Note that this is legacy functionality that should be removed once `MemexEventProcessor` (the legacy
    # denormalization pipeline) has been removed: https://github.com/github/projects-platform/issues/2837
    unless item.cache_title_column_value(self, item.denormalized_title_value, actor)
      return Interface::Writeable::PartialResult.failure("Failed to update denormalized value")
    end

    Interface::Writeable::PartialResult.success
  end
end
