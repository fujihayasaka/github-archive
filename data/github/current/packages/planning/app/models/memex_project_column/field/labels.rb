# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::Labels < MemexProjectColumn::Field::Base
  include Helper::SpecialField

  TermQuery = Elastomer::Interfaces::Api::Search::Request::TermQuery
  WildcardQuery = Elastomer::Interfaces::Api::Search::Request::WildcardQuery

  sig { override.returns(T::Array[String]) }
  def self.register_processors
    [
      "MemexProjectColumn::Interface::Indexable::Processor::IssueUpdateLabels",
      "MemexProjectColumn::Interface::Indexable::Processor::LabelUpdate",
      "MemexProjectColumn::Interface::Indexable::Processor::LabelDelete",
    ]
  end

  sig { override.returns(Elastomer::Interfaces::Mapping::FieldDataType) }
  def self.elasticsearch_mapping
    Elastomer::Interfaces::Mapping::FieldDataTypes::Object.new(properties: {
      id: Elastomer::Interfaces::Mapping::FieldDataTypes::Long.new,
      name: Elastomer::Interfaces::Mapping::FieldDataTypes::KeywordMultiField.new(copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS),
      repository_id: Elastomer::Interfaces::Mapping::FieldDataTypes::Long.new
    })
  end

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_elasticsearch_document_data(items)
    preload_content_tree(items)
    issues = items.select(&:issue?).map(&:content) + items.select(&:pull_request?).map { |item| item.content&.issue }
    GitHub::PrefillAssociations.prefill_associations(issues.compact, :labels)
  end

  sig do
    override
      .params(item: MemexProjectItem)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::LabelsValue)
  end
  def elasticsearch_document(item)
    content_type = Elastomer::Interfaces::Document::MemexProjectItem::ContentType.deserialize(T.must(item.content_type))

    case content_type
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::Issue,
        Elastomer::Interfaces::Document::MemexProjectItem::ContentType::PullRequest
      item.content.labels.sort_by(&:id).map do |l|
        Elastomer::Interfaces::Document::Label.new(
          id: l.id,
          name: l.name,
          repository_id: l.repository_id
        )
      end
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::DraftIssue
      nil
    else
      T.absurd(content_type)
    end
  end

  sig do
    override
      .params(context: Elastomer::Interfaces::Document::MemexProjectItem::SeedContext)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::LabelsValue)
  end
  def seed_elasticsearch_document(context)
    content_type = context.content_type

    case content_type
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::Issue,
        Elastomer::Interfaces::Document::MemexProjectItem::ContentType::PullRequest
      Array(context.labels.sample(context.num_multi_select_values)).sort_by(&:name).map do |label|
        Elastomer::Interfaces::Document::Label.new(
          id: label.id,
          name: label.name,
          repository_id: label.repository_id
        )
      end
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::DraftIssue
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
      sort_by: "field_values.#{self.class.value_name}.name.keyword",
    )
  end

  sig { override.returns(String) }
  def group_by_value_path
    "field_values.#{self.class.value_name}.name.keyword"
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
      .returns(T::Hash[Integer, T.all(Label, Interface::Groupable::Metadata)])
  end
  def preload_group_metadata_objects(metadata_object_ids)
    Label.where(id: metadata_object_ids).index_by(&:id)
  end
  alias_method :preload_slice_metadata_objects, :preload_group_metadata_objects

  sig { override.returns(Symbol) }
  def query_slug
    :label
  end

  sig do
    override
      .params(
        values: T::Array[String],
        is_negated: T::Boolean,
        context: Search::Memex::Context
      )
      .returns(T::Hash[T.untyped, T.untyped])
  end
  def query_fragment(values:, is_negated:, context:)
    should_clauses = values.map do |value|
      {
        nested: {
          path: "field_values",
          query: if value.include?("*")
                   WildcardQuery.new(
                     field_path: "field_values.#{self.class.value_name}.name.keyword",
                     value: WildcardQuery::Value.new(value),
                     case_insensitive: true
                   ).to_hash
                 else
                   TermQuery.new(
                     field_path: "field_values.#{self.class.value_name}.name.keyword",
                     value:,
                     case_insensitive: true
                   ).to_hash
                 end
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
          exists: {
            field: "field_values.#{self.class.value_name}.name"
          }
        }
      }
    }
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
  private def update_mysql_field_value(item:, new_value:, actor:, suppress_hydro_events:)
    unless item.issue_for_content
      return Interface::Writeable::PartialResult.failure("Content issue not found")
    end

    labels = if new_value.present?
      Label.where(id: new_value, repository_id: item.issue_for_content.repository_id).to_a
    else
      []
    end

    if item.issue_for_content.replace_labels(labels)
      total_label_ids = new_value&.count || 0
      if item.issue_for_content.label_ids.count == total_label_ids
        return Interface::Writeable::PartialResult.success
      end
      msg = "Not all labels could be found"
    else
      msg = item.issue_for_content.errors.full_messages.to_sentence
    end
    Interface::Writeable::PartialResult.failure(msg)
  end
end
