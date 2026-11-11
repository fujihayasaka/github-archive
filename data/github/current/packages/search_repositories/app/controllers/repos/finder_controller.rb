# typed: strict
# frozen_string_literal: true

class Repos::FinderController < ApplicationController
  include Orgs::CustomPropertiesHelper

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
  only: [:index, :layout]

  before_action :login_required
  after_action :instrument_query_terms, only: [:index]

  global_navigation_title "Repositories", only: [:index]

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

  class ReposFinderLayoutPayload < ReactPayload::Base
    sig { params(payload: T::Hash[Symbol, T.untyped]).void }
    def initialize(payload:)
      @payload = payload
    end

    sig { override.returns(String) }
    def route_id
      "reposFinderLayoutRoute"
    end

    sig { override.returns(T.untyped) }
    def payload
      @payload
    end
  end

  sig { void }
  def index
    respond_with_react(
      title: "Repositories",
      payload: ReposFinderPagePayload.new(payload: repos_finder_payload),
      layout: layout_for_turbo_request,
      app_payload_generator: -> { global_sso_app_payload },
      nested_payloads: -> {
        [ReposFinderLayoutPayload.new(payload: repos_finder_layout_payload)]
      },
    )
  end

  sig { void }
  def layout # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        render_react_json(payload: ReposFinderLayoutPayload.new(payload: repos_finder_layout_payload))
      end
    end
  end

  private

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def repos_finder_payload
    result = fetch_repositories
    can_admin_all_results = has_admin_qualifier?

    payload = {
      customProperties: custom_properties_payload,
      additionalFilterProviders: additional_filter_providers,
    }

    properties_source = common_source_from_query
    if properties_source && Repositories.domain.custom_properties.external_properties_enabled?(properties_source)
      payload[:properties] = properties_payload
    end

    ::Search::Helpers::RepoListPayloadHelper.query_result_payload(result, current_user, can_admin_all_results: can_admin_all_results).merge(payload).compact
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def repos_finder_layout_payload
    {
      compactMode: current_user ? current_user.settings.get(:repos_finder_compact_mode) : false,
      suggestedOrgs: current_user ? suggested_orgs : [],
      repoShortcuts: repos_user_shortcuts,
      sso: global_sso_app_payload,
    }
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
      experiment_unbounded: FeatureFlag.vexi.enabled?(:repos_finder_unbounded, current_user, default: false)
    )
  end

  DEFAULT_PHRASE = "contributed-by:@me"

  sig { returns(String) }
  def query
    params[:q].present? ? params[:q] : DEFAULT_PHRASE
  end

  # Returns whether the query is limited to repos adminable by the current user.
  sig { returns(T::Boolean) }
  def has_admin_qualifier?
    terms = query.split(" ")
    terms.include?("admin:@me")
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

  sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def custom_properties_payload
    return nil unless current_user

    source = common_source_from_query
    return nil unless source.present?
    return nil unless ::Repositories.domain.custom_properties.can_see_property_definitions?(current_user, source, cap_filter)

    defs = ::Repositories.domain.custom_properties.get_definitions(source)

    {
      definitions: definitions_payload(defs),
      source: { type: source.is_a?(Organization) ? "organization" : "enterprise", login: source.display_login },
    }
  end

  sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def properties_payload
    return nil unless current_user

    source = common_source_from_query
    return nil unless source.present?
    return nil unless ::Repositories.domain.custom_properties.can_see_property_definitions?(current_user, source, cap_filter)

    definitions = { "props" => ::Repositories.domain.custom_properties.get_definitions(source) }

    if ::Repositories.domain.custom_properties.external_properties_enabled?(source)
      external_defs = ::Repositories.domain.custom_properties.get_external_property_definitions(source)
      definitions.merge!(external_defs)
    end

    {
      namespaces: namespaced_definitions_payload(definitions),
      source: { type: source.is_a?(Organization) ? "organization" : "enterprise", login: source.display_login },
    }
  end

  sig { returns(T::Array[String]) }
  def additional_filter_providers
    source = common_source_from_query
    source.present? ? ::Repositories.domain.custom_properties.system_property_names(source) : []
  end

  sig { returns(T.nilable(T.any(Business, Organization))) }
  memoize def common_source_from_query
    logins = org_logins_from_query
    return nil if logins.empty?

    ::Search::Repositories.get_common_source(logins)
  end

  sig { returns(T::Array[String]) }
  memoize def org_logins_from_query
    parsed = Search::ParsedQuery.parse(
      query,
      terms: [:org, :owner, :user, :repo],
      enumerable_terms: [:org],
    )

    logins = parsed.each_with_object([]) do |component, logins|
      next unless component.is_a?(Array)
      term, value, negated = component
      next if negated
      return [] if [:owner, :user, :repo].include?(term)
      next unless term == :org
      if value.is_a?(Array)
        logins.concat(value.map(&:strip))
      else
        logins << value.strip
      end
    end

    logins.compact.uniq
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
