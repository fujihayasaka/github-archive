# typed: true
# frozen_string_literal: true

# Public: methods for fetching and checking the existence of pull request contributions created
# by a given user.
#
# Results are always filtered to include only PRs associated with active repositories, and
# may be filtered to include those created within a given date range.
#
# Results may optionally be filtered to include or exclude PRs associated with repositories
# which belong to given organizations.
class Contribution::Fetcher::CreatedPullRequest
  include Contribution::TimezoneFiltering

  attr_reader :user, :date_range, :excluded_organization_ids, :lightweight

  def initialize(user:, date_range:, organization_id:, excluded_organization_ids:, lightweight:)
    @user = user
    @date_range = date_range
    @organization_id = organization_id
    @excluded_organization_ids = excluded_organization_ids
    @lightweight = lightweight
  end

  # Public: returns filtered pull requests created in the given date range.
  #
  # Returns an ActiveRecord::Relation.
  def subjects_in_date_range
    @subjects_in_date_range ||= begin
      Contribution.measure(
        "created_pull_request_subjects_for",
        tags: ["lightweight:#{lightweight}", "using_contribution_fetchers:true"],
      ) do
        scope = scope_with_repo_filters(organization_id: @organization_id).
          where(created_at: buffered_time_range(date_range)).order(:created_at, :id).
          limit(Contribution::DEFAULT_COUNT_LIMIT)

        if lightweight
          scope = scope.reselect(Contribution::CreatedPullRequest::LIGHTWEIGHT_ATTRIBUTE_SELECT_LIST)
        end

        scope.preload(:issue, repository: :owner).to_a # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end
    end
  end

  # Public: returns the first filtered pull request, where pull requests are ordered by
  # created_at, then by ID.
  #
  # Returns a PullRequest or nil.
  def first_subject
    return @first_subject if defined?(@first_subject)

    @first_subject = Contribution.measure(
      "created_pull_request_first_subject_for",
      tags: ["using_contribution_fetchers:true"]
    ) do
      scope_with_repo_filters.
        from("pull_requests FORCE INDEX(index_pull_requests_on_user_id_and_repository_id)").
        order(id: :asc).
        first
    end
  end

  # Public: whether a filtered pull request created prior to the specified subject PR exists,
  # where pull requests are ordered by created_at then by ID.
  #
  # Returns a boolean.
  def any_contribution_before?(subject)
    @contributions_before ||= {}
    return @contributions_before[subject.id] if @contributions_before.key?(subject.id)

    @contributions_before[subject.id] =
      Contribution.measure("created_pull_request_any_subjects_created_before") do
        scope_with_repo_filters.where(
          "created_at < ? OR (created_at = ? AND id < ?)",
          subject.created_at, subject.created_at, subject.id
        ).exists?
      end
  end

  private

  def needs_filtering_by_occurred_at?
    true
  end

  # Private: returns a scope for the user's pull requests that are associated with
  # appropriate repositories.
  #
  # Results are always scoped to include only PRs associated with active repos.
  #
  # When excluded_organization_ids are present, eg. for CAP filtering, results are scoped to
  # include only PRs associated with repos not belonging to excluded_organization_ids.
  #
  # When organization_id is present, results are scoped to include only PRs associated with
  # repos belonging to organization_id.
  #
  # Returns an ActiveRecord::Relation.
  def scope_with_repo_filters(organization_id: nil)
    return active_pull_requests unless org_filtering_required?(organization_id)

    tags = default_stats_tags
    if organization_id.present? && excluded_organization_ids.any?
      tags << "scope:orgs_both"
    elsif organization_id.present?
      tags << "scope:org"
    else
      tags << "scope:excluded_orgs"
    end
    GitHub.dogstats.increment("contribution.fetcher.created_pull_request.query", tags: tags)

    repository_ids = filtered_repository_ids(organization_id: organization_id)
    user.pull_requests.where(repository_id: repository_ids)
  end

  # Private: whether excluded_organization_ids are present, and the user has PRs associated with repos
  # belonging to excluded orgs.
  #
  # Returns a boolean.
  def excluded_repos_exist?
    return @excluded_repos_exist if defined?(@excluded_repos_exist)
    @excluded_repos_exist =
      excluded_organization_ids.any? &&
      Repository.where(id: all_repository_ids).where(organization_id: excluded_organization_ids).exists?
  end

  # Private: returns a scope for the users's pull requests which are not associated with
  # inactive repositories.
  #
  # If there are PRs associated with inactive repos, scope to exclude those PRs.
  #
  # Returns an ActiveRecord::Relation.
  def active_pull_requests
    if deleted_repository_ids.empty?
      GitHub.dogstats.increment("contribution.fetcher.created_pull_request.query", tags: ["scope:all"])
      user.pull_requests
    else
      GitHub.dogstats.increment("contribution.fetcher.created_pull_request.query", tags: ["scope:active"])
      user.pull_requests.where.not(repository_id: deleted_repository_ids)
    end
  end

  # Private: whether org filtering is required - either because we're finding contributions
  # associated with a specific org ID, or because we're excluding contributions associated with
  # one of excluded_org_ids and the contribution owner has PRs associated with excluded orgs.
  #
  # Returns a boolean.
  def org_filtering_required?(organization_id)
    organization_id.present? || excluded_repos_exist?
  end

  # Private: returns a list of repositories IDs which match the filters for active status and
  # optionally for organization association.
  #
  # - organization_id: only include repos with the specified organization ID
  #
  # Returns nil if no repo ID filtering is required, or an Array of Integer repository IDs otherwise.
  def filtered_repository_ids(organization_id: nil)
    @filtered_repository_ids ||= {}
    @filtered_repository_ids[organization_id] ||= begin
      filtered_repo_ids = Repository.where(id: all_repository_ids).active

      if excluded_repos_exist?
        filtered_repo_ids = filtered_repo_ids.where.not(organization_id: excluded_organization_ids).or(filtered_repo_ids.where(organization_id: nil))
      end

      if organization_id.present?
        filtered_repo_ids = filtered_repo_ids.where(organization_id: organization_id)
      end

      filtered_repo_ids.pluck(:id)
    end
  end

  # Private: returns the subset of IDs for associated repositories which have been flagged as
  # deleted/inactive.
  #
  # Returns an Array of Integer IDs.
  def deleted_repository_ids
    @deleted_repository_ids = all_repository_ids - active_repository_ids
  end

  # Private: returns the subset of IDs for associated repositories which exist and have not been
  # flagged as deleted/inactive.
  #
  # Returns an Array of Integer IDs.
  def active_repository_ids
    @active_repository_ids ||= Repository.active.where(id: all_repository_ids).pluck(:id)
  end

  # Private: returns a list of all repositories IDs which are associated with this
  # user's pull requests.
  #
  # Returns an Array of Integer IDs.
  def all_repository_ids
    @all_repository_ids ||= user.pull_requests.distinct.pluck(:repository_id)
  end

  # Private: returns a list of stats tags for this fetcher instance.
  #
  # Returns an Array of String tags.
  def default_stats_tags
    @default_stats_tags ||= [
      "excluding_orgs:#{excluded_organization_ids.any?}",
      "organization_id:#{@organization_id.present?}",
    ]
  end
end
