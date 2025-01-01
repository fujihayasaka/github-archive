# typed: strict
# frozen_string_literal: true

class Repos::FinderController < ApplicationController
  include Orgs::RepoListPayloadHelper

  depends_on_clusters ApplicationRecord::Mysql1,
  ApplicationRecord::Configurations,
  ApplicationRecord::Collab,
  ApplicationRecord::Mysql2,
  ApplicationRecord::NotificationsEntries,
  ApplicationRecord::IssuesPullRequests,
  ApplicationRecord::Repositories,
  ApplicationRecord::IamAbilities,
  ApplicationRecord::Iam,
  only: [:index, :repos_list]

  before_action :login_required
  before_action :repos_relevance_page_enabled

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

    query_result_payload(result, current_user).merge({
      compactMode: current_user ? current_user.settings.get(:repos_finder_compact_mode) : false,
      suggestedOrgs: current_user ? suggested_orgs : [],
    })
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
      allow_contributed_by_filter: true,
      support_single_owner_in_mysql: true,
      experiment_unbounded: true,
    )
  end

  DEFAULT_PHRASE = "contributed-by:@me"

  sig { returns(String) }
  def query
    params[:q].present? ? params[:q] : DEFAULT_PHRASE
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
