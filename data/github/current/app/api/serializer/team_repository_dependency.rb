# typed: false
# frozen_string_literal: true

module Api::Serializer::TeamRepositoryDependency
  include CustomPropertiesHelper
  # Creates a hash of the repo and which permissions the specified team has for
  # it, to be serialized to JSON.
  #
  # repo    - Team Repository instance.
  # options - Hash
  #           :team - a Team Instance
  #
  # Returns a Hash with the repository attributes and a :permissions Hash with
  # :admin, :push, and :pull keys and boolean values.
  # If the repo does not exist, it returns nil
  #
  def team_repo_hash(repo, options = {})
    return nil if !repo
    options = Api::SerializerOptions.from(options)

    # Fix for #37741. These attributes require a routed repo, but since
    # this serializer method is used in lists, we can't just bail on the
    # whole repo.
    default_branch = "master"

    begin
      default_branch = repo.default_branch
    rescue GitRPC::RepositoryOffline => boom
      Failbot.push app: "github-unrouted"
      Failbot.report boom
    end

    return nil unless hash = simple_repository_hash(repo, options)

    team = options.team

    hash.update \
      created_at: time(repo.created_at),
      updated_at: time(repo.updated_at),
      pushed_at: time(repo.pushed_at),
      git_url: repo.gitweb_url_for_api(serialize_login: options[:serialize_login]),
      ssh_url: repo.ssh_url_for_api(serialize_login: options[:serialize_login]),
      clone_url: repo.clone_url_for_api(serialize_login: options[:serialize_login]),
      svn_url: repo.svn_url_for_api(serialize_login: options[:serialize_login]),
      homepage: repo.homepage,
      size: repo.disk_usage.to_i,
      stargazers_count: repo.stargazer_count,
      watchers_count: repo.stargazer_count,
      language: repo.primary_language_name,
      has_issues: repo.has_issues?,
      has_projects: repo.has_projects_enabled?,
      has_downloads: repo.has_downloads?,
      has_wiki: repo.has_wiki?,
      has_pages: repo.page.present?,
      forks_count: repo.forks_count,
      mirror_url: repo.mirror? ? repo.mirror.url : nil,
      archived: repo.archived?,
      disabled: repo.disabled?,
      open_issues_count: repo.open_issues_count,
      license: license_hash(repo.license, options),
      allow_forking: repo.allows_forking?

    hash[:topics] = repo.topic_names
    hash[:visibility] = repo.visibility

    if options.accepts_semantic_version?("extended-search-results") && options[:license].nil?
      hash[:license] = license_hash(repo.license, options)
    end

    # DEPRECATED: These attributes will be removed in API v4.
    hash.update \
      forks: hash[:forks_count],
      open_issues: hash[:open_issues_count],
      watchers: hash[:watchers_count]

    hash[:default_branch] = default_branch


    hash[:master_branch] = default_branch if options.wants_beta_media_type? && !options.changeset_active?(:deprecate_beta_media_type)

    if options[:generate_temp_clone_token]
      hash[:temp_clone_token] = repo.temp_clone_token(options[:current_user])
    end

    if options[:show_merge_settings]
      hash[:allow_squash_merge] = repo.squash_merge_allowed?
      hash[:allow_merge_commit] = repo.merge_commit_allowed?
      hash[:allow_rebase_merge] = repo.rebase_merge_allowed?
      hash[:allow_auto_merge] = repo.auto_merge_allowed?
      hash[:delete_branch_on_merge] = repo.delete_branch_on_merge?
    end

    if GitHub.anonymous_git_access_enabled?
      hash[:anonymous_access_enabled] = repo.anonymous_git_access_enabled?
    end

    hash[:permissions] = permissions_hash(repo, actor: team)
    hash[:role_name] = team.async_most_capable_action_or_role_for(repo, include_custom_roles: true, role_priority: true).sync

    hash.delete(:has_downloads) if options.changeset_active?(:remove_has_downloads)

    hash
  end

  # Creates a hash of the repo to be serialized to JSON.
  #
  # repo    - Team repository instance.
  # options - Hash
  #           :team - a Team Instance
  #
  # Returns a Hash if the team repository exists with the custom properties, or nil.
  def team_repo_with_custom_properties_hash(repo, options = {})
    hash = team_repo_hash(repo, options)
    return nil unless hash

    hash[:custom_properties] = repo_custom_properties_hash(repo) if repo.owner&.organization?

    hash
  end
end
