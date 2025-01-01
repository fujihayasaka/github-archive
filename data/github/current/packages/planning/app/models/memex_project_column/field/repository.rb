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
      full_name: Elastomer::Interfaces::Mapping::FieldDataTypes::KeywordMultiField.new(copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS)
    })
  end

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_elasticsearch_document_data(items)
    preload_content_tree(items)
    GitHub::PrefillAssociations.prefill_associations(items.map(&:repository), [:owner])
  end

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_web_api_response_data(items)
    preload_content_tree(items)
    GitHub::PrefillAssociations.prefill_batch_method(items.map(&:repository), :has_any_trade_restrictions?)
  end

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_rest_api_response_data(items)
    preload_content_tree(items)
    GitHub::PrefillAssociations.prefill_associations(items.map(&:repository), [:owner, :network])
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
        full_name: item.repository&.full_name
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

  sig do
    override
      .params(direction: String)
      .returns(T::Hash[T.untyped, T.untyped])
  end
  def sort_fragment(direction:)
    build_version_compatible_sort_fragment(
      direction: direction,
      sort_by: "field_values.#{self.class.value_name}.full_name.keyword",
    )
  end

  sig { override.returns(T::Hash[T.untyped, T.untyped]) }
  def existence_fragment
    {
      nested: {
        path: "field_values",
        query: {
          exists: {
            field: "field_values.#{self.class.value_name}.full_name"
          }
        }
      }
    }
  end

  sig { override.returns(String) }
  def group_by_value_path
    "field_values.#{self.class.value_name}.full_name.keyword"
  end
  [:chart_by_value_path, :slice_by_value_path].each { |method| alias_method method, :group_by_value_path }

  sig { override.returns(String) }
  def query_by_value_path
    "field_values.#{self.class.value_name}.full_name.lowercased_keyword"
  end

  sig do
    override
    .params(value: String, context: Search::Memex::Context)
    .returns(T.nilable(T::Hash[T.untyped, T.untyped]))
  end
  def query_strategy(value:, context:)
    if GitHub.multi_tenant_enterprise? && FeatureFlag.vexi.enabled?(:memex_pwl_proxima_repo_filter, default: false)
      # Repository field values are indexed by the full_name of the repo
      # which includes the tenant shortcode in multi-tenant mode.
      # However the user may filter by repo.name_with_display_owner
      shortcode = GitHub::CurrentTenant.get&.shortcode
      if shortcode && !value.match?(/#{shortcode}\//i)
        value = value.gsub("/", "#{User::ENTERPRISE_MANAGED_USER_LOGIN_SEPARATOR}#{shortcode}/")
      end
    end
    super(value:, context:)
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
