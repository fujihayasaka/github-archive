# typed: true
# frozen_string_literal: true

module Api::Serializer::LegacyDependency
  include Api::Serializer

  def legacy_issue_search_result_hash(issue, options = nil)
    hash = {
      labels: issue.labels.map { |l| l.to_s },
      votes: 0,
      number: issue.number,
      position: issue.position,
      title: issue.title,
      body: issue.body,
      user: issue.user.try(:login),
      gravatar_id: "",
      state: issue.state,
      comments: issue.issue_comments_count,
    }

    url = issue.url
    if issue.pull_request_id
      url = url.sub(/\/issues\/(\d+)$/, '/pull/\1')
      hash.update \
        pull_request_url: url,
        diff_url: "#{url}.diff",
        patch_url: "#{url}.patch"
    end
    hash[:html_url] = url

    [:updated_at, :created_at, :closed_at].each do |field|
      if timestamp = issue.send(field)
        hash[field] = time(timestamp)
      end
    end

    hash
  end

  def legacy_repository_search_result_hash(repository, options = nil)
    options = Api::Serializer::LegacySearchOptions.from(options)
    search_hit = options.search_hit
    hash = {
      type: "repo",
      username: repository.owner.try(:login).to_s,
      name: repository.name,
      owner: repository.owner.try(:login).to_s,
      homepage: repository.homepage,
      description: repository.description.to_s,
      language: repository.primary_language_name.to_s,
      watchers: search_hit["followers"].to_i,
      followers: search_hit["followers"].to_i,
      forks: search_hit["forks"].to_i,
      size: search_hit["size"].to_i,
      open_issues: repository.issues.open_issues.count,
      score: options.score,
      has_downloads: repository.has_downloads?,
      has_issues: repository.has_issues?,
      has_projects: repository.has_projects_enabled?,
      has_wiki: repository.has_wiki?,
      fork: repository.fork?,
      private: repository.private?,
      url: repository.permalink,
      created: time(repository.created_at),
      created_at: time(repository.created_at),
      pushed_at: time(repository.pushed_at),
      pushed: time(repository.pushed_at),
    }

    hash.delete(:has_downloads) if options.changeset_active?(:remove_has_downloads)

    hash
  end

  def legacy_user_search_result_hash(user, options = nil)
    options = Api::Serializer::LegacySearchOptions.from(options)
    search_hit = options.search_hit
    created_at = time(time_from_string(search_hit["created_at"]))
    profile_name = search_hit["name"]
    {
      id: "user-#{user.id}",
      gravatar_id: "",
      username: user.login_for_api,
      login: user.login_for_api,
      name: profile_name,
      fullname: profile_name,
      location: search_hit["location"],
      language: Search.language_name_from_id(search_hit["language_id"]),
      type: "user",
      public_repo_count: search_hit["repos"].to_i,
      repos: search_hit["repos"].to_i,
      followers: search_hit["followers"].to_i,
      followers_count: search_hit["followers"].to_i,
      score: options.score,
      created_at: created_at,
      created: created_at,
    }
  end

  def legacy_user_email_result_hash(user, options = nil)
    hash = {
      public_repo_count: user.public_repositories.size.to_i,
      public_gist_count: user.public_gists.size.to_i,
      followers_count: user.followers_count(viewer: nil).to_i,
      following_count: user.following_count(viewer: nil).to_i,
      created: time(user.created_at),
      created_at: time(user.created_at),
      gravatar_id: "",
    }

    if profile = user.profile
      [:name, :company, :blog, :location, :email].each do |field|
        hash[field] = profile.send(field)
      end
    end

    [:id, :login, :type].each do |field|
      hash[field] = user.send(field)
    end

    hash
  end

end
