# typed: true
# frozen_string_literal: true

class Contribution::AnsweredDiscussion < Contribution
  LIGHTWEIGHT_ATTRIBUTE_SELECT_LIST = [
    :comment_id,
    :created_at,
    :discussion_id,
    :id,
    :repository_id,
  ].freeze

  delegate :repository, :discussion, :comment, :hash, :async_repository,
    :repository_id, to: :discussion_event
  delegate :title, :number, :comment_count, :state, :state_reason, to: :discussion

  sig { returns(T.untyped) }
  def discussion_event
    subject
  end

  sig { returns(T.untyped) }
  def comment_id
    comment.id
  end

  sig { returns(T.untyped) }
  def associated_subject
    discussion_event.repository
  end

  sig { returns(T.untyped) }
  def organization_id
    associated_subject&.organization_id
  end

  # Public: Returns the discussion event's creation time as a Time.
  sig { returns(T.untyped) }
  def occurred_at
    discussion_event.created_at
  end

  sig { params(other_contribution: T.untyped).returns(T.untyped) }
  def eql?(other_contribution)
    other_contribution.respond_to?(:discussion_event) &&
      discussion_event == other_contribution.discussion_event
  end

  sig do
    params(
      user: T.untyped,
      date_range: T.untyped,
      organization_id: T.untyped,
      excluded_organization_ids: T.untyped,
      lightweight: T.untyped
    ).returns(T.untyped)
  end
  def self.subjects_for(
    user,
    date_range:,
    organization_id: nil,
    excluded_organization_ids: [],
    lightweight: false
  )
    Contribution.measure(
      "answered_discussion_subjects_for",
      tags: ["lightweight:#{lightweight}"],
    ) do
      contribs = DiscussionEvent.for_comment_authored_by(user).still_marked_as_answer.
        where(created_at: date_range_to_time_range(date_range))

      if organization_id
        contrib_repo_ids = contribs.joins(:discussion).distinct.pluck("discussions.repository_id")
        contribs = contribs.for_organization(organization_id, only_repo_ids: contrib_repo_ids)
      end

      if lightweight
        contribs = contribs.reselect(LIGHTWEIGHT_ATTRIBUTE_SELECT_LIST)
      end

      contribs = contribs
        .includes(:repository)
        .preload(:comment, discussion: [:category, :chosen_comment])
        .limit(Contribution::DEFAULT_COUNT_LIMIT)
        .to_a

      if excluded_organization_ids.any?
        contribs = contribs.reject do |event|
          next true unless event.repository
          excluded_organization_ids.include?(T.must(event.repository).organization_id)
        end
      end

      contribs
    end
  end
end
