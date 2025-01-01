# typed: strict
# frozen_string_literal: true

module SecretScanning
  class BulkEnablementQuery
    class FastRepoQuery < Search::Queries::RepoQuery
      Results = T.type_alias { T::Array[T::Hash[String, T.untyped]] }

      sig { params(results: Results).returns(Results) }
      def prune_results(results)
        repo_ids = results.map { |result| result["_id"] }
        repos_by_id = Repository.where(id: repo_ids).index_by(&:id)

        results.keep_if do |result|
          repo_id = result["_id"].to_i
          repo = repos_by_id[repo_id]

          result["_model"] = repo
        end
      end
    end

    # This type should always be a superset of:
    # ReposPicker::RepositoriesPayloadDependency::FilterRepository
    PickerRepository = T.type_alias do
      {
        id: Integer,
        nodeId: String,
        name: String,
        ownerLogin: String,
        visibility: String,
        tokensFound: T.nilable(Integer),
        additionalCommitterIds: T::Array[Integer],
        archived: T::Boolean,
      }
    end

    DEFAULT_PER_PAGE = 500
    INJECTED_TERMS = "in:name sort:name-asc"

    include GitHub::Memoizer
    include ReposPicker::RepositoriesPayloadDependency

    sig { returns(T.nilable(User)) }
    attr_reader :actor
    alias_method :current_user, :actor

    sig { returns(T.nilable(ConditionalAccess::Web::Filter)) }
    attr_reader :cap_filter

    sig { returns(Organization) }
    attr_reader :org

    sig { returns(Integer) }
    attr_reader :page

    sig { returns(Integer) }
    attr_reader :per_page

    sig { returns(T.nilable(String)) }
    attr_reader :remote_ip

    sig { returns(String) }
    attr_reader :search_query

    sig { returns(T.nilable(UserSession)) }
    attr_reader :user_session

    sig { returns(T.nilable(Integer)) }
    attr_reader :assessment_number

    sig do
      params(
        org: Organization,
        actor: T.nilable(User),
        cap_filter: T.nilable(ConditionalAccess::Web::Filter),
        page: Integer,
        per_page: Integer,
        remote_ip: T.nilable(String),
        search_query: T.nilable(String),
        user_session: T.nilable(UserSession),
        assessment_number: T.nilable(Integer),
      ).void
    end
    def initialize(
      org:,
      actor: nil,
      cap_filter: nil,
      page: 1,
      per_page: DEFAULT_PER_PAGE,
      remote_ip: nil,
      search_query: nil,
      user_session: nil,
      assessment_number: nil
    )
      @org = org
      @actor = actor
      @cap_filter = cap_filter
      @page = T.let([page, 1].min, Integer)
      @per_page = per_page
      @remote_ip = remote_ip
      @search_query = T.let(search_query.to_s, String)
      @user_session = user_session
      @assessment_number = assessment_number
    end

    sig { returns(T::Array[PickerRepository]) }
    memoize def picker_repos
      repos.map { |repo| repo_payload_with_metadata(repo) }
    end

    sig { returns(Integer) }
    memoize def count
      executed_repo_query.total
    end

    private

    sig { returns(T::Array[Repository]) }
    memoize def repos
      repos = executed_repo_query.models

      GitHub::PrefillAssociations.prefill_associations(repos, [:owner, :organization], available_records: [org])
      GitHub::PrefillAssociations.prefill_batch_method(repos, :archived?)

      # Exclude repositories that are locked (by staff) out of
      # Secret Protection enablement.
      Configurable.preload_configuration(repos)
      repos.delete_if do |repo|
        SecretScanning::Features::Repo::TokenScanning.new(repo).staff_locked?
      end

      repos
    end

    sig { returns(Search::Results[Repository]) }
    memoize def executed_repo_query
      repo_query.execute
    end

    sig { returns(Search::Queries::RepoQuery) }
    memoize def repo_query
      query =
        FastRepoQuery.new(
          binary_fork_filter: true,
          cap_filter:,
          current_user: actor,
          include_forks: true,
          limit_to_repo_ids: secret_protection_disabled_repo_ids,
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

    sig { returns(T::Array[Integer]) }
    memoize def secret_protection_disabled_repo_ids
      query_parts = ["secret-scanning-alerts:not-enabled"]
      query_parts << search_query unless search_query.blank?
      query_string = query_parts.join(" ")

      parser = ::Search::Queries::SecurityCenter::CoverageQueryParser.new(query_string)

      # Use SecurityOverviewAnalytics for organizations
      result = ::SecurityOverviewAnalytics::Coverage::ListQuery
        .for_organization(
          organization: org,
          repo_ids: nil,
          user: actor || org,
          user_session: user_session || UserSession.new,
          parser: parser,
        )
        .perform(page: 1, page_size: 10_000) # Large page size to get all results

      # Extract repository IDs from the results
      result.items.map { |item| item.repo_metadata.id }
    rescue StandardError => e
      # Log error and fall back to empty array to avoid breaking the caller
      GitHub.logger.warn("Failed to fetch secret scanning disabled repos via analytics: #{e.message}")
      []
    end

    sig { params(repo: Repository).returns(PickerRepository) }
    def repo_payload_with_metadata(repo)
      # From: ReposPicker::RepositoriesPayloadDependency
      repository_payload(repo).merge(
        tokensFound: tokens_found_by_repo_id[repo.id],
        additionalCommitterIds: additional_committer_ids_by_repo_id.fetch(repo.id, []),
        archived: repo.archived?,
      )
    end

    sig { returns(T::Hash[Integer, T::Array[Integer]]) }
    memoize def additional_committer_ids_by_repo_id
      memo = T.let({}, T::Hash[Integer, T::Array[Integer]])
      cursor = T.let(nil, T.nilable(Turboghas::Proto::Cursor))

      return memo if paid_repo_ids.empty?

      begin
        loop do
          response = GitHub::Turboghas.check_error(
            GitHub::Turboghas.client.get_committers_for_owner(Turboghas::Proto::GetCommittersForOwnerRequest.new(
              owner_id: org.id,
              committer_type: :ADDITIONAL_COMMITTERS,
              features: [MonolithTwirp::CodeScanning::Turboghas::V1::Feature::FEATURE_SECRET_SCANNING],
              repository_ids: paid_repo_ids,
              cursor: cursor,
              limit: DEFAULT_PER_PAGE,
            ))
          )

          response.committers.each do |committer|
            repo_id = committer.repository_id
            memo[repo_id] ||= []
            T.must(memo[repo_id]) << committer.id
          end

          cursor = response.next_cursor
          break if cursor.nil?
        end
      rescue GitHub::Turboghas::ResponseError, Faraday::ConnectionFailed, Faraday::TimeoutError => e
        # Log the error but don't fail the entire request
        GitHub.logger.warn("Failed to calculate additional committer IDs: #{e.message}")
      end

      memo
    end

    # We only care about committer data for repositories that aren't
    # considered "free" in the pricing calculator.
    sig { returns(T::Array[Integer]) }
    memoize def paid_repo_ids
      repos.filter_map { |r| r.id unless r.public? || r.archived? }
    end

    # A hash with repository ID keys and secret count values. If the repo
    # wasn't scanned in the risk assessment, it won't appear in this hash and
    # we'll show "not scanned" or similar in the view.
    sig { returns(T::Hash[Integer, Integer]) }
    memoize def tokens_found_by_repo_id
      return {} unless assessment_number

      result, error = SecretScanning::Services::SecretRiskAssessmentsService.token_counts_by_repository_id(
        org,
        T.must(assessment_number),
      )

      error ? {} : result
    end
  end
end
