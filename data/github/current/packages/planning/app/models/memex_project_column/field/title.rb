# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::Title < MemexProjectColumn::Field::Base
  include Interface::SpecialTypeSerializable

  sig { override.returns(T::Array[String]) }
  def self.register_processors
    [
      "MemexProjectColumn::Interface::Indexable::Processor::IssueTitleValueUpdate",
      "MemexProjectColumn::Interface::Indexable::Processor::DraftIssueTitleUpdate",
    ]
  end

  sig { override.returns(Elastomer::Interfaces::Mapping::FieldDataType) }
  def self.elasticsearch_mapping
    Elastomer::Interfaces::Mapping::FieldDataTypes::KeywordMultiField.new(
      fields: {
        keyword: Elastomer::Interfaces::Mapping::FieldDataTypes::Keyword.new,
        lowercased_keyword: Elastomer::Interfaces::Mapping::FieldDataTypes::Keyword.new(
          normalizer: Elastomer::Interfaces::Mapping::Normalizer::Lowercase
        ),
        wildcard: Elastomer::Interfaces::Mapping::FieldDataTypes::Wildcard.new,
      },
      copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS
    )
  end

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_elasticsearch_document_data(items)
    preload_content_tree(items)
  end

  sig { override.returns(T::Boolean) }
  def self.should_preload_content_tree? = true

  sig do
    override
      .params(items: T::Array[MemexProjectItem], fields: T::Array[MemexProjectColumn::Field::Base])
      .returns(T.nilable(T::Hash[Integer, T.untyped]))
  end
  private def preload_web_api_response_data(items:, fields:)
    # This is an intentional no-op; setting `web_api_serialization_requires_content_tree?` to true ensures that all
    # preloading required for this field is performed in `MemexProject#preload_web_api_response_data`.
  end

  sig do
    override
      .params(items: T::Array[MemexProjectItem], opts: RestApiPreloadOptions).void
  end
  public def preload_rest_api_response_data(items, opts = RestApiPreloadOptions.new)
    preload_content_tree(items)

    contents = items.select { |item| item.pull_request? }.map(&:content).compact # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    GitHub::PrefillAssociations.prefill_associations(contents, :merge_queue_entry)
  end

  sig do
    override
      .params(item: MemexProjectItem)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::TitleValue)
  end
  def elasticsearch_document(item)
    content = item.content # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    if (content.is_a?(Issue) || content.is_a?(PullRequest)) && content.repository.nil?
      raise CanonicalDataMissingError, "repository for item_id: #{item.id} does not exist"
    end

    item.denormalized_title_value&.dig(:title, :raw)
  end

  sig do
    override.
      params(
        item: MemexProjectItem,
        prefilled_associations: T.nilable(MemexProjectItem::PrefilledAssociations),
        redacted_issue_ids: T::Array[Integer],
      ).
      returns(T.nilable(T::Hash[T.untyped, T.untyped]))
  end
  def serializable(item, prefilled_associations: nil, redacted_issue_ids: [])
    if prefilled_associations
      return unless (column_value = item.find_preloaded_column_value(id))
      json_value = column_value.json_value
      return unless json_value.is_a?(Hash)

      merge_queue_status = prefilled_associations.is_in_merge_queue?(item)
      json_value = json_value.merge("isInMergeQueue" => merge_queue_status) unless merge_queue_status.nil?
    else
      json_value = T.must(item.content).memex_denormalized_title_value # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      json_value = json_value.deep_stringify_keys

      # When using the preloading path without prefilled_associations, check the content's
      # merge_queue_entry association which is preloaded in MemexProject#preload_web_api_response_data.
      if item.pull_request?
        json_value = json_value.merge("isInMergeQueue" => T.cast(item.content, PullRequest).merge_queue_entry.present?)
      end
    end

    T.cast(json_value, T::Hash[T.untyped, T.untyped])
  end

  sig do
    override.
      params(
        item: MemexProjectItem,
        prefilled_associations: T.nilable(MemexProjectItem::PrefilledAssociations),
        redacted_issue_ids: T::Array[Integer],
      ).
      returns(T.nilable(MemexProjectColumnValue::SerializableValue))
  end
  def value(item, prefilled_associations: nil, redacted_issue_ids: [])
    return unless value = serializable(item, prefilled_associations:, redacted_issue_ids:)

    MemexProjectColumnValue::Title.new(
      raw_title: value["title"]["raw"],
      html_title: value["title"]["html"],
      number: value["number"],
      url: value["url"],
      issue_id: value["issueId"],
      state: value["state"],
      state_reason: value["stateReason"],
      is_draft: value["isDraft"],
      is_in_merge_queue: value["isInMergeQueue"],
    )
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

  sig { override.returns(String) }
  def query_by_value_path
    "field_values.#{self.class.value_name}.lowercased_keyword"
  end

  sig { override.params(value: String, context: Search::Memex::Context).returns(T.nilable(WildcardQuery)) }
  private def wildcard_query(value:, context:)
    return nil unless value.include?("*")

    WildcardQuery.new(
      field_path: "field_values.#{self.class.value_name}.wildcard",
      value: WildcardQuery::Value.new(value),
      case_insensitive: true,
    )
  end

  sig { override.returns(T::Boolean) }
  def self.writeable? = true

  # Title is editable for Issues, PRs, and DraftIssues (modifying the underlying content's title),
  # but read-only for AgentTasks whose title is sourced from Mission Control and not editable via Projects.
  #
  # Note: We override capabilities_for_content_type rather than excluding AgentTask from
  # supported_content_types because Title still needs to *display* for AgentTask items —
  # and supported_content_types controls preloading (see MemexProject#preload_web_api_response_data).
  sig { override.params(content_type: MemexProjectItem::ContentType).returns(T::Hash[Symbol, T::Boolean]) }
  def self.capabilities_for_content_type(content_type)
    super.merge(
      readOnly: content_type == MemexProjectItem::ContentType::AgentTask,
    )
  end

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

    content = item.content # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    title_receiver = T.must(content.is_a?(PullRequest) ? content.issue : content)
    title_receiver.modifying_user = actor if title_receiver.is_a?(Issue)

    unless title_receiver.update(title: new_value[:title]) # domain-isolation-query-violation:ignore:packages/issues (UPDATE)
      return Interface::Writeable::PartialResult.failure(title_receiver.errors.full_messages.to_sentence)
    end

    # Note that this is legacy functionality that should be removed once `MemexEventProcessor` (the legacy
    # denormalization pipeline) has been removed: https://github.com/github/projects-platform/issues/2837
    unless item.cache_title_column_value(self, item.denormalized_title_value, actor)
      return Interface::Writeable::PartialResult.failure("Failed to update denormalized value")
    end

    Interface::Writeable::PartialResult.success
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
    return unless value = serializable(item, redacted_issue_ids:)

    {
      raw: value["title"]["raw"],
      html: value["title"]["html"],
    }
  end
end
