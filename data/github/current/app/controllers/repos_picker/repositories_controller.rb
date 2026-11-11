# typed: true
# frozen_string_literal: true

class ReposPicker::RepositoriesController < ApplicationController
  include ReposPicker::CurrentOwnerDependency

  depends_on_clusters \
    ApplicationRecord::Iam,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Profiles,
    ApplicationRecord::Repositories

  layout false

  before_action :login_required
  before_action :ensure_correct_owner_scope

  MAX_ITEMS = 100
  # Delete along with the repos_picker_use_mysql feature flag.
  INJECTED_TERMS = "in:name sort:name-asc"

  sig { void }
  def index
    if use_mysql_enabled?
      results = search_results

      render json: {
        items: Search::Helpers::RepoListPayloadHelper.serialize_repositories(results[:repos]),
        totalCount: results[:total],
      }
    else
      results = repo_query.execute

      render json: {
        items: Search::Helpers::RepoListPayloadHelper.serialize_repositories(results.results.map { |r| r["_model"] }),
        totalCount: results.total,
      }
    end
  end

  sig { void }
  def count # rubocop:disable GitHub/UseRestfulActions
    return head :not_found if params[:q].blank?
    return head :not_found unless current_owner || current_enterprise

    results = repo_query.count_with_timeout
    render json: {
      totalCount: results.total,
    }
  end

  private

  sig { returns(Search::Repositories::ReposSearchResult) }
  def search_results
    experiment_unbounded = FeatureFlag.vexi.enabled?(:repos_finder_unbounded, current_user, default: false)
    Search::Repositories.search_repos(current_user, phrase, 1, scope:, per_page: MAX_ITEMS, sort_order:, user_session:, cap_filter:, experiment_unbounded:)
  end

  sig { returns(Search::Queries::RepoQuery) }
  def repo_query
    query = Search::Queries::RepoQuery.new(
      current_user: current_user,
      cap_filter: cap_filter,
      user_session: user_session,
      remote_ip: remote_ip,
      phrase: phrase,
      include_forks: true,
      binary_fork_filter: true,
      visibility_and_execution: true,
      per_page: MAX_ITEMS,
      page: 1,
    )

    org_logins = if current_owner
      [T.must(current_owner).display_login]
    elsif current_enterprise
      T.must(current_enterprise).organizations.limit(Search::Repositories::MAX_BIZ_ORGS).pluck(:display_login)
    end
    query.qualifiers[:org].clear.must(org_logins) if org_logins.present?

    query
  end

  sig { returns(String) }
  def phrase
    injected_terms = use_mysql_enabled? ? "in:name" : INJECTED_TERMS

    result = "#{params[:q].to_s.strip} #{injected_terms}"
    result = "visibility:#{params[:visibility]} #{result}" if params[:visibility].present?

    result
  end

  sig { returns(Search::Repositories::ScopeType) }
  def scope
    owner = current_owner
    if owner&.organization?
      { org: T.cast(owner, Organization) }
    elsif owner.present?
      { owner: T.cast(owner, User) }
    elsif current_enterprise
      { enterprise: T.must(current_enterprise) }
    end
  end

  sig { returns(T.nilable(String)) }
  def sort_order
    return if params[:q]&.include?("sort:")
    scope.present? ? "name-asc" : "relevance"
  end

  sig { returns(T::Boolean) }
  def use_mysql_enabled?
    FeatureFlag.vexi.enabled?(:repos_picker_use_mysql, current_user, default: false)
  end

  def ensure_correct_owner_scope
    head :not_found if current_owner && current_enterprise
  end
end
