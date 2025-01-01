# typed: false
# frozen_string_literal: true

module HovercardHelper
  extend self
  extend DashboardHelper
  include DashboardHelper

  ORG_SSO_PATH = "%{path}{?return_to}"
  ACHIEVEMENT_HOVERCARD_PATH = "/users/%{login}/achievements/%{slug}/detail?hovercard=1"
  TEAM_HOVERCARD_PATH_TEMPLATE = Addressable::Template.new("/orgs/{org}/teams/{slug}/hovercard")
  ORG_HOVERCARD_PATH_TEMPLATE = Addressable::Template.new("/orgs/{org_login}/hovercard")
  ADVISORY_HOVERCARD_PATH_TEMPLATE = Addressable::Template.new("/advisories/{ghsa_id}/hovercard")
  DISCUSSION_HOVERCARD_PATH_TEMPLATE = Addressable::Template.new("/{owner}/{name}/discussions/{number}/hovercard")
  CWE_HOVERCARD_PATH_TEMPLATE = Addressable::Template.new("/advisories/cwes/{id}/hovercard{?query*}")
  SPONSORS_LISTING_HOVERCARD_PATH_TEMPLATE = Addressable::Template.new("/sponsors/{sponsorable_login}/hovercard")
  REPO_HOVERCARD_PATH_TEMPLATE = Addressable::Template.new("/{owner}/{name}/hovercard")
  USER_HOVERCARD_PATH_TEMPLATE = Addressable::Template.new("/users/{login}/hovercard")
  COPILOT_HOVERCARD_PATH_TEMPLATE = Addressable::Template.new("/copilot/hovercard?bot={bot_slug}")

  def review_status_octicon_class(review_decision)
    case review_decision.to_s
    when "changes_requested"
      "color-fg-danger"
    when "approved"
      "color-fg-success"
    when "review_required"
      "color-fg-muted"
    end
  end

  # Return the data attributes necessary to add hovercard support for a given
  # repo
  #
  # obj - An AR Repository
  # url_params [Hash] (optional) - Additional url parameters to include in the hovercard request
  def hovercard_data_attributes_for_repository(obj, url_params: {})
    if obj.instance_of?(Repository)
      owner = obj.owner_display_login
      name = obj.name
    end

    hovercard_data_attributes_for_repo_owner_and_name(owner, name, params: url_params)
  end

  # A shortcut function to generate data attributes for a repository owner and name
  #
  # owner_login - A string representing the owner of the repository
  # repo_name - A string representing the name of the repository
  # url_params [Hash] (optional) - Additional url parameters to include in the hovercard request
  def hovercard_data_attributes_for_repo_owner_and_name(owner_login, repo_name, params: {})
    return {} unless repo_name && owner_login

    {
      "hovercard-type" => "repository",
      "hovercard-url" =>  hovercard_url_for_repo(owner_login, repo_name, params: params),
    }
  end

  # Public: returns the repo hovercard path with the given query params
  #
  # repo_owner - A String representing the owner of the repository
  # repo_name - A String representing the name of the repository
  # params - The Hash of params to be added to the path
  # Example
  #  hovercard_url_for_repo('octocat', 'goothoob') => "/octocat/goothoob/hovercard"
  #  hovercard_url_for_repo('octocat', 'goothoob', { foo: 'bar' }) => "/octocat/goothoob/hovercard?foo=bar"
  # Returns a String url
  def hovercard_url_for_repo(repo_owner, repo_name, params: {})
    return nil unless repo_name && repo_owner

    url = REPO_HOVERCARD_PATH_TEMPLATE.expand(owner: repo_owner, name: repo_name).to_s
    # we add the params after since the template handles the query params in a way that makes it difficult to match our hydro schema
    url += "?#{params.to_query}" unless params.empty?
    url
  end

  # Public: Shortcut to build data attributes for a hovercard representing the owner of a repo - either user or org.
  #
  # obj - A User or Org AR model
  #
  # Returns a hash that can be passed as the `data` argument to a rails tag helper
  # Returns an empty hash if the object is a different type
  def hovercard_data_attributes_for_repository_owner(obj)
    user_login = obj.login if obj.instance_of?(User)
    return hovercard_data_attributes_for_user_login(user_login) if user_login

    org_login = obj.login if obj.instance_of?(Organization)
    return hovercard_data_attributes_for_org(login: org_login) if org_login

    {}
  end

  # Public: Build data attributes to add hovercard support to a user link
  #
  # obj - The user AR model
  # tracking [Boolean] (optional) - Whether or not to include octolytics tracking attributes
  # url_params [Hash] (optional) - Additional parameters to add to the hovercard request URL as query params
  #
  # Example
  # hovercard_data_attributes_for_user(user, tracking: true, url_params: { "foo" => "bar" })
  # Returns a hash that can be passed as the `data` argument to a rails tag helper
  # Returns an empty hash if the object is a different type
  def hovercard_data_attributes_for_user(obj, tracking: true, url_params: {})
    if obj.instance_of?(Organization)
      return hovercard_data_attributes_for_org(login: obj.login, tracking: tracking, url_params: url_params)
    end

    user_login =
      case
      when obj.instance_of?(User) then obj.display_login
      end

    return {} unless user_login

    hovercard_data_attributes_for_user_login(user_login, tracking: tracking, url_params: url_params)
  end

  # Generates data attributes for a hovercard for a bot object.
  #
  # @param obj [Bot] The bot object for which the hovercard data attributes are generated.
  # @param tracking [Boolean] Whether to include tracking information in the data attributes. Default is true.
  # @param url_params [Hash] Additional URL parameters to include in the data attributes. Default is an empty hash.
  #
  # @return [Hash] A hash of data attributes for the hovercard.
  def hovercard_data_attributes_for_bot(obj, tracking: true, url_params: {})
    if obj.is_a?(Bot) && (obj&.slug == Apps::Privileged::CopilotPullRequestReviewer::SLUG || obj&.slug == Apps::Privileged::CopilotSWEAgent::SLUG)
      hovercard_data_attributes_for_copilot_bot(obj&.slug, tracking: tracking, url_params: url_params)
    elsif obj.is_a?(User)
      hovercard_data_attributes_for_user(obj, tracking: tracking, url_params: url_params)
    else
      {}
    end
  end

  # Public: Build data attributes to add hovercard support to a business user
  # account link.
  #
  # obj - A BusinessUserAccount AR model
  #
  # Returns a hash that can be passed as the `data` argument to a rails tag helper
  # Returns an empty hash if the object is a different type
  def hovercard_data_attributes_for_business_user_account(obj, tracking: true)
    user_login = obj&.user&.login if obj.is_a?(BusinessUserAccount)
    return {} unless user_login

    hovercard_data_attributes_for_user_login(user_login, tracking: tracking)
  end

  # Public: Return the data attributes necessary to add hovercard support for the sponsorable user or organization of
  # the given SponsorsListing.
  #
  # sponsors_listing - a SponsorsListing
  #
  # Returns a Hash.
  def sponsorable_hovercard_attributes(sponsors_listing)
    return {} unless GitHub.sponsors_enabled?

    login = sponsors_listing.sponsorable_login
    if sponsors_listing.for_organization?
      hovercard_data_attributes_for_org(login: login)
    else
      hovercard_data_attributes_for_user_login(login)
    end
  end

  # Return the data attributes necessary to add hovercard support for a given
  # user_login
  #
  # user_login - Login of the user to generate data attrs for
  # tracking [Boolean] (optional) - If true, include octolytics tracking attributes (octo-click, octo-dimensions)
  # url_params [Hash] (optional) - Additional url parameters to include in the hovercard request
  def hovercard_data_attributes_for_user_login(user_login, tracking: true, url_params: {})
    return {} if !user_login || atom_feed?

    data = {
      "hovercard-type" => "user",
      "hovercard-url" => user_hovercard_path(user_login: user_login, params: url_params)
    }

    if tracking
      data.merge!(
        "octo-click" => "hovercard-link-click",
        "octo-dimensions" => "link_type:self",
      )
    end

    data
  end

  def hovercard_data_attributes_for_team(obj)
    if obj.instance_of?(Team)
      org_display_login = obj.organization.display_login
      team_slug = obj.slug
    end

    hovercard_data_attributes_for_org_and_team(org_display_login, team_slug)
  end

  def hovercard_data_attributes_for_discussion(repo_owner, repo_name, number, comment_id: nil, url_params: {})
    return {} unless repo_owner.present? && repo_name.present? && number.present?

    {
      "hovercard-type" => "discussion",
      "hovercard-url" => hovercard_url_for_discussion(repo_owner,
        repo_name, number, comment_id: comment_id, params: url_params),
    }
  end

  # Public: Get the discussion hovercard URL for a given discussion
  #
  # repo_owner - The owner of the repository the discussion belongs to
  # repo_name - The name of the repository the discussion belongs to
  # number - The number of the discussion
  # comment_id - The id of the comment to highlight
  # params - Additional url parameters to include in the hovercard request
  # Examples
  #   hovercard_url_for_discussion("github", "github", 1) => "/github/github/discussions/1/hovercard"
  #   hovercard_url_for_discussion("github", "github", 1, comment_id: 1) =>
  #     "/github/github/discussions/1/hovercard?comment_id=1"
  #   hovercard_url_for_discussion("github", "github", 1, comment_id: 1, params: { foo: "bar" }) =>
  #     "/github/github/discussions/1/hovercard?comment_id=1&foo=bar"
  # Returns a String
  def hovercard_url_for_discussion(repo_owner, repo_name, number, comment_id: nil, params: {})
    query = {}
    query[:comment_id] = comment_id if comment_id
    query.merge!(params) unless params.empty?
    url = DISCUSSION_HOVERCARD_PATH_TEMPLATE.expand(owner: repo_owner, name: repo_name,
      number: number).to_s
    url += "?" + query.to_query unless query.empty?
    url
  end

  def hovercard_data_attributes_for_org_and_team(org_display_login, team_slug)
    return {} unless org_display_login.present? && team_slug.present?

    {
      "hovercard-type" => "team",
      "hovercard-url" => hovercard_url_for_org_and_team(org_display_login, team_slug),
    }
  end

  def hovercard_data_attributes_for_achievement(login:, slug:)
    return {} unless login.present? && slug.present?

    {
      "hovercard-type" => "achievement",
      "hovercard-url" => hovercard_url_for_achievement(login, slug),
    }
  end

  def hovercard_url_for_achievement(login, slug)
    ACHIEVEMENT_HOVERCARD_PATH % { login: login, slug: slug }
  end

  def hovercard_url_for_org_and_team(org_display_login, team_slug)
    TEAM_HOVERCARD_PATH_TEMPLATE.expand(org: org_display_login, slug: team_slug).to_s
  end

  # Public: get the hovercard data attributes for an Issue or PullRequest
  #
  # obj - Either Issue or PullRequest AR model
  # comment_id - optional Integer database ID for an IssueComment on the given issue or pull request
  #
  # Examples
  #
  #   hovercard_data_attributes_for_issue_or_pr(pull_request)
  #   # => { hovercard_url: "/owner/repo/pull/123/hovercard", hovercard_type: "pull_request" }
  #
  #   hovercard_data_attributes_for_issue_or_pr(issue)
  #   # => { hovercard_url: "/owner/repo/issues/123/hovercard", hovercard_type: "issue" }
  #
  #   hovercard_data_attributes_for_issue_or_pr(pull_request.issue)
  #   # => { hovercard_url: "/owner/repo/pull/123/hovercard", hovercard_type: "pull_request" }
  #
  #   # To properly set data attributes on a tag, this should be used like so:
  #   content_tag(:a, data: hovercard_data_attributes_for_issue_or_pr(issue)) do
  #     # link content
  #   end
  #
  # Returns a hash of attributes to be passed as a rails tag helper's `data` keyword
  def hovercard_data_attributes_for_issue_or_pr(obj, resource_path: nil, comment_id: nil, comment_type: nil)
    hovercard_type =
      case obj
      when PlatformTypes::Issue, Issue::Adapter::CrossReferenceSourceIssueAdapter then "issue"
      when Commit then "commit"
      when Issue then obj.pull_request? ? "pull_request" : "issue"
      # TODO: issue_timeline unify Issue::Adapter::CrossReferenceSourcePullRequestAdapter & Issue::Adapter::PullRequestAdapter
      when PlatformTypes::PullRequest, Issue::Adapter::CrossReferenceSourcePullRequestAdapter, Issue::Adapter::PullRequestAdapter, PullRequest then "pull_request"
      else
        raise "Not an issue or a pull request: #{obj.class}"
      end

    resource_path ||= if obj.is_a?(Issue::Adapter::Base)
      obj.resource_path
    else
      obj.async_path_uri.sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    hovercard_url = if comment_id && comment_type
      "#{resource_path}/hovercard?comment_id=#{comment_id}&comment_type=#{comment_type}"
    else
      "#{resource_path}/hovercard"
    end

    { "hovercard-type" => hovercard_type, "hovercard-url" => hovercard_url }
  end

  # Public: get the hovercard data attributes for issues tracking the issue
  #
  # Examples
  #
  #   hovercard_data_attributes_for_tracked_in(issue)
  #   # => { hovercard_url: "/owner/repo/issues/123/tracked_in/hovercard", hovercard_type: "tracked_in" }
  #
  # Returns a hash of attributes to be passed as a rails tag helper's `data` keyword
  def hovercard_data_attributes_for_tracked_in(obj)
    raise "Not an issue: #{obj.class}" unless obj.is_a?(Issue)

    {
      "hovercard-type" => "tracked_in",
      "hovercard-url" => "#{issue_path(obj)}/tracked_in/hovercard",
    }
  end

  # Public: get the hovercard data attributes for issues tracking the code_scanning alert
  #
  # Examples
  #
  #   hovercard_data_attributes_for_alert_tracked_in(owner_login, repo_name, alert_number)
  #   # => { hovercard_url: "/owner_login/repo_name/security/code-scanning/1/tracked_in/hovercard", hovercard_type: "tracked_in" }
  #
  # Returns a hash of attributes to be passed as a rails tag helper's `data` keyword
  def hovercard_data_attributes_for_alert_tracked_in(owner_login, repo_name, alert_number)
    {
      "hovercard-type" => "tracked_in",
      "hovercard-url" => repository_code_scanning_show_tracked_in_hovercard_path(owner_login, repo_name, alert_number),
    }
  end

  # Public: get the hovercard data attributes for the code_scanning alert
  #
  # Examples
  #
  #   hovercard_data_attributes_for_security_alert(owner_login, repo_name, alert_number)
  #   # => { hovercard_url: "/owner_login/repo_name/security/code-scanning/1/hovercard", hovercard_type: "tracked_in" }
  #
  # Returns a hash of attributes to be passed as a rails tag helper's `data` keyword
  def hovercard_data_attributes_for_security_alert(owner_login, repo_name, alert_number)
    {
      "hovercard-type" => "security_alert",
      "hovercard-url" => UrlHelpers.repository_code_scanning_alert_hovercard_path(owner_login, repo_name, alert_number),
    }
  end

  # Public: get the hovercard data attributes for a Dependabot Alert
  #
  # Examples
  #
  #   hovercard_data_attributes_for_dependabot_alert(owner_login, repo_name, alert_number)
  #   # => { hovercard_url: "/owner_login/repo_name/security/dependabot/1/hovercard" }
  #
  # Returns a hash of attributes to be passed as a rails tag helper's `data` keyword
  def hovercard_data_attributes_for_dependabot_alert(owner_login, repo_name, alert_number)
    {
      "hovercard-type" => "dependabot_alert",
      "hovercard-url" => UrlHelpers.dependabot_alert_hovercard_path(owner_login, repo_name, alert_number),
    }
  end

  # Public: Get the hovercard data attributes for a Dependency Graph package
  #
  # Example
  #
  #   hovercard_data_attributes_for_dependency_graph_package(repository: current_repository, package_repository_id: 5, package_name: "rails")
  #   # => { hovercard_url: "/monalisa/smile/dependency-graph/package_hovercards/5/rails" }
  # Returns a hash of attributes to be passed as a rails tag helper's `data` keyword
  def hovercard_data_attributes_for_dependency_graph_package(repository:, package_repository_id:, package_name:)
    {
      "hovercard-type" => "dependendency_graph_package",
      "hovercard-url" => UrlHelpers.dependency_graph_package_hovercard_path(
        user_id: repository.owner_display_login,
        repository: repository,
        package_repository_id: package_repository_id,
        package_name: package_name
      )
    }
  end

  # Public: Get the user hovercard path for the given user
  # Can't use path helpers because hovercard_data_attributes_for_user
  # is used in Goomba pipeline, where we don't have a `request` instance
  #
  # user_login - The String login of the user
  # params - The Hash of params to be added to the path
  # Example
  #  hovercard_path_for_user('octocat') => "/users/octocat/hovercard"
  #  hovercard_path_for_user('octocat', { foo: 'bar' }) => "/users/octocat/hovercard?foo=bar"
  def user_hovercard_path(user_login:, params: {})
    return nil unless user_login

    user_login = user_login.to_s
    url = USER_HOVERCARD_PATH_TEMPLATE.expand(login: user_login).to_s
    url += "?#{params.to_query}" if params.present?
    url
  end

  # Public: Get the org hovercard path for the given org
  #
  # org - The String organization
  # params - The Hash of params to be added to the path
  def org_hovercard_path(org:, params: {})
    return nil unless org

    org = org.to_s
    url = ORG_HOVERCARD_PATH_TEMPLATE.expand(org_login: org).to_s
    url += "?#{params.to_query}" unless params.empty?
    url
  end

  # Public: Build data attributes to add hovercard support to an organization link
  #
  # login - The login for the organization as a String
  # tracking [Boolean] (optional) - If true, include octolytics tracking attributes (octo-click, octo-dimensions)
  # url_params [Hash] (optional) - Additional url parameters to include in the hovercard request
  #
  # Returns a hash that can be passed as the `data` argument to a rails tag helper
  # Returns an empty hash if `login` is `nil`
  def hovercard_data_attributes_for_org(login:, tracking: true, url_params: {})
    return {} unless login

    hovercard_url = org_hovercard_path(org: login, params: url_params)
    data = { "hovercard-type" => "organization", "hovercard-url" => hovercard_url }

    if tracking
      data.merge!(
        "octo-click" => "hovercard-link-click",
        "octo-dimensions" => "link_type:self",
      )
    end
    data
  end

  # Public: returns the sso path with the given return_to query param
  #
  # Returns a String url
  def org_sso_path(path:, return_to: nil)
    Addressable::Template.new(ORG_SSO_PATH % { path: path }).expand(return_to: return_to)
  end

  def hovercard_data_attributes_for_commit(commit_url:)
    return {} if atom_feed?

    {
      "hovercard-type" => "commit",
      "hovercard-url" => [commit_url, "hovercard"].join("/"),
    }
  end

  def hovercard_data_attributes_for_advisory(ghsa_id:)
    {
      "hovercard-type": "advisory",
      "hovercard-url":  ADVISORY_HOVERCARD_PATH_TEMPLATE.expand(ghsa_id: ghsa_id).to_s,
    }
  end

  def hovercard_data_attributes_for_cwe(id:, hide_link: false)
    {
      "hovercard-type": "cwe",
      "hovercard-url": CWE_HOVERCARD_PATH_TEMPLATE.expand(id: id, query: { hide_link: (true if hide_link) }.compact).to_s
    }
  end

  def hovercard_data_attributes_for_sponsors_listing(sponsorable_login:)
    return {} if !sponsorable_login
    {
      "hovercard-type" => "sponsors_listing",
      "hovercard-url" => hovercard_url_for_sponsors_listing(sponsorable_login: sponsorable_login),
    }
  end

  def hovercard_url_for_sponsors_listing(sponsorable_login:)
    SPONSORS_LISTING_HOVERCARD_PATH_TEMPLATE.expand(sponsorable_login: sponsorable_login).to_s
  end

  # Public: get hydro-click data attributes for a
  # clickable area within the hovercard body.
  #
  # click_target [String] - the name of the clickable hovercard area ex. [hovercard type]:[hovercard area (optional)]
  # data [Hash] (optional) - the params to pass to the hovercard.
  #
  # Some `data` gotchas:
  # - Values in data[:payload] that are strings with potential integers will be converted to integers.
  # This is because we are receiving the data as query params and we need to convert the values to integers for most hydro schema types.
  # - If data[:hover_target] is provided, it will be appended with the hovercard click area in the final payload to specify which element triggered the hovercard.
  # - If data[:event_type] is provided, it will override the default value of "hovercard_click"
  #
  # Examples
  #
  #   hovercard_click_hydro_attrs("user_hovercard")
  #   => {
  #        hydro-click: {
  #          event_type: "hovercard.click",
  #          payload: {
  #            hover_target: "user_hovercard"
  #          },
  #        },
  #        hydro-click-hmac: "SOME_HMAC"
  #      }
  #
  #   hovercard_click_hydro_attrs("user_hovercard:avatar", data: { event_type: "feeds.feed_click", hover_target: "feed_user_login", payload: { card_id: "3" }})
  #   => {
  #        hydro-click: {
  #          event_type: "feeds.feed_click",
  #          payload: {
  #            click_target: "feed_user_login:user_hovercard:avatar",
  #            card_id: 3, // note that card_id is converted to an integer
  #          },
  #        },
  #        hydro-click-hmac: "SOME_HMAC"
  #      }
  # Returns a hash of attributes to be passed as a rails tag helper's `data` keyword or `hydro_data` where available
  def hovercard_click_hydro_attrs(click_target, data: {})
    event = data[:event_type] || "hovercard.click"
    click_target = data[:hover_target] ? "#{data[:hover_target]}:#{click_target}" : click_target

    payload = data[:payload] || {}
    payload[:click_target] = click_target

    payload.deep_transform_values! do |v|
      integer_from_string(v) unless v.blank?
    end

    hydro_click_tracking_attributes(event, payload)
  end

  private

  # Private: extracts the integer value from a string if it is integer-like
  # otherwise returns the original string value
  #
  # str [String] - a string that may contain an integer
  #
  # Examples
  # integer_from_string("3") => 3
  # integer_from_string("asdf1234") => "asdf1234"
  # integer_from_string("not an integer") => "not an integer"
  def integer_from_string(str)
    str.to_i.to_s == str.to_s ? str.to_i : str
  end

  # Returns the path for Copilot's hovercard.
  # This path is used to display additional information about Copilot in a hovercard.
  # Example usage:
  #   copilot_hovercard_path(bot_slug: 'bot_123', params: { foo: 'bar' })
  # @param bot_slug [String] the slug of the bot
  # @param params [Hash] additional parameters for the hovercard
  # @return [String] the path to Copilot's hovercard
  def copilot_hovercard_path(bot_slug:, params: {})
    return if bot_slug.nil?

    url = COPILOT_HOVERCARD_PATH_TEMPLATE.expand(bot_slug: bot_slug).to_s
    if params.present?
      separator = url.include?("?") ? "&" : "?"
      url += "#{separator}#{params.to_query}"
    end
    url
  end

  def hovercard_data_attributes_for_copilot_bot(bot_slug, tracking: true, url_params: {})
    return {} if !bot_slug

    data = {
      "hovercard-type" => "copilot",
      "hovercard-url" => copilot_hovercard_path(bot_slug: bot_slug, params: url_params)
    }

    if tracking
      data.merge!(
        "octo-click" => "hovercard-link-click",
        "octo-dimensions" => "link_type:self",
      )
    end

    data
  end
end
