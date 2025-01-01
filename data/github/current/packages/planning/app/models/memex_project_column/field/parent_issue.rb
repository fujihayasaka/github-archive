# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::ParentIssue < MemexProjectColumn::Field::Base
  include Helper::SpecialField

  TermQuery = Elastomer::Interfaces::Api::Search::Request::TermQuery
  WildcardQuery = Elastomer::Interfaces::Api::Search::Request::WildcardQuery

  sig { override.returns(T::Array[String]) }
  def self.register_processors
    [
      "MemexProjectColumn::Interface::Indexable::Processor::SubIssueParentChange",
      "MemexProjectColumn::Interface::Indexable::Processor::ParentIssueTitleValueUpdate",
      "MemexProjectColumn::Interface::Indexable::Processor::RepositoryTransferParentIssue",
      "MemexProjectColumn::Interface::Indexable::Processor::RepositoryRenameParentIssue",
    ]
  end

  sig { override.returns(Elastomer::Interfaces::Mapping::FieldDataType) }
  def self.elasticsearch_mapping
    Elastomer::Interfaces::Mapping::FieldDataTypes::Object.new(properties: {
      id: Elastomer::Interfaces::Mapping::FieldDataTypes::Long.new,
      nwo_reference: Elastomer::Interfaces::Mapping::FieldDataTypes::KeywordMultiField.new(copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS),
      title: Elastomer::Interfaces::Mapping::FieldDataTypes::KeywordMultiField.new,
      owner_id: Elastomer::Interfaces::Mapping::FieldDataTypes::Long.new,
    })
  end

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_elasticsearch_document_data(items)
    issue_items = items.select(&:issue?)
    preload_content_tree(issue_items)
    issues = issue_items.map(&:content).compact
    GitHub::PrefillAssociations.prefill_associations(issues, :parent_issue_relation)

    parent_relations = issues.map(&:parent_issue_relation).compact
    GitHub::PrefillAssociations.prefill_associations(parent_relations, :source)

    parents = parent_relations.map(&:source).compact
    GitHub::PrefillAssociations.prefill_associations(parents, { repository: :owner }, available_records: issue_items.map(&:repository))
  end

  sig do
    override
      .params(item: MemexProjectItem)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::ParentIssueValue)
  end
  def elasticsearch_document(item)
    content_type = Elastomer::Interfaces::Document::MemexProjectItem::ContentType.deserialize(item.content_type)

    case content_type
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::Issue
      content = item.content
      return unless (relation = content&.parent_issue_relation)
      return unless (parent = relation&.source)
      Elastomer::Interfaces::Document::ParentIssue.new(
        id: parent.id,
        nwo_reference: parent.name_with_display_owner_reference,
        title: parent.title,
        owner_id: parent.owner.id,
      )
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::DraftIssue,
        Elastomer::Interfaces::Document::MemexProjectItem::ContentType::PullRequest
      nil
    else
      T.absurd(content_type)
    end
  end

  sig do
    override
      .params(context: Elastomer::Interfaces::Document::MemexProjectItem::SeedContext)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::ParentIssueValue)
  end
  def seed_elasticsearch_document(context)
    content_type = context.content_type

    case content_type
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::Issue
      id = rand(1..1000)
      repository = id + 1
      owner_display_login = id + 2
      owner_id = id + 3
      Elastomer::Interfaces::Document::ParentIssue.new(
        id: id,
        nwo_reference: "owner#{owner_display_login}/repository#{repository}##{id}",
        title: "issue ##{id}",
        owner_id: owner_id,
      )
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::DraftIssue,
        Elastomer::Interfaces::Document::MemexProjectItem::ContentType::PullRequest
      nil
    else
      T.absurd(content_type)
    end
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
          query: if value.include?("*")
                   WildcardQuery.new(
                     field_path: "field_values.#{self.class.value_name}.nwo_reference.keyword",
                     value: WildcardQuery::Value.new(value),
                     case_insensitive: true,
                   ).to_hash
                 else
                   TermQuery.new(
                     field_path: "field_values.#{self.class.value_name}.nwo_reference.keyword",
                     value:,
                     case_insensitive: true,
                   ).to_hash
                 end
        }
      }
    end

    wrap_query_fragment(should_clauses:, is_negated:)
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
                  "field_values.field_id": id
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

  sig { override.returns(String) }
  def group_by_value_path
    "field_values.#{self.class.value_name}.nwo_reference.keyword"
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
      .returns(T::Hash[Integer, T.all(Issue, Interface::Groupable::Metadata)])
  end
  def preload_group_metadata_objects(metadata_object_ids)
    issues = Issue.where(id: metadata_object_ids)
      .includes(repository: :owner)
      .includes(:sub_issue_list)
      .index_by(&:id)
  end
  alias_method :preload_slice_metadata_objects, :preload_group_metadata_objects

  sig { override.returns(T::Boolean) }
  def redactable?
    true
  end

  sig { override.params(metadata: T.any(MemexProjectColumn::Interface::Groupable::Metadata, MemexProjectColumn::Interface::Sliceable::Metadata)).returns(Integer) }
  def repository_id(metadata:)
    T.let(T.cast(metadata, Issue).repository_id, Integer)
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
  def update_mysql_field_value(item:, new_value:, actor:, suppress_hydro_events:)
    unless item.content.is_a?(Issue)
      return Interface::Writeable::PartialResult.failure("Only issues are supported")
    end

    if new_value.present?
      parent_issue = Issue.find_by(id: new_value)

      unless parent_issue
        return Interface::Writeable::PartialResult.failure("Parent issue does not exist")
      end

      relationship = item.content.add_or_replace_parent!(parent_issue, actor)

      unless relationship&.persisted?
        return Interface::Writeable::PartialResult.failure(relationship.errors.full_messages.to_sentence)
      end
    else
      # In the event that the sub-issue no longer belongs to this parent
      # continue normally as if the sub-issue was removed.
      item.content.parent.remove_sub_issue!(item.content) if item.content.parent.present?
    end

    Interface::Writeable::PartialResult.success
  # Unlike most sub-issues validations, max-height errors are raised in the `after_create` callback.
  rescue SubIssue::MaximumHeightError => e
    Interface::Writeable::PartialResult.failure(e.message)
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
