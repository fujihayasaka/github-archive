# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::Reviewers < MemexProjectColumn::Field::Base
  include Interface::SpecialTypeSerializable
  include MemexProjectColumn::Helper::Macro

  sig { override.returns(T::Array[String]) }
  def self.register_processors
    [
      "MemexProjectColumn::Interface::Indexable::Processor::ReviewersChange",
      "MemexProjectColumn::Interface::Indexable::Processor::TeamRename",
      "MemexProjectColumn::Interface::Indexable::Processor::UserDestroy",
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

    pulls = T.cast(items.select(&:pull_request?).map(&:content).compact, T::Array[PullRequest])
    GitHub::PrefillAssociations.prefill_associations(pulls, :review_requests)

    review_requests = pulls.flat_map(&:review_requests).compact
    GitHub::PrefillAssociations.prefill_associations(review_requests, [:reviewer, :pull_request_reviews])

    # PullRequestReviews have the potential to contain large `body` columns which could exceed the MySQL size limit
    # when returning results. Since we don't need the body column for the Elasticsearch document, we can selectively
    # query for the columns we need. +GitHub::PrefillAssociations.prefill_associations+ does not support providing
    # available records for a +has_many+ association so we need to manually populate the associated records.
    #
    # See https://github.com/github/projects-platform/issues/2412 for more details.
    pull_request_reviews = PullRequestReview.select(:id, :pull_request_id, :state, :user_id).where(pull_request: pulls).to_a
    GitHub::PrefillAssociations.prefill_associations(pull_request_reviews, :user)
    grouped_pull_request_reviews = pull_request_reviews.group_by(&:pull_request_id)
    pulls.each do |pull|
      pull.association(:reviews).target = grouped_pull_request_reviews.fetch(pull.id, [])
    end
  end

  sig do
    override
      .params(item: MemexProjectItem)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::ReviewersValue)
  end
  def elasticsearch_document(item)
    content_type = Elastomer::Interfaces::Document::MemexProjectItem::ContentType.deserialize(item.content_type)

    case content_type
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::PullRequest
      pull_request = T.cast(item.content, PullRequest)
      request_names = pull_request.review_requests
        .select { !_1.deferred? && !_1.dismissed? && _1.reviewer.present? && _1.pending? }
        .map do |r|
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

      review_names = pull_request.reviews
        .select { |r| r.state != PullRequestReview.state_value(:pending) }
        .map do |r|
          {
            actor_id: r.user_id,
            actor_slug: r.user&.display_login,
            actor_type: "User"
          }
        end

      (request_names + review_names).uniq
        .sort_by { [_1[:actor_id], _1[:actor_type]] }
        .map { Elastomer::Interfaces::Document::Reviewers.new(_1) }
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::Issue,
      Elastomer::Interfaces::Document::MemexProjectItem::ContentType::DraftIssue
      []
    else
      T.absurd(content_type)
    end
  end

  sig do
    override
      .params(context: Elastomer::Interfaces::Document::MemexProjectItem::SeedContext)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::ReviewersValue)
  end
  def seed_elasticsearch_document(context)
    Array(context.users.sample(context.num_multi_select_values)).sort_by { |u| u.id }.map do |u|
      Elastomer::Interfaces::Document::Reviewers.new(
        actor_id: u.id,
        actor_slug: u.display_login,
        actor_type: "User"
      )
    end
  end

  sig do
    override.
      params(
        item: MemexProjectItem,
        prefilled_associations: T.nilable(MemexProjectItem::PrefilledAssociations),
        redacted_issue_ids: T::Array[Integer],
      ).
      returns(T.nilable(T::Array[MemexProjectColumn::Interface::Serializable]))
  end
  def serializable(item, prefilled_associations: nil, redacted_issue_ids: [])
    content_type = Elastomer::Interfaces::Document::MemexProjectItem::ContentType.deserialize(item.content_type)

    case content_type
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::PullRequest
      reviewers = if prefilled_associations
        prefilled_associations.reviewers(item)
      else
        pull_request = T.cast(item.content, PullRequest)
        pull_request.memex_pull_request_reviewers
      end
      return if reviewers.nil?

      reviewers.collect { MemexProjectItem::Reviewer.new(_1) }
    when Elastomer::Interfaces::Document::MemexProjectItem::ContentType::Issue,
      Elastomer::Interfaces::Document::MemexProjectItem::ContentType::DraftIssue
      nil
    else
      T.absurd(content_type)
    end
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

  sig { override.returns(String) }
  def query_by_value_path
    "field_values.#{self.class.value_name}.actor_slug.lowercased_keyword"
  end

  sig do
    override
      .params(
        value: String,
        context: Search::Memex::Context
      )
      .returns(T.nilable(T::Hash[T.untyped, T.untyped]))
  end
  def query_strategy(value:, context:)
    super(value: resolve_me_macro(value:, context:), context:)
  end

  # Returns a value that can be used to sort a MemexProjectItem by a given field.
  #
  # When querying for project items outside of ElasticSearch, this method returns the sortable value
  # for a field to regenerate the same sort order as ElasticSearch. The output for these methods should match
  # what ElasticSearch returns for the sorting order. Depending on the data type and direction, fields could
  # return the max or minimum 64-bit signed integer, a String, or a representation for Infinity.
  #
  # direction   - The direction to sort by, either :asc or :desc.
  # column_data - The data for the column to be sorted, this is JSON data stored in the column record, after
  #               extracting more specific information using the column data type to query through
  #               the MemexProjectItem::ColumnDependency::COLUMN_VALUE_KEYS Hash.
  #
  sig { override.params(direction: Symbol, column_data: T.untyped).returns(T.untyped) }
  def graphql_sortable_column_value(direction:, column_data:)
    column_data
  end
end
