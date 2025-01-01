# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::Base < MemexProjectColumn
  extend T::Helpers

  include MemexProjectColumn::Helper::Serializable

  include Interface::Indexable
  include Interface::Queryable
  include Interface::Sortable
  include Interface::Groupable
  include Interface::Sliceable
  include Interface::Chartable
  include Interface::Writeable
  include Interface::Summable
  include Interface::Redactable
  include Interface::Serializable::WebApi
  include Interface::Serializable::RestApi

  abstract!

  class InterfaceNotSupportedError < StandardError; end

  # Abbreviations to improve readability of types in this module.
  ElasticsearchRequest = Elastomer::Interfaces::Api::Search::Request
  TermQuery = Elastomer::Interfaces::Api::Search::Request::TermQuery
  WildcardQuery = Elastomer::Interfaces::Api::Search::Request::WildcardQuery

  # Whether or not the field has been turned off, in which case it should not be used at all (i.e. it should not be
  # indexed, queried, or serialized for consumption by the client).
  sig { overridable.returns(T::Boolean) }
  def self.disabled?
    false
  end

  # Whether or not the field is a field where the underlying data comes from an existing data source on GitHub.
  #
  # Fields become special types by implementing the MemexProjectColumn::Interface::SpecialTypeSerializable interface.
  sig(:final) { returns(T::Boolean) }
  def self.special_type?
    false
  end

  sig { override.returns(T::Boolean) }
  def self.indexable?
    # By default, if the field is disabled entirely then it should also be excluded from the index.
    #
    # However, some fields may choose to override this so that data is excluded from the index even if other aspects
    # of the field are still in use. That type of configuration may be useful for shipping incrementally.
    !disabled?
  end

  # Whether or not the field is considered safe for serialization.
  #
  # By default, fields are not considered safe for serialization and implementors must explicitly opt-in.
  sig { override.overridable.returns(T::Boolean) }
  def self.web_api_serializable? = false

  # Whether or not the field is considered safe for REST API serialization.
  #
  # By default, fields are not considered safe for REST API serialization and implementors must explicitly opt-in.
  sig { override.returns(T::Boolean) }
  def self.rest_api_serializable? = false

  sig { override.returns(Symbol) }
  def self.data_type
    T.must(self.name).demodulize.underscore.to_sym
  end

  # Declares the list of MemexProjectItem content types for which data can be stored or retrieved in this field type.
  #
  # Values returned from this method must be a subset of MemexProjectItem::VALID_CONTENT_TYPES.
  #
  # EXAMPLES:
  #
  #    project = MemexProject.find(1)
  #    linked_pull_requests_field = project.memex_project_columns.find(&:linked_pull_request?).to_field
  #    linked_pull_requests_field.supported_content_types # Returns [MemexProjectItem::ContentType::Issue]
  #
  #    reviewers_field = project.memex_project_columns.find(&:reviewers?).to_field
  #    reviewers_field.supported_content_types # Returns [MemexProjectItem::ContentType::PullRequest]
  #
  #    title_field = project.memex_project_columns.find(&:title?).to_field
  #    title_field.supported_content_types # Returns all content types: MemexProjectItem::ContentType.values
  #
  sig { overridable.returns(T::Array[MemexProjectItem::ContentType]) }
  def self.supported_content_types = MemexProjectItem::ContentType.values

  sig { returns(Symbol) }
  def self.value_name
    "#{data_type}_value".to_sym
  end

  sig { override.returns(Symbol) }
  def query_slug
    name_slug.to_sym
  end

  sig do
    overridable
    .params(
      item: MemexProjectItem,
      prefilled_associations: T.nilable(MemexProjectItem::PrefilledAssociations),
      redacted_issue_ids: T::Array[Integer]
    ).returns(T.nilable(String))
  end
  def string_value(item, prefilled_associations: nil, redacted_issue_ids: [])
    value(item, prefilled_associations:, redacted_issue_ids:)&.to_s
  end

  sig do
    override
    .overridable
    .params(item: MemexProjectItem)
    .returns(T.nilable(Elastomer::Interfaces::Document::MemexProjectItem::Value))
  end
  def elasticsearch_document(item); end

  sig { override.overridable.params(items: T::Array[MemexProjectItem]).void }
  def preload_elasticsearch_document_data(items); end
  alias_method :preload_web_api_response_data, :preload_elasticsearch_document_data
  alias_method :preload_rest_api_response_data, :preload_elasticsearch_document_data

  sig do
    params(item: MemexProjectItem)
    .returns(T.nilable(Elastomer::Interfaces::Document::MemexProjectItem::FieldValue))
  end
  def elasticsearch_field_value(item)
    value = elasticsearch_document(item)
    # Note that value.present? should return false on any empty values (e.g. nil, "", " ", [], {})
    return nil unless value.present?

    Elastomer::Interfaces::Document::MemexProjectItem::FieldValue.new(
      field_slug: self.name_slug,
      field_type: self.data_type,
      field_id: elasticsearch_field_id,
      value_name: self.class.value_name,
      value:,
    )
  end

  sig { overridable.returns(Elastomer::Interfaces::Document::MemexProjectItem::FieldValues::FieldIdProperty) }
  def elasticsearch_field_id
    Elastomer::Interfaces::Document::MemexProjectItem::FieldValues::FieldIdProperty::ProjectFieldId.new(id)
  end

  # Elasticsearch term filter to match a project item based on one of the field values. Typically this would match
  # an object within field_values matching the current field.
  sig { overridable.returns(T::Hash[T.untyped, T.untyped]) }
  def elasticsearch_field_value_term_filter
    {
      term: {
        "field_values.#{elasticsearch_field_id.property}": {
          value: elasticsearch_field_id.id,
        },
      },
    }
  end

  sig do
    params(item: MemexProjectItem)
    .returns(Elastomer::Interfaces::Api::Request::Script)
  end
  def elasticsearch_field_value_update_script(item)
    if updated_field_value = elasticsearch_field_value(item)
      Elastomer::Interfaces::Api::Request::Script.new(
        # To ensure we don't update unnecessarily, we abort/noop if we find that the value exists already. Otherwise,
        # we proceed by removing the existing metadata and value and replace it with the new one. Note that we don't
        # need to worry about replacing newer data with older data because we're fetching the latest canonical data
        # from the database.
        source: """
          def existing_field_value = ctx._source.field_values.find(field -> field[params.field_id_property] == params.field_id);
          if (existing_field_value == params.updated_field_value) {
            ctx.op = 'noop';
          } else {
            ctx._source.field_values.removeIf(field -> field[params.field_id_property] == params.field_id);
            ctx._source.field_values.add(params.updated_field_value);
          }
        """,
        params: {
          field_id_property: elasticsearch_field_id.property,
          field_id: elasticsearch_field_id.id,
          updated_field_value: updated_field_value.to_hash
        }
      )
    else
      # If the updated field value is nil, we remove the related field entirely from the field_values array. Note that
      # this will be a noop if the field does not already exist in the array.
      Elastomer::Interfaces::Api::Request::Script.new(
        source: """
          boolean field_removed = ctx._source.field_values.removeIf(field -> field[params.field_id_property] == params.field_id);
          if (!field_removed) {
            ctx.op = 'noop';
          }
        """,
        params: {
          field_id_property: elasticsearch_field_id.property,
          field_id: elasticsearch_field_id.id,
        }
      )
    end
  end

  # Disabled fields are not queryable
  sig { override.overridable.returns(T::Boolean) }
  def self.queryable?
    !self.disabled?
  end

  # This should be overridden by subclasses.
  sig { override.overridable.returns(String) }
  def query_by_value_path
    if self.class.queryable?
      raise NotImplementedError
    else
      raise InterfaceNotSupportedError
    end
  end

  sig do
    override
    .params(value: String, context: Search::Memex::Context)
    .returns(T.nilable(T::Hash[T.untyped, T.untyped]))
  end
  def query_strategy(value:, context:)
    return nil unless self.class.queryable?
    wildcard_query(value:, context:)&.to_hash || term_query(value:, context:)&.to_hash
  end

  sig { overridable.params(value: String, context: Search::Memex::Context).returns(T.nilable(WildcardQuery)) }
  private def wildcard_query(value:, context:)
    return nil unless value.include?("*")

    WildcardQuery.new(
      field_path: query_by_value_path,
      value: WildcardQuery::Value.new(value),
    )
  end

  sig { overridable.params(value: String, context: Search::Memex::Context).returns(T.nilable(TermQuery)) }
  private def term_query(value:, context:)
    TermQuery.new(
      field_path: query_by_value_path,
      value:,
    )
  end

  sig do
    override
      .params(direction: String)
      .returns(T::Hash[T.untyped, T.untyped])
  end
  def sort_fragment(direction:)
    {}
  end

  sig { override.returns(T::Hash[T.untyped, T.untyped]) }
  def existence_fragment
    {}
  end

  # Provides the optional Elasticsearch query fragment to aggregate on slice_by field values.
  # This returns total counts for each distinct field value.  Missing/nil values are not included.
  # The count of missing/nil slice values is calculated by subtracting the sum of value counts
  # from the total hits of all documents matching the overall query filter.
  sig { override.params(key_prefix: String).returns(ElasticsearchRequest::Aggregation::Collection) }
  def slice_by_fragment(key_prefix: "")
    slice_by_aggregation = ElasticsearchRequest::Aggregation::Nested.new(
      slug: "#{key_prefix}slice_by".to_sym,
      path: "field_values",
    )
    values_filter_aggregation = ElasticsearchRequest::Aggregation::Filter.new(
      slug: :values,
      filter: elasticsearch_field_value_term_filter,
    )
    slices_terms_aggregation = ElasticsearchRequest::Aggregation::Terms.new(
      slug: :slices,
      field: slice_by_value_path,
      order: index.index_running_version_8_plus? ? { _key: "asc" } : { _term: "asc" },
      size: MAX_SLICE_VALUES_SIZE,
    )
    if include_slice_metadata && slice_by_metadata_sample_aggregation = slice_by_metadata_sample_agg
      slices_terms_aggregation.add_subaggregation(slice_by_metadata_sample_aggregation)
    end

    slice_by_aggregation.add_subaggregation(
      values_filter_aggregation.add_subaggregation(
        slices_terms_aggregation
      )
    )

    # Gets the counts of items with a nil or missing slice value
    no_slice_value_aggregation = ElasticsearchRequest::Aggregation::Filter.new(
      slug: "#{key_prefix}no_slice_value".to_sym,
      filter: {
        bool: {
          must_not: existence_fragment
        }
      }
    )

    ElasticsearchRequest::Aggregation::Collection.new([
      slice_by_aggregation,
      no_slice_value_aggregation,
    ])
  end

  sig { override.params(group_by_value: T.nilable(String)).returns(T.untyped) }
  def graphql_value(group_by_value)
    return nil if group_by_value.blank? || group_by_value == MISSING_VALUE_GROUP_KEY

    group_by_value
  end

  sig { override.params(group_by_value: T.nilable(String)).returns(String) }
  def graphql_title(group_by_value)
    return "No #{name}" if group_by_value.blank? || group_by_value == MISSING_VALUE_GROUP_KEY

    group_by_value
  end

  sig { override.overridable.returns(T::Boolean) }
  def self.summable? = false

  sig { override.overridable.returns(T::Boolean) }
  def self.writeable? = false

  sig { override.overridable.returns(T::Boolean) }
  def self.value_required? = false

  sig(:final) { returns(T::Boolean) }
  def self.value_not_required? = !value_required?

  sig do
    override
    .overridable
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
    raise InterfaceNotSupportedError.new("#{data_type} field is not writeable".strip) unless self.class.writeable?

    mysql_result = if self.class.value_required? && new_value.nil?
      Interface::Writeable::PartialResult.failure("#{data_type} value cannot be blank")
    else
      update_mysql_field_value(item:, new_value:, actor:, suppress_hydro_events:)
    end

    if mysql_result.failed?
      error = T.must(mysql_result.error)
      item.errors.add(error.attribute, error.message)
    end

    if mysql_result.failed? || skip_elasticsearch_updates
      Interface::Writeable::Result.new(mysql: mysql_result)
    else
      Interface::Writeable::Result.new(
        mysql: mysql_result,
        elasticsearch: update_elasticsearch_field_value(item:, new_value:, actor:)
      )
    end
  end

  sig do
    override
    .overridable
    .params(item: MemexProjectItem, new_value: T.untyped, actor: User, suppress_hydro_events: T::Boolean)
    .returns(Interface::Writeable::PartialResult)
  end
  private def update_mysql_field_value(item:, new_value:, actor:, suppress_hydro_events:)
    raise NotImplementedError
  end

  sig do
    override
    .overridable
    .params(item: MemexProjectItem, new_value: T.untyped, actor: User)
    .returns(T.nilable(Interface::Writeable::PartialResult))
  end
  private def update_elasticsearch_field_value(item:, new_value:, actor:)
    client = Search::Memex::Client.new(index)

    MemexProjectColumn::Interface::Writeable.rescue_client_error(context: self.class.name) do
      response = client.update(
        Elastomer::Interfaces::Api::Update::Request::Body.new(
          script: elasticsearch_field_value_update_script(item)
        ),
        Elastomer::Interfaces::Api::Update::Request::Params.new(
          id: item.id,
          routing: item.memex_project_id,
          refresh: Elastomer::Interfaces::Api::Update::Request::Params::Refresh::WaitFor,
        )
      )

      if response.success?
        Interface::Writeable::PartialResult.success
      else
        GitHub.logger.error(
          "Synchronous update of project item field value in Elasticsearch failed",
          {
            "code.namespace" => self.class.name,
            "code.function" => "update_elasticsearch_field_value",
            "gh.user.id" => actor.id,
            "gh.memex.project.id" => item.memex_project_id,
            "gh.memex.item.id" => item.id,
            "gh.memex.es.api.update.response" => response.to_hash.to_json
          }
        )
        Interface::Writeable::PartialResult.failure(response.result.serialize)
      end
    end
  end

  sig { override.overridable.params(item: MemexProjectItem).returns(T.nilable(BulkUpdateAction)) }
  def elasticsearch_bulk_update_action(item)
    return unless self.class.writeable?

    Interface::Writeable::BulkUpdateAction.new(
      body: { script: elasticsearch_field_value_update_script(item).to_hash },
      params: { _id: item.id, _routing: item.memex_project_id },
    )
  end

  sig { override.returns(Elastomer::Indexes::MemexProjectItems) }
  private def index
    @index ||= T.let(Elastomer::Indexes::MemexProjectItems.new, T.nilable(Elastomer::Indexes::MemexProjectItems))
  end

  sig do
    params(direction: String, sort_by: String)
      .returns(T::Hash[T.untyped, T.untyped])
  end
  private def build_version_compatible_sort_fragment(direction:, sort_by:)
    if index.index_running_version_8_plus?
      {
        "#{sort_by}": {
          order: direction,
          nested: {
            path: "field_values",
            filter: {
              bool: {
                must: [elasticsearch_field_value_term_filter],
              }
            }
          }
        }
      }
    else
      {
        "#{sort_by}": {
          order: direction,
          nested_path: "field_values",
          nested_filter: {
            bool: {
              must: [elasticsearch_field_value_term_filter],
            }
          }
        }
      }
    end
  end

  sig do
    override.
      params(
        item: MemexProjectItem,
        prefilled_associations: T.nilable(MemexProjectItem::PrefilledAssociations),
        redacted_issue_ids: T::Array[Integer],
      ).
      returns(T.nilable(SerializableReturn))
  end
  def serializable(item, prefilled_associations: nil, redacted_issue_ids: []); end

  sig do
    override.
      params(
        item: MemexProjectItem,
        prefilled_associations: T.nilable(MemexProjectItem::PrefilledAssociations),
        redacted_issue_ids: T::Array[Integer],
      ).
      returns(T.nilable(ValueReturn))
  end
  def value(item, prefilled_associations: nil, redacted_issue_ids: []); end

  sig do override.
      params(
        item: MemexProjectItem,
        redacted_issue_ids: T::Array[Integer],
      ).
      returns(T.nilable(RestApiSerializedValue))
  end
  def to_rest_api_hash(item, redacted_issue_ids: []); end

end
