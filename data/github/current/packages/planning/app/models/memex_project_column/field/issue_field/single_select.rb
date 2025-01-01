# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::IssueField::SingleSelect < MemexProjectColumn::Field::IssueField::Base
  DEFAULT_PRIORITY = 500

  sig { override.returns(T::Boolean) }
  def self.writeable? = true

  sig { override.returns(T::Boolean) }
  def self.web_api_serializable? = true

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
    GitHub::PrefillAssociations.prefill_associations(issues, [{ issue_field_values: { issue_field: :options } }])
  end
  alias_method :preload_web_api_response_data, :preload_elasticsearch_document_data

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
      MemexProjectItem::ContentType::PullRequest

      nil
    else
      T.absurd(content_type)
    end
  end

  sig { override.returns(String) }
  def query_by_value_path
    "field_values.#{self.class.value_name}.name.lowercased_keyword"
  end

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
end
