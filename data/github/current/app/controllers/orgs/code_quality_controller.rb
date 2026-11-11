# typed: strict
# frozen_string_literal: true

class Orgs::CodeQualityController < Orgs::Controller
  before_action :organization_read_required
  before_action :code_quality_required

  helper_method :auth_enumerator

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::SecurityOverviewAnalytics,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  class IndexPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "orgCodeQualityIndexRoute"
    end

    sig do
      params(
        organization_login: String,
        custom_property_names: T::Array[String],
        repo_limit_exceeded: T::Boolean,
        counts: T::Array[T::Hash[Symbol, T.untyped]],
        repos: T::Array[T::Hash[Symbol, T.untyped]],
        code_quality_docs_urls: T::Hash[String, String],
        prev_cursor: T.nilable(String),
        next_cursor: T.nilable(String),
      ).void
    end
    def initialize(
      organization_login:,
      custom_property_names:,
      repo_limit_exceeded:,
      counts:,
      repos:,
      code_quality_docs_urls:,
      prev_cursor:,
      next_cursor:
    )
      @organization_login = organization_login
      @custom_property_names = custom_property_names
      @repo_limit_exceeded = repo_limit_exceeded
      @counts = counts
      @repos = repos
      @code_quality_docs_urls = code_quality_docs_urls
      @prev_cursor = prev_cursor
      @next_cursor = next_cursor
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      {
        organizationLogin: @organization_login,
        customPropertyNames: @custom_property_names,
        repoLimitExceeded: @repo_limit_exceeded,
        counts: @counts,
        repos: @repos,
        codeQualityDocsUrls: @code_quality_docs_urls,
        prevCursor: @prev_cursor,
        nextCursor: @next_cursor,
      }
    end
  end

  sig { void }
  def index
    counts = []
    serialized_repos = []
    prev_cursor = nil
    next_cursor = nil

    # If there are no filtered repositories to query, we skip making the request. This is the case when the
    # user-specified filters exclude all repositories the user has access to, or if the user does not have access to
    # any repositories.
    if !filtered_repository_ids.invalid
      counts_response = GitHub::Turboquality.client.get_org_counts(Turboquality::Proto::GetOrgCountsRequest.new(
        owner_id: this_organization.id,
        repository_ids: filtered_repository_ids.included_repository_ids,
        excluded_repository_ids: filtered_repository_ids.excluded_repository_ids,
        ai_findings_filter: parsed_query.ai_findings_filter,
        standard_findings_filter: parsed_query.standard_findings_filter,
      ))
      raise StandardError.new(counts_response.error.to_s) if counts_response.error.present?
      counts = counts_response.data.repo_counts.to_a.map { |rc| serialized_org_repo_count(rc) }

      after_cursor = params[:after].try(:to_str)
      before_cursor = params[:before].try(:to_str)
      if before_cursor.present? && after_cursor.present?
        before_cursor = nil
      end

      repos_response = GitHub::Turboquality.client.get_org_repos(Turboquality::Proto::GetOrgReposRequest.new(
        owner_id: this_organization.id,
        repository_ids: filtered_repository_ids.included_repository_ids,
        excluded_repository_ids: filtered_repository_ids.excluded_repository_ids,
        ai_findings_filter: parsed_query.ai_findings_filter,
        standard_findings_filter: parsed_query.standard_findings_filter,
        reliability_score_filter: parsed_query.reliability_score_filter,
        maintainability_score_filter: parsed_query.maintainability_score_filter,
        sort_order: parsed_query.sort_order,
        page_size: 10,
        before: before_cursor,
        after: after_cursor,
      ))
      raise StandardError.new(repos_response.error.to_s) if repos_response.error.present?

      repo_ids = repos_response.data.repos.to_a.map(&:repository_id)
      repos = this_organization.repositories.active.where(id: repo_ids).index_by(&:id)

      prev_cursor = repos_response.data.prev_cursor.presence
      next_cursor = repos_response.data.next_cursor.presence

      serialized_repos = repos_response.data.repos.filter_map do |org_repo|
        repo = repos[org_repo.repository_id]

        # Account for the fact that turboquality's data may be out of sync.
        if repo.nil?
          # Because we do `this_organization.repositories.active` above, we can't tell
          # at this point if the repo has been deleted or has changed owners.
          CodeQuality::RepositoryUpdatePublisher.publish_repository_id(repository_id: org_repo.repository_id)
          GitHub.dogstats.increment("code_quality.org_dashboard.repo_out_of_sync")
          GitHub.logger.info("Detected inconsistencies in turboquality data for org dashboard",
            "gh.repo.id": org_repo.repository_id,
            "gh.owner.id": this_organization.id,
          )
          next nil
        end

        # Re-check authz. This is an extra layer of defence. We already filtered
        # the repo IDs passed to turboquality, but the authz enumerator is implemented
        # as part of security products rather than part of authz. Since we're only
        # displaying a very small number of repos, we can afford to re-check here.
        next nil unless CodeQualityRepositoryPermissions.new(repo).code_quality_readable_by?(current_user)

        serialized_org_repo(org_repo, repo)
      end
    end

    payload = IndexPayload.new(
      organization_login: this_organization.display_login,
      custom_property_names:,
      repo_limit_exceeded: allowed_repos.limit_exceeded,
      counts:,
      repos: serialized_repos,
      code_quality_docs_urls: CodeQuality.code_quality_docs_urls,
      prev_cursor:,
      next_cursor:,
    )

    respond_with_react(
      title: "Code quality · #{this_organization.display_login}",
      app_name: "code-quality",
      payload:,
      layout: "layouts/security_center/with_sidebar",
      page_data: {
        data: {
          backfill_in_progress: this_organization.trigger_security_center_reconciliation,
          selected_tab: :code_quality,
        },
      },
    )
  end

  private

  sig { returns(CodeQuality::OrgAuthz::AllowedRepos) }
  memoize def allowed_repos
    CodeQuality::OrgAuthz.allowed_repo_ids(user: current_user, organization: this_organization)
  end

  sig { params(count: Turboquality::Proto::OrgRepoCount).returns(T::Hash[Symbol, T.untyped]) }
  def serialized_org_repo_count(count)
    {
      reliabilityGrade: serialized_grade(count.reliability_grade),
      maintainabilityGrade: serialized_grade(count.maintainability_grade),
      repositoryCount: count.repository_count,
    }
  end

  sig { params(org_repo: Turboquality::Proto::OrgRepo, actual_repo: Repository).returns(T::Hash[Symbol, T.untyped]) }
  def serialized_org_repo(org_repo, actual_repo)
    result = {
      id: actual_repo.id,
      name: actual_repo.name,
      lastActiveAt: org_repo.last_active_at,
    }
    if org_repo.ai_findings_count.present?
      result[:aiFindingsCount] = T.must(org_repo.ai_findings_count).value
    end
    if org_repo.standard_findings_count.present?
      result[:standardFindingsCount] = T.must(org_repo.standard_findings_count).value
      result[:maintainabilityGrade] = serialized_grade(org_repo.maintainability_score)
      result[:reliabilityGrade] = serialized_grade(org_repo.reliability_score)
    end
    result
  end

  sig { params(grade: T.any(Symbol, Integer)).returns(String) }
  def serialized_grade(grade)
    grade = Turboquality::Proto::Grade.lookup(grade) if grade.is_a?(Integer)
    case grade
    when :GRADE_A
      "A"
    when :GRADE_B
      "B"
    when :GRADE_C
      "C"
    when :GRADE_D
      "D"
    else
      raise ArgumentError, "Unknown grade: #{grade}"
    end
  end

  sig { returns(Search::Queries::CodeQualityOrgQuery) }
  memoize def parsed_query
    Search::Queries::CodeQualityOrgQuery.new(params.fetch(:query, ""))
  end

  # Returns the repository IDs that should be included/excluded based on the user's filters and the repos the user
  # is allowed to see.
  sig { returns(CodeQuality::FilteredRepositories::Result) }
  memoize def filtered_repository_ids
    repository_filter = CodeQuality::FilteredRepositories.new(
      allowed_repository_ids: allowed_repos.repository_ids,
      query: parsed_query,
      organization: this_organization,
      user: current_user,
      user_session: user_session,
    )
    repository_filter.filtered_repository_ids
  end

  # Required by SecurityCenter::NavComponent
  sig { returns(T.nilable(SecurityCenter::AuthorizationEnumerator)) }
  memoize def auth_enumerator
    nil
  end

  sig { returns(T::Array[String]) }
  def custom_property_names
    Repositories.domain.custom_properties.get_definitions(this_organization).map do |definition|
      definition.property_name
    end
  end

  sig { void }
  def code_quality_required
    render_404 unless CodeQuality.available?(this_organization)
  end
end
