# typed: false
# frozen_string_literal: true

module DesktopHelper
  include UrlHelper

  # The URL to use for GitHub Desktop links if the user doesn't have Desktop
  # installed.
  DESKTOP_URL = "https://desktop.github.com"

  def app_clone_url(repo = nil, pull_request = nil, branch = nil, filepath = nil)
    return DESKTOP_URL unless desktop_urls_enabled?

    repo ||= current_repository

    uri = Addressable::URI.new
    uri.scheme = "x-github-client"
    uri.host = "openRepo"
    if repo.is_a? GitHub::Unsullied::Wiki
      uri.path = File.join(host_for_repo(repo), repo.short_git_path)
    elsif repo.is_a? Gist
      uri.path = File.join(host_for_repo(repo), repo.short_git_path)
    else
      uri.path = repository_url(repo)
    end
    return uri.to_s unless pull_request || branch

    params = {}
    if pull_request
      if pull_request.head_repository? && pull_request.head_repository.id != pull_request.base_repository.id
        pr_num = pull_request.number
        params["pr"] = pr_num
        params["branch"] = "pr/#{pr_num}"
      else
        params["branch"] = pull_request.head_ref_name
      end
    end

    params["branch"] = branch if branch
    params["filepath"] = filepath if filepath

    uri.query_values = params
    uri.to_s
  end

  def desktop_urls_enabled?
    return true if Rails.env.development?

    logged_in? && current_user.desktop_app_enabled?
  end
end
