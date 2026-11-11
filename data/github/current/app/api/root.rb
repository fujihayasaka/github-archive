# typed: true
# frozen_string_literal: true

# Core Sinatra controller for all API requests.
class Api::Root < Api::App

  get "/", operation_id: "meta/root" do
    control_access :public_site_information,
      resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
      allow_integrations: true,
      allow_user_via_granular_actor: true

    hash = {
      current_user_url: api_url("/user"),
      current_user_authorizations_html_url: html_url("/settings/connections/applications{/client_id}"),
      authorizations_url: api_url("/authorizations"),
      code_search_url: api_url("/search/code?q={query}{&page,per_page,sort,order}"),
      commit_search_url: api_url("/search/commits?q={query}{&page,per_page,sort,order}"),
      emails_url: api_url("/user/emails"),
      emojis_url: api_url("/emojis"),
      events_url: api_url("/events"),
      feeds_url: api_url("/feeds"),
      followers_url: api_url("/user/followers"),
      following_url: api_url("/user/following{/target}"),
      gists_url: api_url("/gists{/gist_id}"),
      hub_url: api_url("/hub"),
      issue_search_url: api_url("/search/issues?q={query}{&page,per_page,sort,order}"),
      issues_url: api_url("/issues"),
      keys_url: api_url("/user/keys"),
      label_search_url: api_url("/search/labels?q={query}&repository_id={repository_id}" \
                                "{&page,per_page}"),
    }

    hash = hash.merge(
      notifications_url: api_url("/notifications"),
      organization_url: api_url("/orgs/{org}"),
      organization_repositories_url: api_url("/orgs/{org}/repos{?type,page,per_page,sort}"),
      organization_teams_url: api_url("/orgs/{org}/teams"),
      public_gists_url: api_url("/gists/public"),
      rate_limit_url: api_url("/rate_limit"),
      repository_url: api_url("/repos/{owner}/{repo}"),
      repository_search_url: api_url("/search/repositories?q={query}{&page,per_page,sort,order}"),
      current_user_repositories_url: api_url("/user/repos{?type,page,per_page,sort}"),
      starred_url: api_url("/user/starred{/owner}{/repo}"),
      starred_gists_url: api_url("/gists/starred"),
    )

    hash[:topic_search_url] = api_url("/search/topics?q={query}{&page,per_page}")

    hash = hash.merge(
      user_url: api_url("/users/{user}"),
      user_organizations_url: api_url("/user/orgs"),
      user_repositories_url: api_url("/users/{user}/repos{?type,page,per_page,sort}"),
      user_search_url: api_url("/search/users?q={query}{&page,per_page,sort,order}"),
    )

    hash.delete(:authorizations_url) if changeset_active?(:remove_authorizations_url_from_api_root)
    hash.delete(:hub_url) if changeset_active?(:remove_hub_url_from_api_root)

    deliver_raw hash
  end

  get "/emojis", operation_id: "emojis/get" do
    control_access :public_site_information,
      resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
      allow_integrations: true,
      allow_user_via_granular_actor: true

    url_prefix = GitHub.asset_host_url
    url_prefix = GitHub.url if url_prefix.blank?

    emojis = GitHub::Emoji.each_by_alias.each_with_object({}) do |(name, emoji), all|
      all[name] = "#{url_prefix}/images/icons/emoji/#{emoji.image_filename}?v8"
    end
    deliver_raw emojis
  end

  get "/rate_limit", operation_id: "rate-limit/get", skip_rate_limit: true do
    control_access :public_site_information,
      resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
      allow_integrations: true,
      allow_user_via_granular_actor: true

    cache_control "no-cache"
    if GitHub.rate_limiting_enabled?
      deliver :rate_limit_statuses_hash, Api::RateLimitStatus.all(self)
    else
      deliver_error 404, message: "Rate limiting is not enabled."
    end
  end

  get "/boomtown", operation_id: :internal do
    @route_owner = "@github/api-platform"
    control_access :staff_api, allow_integrations: false, allow_user_via_granular_actor: false, disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed
    fail "BOOM (#{GitHub.host_name})"
  end

  get "/deprecated", operation_id: :internal do
    deprecation_date = Time.now

    deprecated(
      deprecation_date: deprecation_date,
      sunset_date: deprecation_date + 1.year,
      info_url: "#{GitHub.developer_help_url}/deprecation-1",
      alternate_path_url: "/not-deprecated",
    )

    @route_owner = "@github/api-platform"
    control_access :staff_api, allow_integrations: false, allow_user_via_granular_actor: false, disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    deliver_raw(string: "Test Deprecated Endpoint")
  end

  get "/sleeptown", operation_id: :internal do
    @route_owner = "@github/api-platform"
    control_access :staff_api, allow_integrations: false, allow_user_via_granular_actor: false, disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed
    duration = (params[:n] || 30).to_i
    sleep duration
    deliver_empty
  end
end
