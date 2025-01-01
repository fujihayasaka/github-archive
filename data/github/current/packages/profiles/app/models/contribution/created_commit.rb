# typed: true
# frozen_string_literal: true

class Contribution::CreatedCommit < Contribution
  extend Scientist

  BATCH_SIZE = 100
  REPOSITORY_LIMIT = 5000
  LIGHTWEIGHT_ATTRIBUTE_SELECT_LIST = [
    :commit_count,
    :committed_date,
    :id,
    :user_id,
    :repository_id,
  ].freeze

  def commit_contribution
    subject
  end

  def commit_count
    commit_contribution.commit_count
  end

  def repository
    commit_contribution.repository
  end

  def organization_id
    repository.try(:organization_id)
  end

  # Public: Returns the Date the commit contribution was counted.
  def occurred_at
    commit_contribution.committed_date
  end

  def associated_subject
    repository
  end

  def repository_id
    commit_contribution.repository_id
  end

  def contributions_count
    commit_contribution.commit_count
  end

  def id
    commit_contribution.id
  end

  def platform_type_name
    "CreatedCommitContribution"
  end

  def self.subjects_for(
    user,
    date_range:,
    organization_id: nil,
    excluded_organization_ids: [],
    lightweight: false
  )
    Contribution.measure("created_commit_subjects_for", tags: ["lightweight:#{lightweight}", "using_contribution_fetchers:false"]) do
      ::Collab::Responses::Array.new do
        # Build up a scope that we can use for this date range
        contributions_scope = contributions_scope_for(user, date_range: date_range)

        valid_repository_ids = valid_repo_ids(
          user: user,
          contributions: contributions_scope,
          organization_id: organization_id,
        )

        # Preload the associated repositories
        contributions_scope = contributions_scope.includes(:repository)

        if lightweight
          contributions_scope = contributions_scope.reselect(LIGHTWEIGHT_ATTRIBUTE_SELECT_LIST)
        end

        commit_contributions = valid_repository_ids.each_slice(BATCH_SIZE).with_object([]) do |repo_ids, list|
          contribs = science("contribution_summaries_created_commit_subjects_for") do |e|
            e.use { contributions_scope.where(repository_id: repo_ids).load }
            e.try { CommitContributionSummary.commit_contributions_for(date_range: date_range, user: user, repositories: repo_ids) }

            e.compare do |control, candidate|
              control_data = control.map do |cc|
                {
                  user_id: cc.user_id,
                  repository_id: cc.repository_id,
                  committed_date: cc.committed_date,
                  commit_count: cc.commit_count
                }
              end.sort_by { |cc| [cc[:user_id], cc[:repository_id], cc[:committed_date], cc[:commit_count]] }
              candidate_data = candidate.map do |cc|
                {
                  user_id: cc.user_id,
                  repository_id: cc.repository_id,
                  committed_date: cc.committed_date,
                  commit_count: cc.commit_count
                }
              end.sort_by { |cc| [cc[:user_id], cc[:repository_id], cc[:committed_date], cc[:commit_count]] }

              control_data == candidate_data
            end

            e.clean do |value|
              value.map do |cc|
                {
                  user_id: cc.user_id,
                  repository_id: cc.repository_id,
                  committed_date: cc.committed_date,
                  commit_count: cc.commit_count
                }
              end.sort_by { |cc| [cc[:user_id], cc[:repository_id], cc[:committed_date], cc[:commit_count]] }
            end

            # Only run if all the repos in the slice have been summarized
            e.run_if do
              summarized_repo_ids = CommitContributionSummary.for_user(user).for_repository(repo_ids).distinct.pluck(:repository_id)
              summarized_repo_ids.sort == repo_ids.sort
            end
          end

          if excluded_organization_ids.any?
            contribs = contribs.reject do |contribution|
              excluded_organization_ids.include?(contribution.repository.organization_id)
            end
          end
          list.concat(contribs)
        end

        # Flag as large scale contributor if over limit
        check_large_scale_contributor(user, commit_contributions.size)

        commit_contributions
      end
    end
  end

  # Private: Get a CommitContribution scope for the given user in the specified date range.
  def self.contributions_scope_for(user, date_range:)
    contributions_scope = user.commit_contributions.where(committed_date: date_range)

    # Ignore the unique index to force the optimizer to use another, better index for large scale
    # contributors
    if user.large_scale_contributor?
      index_to_ignore = "commit_contrib_user_repo_date"
      contributions_scope = contributions_scope.
        from("`#{CommitContribution.table_name}` IGNORE INDEX (#{index_to_ignore})")
    end

    contributions_scope
  end
  private_class_method :contributions_scope_for

  # Private: Returns IDs of all repositories the user committed to in the given date range, filtered
  # based on the given organization ID and if the user is a large-scale contributor or not.
  #
  # If users have a lot of contributions, only count public repos they own directly in their
  # totals. Note: when filtering by organization, this will be empty for such users.
  #
  # Returns an Array of valid Repository IDs (integers).
  def self.valid_repo_ids(user:, contributions:, organization_id:)
    if user.large_scale_contributor?
      return CommitContribution.none if organization_id

      user.repositories.public_scope.pluck(:id)
    else
      valid_ids = valid_repo_ids_from_contributions(user, contributions)

      if organization_id
        org_repo_ids = Repository.where(organization_id: organization_id).pluck(:id)
        valid_ids = valid_ids & org_repo_ids
      end

      valid_ids
    end
  end
  private_class_method :valid_repo_ids

  # Private: Returns IDs of all repositories the user committed to in the given
  # date range.
  #
  # Returns an Array of valid repository ids
  def self.valid_repo_ids_from_contributions(user, contributions)
    repository_ids = contributions.distinct.limit(REPOSITORY_LIMIT).pluck(:repository_id)

    validator = CommitContribution::RepositoryValidator.new(user, repository_ids: repository_ids)
    validator.valid_repository_ids
  end
  private_class_method :valid_repo_ids_from_contributions

  # Private: If the user has a large number of contributions, flag them as a large scale contributor.
  def self.check_large_scale_contributor(user, contribution_count)
    return if user.large_scale_contributor?

    if contribution_count > CommitContribution::LARGE_SCALE_CONTRIBUTOR_LIMIT
      ActiveRecord::Base.connected_to(role: :writing) do
        user.flag_as_large_scale_contributor!
      end
    end
  end
  private_class_method :check_large_scale_contributor
end
