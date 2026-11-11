# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement
  # Query class for fetching repositories for Code Security Risk Assessment.
  # Eligibility criteria:
  # - Private or internal repositories only (not public)
  # - Not archived
  # - Must have at least one Code Scanning supported language
  #
  # Performance notes:
  # - Uses the `languages` table to check all languages in a repo (not just primary)
  # - Derives supported languages from CodeScanning::ManagedAnalysesLanguageSupport::LANGUAGE_DATA
  # - Suggested repos query limits to top 20 by commit activity
  # - Uses Elasticsearch via FastRepoQuery for search filtering (matches BulkEnablementQuery behavior)
  class CodeSecurityRiskAssessmentReposQuery
    include GitHub::Memoizer

    SUGGESTED_REPOS_LIMIT = 20
    COMMIT_ACTIVITY_LOOKBACK_DAYS = 90
    DEFAULT_PER_PAGE = 500
    REPO_ID_BATCH_SIZE = 1000
    INJECTED_TERMS = "in:name sort:name-asc"

    sig { returns(Organization) }
    attr_reader :org

    sig { returns(T.nilable(User)) }
    attr_reader :actor
    alias_method :current_user, :actor

    sig { returns(String) }
    attr_reader :search_query

    sig { returns(T.nilable(ConditionalAccess::Web::Filter)) }
    attr_reader :cap_filter

    sig { returns(T.nilable(String)) }
    attr_reader :remote_ip

    sig { returns(T.nilable(UserSession)) }
    attr_reader :user_session

    sig { returns(Integer) }
    attr_reader :page

    sig { returns(Integer) }
    attr_reader :per_page

    sig do
      params(
        org: Organization,
        actor: T.nilable(User),
        search_query: T.nilable(String),
        cap_filter: T.nilable(ConditionalAccess::Web::Filter),
        remote_ip: T.nilable(String),
        user_session: T.nilable(UserSession),
        page: Integer,
        per_page: Integer,
      ).void
    end
    def initialize(
      org:,
      actor: nil,
      search_query: nil,
      cap_filter: nil,
      remote_ip: nil,
      user_session: nil,
      page: 1,
      per_page: DEFAULT_PER_PAGE
    )
      @org = org
      @actor = actor
      @search_query = T.let(search_query.to_s, String)
      @cap_filter = cap_filter
      @remote_ip = remote_ip
      @user_session = user_session
      @page = T.let([page, 1].max, Integer)
      @per_page = per_page
    end

    sig { returns(Integer) }
    memoize def count
      return 0 if repo_ids_with_supported_languages.empty?

      if search_query.present?
        executed_repo_query.total
      else
        repo_ids_with_supported_languages.size
      end
    end

    # Returns the IDs of suggested repos for CSRA scanning.
    #
    # Strategy order:
    # 1. Reuse repos that completed successfully in the most recent completed
    #    CSRA assessment (intersected with currently eligible repos).
    # 2. Rank eligible repos by commit activity in the past 90 days.
    # 3. Fall back to the N most recently updated eligible repos (ensures
    #    suggestions are never empty when eligible repos exist).
    sig { returns(T::Array[Integer]) }
    memoize def suggested_repo_ids
      return [] if repo_ids_with_supported_languages.empty?

      prior_ids = completed_repo_ids_from_latest_assessment
      return prior_ids if prior_ids.present?

      activity_ids = suggested_repo_ids_by_commit_activity
      return activity_ids if activity_ids.present?

      # Final fallback: suggest most recently updated eligible repos
      ::Repository
        .where(id: repo_ids_with_supported_languages)
        .order(updated_at: :desc, id: :desc)
        .limit(SUGGESTED_REPOS_LIMIT)
        .pluck(:id)
    end

    # Returns all eligible repos formatted for the picker UI.
    # Suggested repos are returned first (sorted by name), followed by remaining repos (also sorted by name).
    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    memoize def eligible_repos
      return [] if repo_ids_with_supported_languages.empty?

      repos = if search_query.present?
        executed_repo_query.models
      else
        suggested = suggested_repo_ids.to_set
        suggested_repos = ::Repository
          .where(id: repo_ids_with_supported_languages.select { |id| suggested.include?(id) })
          .order(:name)
          .to_a
        remaining_repos = ::Repository
          .where(id: repo_ids_with_supported_languages.reject { |id| suggested.include?(id) })
          .order(:name)
          .limit(per_page - suggested_repos.size)
          .to_a
        suggested_repos + remaining_repos
      end

      # Prefill associations to avoid N+1 queries when building payload
      # (serialize_repositories accesses repo.owner.display_login)
      GitHub::PrefillAssociations.prefill_associations(repos, [:owner, :organization], available_records: [org])

      Search::Helpers::RepoListPayloadHelper.serialize_repositories(repos)
    end

    private

    sig { returns(Search::Results[::Repository]) }
    memoize def executed_repo_query
      repo_query.execute
    end

    sig { returns(Search::Queries::RepoQuery) }
    memoize def repo_query
      query = FastRepoQuery.new(
        binary_fork_filter: true,
        cap_filter:,
        current_user: actor,
        include_forks: true,
        limit_to_repo_ids: repo_ids_with_supported_languages,
        page:,
        per_page:,
        phrase: repo_query_phrase,
        remote_ip:,
        user_session:,
        visibility_and_execution: true,
      )

      query.qualifiers[:org].clear.must([org.display_login])

      query
    end

    sig { returns(String) }
    memoize def repo_query_phrase
      "#{search_query} #{INJECTED_TERMS}".squish
    end

    # Get IDs of CodeQL-supported languages from LANGUAGE_DATA
    # This dynamically derives supported languages to stay in sync with CodeQL support
    sig { returns(T::Array[Integer]) }
    memoize def codeql_language_ids
      # Get all language name variants from the authoritative LANGUAGE_DATA source
      # Excludes "actions" as it's not a Linguist-detected language
      language_variants = CodeScanning::ManagedAnalysesLanguageSupport::LANGUAGE_DATA
        .flat_map(&:variants)
        .reject { |name| name == "actions" }

      # Resolve variants to canonical Linguist language names in memory
      canonical_names = language_variants
        .filter_map { |variant| Linguist::Language[variant]&.name }
        .uniq

      # Batch-resolve LanguageName IDs with a single query to avoid N+1 lookups
      LanguageName.where(name: canonical_names).pluck(:id)
    end

    # Get repository IDs that have at least one CodeQL-supported language
    # Batches the query to avoid exceeding MySQL statement timeout for large orgs
    # where actor_visible_repo_ids can contain tens of thousands of IDs.
    sig { returns(T::Array[Integer]) }
    memoize def repo_ids_with_supported_languages
      visible_ids = actor_visible_repo_ids
      return [] if visible_ids.empty?

      language_ids = codeql_language_ids
      return [] if language_ids.empty?

      supported_languages = Language.where(language_name_id: language_ids)

      visible_ids
        .each_slice(REPO_ID_BATCH_SIZE)
        .flat_map { |batch| supported_languages.where(repository_id: batch).distinct.pluck(:repository_id) }
    end

    # Get repository IDs visible to the actor (private/internal, not archived)
    # Uses pluck + associated_repository_ids to keep filtering in SQL/authorization infrastructure
    sig { returns(T::Array[Integer]) }
    memoize def actor_visible_repo_ids
      repo_ids = @org.repositories
        .private_scope
        .where(maintained: true)
        .pluck(:id)

      return repo_ids unless actor

      T.must(actor).associated_repository_ids(repository_ids: repo_ids)
    end

    # Returns repo IDs from the most recent completed CSRA assessment,
    # intersected with the current eligible repos.
    # Returns an empty array when no completed assessment exists.
    sig { returns(T::Array[Integer]) }
    memoize def completed_repo_ids_from_latest_assessment
      latest = CodeScanningAssessment
        .where(owner_id: org.id, status: :completed)
        .order(number: :desc)
        .first

      return [] if latest.nil?

      prior_repo_ids = CodeScanningAssessmentRepository
        .where(assessment_id: latest.id, status: :completed)
        .order(:id)
        .limit(SUGGESTED_REPOS_LIMIT)
        .pluck(:repository_id)

      return [] if prior_repo_ids.empty?

      # Intersect with current eligible repos to exclude deleted/archived/public repos
      eligible_set = repo_ids_with_supported_languages.to_set
      prior_repo_ids.select { |id| eligible_set.include?(id) }
    end

    # Fallback suggestion strategy: rank eligible repos by commit activity
    sig { returns(T::Array[Integer]) }
    memoize def suggested_repo_ids_by_commit_activity
      since = COMMIT_ACTIVITY_LOOKBACK_DAYS.days.ago

      recently_pushed_repo_ids = ::Repository
        .where(id: repo_ids_with_supported_languages)
        .where("pushed_at >= ?", since)
        .pluck(:id)

      return [] if recently_pushed_repo_ids.empty?

      CommitContributions.domain.top_repositories_by_commit_activity(
        repository_ids: recently_pushed_repo_ids,
        since: since,
        limit: SUGGESTED_REPOS_LIMIT
      )
    end
  end
end
