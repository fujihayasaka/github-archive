# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::TrackedBy < MemexProjectColumn::Field::Base
  include Interface::SpecialTypeSerializable

  # We don't register any processors here because TrackedBy is no longer supported in projects.
  # We expect the full field implementation to removed before long.
  sig { override.returns(T::Array[String]) }
  def self.register_processors
    []
  end

  sig { override.returns(T::Boolean) }
  def self.disabled?
    true
  end

  sig { override.returns(Elastomer::Interfaces::Mapping::FieldDataType) }
  def self.elasticsearch_mapping
    Elastomer::Interfaces::Mapping::FieldDataTypes::Keyword.new(copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS)
  end

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_elasticsearch_document_data(items)
    GitHub::PrefillAssociations.prefill_batch_method(items, :tracked_by_items)
  rescue MemexProjectItem::ItemPrefillError
  end

  sig do
    override
      .params(item: MemexProjectItem)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::TrackedByValue)
  end
  def elasticsearch_document(item)
    item.tracked_by_items&.sort_by(&:number)&.map do |i|
      h = i.to_h
      "#{h[:owner_login]}/#{h[:repository_name]}##{h[:display_number]}"
    end
  rescue MemexProjectItem::ItemPrefillError
    nil
  end

  sig do
    override
      .params(context: Elastomer::Interfaces::Document::MemexProjectItem::SeedContext)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::TrackedByValue)
  end
  def seed_elasticsearch_document(context)
    context.num_multi_select_values.times.map { |_| rand(1...1000) }.sort.map do |number|
      "#{Faker::Internet.username}/#{Faker::Lorem.word}##{number}"
    end
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
end
