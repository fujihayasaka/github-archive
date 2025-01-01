# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::Milestone < MemexProjectColumn::Field::Base
  include Helper::SpecialField

  TermQuery = Elastomer::Interfaces::Api::Search::Request::TermQuery
  WildcardQuery = Elastomer::Interfaces::Api::Search::Request::WildcardQuery

  sig { override.returns(T::Array[String]) }
  def self.register_processors
    [
      "MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateMilestone",
      "MemexProjectColumn::Interface::Indexable::Processor::MilestoneDelete",
      "MemexProjectColumn::Interface::Indexable::Processor::MilestoneUpdate",
    ]
  end

  sig { override.returns(Elastomer::Interfaces::Mapping::FieldDataType) }
  def self.elasticsearch_mapping
    Elastomer::Interfaces::Mapping::FieldDataTypes::Object.new(properties: {
      id: Elastomer::Interfaces::Mapping::FieldDataTypes::Long.new,
      repository_id: Elastomer::Interfaces::Mapping::FieldDataTypes::Long.new,
      title: Elastomer::Interfaces::Mapping::FieldDataTypes::KeywordMultiField.new(copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS),
    })
  end

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_elasticsearch_document_data(items)
    preload_content_tree(items)
    issues = items.select(&:issue?).map(&:content) + items.select(&:pull_request?).map { |item| item.content&.issue }
    GitHub::PrefillAssociations.prefill_associations(issues.compact, :milestone)
  end

  sig do
    override
      .params(item: MemexProjectItem)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::MilestoneValue)
  end
  def elasticsearch_document(item)
    content_type = Elastomer::Interfaces::Document::MemexProjectItem::ContentType.deserialize(item.content_type)

    case content_type
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::Issue,
        Elastomer::Interfaces::Document::MemexProjectItem::ContentType::PullRequest
      return nil if !item.content.milestone
      Elastomer::Interfaces::Document::Milestone.new(
        title: item.content.milestone.title,
        repository_id: item.repository_id,
        id: item.content.milestone.id
      )
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::DraftIssue
      nil
    else
      T.absurd(content_type)
    end
  end

  sig do
    override
      .params(context: Elastomer::Interfaces::Document::MemexProjectItem::SeedContext)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::MilestoneValue)
  end
  def seed_elasticsearch_document(context)
    content_type = context.content_type

    case content_type
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::Issue,
        Elastomer::Interfaces::Document::MemexProjectItem::ContentType::PullRequest
      if context.set_value?
        milestone = T.must(Array(context.milestones.sample).first)
        Elastomer::Interfaces::Document::Milestone.new(
          title: milestone.title,
          repository_id: milestone.repository_id,
          id: milestone.id
        )
      else
        nil
      end
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::DraftIssue
      nil
    else
      T.absurd(content_type)
    end
  end

  sig do
    override
      .params(direction: String)
      .returns(T::Hash[T.untyped, T.untyped])
  end
  def sort_fragment(direction:)
    build_version_compatible_sort_fragment(
      direction: direction,
      sort_by: "field_values.#{self.class.value_name}.title.keyword",
    )
  end

  sig do
    override
      .params(
        values: T::Array[String],
        is_negated: T::Boolean,
        context: Search::Memex::Context
      )
      .returns(T::Hash[T.untyped, T.untyped])
  end
  def query_fragment(values:, is_negated:, context:)
    should_clauses = values.map do |value|
      {
        nested: {
          path: "field_values",
          query: wildcard_query(value)&.to_hash || term_query(value).to_hash
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
          exists: {
            field: "field_values.#{self.class.value_name}.title"
          }
        }
      }
    }
  end

  sig { override.returns(String) }
  def group_by_value_path
    "field_values.#{self.class.value_name}.title.keyword"
  end
  [:chart_by_value_path, :slice_by_value_path].each { |method| alias_method method, :group_by_value_path }

  sig { override.returns(T::Boolean) }
  def has_group_metadata? = true

  sig { override.returns(String) }
  def group_by_metadata_id_path
    "field_values.#{self.class.value_name}.id"
  end
  alias_method :slice_by_metadata_id_path, :group_by_metadata_id_path

  sig do
    override
      .params(metadata_object_ids: T::Array[Integer])
      .returns(T::Hash[Integer, T.all(Milestone, Interface::Groupable::Metadata)])
  end
  def preload_group_metadata_objects(metadata_object_ids)
    ::Milestone.where(id: metadata_object_ids).index_by(&:id)
  end
  alias_method :preload_slice_metadata_objects, :preload_group_metadata_objects

  sig { override.returns(T::Boolean) }
  def self.writeable? = true

  sig do
    override
    .params(
      item: MemexProjectItem,
      new_value: T.untyped,
      actor: User,

      # This parameter is required by the abstract interface, but it is not and should not be used in this method
      # because we are not at liberty to suppress Hydro events for milestones (they are part of the Issues service
      # rather than the Projects service; this method is just a convenience for interacting with milestones from
      # within Projects).
      suppress_hydro_events: T::Boolean)
    .returns(Interface::Writeable::PartialResult)
  end
  private def update_mysql_field_value(item:, new_value:, actor:, suppress_hydro_events:)
    unless item.issue_for_content
      return Interface::Writeable::PartialResult.failure("Content issue not found")
    end

    canonical_write_successful = if new_value.present?
      milestone = item.issue_for_content.repository.milestones.find_by(id: new_value)
      unless milestone
        return Interface::Writeable::PartialResult.failure("Milestone does not exist")
      end
      item.issue_for_content.update(milestone:)
    else
      item.issue_for_content.update(milestone_id: nil)
    end

    unless canonical_write_successful
      return Interface::Writeable::PartialResult.failure(item.issue_for_content.errors.full_messages.to_sentence)
    end

    # Note that this is legacy functionality that should be removed once `MemexEventProcessor` (the legacy
    # denormalization pipeline) has been removed: https://github.com/github/projects-platform/issues/2837
    denormalized_write_successful = item.cache_milestone_column_value(
      self,
      item.denormalized_milestone_value,
      actor
    )

    unless denormalized_write_successful
      return Interface::Writeable::PartialResult.failure("Failed to update denormalized value")
    end
    Interface::Writeable::PartialResult.success
  end

  sig { params(value: String).returns(T.nilable(WildcardQuery)) }
  private def wildcard_query(value)
    return nil unless value.include?("*")

    WildcardQuery.new(
      field_path: "field_values.#{self.class.value_name}.title.keyword",
      value: WildcardQuery::Value.new(value),
      case_insensitive: true,
    )
  end

  sig { params(value: String).returns(TermQuery) }
  private def term_query(value)
    TermQuery.new(
      field_path: "field_values.#{self.class.value_name}.title.keyword",
      value:,
      case_insensitive: true,
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
end
