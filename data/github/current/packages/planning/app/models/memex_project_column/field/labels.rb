# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::Labels < MemexProjectColumn::Field::Base
  include Interface::SpecialTypeSerializable

  sig { override.returns(T::Array[String]) }
  def self.register_processors
    [
      "MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateLabels",
      "MemexProjectColumn::Interface::Indexable::Processor::LabelUpdate",
      "MemexProjectColumn::Interface::Indexable::Processor::LabelDelete",
    ]
  end

  sig { override.returns(Elastomer::Interfaces::Mapping::FieldDataType) }
  def self.elasticsearch_mapping
    Elastomer::Interfaces::Mapping::FieldDataTypes::Object.new(properties: {
      id: Elastomer::Interfaces::Mapping::FieldDataTypes::Long.new,
      name: Elastomer::Interfaces::Mapping::FieldDataTypes::KeywordMultiField.new(copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS),
      repository_id: Elastomer::Interfaces::Mapping::FieldDataTypes::Long.new
    })
  end

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_elasticsearch_document_data(items)
    preload_content_tree(items)
    pull_requests = T.cast(items.select(&:pull_request?).map(&:content), T::Array[T.nilable(PullRequest)])
    pull_request_issues = pull_requests.map { |pull_request| pull_request&.issue }
    issues = T.cast(items.select(&:issue?).map(&:content), T::Array[T.nilable(Issue)])
    preloadable_issues = issues + pull_request_issues

    GitHub::PrefillAssociations.prefill_associations(preloadable_issues.compact, :labels)
  end

  sig do
    override
      .params(item: MemexProjectItem)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::LabelsValue)
  end
  def elasticsearch_document(item)
    content_type = Elastomer::Interfaces::Document::MemexProjectItem::ContentType.deserialize(item.content_type)

    case content_type
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::Issue,
        Elastomer::Interfaces::Document::MemexProjectItem::ContentType::PullRequest
      issue_or_pull = T.cast(item.content, T.any(Issue, PullRequest)) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      issue_or_pull.labels.sort_by(&:id).map do |l|
        Elastomer::Interfaces::Document::Label.new(
          id: l.id,
          name: l.name,
          repository_id: l.repository_id
        )
      end
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::DraftIssue
      nil
    else
      T.absurd(content_type)
    end
  end

  sig do
    override
      .params(context: Elastomer::Interfaces::Document::MemexProjectItem::SeedContext)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::LabelsValue)
  end
  def seed_elasticsearch_document(context)
    content_type = context.content_type

    case content_type
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::Issue,
        Elastomer::Interfaces::Document::MemexProjectItem::ContentType::PullRequest
      Array(context.labels.sample(context.num_multi_select_values)).sort_by(&:name).map do |label|
        Elastomer::Interfaces::Document::Label.new(
          id: label.id,
          name: label.name,
          repository_id: label.repository_id
        )
      end
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::DraftIssue
      nil
    else
      T.absurd(content_type)
    end
  end

  sig do
    override.
      params(
        item: MemexProjectItem,
        prefilled_associations: T.nilable(MemexProjectItem::PrefilledAssociations),
        redacted_issue_ids: T::Array[Integer],
      ).
      returns(T.nilable(T::Array[MemexProjectColumn::Interface::Serializable]))
  end
  def serializable(item, prefilled_associations: nil, redacted_issue_ids: [])
    content_type = Elastomer::Interfaces::Document::MemexProjectItem::ContentType.deserialize(item.content_type)

    case content_type
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::Issue,
      Elastomer::Interfaces::Document::MemexProjectItem::ContentType::PullRequest
      if prefilled_associations
        prefilled_associations.labels(item)
      else
        issue_or_pull = T.cast(item.content, T.any(Issue, PullRequest)) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        issue_or_pull.labels.sort_by { |label| label.name&.downcase }
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
      sort_by: "field_values.#{self.class.value_name}.name.keyword",
    )
  end

  sig { override.returns(String) }
  def group_by_value_path
    "field_values.#{self.class.value_name}.name.keyword"
  end
  [:chart_by_value_path, :slice_by_value_path].each { |method| alias_method method, :group_by_value_path }

  sig { override.returns(String) }
  def query_by_value_path
    "field_values.#{self.class.value_name}.name.lowercased_keyword"
  end

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
      .returns(T::Hash[Integer, T.all(Label, Interface::Groupable::Metadata)])
  end
  def preload_group_metadata_objects(metadata_object_ids)
    Label.where(id: metadata_object_ids).index_by(&:id)
  end
  alias_method :preload_slice_metadata_objects, :preload_group_metadata_objects

  sig { override.returns(Symbol) }
  def query_slug
    :label
  end

  sig { override.returns(T::Hash[T.untyped, T.untyped]) }
  def existence_fragment
    {
      nested: {
        path: "field_values",
        query: {
          exists: {
            field: "field_values.#{self.class.value_name}.name"
          }
        }
      }
    }
  end

  sig { override.returns(T::Boolean) }
  def self.writeable? = true

  sig do
    override
    .params(
      item: MemexProjectItem,
      new_value: T.untyped,
      actor: User,

      # This parameter is required by the abstract interface, but it is not and should not be used in this method
      # because we are not at liberty to suppress Hydro events for labels (they are part of the Issues service
      # rather than the Projects service; this method is just a convenience for interacting with labels from
      # within Projects).
      suppress_hydro_events: T::Boolean)
    .returns(Interface::Writeable::PartialResult)
  end
  private def update_mysql_field_value(item:, new_value:, actor:, suppress_hydro_events:)
    issue = item.issue_for_content
    unless issue
      return Interface::Writeable::PartialResult.failure("Content issue not found")
    end

    labels = if new_value.present?
      Label.where(id: new_value, repository_id: issue.repository_id).to_a
    else
      []
    end

    if issue.replace_labels(labels) # domain-isolation-query-violation:ignore:packages/issues (SELECT, UPDATE)
      total_label_ids = new_value&.count || 0
      if issue.label_ids.count == total_label_ids
        return Interface::Writeable::PartialResult.success
      end
      msg = "Not all labels could be found"
    else
      msg = issue.errors.full_messages.to_sentence
    end
    Interface::Writeable::PartialResult.failure(msg)
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
    (column_data&.first || {})[:name]
  end
end
