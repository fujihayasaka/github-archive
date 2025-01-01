# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Assignees < MemexProjectColumn::Field
  extend T::Sig
  include SpecialFieldHelpers

  ME_MACRO = "@me"

  TermQuery = Elastomer::Interfaces::Api::Search::Request::TermQuery
  WildcardQuery = Elastomer::Interfaces::Api::Search::Request::WildcardQuery

  sig { override.returns(T::Array[String]) }
  def self.register_processors
    [
      "MemexProjectColumn::Indexable::Processor::IssueUpdateAssignee",
      "MemexProjectColumn::Indexable::Processor::AccountRename",
      "MemexProjectColumn::Indexable::Processor::UserDestroy",
    ]
  end

  sig { override.returns(Elastomer::Interfaces::Mapping::FieldDataType) }
  def self.elasticsearch_mapping
    Elastomer::Interfaces::Mapping::FieldDataTypes::Object.new(properties: {
      id: Elastomer::Interfaces::Mapping::FieldDataTypes::Long.new,
      login: Elastomer::Interfaces::Mapping::FieldDataTypes::KeywordMultiField.new(copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS)
    })
  end

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_elasticsearch_document_data(items)
    preload_content_tree(items)

    normal_issues = items.select(&:issue?).map { |item| item.content }.compact
    pull_request_issues = items.select(&:pull_request?).map { |item| item.content&.issue }.compact
    draft_issues = items.select(&:draft_issue?).map(&:content)

    GitHub::PrefillAssociations.prefill_associations(normal_issues + pull_request_issues, :assignees)
    GitHub::PrefillAssociations.prefill_associations(draft_issues, :assignees)
  end

  sig do
    override
      .params(item: MemexProjectItem)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::AssigneesValue)
  end
  def elasticsearch_document(item)
    content_type = Elastomer::Interfaces::Document::MemexProjectItem::ContentType.deserialize(T.must(item.content_type))

    case content_type
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::Issue,
        Elastomer::Interfaces::Document::MemexProjectItem::ContentType::DraftIssue,
        Elastomer::Interfaces::Document::MemexProjectItem::ContentType::PullRequest
      item.content.assignees.sort_by(&:id).map do |assignee|
        Elastomer::Interfaces::Document::Assignee.new(
          id: assignee.id,
          display_login: assignee.display_login
        )
      end
    else
      T.absurd(content_type)
    end
  end

  sig do
    override
      .params(context: Elastomer::Interfaces::Document::MemexProjectItem::SeedContext)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::AssigneesValue)
  end
  def seed_elasticsearch_document(context)
    content_type = context.content_type

    case content_type
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::Issue,
        Elastomer::Interfaces::Document::MemexProjectItem::ContentType::DraftIssue,
        Elastomer::Interfaces::Document::MemexProjectItem::ContentType::PullRequest
      users = Array(context.users.sample(context.num_multi_select_values)).sort_by do |user|
        T.must(user.id)
      end
      users.map do |assignee|
        Elastomer::Interfaces::Document::Assignee.new(
          id: assignee.id,
          display_login: assignee.display_login
        )
      end
    else
      T.absurd(content_type)
    end
  end

  sig { override.returns(Symbol) }
  def query_slug
    :assignee
  end

  sig { returns(String) }
  private def field_path
    "field_values.#{self.class.value_name}.login.keyword"
  end

  sig do
    override
      .params(values: T::Array[String], is_negated: T::Boolean, context: Search::Memex::Context)
      .returns(T::Hash[T.untyped, T.untyped])
  end
  def query_fragment(values:, is_negated:, context:)
    should_clauses = values.map do |value|
      login = value == ME_MACRO ? context.viewer&.display_login : value
      next nil unless login.present?

      {
        nested: {
          path: "field_values",
          query: if login.include?("*")
                   WildcardQuery.new(field_path:, value: WildcardQuery::Value.new(login), case_insensitive: true).to_hash
                 else
                   TermQuery.new(field_path:, value: login, case_insensitive: true).to_hash
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
            field: "field_values.#{self.class.value_name}.login"
          }
        }
      }
    }
  end


  sig do
    override
      .params(direction: String)
      .returns(T::Hash[T.untyped, T.untyped])
  end
  def sort_fragment(direction:)
    build_version_compatible_sort_fragment(
      direction: direction,
      sort_by: "field_values.#{self.class.value_name}.login.keyword",
    )
  end

  sig { override.returns(String) }
  def group_by_value_path
    "field_values.#{self.class.value_name}.login.keyword"
  end
  alias_method :slice_by_value_path, :group_by_value_path

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
      .returns(T::Hash[Integer, T.all(User, Groupable::Metadata)])
  end
  def preload_group_metadata_objects(metadata_object_ids)
    User.where(id: metadata_object_ids).index_by(&:id)
  end
  alias_method :preload_slice_metadata_objects, :preload_group_metadata_objects


  sig { override.params(group_by_value: T.nilable(String)).returns(T.nilable(T::Array[String])) }
  def graphql_value(group_by_value)
    # Calling super helps cleanse potential _noValue values
    Array(super(group_by_value)).presence
  end
end
