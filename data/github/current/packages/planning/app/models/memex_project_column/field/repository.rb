# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::Repository < MemexProjectColumn::Field::Base
  include Interface::SpecialTypeSerializable

  sig { override.returns(T::Array[MemexProjectItem::ContentType]) }
  def self.supported_content_types = [MemexProjectItem::ContentType::Issue, MemexProjectItem::ContentType::PullRequest]

  sig { override.returns(T::Array[String]) }
  def self.register_processors
    [
      "MemexProjectColumn::Interface::Indexable::Processor::RepositoryRename",
      "MemexProjectColumn::Interface::Indexable::Processor::RepositoryTransfer"
    ]
  end

  sig { override.returns(Symbol) }
  def query_slug
    :repo
  end

  sig { override.returns(Elastomer::Interfaces::Mapping::FieldDataType) }
  def self.elasticsearch_mapping
    Elastomer::Interfaces::Mapping::FieldDataTypes::Object.new(properties: {
      id: Elastomer::Interfaces::Mapping::FieldDataTypes::Long.new,
      owner_id: Elastomer::Interfaces::Mapping::FieldDataTypes::Long.new,
      owner_type: Elastomer::Interfaces::Mapping::FieldDataTypes::Keyword.new,
      # WARNING: `full_name` includes the tenant shortcode in Proxima envs
      # and should not be used for user-facing queries.
      # `name_with_display_owner` is the recommended alternative.
      full_name: Elastomer::Interfaces::Mapping::FieldDataTypes::KeywordMultiField.new(copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS),
      name_with_display_owner: Elastomer::Interfaces::Mapping::FieldDataTypes::KeywordMultiField.new(copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS)
    })
  end

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_elasticsearch_document_data(items)
    preload_content_tree(items)
    GitHub::PrefillAssociations.prefill_associations(items.map(&:repository), [:owner])
  end

  sig do
    override
      .params(items: T::Array[MemexProjectItem], fields: T::Array[MemexProjectColumn::Field::Base])
      .returns(T.nilable(T::Hash[Integer, T.untyped]))
  end
  private def preload_web_api_response_data(items:, fields:)
    items.each_with_object({}) do |item, result|
      next if item.draft_issue?
      result[item.id] = item.repository
    end
  end

  sig { override.returns(T::Boolean) }
  def self.should_preload_content_tree? = true

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_rest_api_response_data(items)
    GitHub::PrefillAssociations.prefill_associations(items, [{ content: { repository: [:owner, :network] } }]) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  sig { override.params(item: MemexProjectItem).returns(Elastomer::Interfaces::Document::MemexProjectItem::RepositoryValue) }
  def elasticsearch_document(item)
    content_type = MemexProjectItem::ContentType.deserialize(item.content_type)

    case content_type
    when MemexProjectItem::ContentType::Issue,
        MemexProjectItem::ContentType::PullRequest
      Elastomer::Interfaces::Document::Repository.new(
        id: item.repository_id,
        owner_id: T.must(item.repository).owner_id,
        owner_type: T.must(item.repository).owner&.type,
        # WARNING: `full_name` includes the tenant shortcode in Proxima envs
        # and should not be used for user-facing queries.
        # `name_with_display_owner` is the recommended alternative.
        full_name: item.repository&.full_name,
        name_with_display_owner: item.repository&.name_with_display_owner
      )
    when MemexProjectItem::ContentType::DraftIssue
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
    when MemexProjectItem::ContentType::Issue,
      MemexProjectItem::ContentType::PullRequest
      if prefilled_associations
        prefilled_associations.repository(item)
      elsif preloaded_web_api_response_data?
        preloaded_web_api_response_data[item.id]
      else
        issue_or_pull = T.cast(item.content, T.any(Issue, PullRequest)) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        issue_or_pull.repository
      end
    when MemexProjectItem::ContentType::DraftIssue
      nil
    else
      T.absurd(content_type)
    end
  end

  sig { returns(String) }
  private def name_with_display_owner_value_path
    "field_values.#{self.class.value_name}.name_with_display_owner"
  end

  sig do
    override
      .params(direction: String)
      .returns(T::Hash[T.untyped, T.untyped])
  end
  def sort_fragment(direction:)
    build_version_compatible_sort_fragment(
      direction: direction,
      sort_by: "#{name_with_display_owner_value_path}.keyword",
    )
  end

  sig { override.returns(T::Hash[T.untyped, T.untyped]) }
  def existence_fragment
    {
      nested: {
        path: "field_values",
        query: {
          exists: {
            field: name_with_display_owner_value_path
          }
        }
      }
    }
  end

  sig { override.returns(String) }
  def group_by_value_path
    "#{name_with_display_owner_value_path}.keyword"
  end
  [:chart_by_value_path, :slice_by_value_path].each { |method| alias_method method, :group_by_value_path }

  sig { override.returns(String) }
  def query_by_value_path
    "#{name_with_display_owner_value_path}.lowercased_keyword"
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
      .returns(T::Hash[Integer, T.all(Repository, IDataSource)])
  end
  def preload_metadata_objects(metadata_object_ids)
    ::Repository.where(id: metadata_object_ids).index_by(&:id)
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
    return unless repository = serializable(item, redacted_issue_ids:)

    Api::Serializer.serialize(:simple_repository_hash, repository, { include_timestamps: true })
  end
end
