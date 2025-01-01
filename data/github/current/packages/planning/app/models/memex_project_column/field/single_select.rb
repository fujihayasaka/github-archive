# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::SingleSelect < MemexProjectColumn::Field::Base
  include GitHub::Memoizer
  include Helper::GenericField

  sig { override.returns(T::Array[String]) }
  def self.register_processors
    [
      "MemexProjectColumn::Interface::Indexable::Processor::SingleSelectSettingsChange",
      "MemexProjectColumn::Interface::Indexable::Processor::SingleSelectValueCreate",
      "MemexProjectColumn::Interface::Indexable::Processor::SingleSelectValueUpdate",
      "MemexProjectColumn::Interface::Indexable::Processor::SingleSelectValueDestroy",
    ]
  end

  sig { override.returns(Elastomer::Interfaces::Mapping::FieldDataType) }
  def self.elasticsearch_mapping
    Elastomer::Interfaces::Mapping::FieldDataTypes::Object.new(properties: {
      id: Elastomer::Interfaces::Mapping::FieldDataTypes::Keyword.new,
      name: Elastomer::Interfaces::Mapping::FieldDataTypes::KeywordMultiField.new(copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS)
    })
  end

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_elasticsearch_document_data(items)
    GitHub::PrefillAssociations.prefill_associations(items, :memex_project_column_values)
  end
  alias_method :preload_web_api_response_data, :preload_elasticsearch_document_data
  alias_method :preload_rest_api_response_data, :preload_elasticsearch_document_data

  sig do
    override
      .params(model: MemexProjectItem)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::SingleSelectValue)
  end
  def elasticsearch_document(model)
    single_select_option_id = model
    .column_values(columns: [self])
    .first
    &.deep_symbolize_keys
    &.dig(:value, :id)

    return unless single_select_option_id

    single_select = single_select_option(single_select_option_id)
    return unless single_select

    single_select_option = single_select.deep_symbolize_keys.slice(:id, :name)
    Elastomer::Interfaces::Document::SingleSelect.new(single_select_option)
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
                  "field_values.field_id": {
                    value: id
                  },
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

  # Returns an Elasticsearch fragment that can be used to sort by this single-select field.
  # This uses script-based sorting to sort by the user-defined order of the single-selection options.
  sig do
    override
      .params(direction: String)
      .returns(T::Hash[T.untyped, T.untyped])
  end
  def sort_fragment(direction:)
    options = settings_option_ids.each_with_index.reduce({}) do |hash, (id, index)|
      hash[id] = index
      hash
    end
    {
      _script: {
        type: "number",
        script: {
          lang: "painless",
          params: {
            field_id: id,
            options: options
          },
          source: """
            long field_id = params.field_id;
            for (field in params._source.field_values) {
              if (field.field_id == field_id) {
                String value = field.single_select_value?.id;
                if (value == null) {
                  return #{NO_VALUE_SORT};
                }
                def sort_value = params.options[value] ?: #{STALE_VALUE_SORT};
                return sort_value;
              }
            }
            return #{NO_VALUE_SORT};
          """
        },
        order: direction
      }
    }
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

  sig { override.returns(T::Array[String]) }
  def static_group_values
    settings_options.map { |option| option["name"] }
  end
  alias_method :static_chart_values, :static_group_values

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
    .params(metadata_object_ids: T::Array[String])
    .returns(T::Hash[String, MemexProjectColumn::Settings::OptionEntry])
  end
  def preload_metadata_objects(metadata_object_ids)
    settings_options_objects_all.reduce({}) do |memo, option|
      memo[option.id] = option
      memo
    end
  end

  sig(:final) { returns(T::Hash[String, T.untyped]) }
  memoize private def settings_by_option_name
    settings_options.reduce({}) do |memo, option|
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
    known_value_to_order = settings_options.each_with_index.reduce({}) do |hash, (option, index)|
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
      settings_options.each do |option|
        value = option["name"]
        sorted_slices << create_slice(value, 0) unless fetched_values.include?(value)
      end
      sorted_slices << create_slice(MISSING_VALUE_GROUP_KEY, 0) unless fetched_values.include?(MISSING_VALUE_GROUP_KEY)
    end
    # TODO: https://github.com/github/projects-platform/issues/1955
    # Since this override method adds additional slices after metadata
    # is added, we have to call `add_slice_metadata!` again on the new slices.
    # This is a temporary solution until the above issue is completed.
    add_slice_metadata!(sorted_slices) if include_slice_metadata
    unnested_slices[:slices] = sorted_slices
    unnested_slices
  end

  # GraphQL expected the option's ID, not the option's text for the ProjectV2GroupSingleSelectValue object.
  sig { override.params(group_by_value: T.nilable(String)).returns(T.nilable(String)) }
  def graphql_value(group_by_value)
    # Calling super helps cleanse potential _noValue values
    value = super(group_by_value)

    return if value.blank?

    # We store the option name in ES so we need to map it back to the column option entry and
    # exchange it for the underlying option id for GraphQL.
    settings_option_ids([group_by_value]).first
  end

  sig { override.returns(T::Boolean) }
  def self.writeable? = true

  sig { override.returns(T::Boolean) }
  def self.web_api_serializable? = true

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
    json_value = T.cast(super, T.nilable(T::Hash[String, T.untyped]))

    option_entry = single_select_option(json_value&.dig("id"))
    return unless option_entry

    MemexProjectColumn::Settings::OptionEntry.new(
      id: option_entry["id"],
      name: option_entry["name"],
      name_html: option_entry["name_html"],
      color: option_entry["color"],
      description: option_entry["description"],
      description_html: option_entry["description_html"]
    )
  end

  sig do
    override.
      params(
        item: MemexProjectItem,
        prefilled_associations: T.nilable(MemexProjectItem::PrefilledAssociations),
        redacted_issue_ids: T::Array[Integer],
      ).
      returns(T.nilable(ValueReturn))
  end
  def value(item, prefilled_associations: nil, redacted_issue_ids: [])
    return unless value = serializable(item, prefilled_associations:, redacted_issue_ids:)

    value.memex_project_column_value
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
    return unless option = T.cast(serializable(item, redacted_issue_ids:), T.nilable(MemexProjectColumn::Settings::OptionEntry))

    Api::Serializer.serialize(:projects_v2_single_select_field_value_hash, option)
  end
end
