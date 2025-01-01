# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::ParentIssue < MemexProjectColumn::Field::Base
  include Interface::SpecialTypeSerializable

  sig { override.returns(T::Array[MemexProjectItem::ContentType]) }
  def self.supported_content_types = [MemexProjectItem::ContentType::Issue]

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
      title_with_nwo: Elastomer::Interfaces::Mapping::FieldDataTypes::KeywordMultiField.new,
      owner_id: Elastomer::Interfaces::Mapping::FieldDataTypes::Long.new,
    })
  end

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_elasticsearch_document_data(items)
    issue_items = items.select(&:issue?)
    preload_content_tree(issue_items)
    issues = T.cast(issue_items.map(&:content).compact, T::Array[Issue])
    GitHub::PrefillAssociations.prefill_associations(issues, :parent_issue_relation)

    parent_relations = issues.map(&:parent_issue_relation).compact
    GitHub::PrefillAssociations.prefill_associations(parent_relations, :source) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

    parents = parent_relations.map(&:source).compact
    GitHub::PrefillAssociations.prefill_associations(parents, { repository: :owner }, available_records: issue_items.map(&:repository))
  end

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_web_api_response_data(items)
    issue_items = items.select(&:issue?)
    preload_content_tree(issue_items)

    issues = T.cast(issue_items.map(&:content).compact, T::Array[Issue])

    GitHub::PrefillAssociations.prefill_associations(issues, { parent_issue_relation: :source }) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

    parents = issues.map { |issue| issue.parent_issue_relation&.source }.compact
    GitHub::PrefillAssociations.prefill_associations(
      parents,
      [:issue_dependency_list, :sub_issue_list, { repository: :owner }],
      available_records: issue_items.map(&:repository)
    )
  end

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_rest_api_response_data(items)
    issue_items = items.select(&:issue?)

    preload_content_tree(issue_items)

    issues = T.cast(issue_items.map(&:content).compact, T::Array[Issue])

    parent_relations = issues.map(&:parent_issue_relation).compact
    GitHub::PrefillAssociations.prefill_associations(parent_relations, :source, available_records: issues) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

    parents = parent_relations.map(&:source).compact

    available_records = issues
    available_records += issues.map(&:repository)
    available_records.compact.uniq!

    # Ideally, we want to leverage the existing IssuePrefiller to ensure changes
    # outside of projects are accounted for. However, because it's currently gated
    # behind a feature flag, we opt for a bit of duplication in an attempt to
    # minimize queries, if/when necessary.
    if FeatureFlag.vexi.enabled?(:updated_issue_prefillers, default: false)
      IssuePrefiller.optimized_prefill(parents, available_records:)
    else
      associations = [
        :assignees,
        :issue_dependency_list,
        :issue_field_values,
        :labels,
        :parent_issue_relation,
        :sub_issue_list,
        { user: :profile },
        { repository: :owner },
      ]
      GitHub::PrefillAssociations.prefill_associations(parents, associations, available_records:)
    end

    Reaction::Summary.prefill(parents)
  end

  sig do
    override
      .params(item: MemexProjectItem)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::ParentIssueValue)
  end
  def elasticsearch_document(item)
    content_type = MemexProjectItem::ContentType.deserialize(item.content_type)

    case content_type
    when MemexProjectItem::ContentType::Issue
      content = T.cast(item.content, Issue) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      return unless (relation = content.parent_issue_relation)
      return unless (parent = relation.source) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      Elastomer::Interfaces::Document::ParentIssue.new(
        id: parent.id,
        nwo_reference: parent.name_with_display_owner_reference,
        title: parent.title,
        title_with_nwo: parent.title_with_nwo,
        owner_id: parent.owner.id,
      )
    when MemexProjectItem::ContentType::DraftIssue,
        MemexProjectItem::ContentType::PullRequest
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
      returns(T.nilable(MemexProjectColumn::IDataSource))
  end
  def serializable(item, prefilled_associations: nil, redacted_issue_ids: [])
    content_type = MemexProjectItem::ContentType.deserialize(item.content_type)

    case content_type
    when MemexProjectItem::ContentType::Issue
      if prefilled_associations
        parent_issue = prefilled_associations.parent_issue(item)
        return if parent_issue.nil? || redacted_issue_ids.include?(parent_issue.id)

        parent_issue
      else
        issue = T.cast(item.content, Issue) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        return unless (parent_issue_relation = issue.parent_issue_relation)
        return if redacted_issue_ids.include?(parent_issue_relation.source_issue_id)

        parent_issue_relation.source # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end
    when MemexProjectItem::ContentType::PullRequest,
      MemexProjectItem::ContentType::DraftIssue
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
      sort_by: "field_values.#{self.class.value_name}.title_with_nwo.lowercased_keyword"
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
    "field_values.#{self.class.value_name}.title_with_nwo.lowercased_keyword"
  end
  alias_method :slice_by_value_path, :group_by_value_path

  sig { override.returns(String) }
  def chart_by_value_path
    "field_values.#{self.class.value_name}.nwo_reference.keyword"
  end

  sig { override.returns(String) }
  def query_by_value_path
    "field_values.#{self.class.value_name}.nwo_reference.lowercased_keyword"
  end

  sig { override.returns(T::Boolean) }
  def has_group_metadata? = true

  sig { override.returns(String) }
  def metadata_id_path
    "field_values.#{self.class.value_name}.id"
  end

  sig do
    override
      .params(metadata_object_ids: T::Array[Integer])
      .returns(T::Hash[Integer, T.all(Issue, IDataSource)])
  end
  def preload_metadata_objects(metadata_object_ids)
    issues = Issue.where(id: metadata_object_ids)
      .includes(repository: :owner)
      .includes(:sub_issue_list)
      .includes(:issue_dependency_list)
      .index_by(&:id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  sig { override.returns(T::Boolean) }
  def redactable?
    true
  end

  sig { override.params(metadata: IDataSource).returns(Integer) }
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
    content = item.content
    unless content.is_a?(Issue)
      return Interface::Writeable::PartialResult.failure("Only issues are supported")
    end

    if new_value.present?
      parent_issue = Issue.find_by(id: new_value) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

      unless parent_issue
        return Interface::Writeable::PartialResult.failure("Parent issue does not exist")
      end

      relationship = content.add_or_replace_parent!(parent_issue, actor)

      unless relationship.persisted?
        return Interface::Writeable::PartialResult.failure(relationship.errors.full_messages.to_sentence)
      end
    else
      # In the event that the sub-issue no longer belongs to this parent
      # continue normally as if the sub-issue was removed.
      content.parent&.remove_sub_issue!(content) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    Interface::Writeable::PartialResult.success
  # Unlike most sub-issues validations, max-height errors are raised in the `after_create` callback.
  rescue SubIssue::MaximumHeightError => e
    Interface::Writeable::PartialResult.failure(e.message)
  end

  sig { override.returns(T::Boolean) }
  def self.rest_api_serializable? = true

  sig do
    override.
     params(
       item: MemexProjectItem,
       redacted_issue_ids: T::Array[Integer],
     ).
     returns(T.nilable(T::Hash[String, T.untyped]))
  end
  def to_rest_api_hash(item, redacted_issue_ids: [])
    return unless parent_issue = T.cast(serializable(item, redacted_issue_ids:), T.nilable(Issue))

    Api::Serializer.serialize(:issue_hash, parent_issue, skip_author_association: true)
  end
end
