# typed: strict
# frozen_string_literal: true

class Repos::FinderController < ApplicationController
  depends_on_clusters ApplicationRecord::Mysql1,
  ApplicationRecord::Configurations,
  ApplicationRecord::Collab,
  ApplicationRecord::Mysql2,
  ApplicationRecord::NotificationsEntries,
  ApplicationRecord::IssuesPullRequests,
  ApplicationRecord::Repositories,
  ApplicationRecord::IamAbilities,
  ApplicationRecord::Iam,
  ApplicationRecord::Profiles,
  only: [:index, :repos_list]

  before_action :login_required
  before_action :repos_relevance_page_enabled
  after_action :instrument_query_terms, only: [:index, :repos_list]

  sig { returns(String) }
  def self.react_bundle_name
    "repos-finder"
  end

  class ReposFinderPagePayload < ReactPayload::Base
    sig { params(payload: T::Hash[Symbol, T.untyped]).void }
    def initialize(payload:)
      @payload = payload
    end

    sig { override.returns(String) }
    def route_id
      "reposFinderPageRoute"
    end

    sig { override.returns(T.untyped) }
    def payload
      @payload
    end
  end

  sig { void }
  def index
    context_region_title "Repositories"

    add_client_feature_flag [:repos_finder_unbounded, :repos_relevance_page, :repos_finder_suggest_properties, :repos_finder_shortcuts]

    payload = GitHub.dogstats.distribution_time("repos_finder_controller.show.payload.time") do
      repos_finder_payload
    end

    respond_with_react(
      title: "User repositories",
      payload: ReposFinderPagePayload.new(payload: payload),
      layout: layout_for_turbo_request,
      app_payload_generator: -> { global_sso_app_payload },
    )
  end

  sig { void }
  def repos_list # rubocop:todo GitHub/UseRestfulActions
    payload = GitHub.dogstats.distribution_time("repos_finder_controller.repos_list.payload.time") do
      repos_finder_payload
    end

    render json: payload
  end

  private

  sig { void }
  def repos_relevance_page_enabled
    render_404 unless FeatureFlag.vexi.enabled?(:repos_relevance_page, current_user, default: false)
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def repos_finder_payload
    result = fetch_repositories
    can_admin_all_results = has_adminable_by?

    ::Search::Helpers::RepoListPayloadHelper.query_result_payload(result, current_user, can_admin_all_results: can_admin_all_results).merge({
      compactMode: current_user ? current_user.settings.get(:repos_finder_compact_mode) : false,
      suggestedOrgs: current_user ? suggested_orgs : [],
      repoShortcuts: (FeatureFlag.vexi.enabled?(:repos_finder_shortcuts, current_user, default: false) ? repos_user_shortcuts : nil),
    }).compact
  end

  sig { returns(Search::Repositories::ReposSearchResult) }
  def fetch_repositories
    ::Search::Repositories.search_repos(
      current_user,
      query,
      page,
      sort_order: sort_order,
      user_session: user_session,
      cap_filter: cap_filter,
      allow_finder_filters: true,
      experiment_unbounded: FeatureFlag.vexi.enabled?(:repos_finder_unbounded, current_user, default: false)
    )
  end

  DEFAULT_PHRASE = "contributed-by:@me"

  sig { returns(String) }
  def query
    params[:q].present? ? params[:q] : DEFAULT_PHRASE
  end

  # Returns whether the query is limited to repos adminable by the current user
  sig { returns(T::Boolean) }
  def has_adminable_by?
    query.split(" ").include?("adminable-by:@me")
  end

  DEFAULT_SORT_ORDER = "relevance"

  sig { returns(T.nilable(String)) }
  def sort_order
    params[:q]&.include?("sort:") ? nil : DEFAULT_SORT_ORDER
  end

  sig { returns(Integer) }
  def page
    params[:page].present? ? params[:page].to_i : 1
  end

  SUGGESTED_ORGS_LIMIT = 10

  sig { returns(T::Array[String]) }
  memoize def suggested_orgs
    orgs = contributed_org_logins
    return orgs.first(SUGGESTED_ORGS_LIMIT) if orgs.size >= SUGGESTED_ORGS_LIMIT

    (orgs | user_orgs).uniq.first(SUGGESTED_ORGS_LIMIT)
  end

  sig { returns(T::Array[String]) }
  def contributed_org_logins
    contributed_repos = current_user.repositories_contributed_to(
      viewer: current_user,
      limit: nil,
      exclude_owned: false,
      since: 1.year.ago,
    )

    org_ids = contributed_repos.map(&:organization_id).uniq.compact
    Organization.where(id: org_ids).pluck(:display_login)
  end

  sig { returns(T::Array[String]) }
  def user_orgs
    current_user.organizations.map(&:display_login)
  end

  sig { void }
  def instrument_query_terms
    ::Search::Helpers::ListHelper.instrument_query_terms(query, current_user, "repos-finder")
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def repos_user_shortcuts
    repo_shortcuts = current_user.dashboard&.shortcuts&.where(search_type: "repositories")
    return [] if repo_shortcuts.blank?

    repo_shortcuts.map do |shortcut|
      {
        id: shortcut.id,
        name: shortcut.name,
        description: shortcut.description,
        icon: shortcut.icon,
        color: shortcut.color,
        query: shortcut.compressed_query,
        source: "user"
      }
    end
  end

  sig { returns(T.any(User, Symbol)) }
  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_user
  end

  sig { returns(T.any(User, Symbol)) }
  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
