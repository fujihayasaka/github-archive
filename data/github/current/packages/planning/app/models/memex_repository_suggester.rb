# typed: true
# frozen_string_literal: true

class MemexRepositorySuggester
  include Scientist

  # Maximum number of results this suggester will return.
  SUGGESTED_REPOSITORIES_LIMIT = 8

  # Maximum number of the memex owner's repositories that we're willing to
  # query while building possible suggestions. This is limited in order to
  # improve performance, but the consequence is that this suggester may not
  # return any results at all.
  REPOSITORY_SEARCH_LIMIT = 100

  # Number of recent interactions to load
  RECENT_ACTIVITY_LIMIT = 50

  # Lookback time for recent interactions
  RECENT_ACTIVITY_THRESHOLD = 30.days

  ORGANIZATION_ASSOCIATED_REPOSITORY_LOOKUP_PARAMS = [:owned, :direct, :indirect_via_membership, :indirect_via_adminship]

  attr_reader :owner, :viewer

  def initialize(viewer:, owner:, memex_project: nil, milestone: nil, with_issue_types: nil)
    @viewer = viewer
    @owner = owner
    @memex_project = memex_project
    @with_issue_types = with_issue_types
    @milestone = milestone
  end

  # Returns a small list of initial repository suggestions.
  #
  # The goal of this method is to return this list of suggestions as quickly as
  # possible. To do that we do two things:
  #
  #     1. We only return a small, potentially even empty, list of results.
  #     2. We avoid expensive queries even if this hurts relevance a bit.
  #
  # Returns Array<Hash> where each element is the return value of `Repository#memex_suggestion_hash`
  def repositories
    GitHub.dogstats.distribution_time("memex_repository_suggester.repositories.dist") do
      suggestions = viewer_accessible_repositories(candidate_repository_ids)
      Promise.all(suggestions.map(&:async_memex_suggestion_hash)).sync
    end
  end

  private

  def associated_repository_ids_including
    if @owner.organization?
      ORGANIZATION_ASSOCIATED_REPOSITORY_LOOKUP_PARAMS
    end

    nil
  end

  def viewer_accessible_repositories(candidate_repository_ids)
    return @viewer_accessible_repositories if defined?(@viewer_accessible_repositories)


    accessible_repository_ids = Repository
      .where(id: candidate_repository_ids)
      .where(owner_id: @owner.id, public: true)
      .pluck(:id)
    private_candidate_repository_ids = (candidate_repository_ids - accessible_repository_ids)

    if private_candidate_repository_ids.any?
      accessible_repository_ids += @viewer.associated_repository_ids(
        repository_ids: private_candidate_repository_ids,
        organization: @owner.organization? ? @owner : nil,
        including: associated_repository_ids_including
      )
    end


    @viewer_accessible_repositories = Repository
      .where(id: accessible_repository_ids)
      .where(owner_id: @owner.id)
      # return repos in order of candidacy rather than sql index order
      .sort_by { |r| candidate_repository_ids.index(r.id) }
      .take(SUGGESTED_REPOSITORIES_LIMIT)
  end

  sig { returns(T::Array[Integer]) }
  def candidate_repository_ids
    # each list of repository ids is pre-sorted and in order of their relevance left to right in the bitwise OR
    ids = referenced_repository_ids | active_repository_ids | recently_updated_repository_ids

    if @milestone.present?
      ids = filter_by_milestone(ids)
    end

    ids
  end

  # repository ids that are referenced by any of the memex items in order of their frequency
  def referenced_repository_ids
    return @referenced_repository_ids if defined?(@referenced_repository_ids)
    @referenced_repository_ids = repository_id_reference_counts.keys.sort_by { |id| -repository_id_reference_counts[id] }
  end

  # repository ids that have been interacted with by the viewer
  # only fetched if the list of suggestions is not already populated and FF is enabled
  def active_repository_ids
    return @active_repository_ids if defined?(@active_repository_ids)

    @active_repository_ids = @viewer.ranked_contributed_repositories(
      include_issue_comments: true,
      since: RECENT_ACTIVITY_THRESHOLD.ago,
      has_issues: true
    ).keys
      .map(&:id)
      .uniq
      .first(SUGGESTED_REPOSITORIES_LIMIT)
  end

  # repository ids that have been updated recently in order of their last update
  def recently_updated_repository_ids
    return @recently_updated_repository_ids if defined?(@recently_updated_repository_ids)
    @recently_updated_repository_ids = @owner
      .repositories
      .recently_updated
      .where(has_issues: true)
      .limit(REPOSITORY_SEARCH_LIMIT)
      .pluck(:id)
  end

  def repository_id_reference_counts
    @repository_id_reference_counts ||= if @memex_project.present?
      @memex_project.prioritized_scope(:memex_project_items).where.not(repository_id: nil).limit(MemexProjectItem::PER_PAGE_LIMIT).group(:repository_id).count
    else
      {}
    end
  end

  sig { params(candidate_repository_ids: T::Array[Integer]).returns(T::Array[Integer]) }
  def filter_by_milestone(candidate_repository_ids)
    Milestone.where(title: @milestone, repository_id: candidate_repository_ids).pluck(:repository_id)
  end
end
