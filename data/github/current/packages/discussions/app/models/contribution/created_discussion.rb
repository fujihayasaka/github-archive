# typed: true
# frozen_string_literal: true

class Contribution::CreatedDiscussion < Contribution
  LIGHTWEIGHT_ATTRIBUTE_SELECT_LIST = [
    :chosen_comment_id,
    :created_at,
    :discussion_category_id,
    :id,
    :number,
    :repository_id,
    :title,
    :state,
    :state_reason,
  ].freeze

  delegate :repository, :repository_id, :comment_count, :title, :number,
    :async_repository, :hash, to: :discussion

  sig { returns(T.untyped) }
  def discussion
    subject
  end

  sig { returns(T.untyped) }
  def discussion_id
    subject.id
  end

  sig { returns(T.untyped) }
  def associated_subject
    discussion.repository
  end

  sig { returns(T.untyped) }
  def organization_id
    associated_subject.try(:organization_id)
  end

  # Public: Returns the discussion's creation time as a Time.
  sig { returns(T.untyped) }
  def occurred_at
    discussion.created_at
  end

  sig { params(other_contribution: T.untyped).returns(T.untyped) }
  def eql?(other_contribution)
    other_contribution.respond_to?(:discussion) && discussion == other_contribution.discussion
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
    Contribution.measure("created_discussion_subjects_for", tags: ["lightweight:#{lightweight}"]) do
      contribs = user.discussions.where(created_at: date_range_to_time_range(date_range))

      if organization_id
        contrib_repo_ids = contribs.select(:repository_id).distinct.pluck(:repository_id)
        contribs = contribs.for_organization(organization_id, only_repo_ids: contrib_repo_ids)
      end

      contribs = contribs.includes(:repository).limit(Contribution::DEFAULT_COUNT_LIMIT)

      if lightweight
        contribs = contribs.reselect(LIGHTWEIGHT_ATTRIBUTE_SELECT_LIST)
      end

      contribs = contribs.to_a

      if excluded_organization_ids.any?
        contribs = contribs.select do |discussion|
          !excluded_organization_ids.include?(discussion.repository&.organization_id)
        end
      end

      contribs
    end
  end
end
