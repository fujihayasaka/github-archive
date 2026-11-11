# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement
  # Query class for fetching org repositories where Code Scanning is not yet enabled,
  # with committer data for cost estimation. Equivalent to SecretScanning::BulkEnablementQuery
  # but for Code Scanning, using the Bundled SKU for bundled orgs or CodeSecurity SKU otherwise.
  #
  # Filters repos via SecurityOverviewAnalytics::Coverage::ListQuery with
  # "code-scanning-alerts:not-enabled" — mirroring the SRA pattern that uses
  # "secret-scanning-alerts:not-enabled".
  class CsraBulkEnablementQuery
    class PickerRepository < T::Struct
      const :id, Integer
      const :node_id, String
      const :name, String
      const :owner_display_login, String
      const :visibility, String
      const :additional_committer_ids, T::Array[Integer]
      const :archived, T::Boolean
      const :vulnerabilities_found, T.nilable(Integer)

      SerializedHash = T.type_alias do
        {
          id: Integer,
          nodeId: String,
          name: String,
          ownerLogin: String,
          visibility: String,
          additionalCommitterIds: T::Array[Integer],
          archived: T::Boolean,
          vulnerabilitiesFound: T.nilable(Integer),
        }
      end

      sig { returns(SerializedHash) }
      def to_hash
        {
          id: id,
          nodeId: node_id,
          name: name,
          ownerLogin: owner_display_login,
          visibility: visibility,
          additionalCommitterIds: additional_committer_ids,
          archived: archived,
          vulnerabilitiesFound: vulnerabilities_found,
        }
      end
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
      user_session: nil
    )
      @org = org
      @actor = actor
      @cap_filter = cap_filter
      @page = T.let([page, 1].max, Integer)
      @per_page = per_page
      @remote_ip = remote_ip
      @search_query = T.let(search_query.to_s, String)
      @user_session = user_session
    end

    sig { returns(T::Array[PickerRepository::SerializedHash]) }
    memoize def picker_repos
      structs = repos.map { |repo| repo_payload_with_metadata(repo) }

      # Ruby-level sorting supersedes the Elasticsearch sort:name-asc from INJECTED_TERMS.
      # Assessed repos first (sorted by vulnerability count descending),
      # then non-assessed repos sorted by name.
      assessed, rest = structs.partition { |s| !s.vulnerabilities_found.nil? }
      assessed.sort_by! { |s| -(s.vulnerabilities_found || 0) }
      rest.sort_by!(&:name)

      (assessed + rest).map(&:to_hash)
    end

    sig { returns(Integer) }
    memoize def count
      executed_repo_query.total
    end

    private

    sig { returns(T::Array[::Repository]) }
    memoize def repos
      repos = executed_repo_query.models

      GitHub::PrefillAssociations.prefill_associations(repos, [:owner, :organization], available_records: [org])
      GitHub::PrefillAssociations.prefill_batch_method(repos, :archived?)

      repos
    end

    sig { returns(Search::Results[::Repository]) }
    memoize def executed_repo_query
      repo_query.execute
    end

    sig { returns(Search::Queries::RepoQuery) }
    memoize def repo_query
      query =
        ::SecurityProductsEnablement::FastRepoQuery.new(
          binary_fork_filter: true,
          cap_filter:,
          current_user: actor,
          include_forks: true,
          limit_to_repo_ids: code_scanning_disabled_repo_ids,
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
    memoize def code_scanning_disabled_repo_ids
      parser = ::Search::Queries::SecurityCenter::CoverageQueryParser.new("code-scanning-alerts:not-enabled")

      result = ::SecurityOverviewAnalytics::Coverage::ListQuery
        .for_organization(
          organization: org,
          repo_ids: nil,
          user: actor || org,
          user_session: user_session || UserSession.new,
          parser: parser,
        )
        .perform(page: 1, page_size: 10_000)

      result.items.map { |item| item.repo_metadata.id }
    rescue StandardError => e
      GitHub.logger.warn(
        "Failed to fetch code scanning disabled repos via analytics",
        {
          "code.namespace" => self.class.name,
          "gh.org.id" => org.id,
          "error.class" => e.class.name,
          "error.message" => e.message,
        },
      )
      []
    end

    sig { params(repo: ::Repository).returns(PickerRepository) }
    def repo_payload_with_metadata(repo)
      payload = repository_payload(repo)
      PickerRepository.new(
        id: payload.fetch(:id),
        node_id: payload.fetch(:nodeId),
        name: payload.fetch(:name),
        owner_display_login: payload.fetch(:ownerLogin),
        visibility: payload.fetch(:visibility),
        additional_committer_ids: additional_committer_ids_by_repo_id.fetch(repo.id, []),
        archived: repo.archived?,
        vulnerabilities_found: vulnerabilities_found_by_repo_id[repo.id],
      )
    end

    sig { returns(T::Hash[Integer, T::Array[Integer]]) }
    memoize def additional_committer_ids_by_repo_id
      return {} if repos.empty?

      sku = org.advanced_security_products_bundled? ? GitHub::Turboghas::SKU::Bundled : GitHub::Turboghas::SKU::CodeSecurity
      licensing_service = QuickSetupService::LicensingService.new(organization: org)
      repo_hashes = repos.map do |repo|
        { id: repo.id, visibility: repo.visibility, archived: repo.archived? }
      end

      licensing_service.fetch_committer_data_for_feature(repo_hashes, sku)
    rescue StandardError => e
      GitHub.logger.warn(
        "Failed to calculate additional committer IDs for CSRA",
        {
          "code.namespace" => self.class.name,
          "gh.org.id" => org.id,
          "error.class" => e.class.name,
          "error.message" => e.message,
        },
      )
      {}
    end

    # Returns a hash of { repo_id => total_vulnerability_count } from the latest
    # completed CSRA assessment. Repos not in the assessment won't appear in this
    # hash, resulting in nil vulnerabilities_found on the struct.
    sig { returns(T::Hash[Integer, Integer]) }
    memoize def vulnerabilities_found_by_repo_id
      latest_assessment = ::SecurityProductsEnablement::CodeScanningAssessment
        .where(owner_id: org.id, status: :completed)
        .order(number: :desc)
        .first

      return {} unless latest_assessment

      results = latest_assessment.assessment_results.to_a
      results
        .group_by(&:repository_id)
        .transform_values { |items| items.sum(&:vulnerability_count) }
    rescue StandardError => e
      GitHub.logger.warn(
        "Failed to fetch vulnerability counts for CSRA",
        {
          "code.namespace" => self.class.name,
          "gh.org.id" => org.id,
          "error.class" => e.class.name,
          "error.message" => e.message,
        },
      )
      {}
    end
  end
end
