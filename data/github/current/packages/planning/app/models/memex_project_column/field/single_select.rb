# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::SingleSelect < MemexProjectColumn::Field::Base
  include GitHub::Memoizer
  include Helper::GenericField

  TermQuery = Elastomer::Interfaces::Api::Search::Request::TermQuery
  WildcardQuery = Elastomer::Interfaces::Api::Search::Request::WildcardQuery

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

  sig do
    override
      .params(model: MemexProjectItem)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::SingleSelectValue)
  end
  def elasticsearch_document(model)
    single_select_option_id = model
    .column_values(columns: [self], require_prefilled_associations: false)
    .first
    .deep_symbolize_keys
    .dig(:value, :id)

    return unless single_select_option_id

    single_select = single_select_option(single_select_option_id)
    return unless single_select

    single_select_option = single_select.deep_symbolize_keys.slice(:id, :name)
    Elastomer::Interfaces::Document::SingleSelect.new(single_select_option)
  end

  sig do
    override
      .params(context: Elastomer::Interfaces::Document::MemexProjectItem::SeedContext)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::SingleSelectValue)
  end
  def seed_elasticsearch_document(context)
    Elastomer::Interfaces::Document::SingleSelect.new(
      id: settings_option_ids.sample,
      name: settings.dig("options").sample(context.num_single_select_values).first&.dig("name")
    )
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
          query: {
            bool: {
              must: [
                {
                  term: {
                    "field_values.field_id": { value: id },
                  }
                },
                if value.include?("*")
                  WildcardQuery.new(
                    field_path: "field_values.#{self.class.value_name}.name.keyword",
                    value: WildcardQuery::Value.new(value),
                    case_insensitive: true,
                  ).to_hash
                else
                  TermQuery.new(
                    field_path: "field_values.#{self.class.value_name}.name.keyword",
                    value:,
                    case_insensitive: true,
                  ).to_hash
                end
              ]
            }
          }
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

  sig { override.returns(T::Array[String]) }
  def static_group_values
    settings_options.map { |option| option["name"] }
  end
  alias_method :static_chart_values, :static_group_values

  sig { override.returns(T::Boolean) }
  def has_group_metadata? = true

  sig do
    override
    .params(
      field_value_document: T.nilable(T::Hash[T.untyped, T.untyped]),
      group_value: String,
    )
    .returns(T.nilable(String))
  end
  def group_by_metadata_object_id(field_value_document, group_value)
    settings_by_option_name.dig(group_value, "id")
  end
  alias_method :slice_by_metadata_object_id, :group_by_metadata_object_id

  sig do
    override
    .params(metadata_object_ids: T::Array[String])
    .returns(T::Hash[String, MemexProjectColumn::Settings::OptionEntry])
  end
  def preload_group_metadata_objects(metadata_object_ids)
    settings_options_objects_all.reduce({}) do |memo, option|
      memo[option.id] = option
      memo
    end
  end
  alias_method :preload_slice_metadata_objects, :preload_group_metadata_objects

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
end
