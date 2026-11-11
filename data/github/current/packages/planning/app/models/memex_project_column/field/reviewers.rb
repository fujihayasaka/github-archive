# typed: strict
# frozen_string_literal: true

class MemexProjectColumn::Field::Reviewers < MemexProjectColumn::Field::Base
  include Interface::SpecialTypeSerializable
  include MemexProjectColumn::Helper::Macro
  include MemexProjectColumnValue::ReviewerHashable

  sig { override.returns(T::Array[MemexProjectItem::ContentType]) }
  def self.supported_content_types = [MemexProjectItem::ContentType::PullRequest]

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
    pull_request_reviews = PullRequestReview
      .select(:id, :pull_request_id, :state, :user_id, :submitted_at)
      .where(pull_request: pulls)
      .to_a

    GitHub::PrefillAssociations.prefill_associations(pull_request_reviews, :user)
    GitHub::PrefillAssociations.prefill_associations(pull_request_reviews, :pull_request, available_records: pulls)

    grouped_pull_request_reviews = pull_request_reviews.group_by(&:pull_request_id)
    pulls.each do |pull|
      pull.association(:reviews).target = grouped_pull_request_reviews.fetch(pull.id, [])
    end
  end

  sig { override.params(items: T::Array[MemexProjectItem]).void }
  def preload_rest_api_response_data(items)
    supported_items = items.select(&:pull_request?)

    pulls = T.cast(supported_items.map(&:content).compact, T::Array[PullRequest])
    GitHub::PrefillAssociations.prefill_associations(pulls, :review_requests)

    review_requests = pulls.flat_map(&:review_requests).compact
    GitHub::PrefillAssociations.prefill_associations(review_requests, [:reviewer, :pull_request_reviews])

    pull_request_reviews = PullRequestReview.select(:id, :pull_request_id, :state, :user_id, :submitted_at).where(pull_request: pulls).to_a
    GitHub::PrefillAssociations.prefill_associations(pull_request_reviews, [:user, :pull_request], available_records: pulls)

    requested_reviewer_teams = review_requests.map(&:reviewer).grep(Team)
    GitHub::PrefillAssociations.prefill_associations(requested_reviewer_teams, :organization)

    grouped_pull_request_reviews = pull_request_reviews.group_by(&:pull_request_id)

    pulls.each do |pull|
      pull.association(:reviews).target = grouped_pull_request_reviews.fetch(pull.id, [])
    end
  end

  sig { override.returns(T::Boolean) }
  def self.should_preload_content_tree? = true

  sig do
    override
      .params(items: T::Array[MemexProjectItem], fields: T::Array[MemexProjectColumn::Field::Base])
      .returns(T.nilable(T::Hash[Integer, T.untyped]))
  end
  private def preload_web_api_response_data(items:, fields:)
    pull_requests = items.select(&:pull_request?).map(&:content).compact

    # Find all pending review requests, excluding those that:
    #   - are deferred
    #   - have been dismissed
    #   - have a missing reviewer, i.e. deleted team
    pending_requests = ReviewRequest
      .includes({ reviewer: :organization }, :pull_request_reviews)
      .where(pull_request_id: pull_requests.map(&:id))
      .select { |request| should_include_request?(request) }

    # Ensure pending review requests are:
    #   - grouped by pull request
    #   - sorted by ID, in descending order
    #   - unique per reviewer
    pending_requests_by_pull_request_id = pending_requests
      .group_by(&:pull_request_id)
      .transform_values! do |requests|
        requests
          .sort_by(&:id)
          .reverse
          .uniq { |request| request.reviewer_id }
      end

    # Find all submitted reviews, excluding those with a reviewer that:
    #   - have a pending request for the same pull request
    #   - opened the pull request
    #   - is a ghost user, i.e. deleted user
    submitted_reviews = PullRequestReview
      .includes(:user)
      .submitted
      .where(pull_request_id: pull_requests.map(&:id))
      .all
      .to_a

    GitHub::PrefillAssociations.prefill_associations(
      submitted_reviews,
      :pull_request,
      available_records: pull_requests
    )

    submitted_reviews.select! { |review| should_include_review?(review, pending_requests_by_pull_request_id) }

    # Ensure submitted reviews are:
    #   - grouped by pull request
    #   - sorted by ID, in descending order
    #   - unique per reviewer
    submitted_review_by_pull_request_id = submitted_reviews
      .group_by(&:pull_request_id)
      .transform_values! do |reviews|
        reviews
          .sort_by(&:id)
          .reverse
          .uniq { |review| review.safe_user.id }
      end

    # For each pull request, build a 'partitioned' collection of submitted reviews
    # and pending pull requests that can be used for serialization.
    #
    # Example:
    #
    # {
    #   123456:
    #     {
    #       submitted: [<PullRequestReview>]
    #       pending: [<ReviewRequest>]
    #     }
    # }
    items.each_with_object({}) do |item, result|
      next unless item.pull_request?

      result[item.id] = {
        submitted: submitted_review_by_pull_request_id.fetch(item.content_id, []),
        pending: pending_requests_by_pull_request_id.fetch(item.content_id, [])
      }
    end
  end

  # reviews should be included when:
  #   - the review is not for the user's own pull request
  #   - the review is from a non-ghost user, i.e. deleted user
  #   - there are no pending review requests from the user
  sig do
    params(
      submitted_review: PullRequestReview,
      pending_requests: T::Hash[Integer, T::Array[ReviewRequest]]
    ).returns(T::Boolean)
  end
  private def should_include_review?(submitted_review, pending_requests)
    # Check if the review is for the user's own pull request
    return false if submitted_review.safe_user.id == T.must(submitted_review.pull_request).user_id

    # Check if the review is from a ghost user (deleted user)
    return false if submitted_review.safe_user.ghost?

    # Check if there are any pending review requests for this PR from the user
    pending_requests_for_pull = pending_requests[submitted_review.pull_request_id] || []
    has_pending_request = pending_requests_for_pull.any? { |req| req.reviewer_id == submitted_review.safe_user.id }

    !has_pending_request
  end

  # requests should be included when the request:
  #   - is pending
  #   - is not deferred
  #   - has not been dismissed
  #   - the reviewer exists, i.e. not a deleted team
  sig { params(request: ReviewRequest).returns(T::Boolean) }
  private def should_include_request?(request)
    return false unless request.pending?
    return false if request.deferred?
    return false if request.dismissed?

    # Check if the reviewer exists (deleted teams)
    return false if request.reviewer.blank?

    true
  end

  sig do
    override
      .params(item: MemexProjectItem)
      .returns(Elastomer::Interfaces::Document::MemexProjectItem::ReviewersValue)
  end
  def elasticsearch_document(item)
    content_type = MemexProjectItem::ContentType.deserialize(item.content_type)

    case content_type
    when MemexProjectItem::ContentType::PullRequest
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
    when MemexProjectItem::ContentType::Issue,
      MemexProjectItem::ContentType::DraftIssue
      []
    else
      T.absurd(content_type)
    end
  end

  SerializableReviewers = T.type_alias { { submitted: T::Array[PullRequestReview], pending: T::Array[ReviewRequest] } }

  sig do
    override.
      params(
        item: MemexProjectItem,
        prefilled_associations: T.nilable(MemexProjectItem::PrefilledAssociations),
        redacted_issue_ids: T::Array[Integer],
      ).returns(T.nilable(SerializableReviewers))
  end
  def serializable(item, prefilled_associations: nil, redacted_issue_ids: [])
    content_type = MemexProjectItem::ContentType.deserialize(item.content_type)

    case content_type
    when MemexProjectItem::ContentType::PullRequest
      reviewers = if prefilled_associations
        prefilled_associations.reviewers(item)
      elsif preloaded_web_api_response_data?
        preloaded_web_api_response_data[item.id]
      else
        pull_request = T.cast(item.content, PullRequest)
        partition_reviewers(pull_request)
      end
    when MemexProjectItem::ContentType::Issue,
      MemexProjectItem::ContentType::DraftIssue
      nil
    else
      T.absurd(content_type)
    end

    # Although the return type of `prefilled_associations.reviewers(item)` is typed correctly,
    # Sorbet thinks this is of type Hash::[T.untyped, T.untyped] for some reason.
    T.cast(reviewers, T.nilable(SerializableReviewers))
  end

  sig do
    override.
      params(
        item: MemexProjectItem,
        prefilled_associations: T.nilable(MemexProjectItem::PrefilledAssociations),
        redacted_issue_ids: T::Array[Integer],
      ).
      returns(T.nilable(T::Array[MemexProjectColumnValue::SerializableValue]))
  end
  def value(item, prefilled_associations: nil, redacted_issue_ids: [])
    return unless value = serializable(item, prefilled_associations:, redacted_issue_ids:)

    hashed_pending_reviews = T.cast(value[:pending], T::Array[ReviewRequest]).map do |request|
      review_request_hash(request)
    end

    hashed_submitted_reviews = T.cast(value[:submitted], T::Array[PullRequestReview]).map do |review|
      pull_request_review_hash(review)
    end

    reviewers = hashed_submitted_reviews + hashed_pending_reviews

    reviewers.map do |r|
      MemexProjectColumnValue::Reviewer.new(
        type: r[:type],
        status: r[:status],
        reviewer: r[:reviewer]
      )
    end
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

    # Reviews are requested from users and teams
    pending_teams, pending_users = value[:pending].map(&:reviewer).partition { |r| r.is_a?(Team) }

    # Reviews are submitted by users
    submitted_users = value[:submitted].map(&:safe_user)

    serialized_users = (submitted_users + pending_users).map do |user|
      Api::Serializer.serialize(:simple_user_hash, user)
    end

    serialized_teams = pending_teams.map do |team|
      Api::Serializer.serialize(:team_hash, team, { exclude_parent: true })
    end

    {
      requested_reviewers: serialized_users,
      requested_teams: serialized_teams
    }
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

  sig { params(pull: PullRequest).returns(SerializableReviewers) }
  private def partition_reviewers(pull)
    pending_requests = pull.review_requests
      .select { |request| request.pending? && !request.deferred? && !request.dismissed? }
      .select { |r| r.reviewer.present? }
      .sort_by(&:id)
      .reverse
      .uniq { |request| request.reviewer_id }

    pending_reviewer_ids = Set.new(pending_requests.map(&:reviewer_id))

    submitted_reviews = pull.reviews
      .select(&:submitted?)
      .reject do |review|
        pending_reviewer_ids.include?(review.safe_user.id) ||
        review.safe_user.id == T.must(review.pull_request).user_id ||
        review.safe_user.ghost?
      end
      .sort_by(&:id)
      .reverse
      .uniq { |review| review.safe_user.id }

    {
      submitted: submitted_reviews,
      pending: pending_requests
    }
  end
end
