# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Reviewers < MemexProjectColumn::Field
  extend T::Sig
  include SpecialFieldHelpers

  TermQuery = Elastomer::Interfaces::Api::Search::Request::TermQuery
  WildcardQuery = Elastomer::Interfaces::Api::Search::Request::WildcardQuery

  sig { override.returns(T::Array[String]) }
  def self.register_processors
    [
      "MemexProjectColumn::Indexable::Processor::ReviewersChange",
      "MemexProjectColumn::Indexable::Processor::TeamRename",
      "MemexProjectColumn::Indexable::Processor::UserDestroy",
    ]
  end

  sig { override.returns(Elastomer::Interfaces::Mapping::FieldDataType) }
  def self.elasticsearch_mapping
    Elastomer::Interfaces::Mapping::FieldDataTypes::Object.new(properties: {
      actor_id: Elastomer::Interfaces::Mapping::FieldDataTypes::Long.new,
      actor_slug: Elastomer::Interfaces::Mapping::FieldDataTypes::KeywordMultiField.new(copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS),
      actor_type: Elastomer::Interfaces::Mapping::FieldDataTypes::KeywordMultiField.new,
    })
  end

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_elasticsearch_document_data(items)
    preload_content_tree(items)

    pulls = items.select(&:pull_request?).map(&:content)
    GitHub::PrefillAssociations.prefill_associations(pulls, [:review_requests, :reviews])

    review_requests = pulls.flat_map(&:review_requests).compact
    GitHub::PrefillAssociations.prefill_associations(review_requests, :reviewer)

    reviews = pulls.flat_map(&:reviews).compact
    GitHub::PrefillAssociations.prefill_associations(reviews, :user)
  end

  sig do
    override
      .params(item: MemexProjectItem)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::ReviewersValue)
  end
  def elasticsearch_document(item)
    return [] unless item.pull_request?
    request_names = item.content.review_requests.map do |r|
      if r.reviewer_type == "Team"
        {
          actor_id: r.reviewer_id,
          actor_slug: r.reviewer&.name,
          actor_type: "Team"
        }
      else
        {
          actor_id: r.reviewer_id,
          actor_slug: r.reviewer&.display_login,
          actor_type: "User"
        }
      end
    end

    review_names = item.content.reviews.map do |r|
      {
        actor_id: r.user_id,
        actor_slug: r.user&.display_login,
        actor_type: "User"
      }
    end

    (request_names + review_names).uniq
      .sort_by { [_1[:actor_id], _1[:actor_type]] }
      .map { Elastomer::Interfaces::Document::Reviewers.new(_1) }
  end

  sig do
    override
      .params(context: Elastomer::Interfaces::Document::MemexProjectItem::SeedContext)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::ReviewersValue)
  end
  def seed_elasticsearch_document(context)
    Array(context.users.sample(context.num_multi_select_values)).sort_by { |u| T.must(u.id) }.map do |u|
      Elastomer::Interfaces::Document::Reviewers.new(
        actor_id: u.id,
        actor_slug: u.display_login,
        actor_type: "User"
      )
    end
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
      login = value == "@me" ? context.viewer&.display_login : value
      next nil unless login.present?

      {
        nested: {
          path: "field_values",
          query: if login.include?("*")
                   WildcardQuery.new(
                     field_path: "field_values.#{self.class.value_name}.actor_slug.keyword",
                     value: WildcardQuery::Value.new(login),
                     case_insensitive: true
                   ).to_hash
                 else
                   TermQuery.new(
                     field_path: "field_values.#{self.class.value_name}.actor_slug.keyword",
                     value: login,
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
            field: "field_values.#{self.class.value_name}.actor_slug"
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
      sort_by: "field_values.#{self.class.value_name}.actor_slug.keyword",
    )
  end
end
