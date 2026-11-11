# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::IssueField::SingleSelect < MemexProjectColumn::Field::IssueField::Base
  DEFAULT_PRIORITY = 500

  sig { override.returns(T::Boolean) }
  def self.writeable? = true

  sig { override.returns(T::Boolean) }
  def self.rest_api_serializable? = true

  sig { override.returns(T::Array[String]) }
  def self.register_processors
    [
      "MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateIssueFieldSingleSelectValue",
    ]
  end

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_elasticsearch_document_data(items)
    supported_items = items.select(&:issue?)

    preload_content_tree(supported_items)

    issues = supported_items.map(&:issue).compact
    MemexProjectItemPrefiller.preload_issue_field_values_with_repo_id(issues, extra_associations: { issue_field: :options })
  end
  sig { override.params(items: T::Array[MemexProjectItem], opts: RestApiPreloadOptions).void }
  def preload_rest_api_response_data(items, opts = RestApiPreloadOptions.new)
    preload_elasticsearch_document_data(items)
  end

  sig { override.returns(Elastomer::Interfaces::Mapping::FieldDataType) }
  def self.elasticsearch_mapping
    Elastomer::Interfaces::Mapping::FieldDataTypes::Object.new(
      properties: {
        id: Elastomer::Interfaces::Mapping::FieldDataTypes::Long.new,
        name: Elastomer::Interfaces::Mapping::FieldDataTypes::KeywordMultiField.new(
          copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS,
        ),
        priority: Elastomer::Interfaces::Mapping::FieldDataTypes::Long.new,
      },
    )
  end

  sig do
    override
      .params(item: MemexProjectItem)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::IssueFieldSingleSelectValue)
  end
  def elasticsearch_document(item)
    content_type = MemexProjectItem::ContentType.deserialize(item.content_type)

    case content_type
    when MemexProjectItem::ContentType::Issue
      return unless issue_field?

      issue = T.cast(item.content, Issue) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      issue_field_value = issue.issue_field_values.find do |field_value|
        field_value.issue_field_id == issue_field_id
      end
      return unless issue_field_value

      issue_field_value = T.cast(issue_field_value, IssueFieldSingleSelectValue)
      return unless (option = issue_field_value.option)

      Elastomer::Interfaces::Document::IssueFieldSingleSelect.new(
        id: option.id,
        name: option.name,
        priority: option.priority || DEFAULT_PRIORITY,
      )
    when MemexProjectItem::ContentType::DraftIssue,
      MemexProjectItem::ContentType::PullRequest,
      MemexProjectItem::ContentType::AgentTask

      nil
    else
      T.absurd(content_type)
    end
  end

  sig { override.returns(String) }
  def query_by_value_path
    "field_values.#{self.class.value_name}.name.lowercased_keyword"
  end

  sig { override.returns(T::Array[String]) }
  def static_group_values
    issue_field_single_select_options.map { |option| option["name"] }
  end
  alias_method :static_chart_values, :static_group_values

  sig do
    override
      .params(direction: String)
      .returns(T::Hash[Symbol, String])
  end
  def sort_fragment(direction:)
    build_version_compatible_sort_fragment(
      direction:,
      sort_by: "field_values.#{self.class.value_name}.priority"
    )
  end

  sig { override.returns(T::Boolean) }
  def has_group_metadata? = true

  sig { override.params(group: Group).returns(T.untyped) }
  private def group_by_metadata_object_id(group)
    settings_by_option_name.dig(group.group_value, "id")
  end

  sig { override.params(slice: T::Hash[T.untyped, T.untyped]).returns(T.untyped) }
  def slice_by_metadata_object_id(slice)
    settings_by_option_name.dig(slice["slice_value"], "id")
  end

  sig do
    override
      .params(metadata_object_ids: T::Array[Integer])
      .returns(T::Hash[Integer, T.all(IssueFieldOption, IDataSource)])
  end
  def preload_metadata_objects(metadata_object_ids)
    issue_field_single_select_options_objects_all.reduce({}) do |memo, option|
      memo[option.id] = option
      memo
    end
  end

  sig(:final) { returns(T::Hash[String, T.untyped]) }
  memoize private def settings_by_option_name
    issue_field_single_select_options.reduce({}) do |memo, option|
      memo[option["name"]] = option
      memo
    end
  end

  # Returns true since all potential slice field values are known (ie, single-select options)
  sig { override.returns(T::Boolean) }
  def known_slices?
    true
  end

  # Override unnest_slices so that single-select field value slices can be sorted
  # according to the user-defined order of the single-selection options.
  sig do
    override
    .params(
      aggregation_results: T::Hash[T.untyped, T.untyped],
      total_hits: Integer
    )
    .returns(T::Hash[T.untyped, T.untyped])
  end
  def unnest_slices(aggregation_results:, total_hits:)
    unnested_slices = super(aggregation_results:, total_hits:)
    unsorted_slices = unnested_slices[:slices]
    known_value_to_order = issue_field_single_select_options.each_with_index.reduce({}) do |hash, (option, index)|
      hash[option["name"]] = index
      hash
    end
    known_value_to_order[MISSING_VALUE_GROUP_KEY] = NO_VALUE_SORT

    sorted_slices = unsorted_slices.sort_by do |slice|
      known_value_to_order[slice["slice_value"]] || STALE_VALUE_SORT
    end
    # optionally append remaining zero-count slice values (single-select options) that were not fetched from Elasticsearch
    if include_empty_slices
      fetched_values = T.let(unsorted_slices.map { |group| group["slice_value"] }.to_set, T::Set[T::untyped])
      issue_field_single_select_options.each do |option|
        value = option["name"]
        sorted_slices << create_slice(value, 0) unless fetched_values.include?(value)
      end
      sorted_slices << create_slice(MISSING_VALUE_GROUP_KEY, 0) unless fetched_values.include?(MISSING_VALUE_GROUP_KEY)
    end
    # TODO: https://github.com/github/projects-platform/issues/2095
    # Since this override method adds additional slices after metadata
    # is added, we have to call `add_slice_metadata!` again on the new slices.
    # This is a temporary solution until the above issue is completed.
    add_slice_metadata!(sorted_slices) if include_slice_metadata
    unnested_slices[:slices] = sorted_slices
    unnested_slices
  end

  sig { override.returns(String) }
  def group_by_value_path
    "field_values.#{self.class.value_name}.name.keyword"
  end

  sig { override.returns(String) }
  def chart_by_value_path
    group_by_value_path
  end

  sig { override.returns(String) }
  def slice_by_value_path
    group_by_value_path
  end

  sig do
    override
    .params(
      item: MemexProjectItem,
      new_value: T.untyped,
      actor: User,
      suppress_hydro_events: T::Boolean,
      skip_elasticsearch_updates: T::Boolean,
    )
    .returns(Interface::Writeable::Result)
  end
  def update_field_value(item:, new_value:, actor:, suppress_hydro_events: false, skip_elasticsearch_updates: false)
    # To take advantage of the existing generic single-select client behaviors we serialize the single-select option
    # ID as a string. IssueFieldSingleSelectValue which is the underlying model we are writing to requires all values
    # be an integer.
    #
    # Due to how the IssueFieldSingleSelectValue interface is exposed we cannot use ActiveRecord::Attributes to cast
    # the integer like we expect to be able to do with other ActiveRecord models. The database column the
    # single-select option is stored as is named `value`, but the model overrides the `value` method so the attribute
    # serializer instead tries to turn a single-select string value ("Eng Efficiency") into an integer which is always 0.
    #
    # Here we instead take the string value provided by the client and turn it into an integer.
    super(
      item:,
      new_value: new_value.presence&.to_i,
      actor:,
      suppress_hydro_events:,
      skip_elasticsearch_updates:,
    )
  end

  sig do
    override.
     params(
       item: MemexProjectItem,
       redacted_issue_ids: T::Array[Integer],
     ).
     returns(T.nilable(T::Hash[String, T.untyped]))
  end
  def to_rest_api_hash(item, redacted_issue_ids: [])
    return unless issue_field_value = T.cast(serializable(item, redacted_issue_ids:), T.nilable(IssueFieldSingleSelectValue))
    return unless issue_field_value.memex_column_value_present?
    return unless (option = issue_field_value.option)

    Api::Serializer.serialize(:projects_v2_single_select_field_value_hash, option.memex_project_column_value)
  end
end
