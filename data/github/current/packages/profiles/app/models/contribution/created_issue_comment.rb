# typed: true
# frozen_string_literal: true

class Contribution::CreatedIssueComment < Contribution
  LIGHTWEIGHT_ATTRIBUTE_SELECT_LIST = [
    :created_at,
    :id,
    :repository_id,
  ].freeze

  delegate :repository, :repository_id, to: :comment

  def associated_subject
    comment.repository
  end

  def occurred_at
    comment.created_at
  end

  def comment
    subject
  end

  def self.subjects_for(
    user,
    date_range:,
    organization_id: nil,
    excluded_organization_ids: [],
    lightweight: false
  )
    Contribution.measure(
      "created_issue_comment_subjects_for",
      tags: ["lightweight:#{lightweight}"],
    ) do
      ::Collab::Responses::Array.new do
        ActiveRecord::Base.connected_to(role: :reading) do
          return [] if user.spammy?
          filter_by_organization = organization_id.present? || excluded_organization_ids.any?

          scope = user.issue_comments

          if lightweight
            scope = scope.reselect(LIGHTWEIGHT_ATTRIBUTE_SELECT_LIST)
          end

          scope = scope.
            where(created_at: date_range_to_time_range(date_range)).
            preload(:repository).
            limit(Contribution::DEFAULT_COUNT_LIMIT)

          if filter_by_organization
            repo_ids_scope = Repository.where(id: scope.select(:repository_id).distinct.pluck(:repository_id))
            repo_ids_scope = repo_ids_scope.where(organization_id: organization_id) if organization_id
            repo_ids_scope = repo_ids_scope.where.not(organization_id: excluded_organization_ids) if excluded_organization_ids.any?
            repo_ids = repo_ids_scope.pluck(:id)
            scope = scope.where(repository_id: repo_ids)
          end

          scope.to_a
        end
      end
    end
  end
end
