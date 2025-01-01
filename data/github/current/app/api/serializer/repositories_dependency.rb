# typed: true
# frozen_string_literal: true

module Api::Serializer::RepositoriesDependency
  extend T::Helpers
  extend T::Sig

  include AvatarHelper
  include Kernel
  include Scientist
  include Api::App::ContentHelpers
  include CustomPropertiesHelper

  requires_ancestor { Api::Serializer }
  requires_ancestor { Api::Serializer::UserDependency }
  requires_ancestor { Api::Serializer::LicensesDependency }
  requires_ancestor { Api::Serializer::ReactionsDependency }
  requires_ancestor { Api::Serializer::GitDataDependency }
  requires_ancestor { Api::Serializer::CodesOfConductDependency }

  def disabled_repository_hash(repo, options = {})
    return nil if !repo

    message   = "Repository access blocked"

    if repo.access.disabled?
      reason    = repo.access.disabling_reason
      timestamp = repo.access.disabled_at
    elsif repo.network.nil?
      timestamp = repo.updated_at
    elsif repo.network_broken?
      reason    = "broken"
      timestamp = repo.network.updated_at
    elsif repo.trade_restricted?
      message = repo.trade_restriction_api_error_message(repo.actor)
      timestamp = repo.updated_at
    end

    valid_reasons = GitRepositoryAccess::REASONS - ["broken"]
    reason = "unavailable" unless valid_reasons.include?(reason)

    url = if GitHub.enterprise?
      "#{GitHub.enterprise_admin_help_url}/guides/installation/troubleshooting/"
    elsif reason == "dmca"
      repo.access.dmca_url
    else
      "#{GitHub.scheme}://#{GitHub.host_name}/tos"
    end

    response = {
                message: message,
                block: {
                  reason: reason,
                  created_at: time(timestamp),
                  html_url: url,
                },
               }

    response
  end

  sig { params(repo: T.nilable(Repositories::IRepository), options: T.untyped).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
  def repository_identifier_hash(repo, options)
    return nil unless repo && T.cast(repo, Repository).network.present? # rubocop:todo GitHub/AvoidCast

    {
      id: repo.id,
      node_id: global_id_for(repo, options),
      name: repo.name,
      full_name: repo.name_with_owner_for_api(use: options[:serialize_login]),
      private: repo.private?,
    }
  end

  # Creates a Hash to be serialized to JSON.
  #
  # repo    - Repository instance.
  # options - Hash
  #           :include_timestamps - Optional Boolean specifying whether to
  #                                 include repo timestamp information.
  #
  # Returns a Hash if the Repository exists, or nil.
  sig { params(repo: T.nilable(Repositories::IRepository), options: T.untyped).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
  def simple_repository_hash(repo, options = {})
    return nil unless repo && T.cast(repo, Repository).network.present? # rubocop:todo GitHub/AvoidCast
    options = Api::SerializerOptions.from(options)
    repo_api_path = "/repos/#{repo.name_with_owner_for_api(use: options[:serialize_login])}"
    url = url(repo_api_path, options)

    h = {
      owner: user_hash(T.cast(repo, Repository).owner, content_options(options)), # rubocop:todo GitHub/AvoidCast
      html_url: repo.permalink,
      description: repo.description,
      fork: repo.fork?,
      url: url,
    }

    if options[:include_timestamps]
      h.update \
        created_at: time(repo.created_at),
        updated_at: time(repo.updated_at),
        pushed_at: time(repo.pushed_at)
    end

    repository_identifier_hash(repo, options)
      &.merge(h)
      &.merge(repository_url_fields(url, repo_api_path, options))
  end

  def push_hash(push, options = {})
    {
      id: push.id,
      node_id: global_id_for(push, options),
      before: push.before,
      after: push.after,
      ref: push.ref,
      timestamp: time(push.pushed_at),
      activity_type: push.push_type,
      actor: user_hash(push.pusher, options)
    }
  end

  def graphql_simple_repository_hash(repo, options = {})
    repo = SimpleRepositoryFragment.new(repo)
    return nil unless repo && repo.network_present
    options = Api::SerializerOptions.from(options)
    # Hash is used specifically for GraphQL and login in GraphQL already return display login
    name_with_owner = "#{repo.owner.login}/#{repo.name}" # rubocop:disable GitHub/DoNotAllowLogin
    repo_api_path = "/repos/#{name_with_owner}"
    url = url(repo_api_path, options)

    hash = {
      id: repo.database_id,
      node_id: repo.id,
      name: repo.name,
      full_name: name_with_owner,
      owner: graphql_simple_user_hash(repo.owner, content_options(options)),
      private: repo.is_private,
      html_url: repo.permalink.to_s,
      description: repo.description,
      fork: repo.is_fork,
      url: url,
      topics: repo.repository_topics.nodes.map { |rt| rt.topic.name },
    }.merge(repository_url_fields(url, repo_api_path, options))

    hash
  end

  def repository_url_fields(url, repo_api_path, options)
    {
      url: url,
      forks_url: url("#{repo_api_path}/forks", options),
      keys_url: url("#{repo_api_path}/keys{/key_id}", options),
      collaborators_url: url("#{repo_api_path}/collaborators{/collaborator}", options),
      teams_url: url("#{repo_api_path}/teams", options),
      hooks_url: url("#{repo_api_path}/hooks", options),
      issue_events_url: url("#{repo_api_path}/issues/events{/number}", options),
      events_url: url("#{repo_api_path}/events", options),
      assignees_url: url("#{repo_api_path}/assignees{/user}", options),
      branches_url: url("#{repo_api_path}/branches{/branch}", options),
      tags_url: url("#{repo_api_path}/tags", options),
      blobs_url: url("#{repo_api_path}/git/blobs{/sha}", options),
      git_tags_url: url("#{repo_api_path}/git/tags{/sha}", options),
      git_refs_url: url("#{repo_api_path}/git/refs{/sha}", options),
      trees_url: url("#{repo_api_path}/git/trees{/sha}", options),
      statuses_url: url("#{repo_api_path}/statuses/{sha}", options),
      languages_url: url("#{repo_api_path}/languages", options),
      stargazers_url: url("#{repo_api_path}/stargazers", options),
      contributors_url: url("#{repo_api_path}/contributors", options),
      subscribers_url: url("#{repo_api_path}/subscribers", options),
      subscription_url: url("#{repo_api_path}/subscription", options),
      commits_url: url("#{repo_api_path}/commits{/sha}", options),
      git_commits_url: url("#{repo_api_path}/git/commits{/sha}", options),
      comments_url: url("#{repo_api_path}/comments{/number}", options),
      issue_comment_url: url("#{repo_api_path}/issues/comments{/number}", options),
      contents_url: url("#{repo_api_path}/contents/{+path}", options),
      compare_url: url("#{repo_api_path}/compare/{base}...{head}", options),
      merges_url: url("#{repo_api_path}/merges", options),
      archive_url: url("#{repo_api_path}/{archive_format}{/ref}", options),
      downloads_url: url("#{repo_api_path}/downloads", options),
      issues_url: url("#{repo_api_path}/issues{/number}", options),
      pulls_url: url("#{repo_api_path}/pulls{/number}", options),
      milestones_url: url("#{repo_api_path}/milestones{/number}", options),
      notifications_url: url("#{repo_api_path}/notifications{?since,all,participating}", options),
      labels_url: url("#{repo_api_path}/labels{/name}", options),
      releases_url: url("#{repo_api_path}/releases{/id}", options),
      deployments_url: url("#{repo_api_path}/deployments", options),
    }
  end

  # Creates a Hash to be serialized to JSON.
  #
  # repo    - Repository instance.
  # options - Hash
  #           :full - Boolean specifying we want the extended output.
  #
  # Returns a Hash if the Repository exists, or nil.
  sig do
    params(
      repo: T.nilable(Repositories::IRepository),
      options: T.untyped
    ).returns(T.nilable(T::Hash[T.untyped, T.untyped]))
  end
  def repository_hash(repo, options = {})
    return nil if !repo
    options = Api::SerializerOptions.from(options)

    # Fix for #37741. These attributes require a routed repo, but since
    # this serializer method is used in lists, we can't just bail on the
    # whole repo.
    default_branch = begin
      repo.default_branch
    rescue GitRPC::RepositoryOffline => boom
      Failbot.push app: "github-unrouted"
      Failbot.report boom
      if repo.fork?
        T.must(T.cast(repo, Repository).parent).default_branch # rubocop:todo GitHub/AvoidCast
      elsif T.cast(repo, Repository).template_repository_clone # rubocop:todo GitHub/AvoidCast
        T.must(T.must(T.cast(repo, Repository).template_repository_clone).template_repository).default_branch # rubocop:todo GitHub/AvoidCast
      else
        repo.owner_default_new_repo_branch
      end
    end

    return nil unless hash = simple_repository_hash(repo, options)

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
      has_wiki: repo.has_wiki? && T.cast(repo, Repository).plan_supports?(:wikis), # rubocop:todo GitHub/AvoidCast
      has_pages: T.cast(repo, Repository).page.present?, # rubocop:todo GitHub/AvoidCast
      has_discussions: repo.discussions_active?,
      forks_count: repo.forks_count,
      mirror_url: repo.mirror? ? T.must(T.cast(repo, Repository).mirror).url : nil, # rubocop:todo GitHub/AvoidCast
      archived: repo.archived?,
      disabled: repo.disabled? || T.cast(repo, Repository).access&.disabled?, # rubocop:todo GitHub/AvoidCast
      open_issues_count: repo.open_issues_count,
      license: license_hash(repo.license, content_options(options)),
      allow_forking: repo.allows_forking?,
      is_template: repo.template?,
      web_commit_signoff_required: repo.dco_signoff_enabled?

    hash[:topics] = repo.topic_names
    hash[:visibility] = repo.visibility

    if options.accepts_semantic_version?("extended-search-results") && options[:license].nil?
      hash[:license] = license_hash(repo.license, content_options(options))
    end

    # DEPRECATED: These attributes will be removed in API v4.
    hash.update \
      forks: hash[:forks_count],
      open_issues: hash[:open_issues_count],
      watchers: hash[:watchers_count]

    hash[:default_branch] = default_branch

    # [DEPRECATED] Use default_branch instead.
    hash[:master_branch] = default_branch if options.wants_beta_media_type? && !options.changeset_active?(:deprecate_beta_media_type)

    if options[:current_user].present?
      hash[:permissions] = permissions_hash(repo, actor: options[:current_user])
    end

    if options[:generate_temp_clone_token]
      hash[:temp_clone_token] = T.cast(repo, Repository).temp_clone_token(options[:current_user]) # rubocop:todo GitHub/AvoidCast
    end

    if options[:show_merge_settings]
      hash[:allow_squash_merge] = repo.squash_merge_allowed?
      hash[:allow_merge_commit] = repo.merge_commit_allowed?
      hash[:allow_rebase_merge] = repo.rebase_merge_allowed?
      hash[:allow_auto_merge] = repo.auto_merge_allowed?
      hash[:delete_branch_on_merge] = repo.delete_branch_on_merge?
      hash[:allow_update_branch] = repo.enable_update_branch?
      unless options.changeset_active?(:remove_use_squash_pr_title_as_default)
        hash[:use_squash_pr_title_as_default] = repo.squash_pr_title_enabled?
      end
      hash[:squash_merge_commit_message] = repo.squash_merge_commit_message_setting
      hash[:squash_merge_commit_title] = repo.squash_merge_commit_title_setting
      hash[:merge_commit_message] = repo.merge_commit_message_setting
      hash[:merge_commit_title] = repo.merge_commit_title_setting
    end

    if options.dig(:show_repo_security_settings, repo.id)
      hash[:security_and_analysis] = security_and_analysis_hash(T.cast(repo, Repository), options) # rubocop:todo GitHub/AvoidCast
    end

    if GitHub.anonymous_git_access_enabled?
      hash[:anonymous_access_enabled] = repo.anonymous_git_access_enabled?
    end

    hash.delete(:has_downloads) if options.changeset_active?(:remove_has_downloads)

    hash
  end

  # Creates a Hash to be serialized to JSON.
  #
  # repo    - Repository instance.
  # options - Hash
  #           :full - Boolean specifying we want the extended output.
  #
  # Returns a Hash if the Repository exists with the custom properties, or nil.
  def repository_with_custom_properties_hash(repo, options = {})
    hash = repository_hash(repo, options)
    return nil unless hash

    if repo.owner&.organization?
      hash[:custom_properties] = repo_custom_properties_hash(repo)
    end

    hash
  end

  # GraphQL versions of permissions_hash

  def graphql_permissions_hash(object, options = {})
    raise ArgumentError unless object

    permission = RepositoryPermissionFragment.new(object).permission
    Repository.permissions_hash(permission)
  end

  def graphql_repository_hash(repo, options = {})
    return nil unless repo

    repo = RepositoryFragment.new(repo)
    options = Api::SerializerOptions.from(options)

    hash = graphql_simple_repository_hash(repo, options)
    return if hash.nil?

    hash.update \
      created_at: time(repo.created_at),
      updated_at: time(repo.updated_at),
      pushed_at: time(repo.pushed_at),
      git_url: repo.git_url.to_s,
      ssh_url: repo.ssh_url.to_s,
      clone_url: repo.clone_url.to_s,
      svn_url: repo.svn_url.to_s,
      homepage: repo.homepage_url&.to_s,
      size: repo.disk_usage,
      stargazers_count: repo.stargazers.total_count,
      watchers_count: repo.stargazers.total_count,
      language: repo.primary_language&.name,
      has_issues: repo.has_issues_enabled?,
      has_projects: repo.has_projects_enabled?,
      has_downloads: repo.has_downloads?,
      has_wiki: repo.has_wiki_enabled?,
      has_pages: repo.has_pages?,
      forks_count: repo.forks.total_count,
      mirror_url: repo.mirror_url&.to_s,
      archived: repo.is_archived?,
      disabled: repo.is_disabled?,
      open_issues_count: repo.issues.total_count + repo.pull_requests.total_count,
      license: graphql_simple_license_hash(repo.license_info),
      allow_forking: repo.forking_allowed?,
      is_template: repo.is_template?

    hash.update \
      forks: hash[:forks_count],
      open_issues: hash[:open_issues_count],
      watchers: hash[:watchers_count]

    hash[:default_branch] = repo.default_branch

    if options[:current_user]
      hash[:permissions] = graphql_permissions_hash(repo, options)
    end

    if options[:generate_temp_clone_token]
      hash[:temp_clone_token] = repo.temp_clone_token
    end

    hash[:visibility] = repo.visibility

    if options[:show_merge_settings]
      hash[:allow_squash_merge] = repo.squash_merge_allowed?
      hash[:allow_merge_commit] = repo.merge_commit_allowed?
      hash[:allow_rebase_merge] = repo.rebase_merge_allowed?
      hash[:allow_auto_merge] = repo.auto_merge_allowed?
      hash[:delete_branch_on_merge] = repo.delete_branch_on_merge?
      unless options.changeset_active?(:remove_use_squash_pr_title_as_default)
        hash[:use_squash_pr_title_as_default] = repo.squash_pr_title_enabled?
      end
      hash[:squash_merge_commit_message] = repo.squash_merge_commit_message_setting
      hash[:squash_merge_commit_title] = repo.squash_merge_commit_title_setting
      hash[:merge_commit_message] = repo.merge_commit_message_setting
      hash[:merge_commit_title] = repo.merge_commit_title_setting
    end

    if GitHub.anonymous_git_access_enabled?
      hash[:anonymous_access_enabled] = repo.has_anonymous_access_enabled?
    end

    hash.delete(:has_downloads) if options.changeset_active?(:remove_has_downloads)

    hash
  end

  def full_repository_hash(repo, options)
    return nil if !repo

    options = Api::SerializerOptions.from(options)

    return nil unless hash = repository_hash(repo, options)

    if options[:show_template_repository]
      hash[:template_repository] = if (template = repo.template_repository)
        repository_hash(template, options)
      end
    end

    if repo.owner&.organization?
      hash[:custom_properties] = repo_custom_properties_hash(repo)
    end

    if org = repo.organization
      hash[:organization] = user_hash(org, content_options(options))
    end

    if parent = repo.parent
      hash[:parent] = repository_hash(parent, content_options(options))
    end

    if (root = repo.root) && root.id != repo.id
      hash[:source] = repository_hash(root, content_options(options))
    end

    # The option `show_security_settings` is set depending on whether the user can see this information.
    # It currently only accounts for the permission required to see advanced security.
    # When adding more security products, we need to consider if different permissions are required
    # and if so we might want to revisit how we build this object.
    if options.show_security_settings
      hash[:security_and_analysis] = security_and_analysis_hash(repo, options)
    end

    hash.update \
      network_count: repo.network_count,
      subscribers_count: repo.watchers_count

    hash
  end

  sig { params(repo: Repository, options: T.untyped).returns(T::Hash[T.untyped, T.untyped]) }
  def security_and_analysis_hash(repo, options)
    push_protection = SecretScanning::Features::Repo::PushProtection.new(repo)
    validity_checks = SecretScanning::Features::Repo::ValidityChecks.new(repo)
    lower_confidence_patterns = SecretScanning::Features::Repo::LowerConfidencePatterns.new(repo)

    hash = {}
    # it's possible to have secret scanning without GHAS for public repos
    if repo.advanced_security_configurable?
      hash[:advanced_security] = {
        status: repo.advanced_security_enabled? ? "enabled" : "disabled"
      }
    end

    hash[:secret_scanning] = {
      status: SecretScanning::Features::Repo::TokenScanning.new(repo).enabled? ? "enabled" : "disabled"
    }
    hash[:secret_scanning_push_protection] = {
      status: push_protection.enabled? ? "enabled" : "disabled"
    }
    hash[:dependabot_security_updates] = {
      status: SecurityProduct::VulnerabilityUpdates.new(repo).enabled? ? "enabled" : "disabled"
    }
    if lower_confidence_patterns.enablement_api_available?
      hash[:secret_scanning_non_provider_patterns] = {
        status: lower_confidence_patterns.enabled? ? "enabled" : "disabled"
      }
    end
    if !GitHub.single_or_multi_tenant_enterprise?
      hash[:secret_scanning_validity_checks] = {
        status: validity_checks.enabled? ? "enabled" : "disabled"
      }
    end
    hash
  end

  def graphql_full_repository_hash(repo, options)
    repo = ExtendedRepositoryFragment.new(repo)
    options = Api::SerializerOptions.from(options)

    hash = graphql_repository_hash(repo, options)

    if options[:show_template_repository]
      hash[:template_repository] = if (template = repo.template_repository)
        graphql_repository_hash(template, options)
      end
    end

    if repo.owner.is_a? Api::App::PlatformTypes::Organization
      hash.update organization: hash[:owner]
    end

    hash.update \
      subscribers_count:  repo.watchers.total_count,
      network_count:      repo.network.repositories.total_count

    hash
  end

  # Returns a permissions hash, suitable for use as `hash[:permissions]` for
  # `repository_hash`.
  #
  # repo    - Repository instance.
  # options - Hash
  #           :actor - User or Team instance for computing permissions values
  #
  # Returns a Hash with :pull, :triage, :push, :maintain, and :admin keys with boolean values.
  def permissions_hash(repo, options)
    raise ArgumentError if options[:actor].nil?

    repo.permissions_hash_for(actor: options[:actor])
  end

  # Returns the name of the most permissive role a user has on a repository.
  # Suitable for use as `hash[:role]` for `repository_hash`.
  #
  # repo - Repository instance
  # options - Hash
  #           :user - user instance for computing role name.
  # Returns the name of the most permissive rold as a string.
  def role_name(repo, options = {})
    role = repo.role_based_access_level(
      options[:user],
      include_custom_roles: repo.owner.custom_roles_supported?
    )
    if role.respond_to?(:name)
      role.name
    else
      role
    end
  end

  # Creates a Hash to be serialized to JSON.
  #
  # comment - CommitComment instance.
  # options - Hash
  #           :repo - Optional Repository instance.
  #
  # Returns a Hash if the CommitComment exists, or nil.
  def commit_comment_hash(comment, options = {})
    return nil if !comment

    options = Api::SerializerOptions.from(options)
    repo = repo_path(options, comment)

    hash = {
      url: url("/repos/#{repo}/comments/#{comment.id}", options),
      html_url: comment.full_permalink,
      id: comment.id,
      node_id: global_id_for(comment, options),
      user: user_hash(comment.user, content_options(options)),
      position: comment.position,
      line: comment.line,
      path: comment.path,
      commit_id: comment.commit_id,
      created_at: time(comment.created_at),
      updated_at: time(comment.updated_at),
      author_association: comment.author_association(options[:current_user]).to_s,
    }.update(mime_body_hash(comment, options))

    hash[:reactions] = reactions_rollup(comment, url("/repos/#{repo}/comments/#{comment.id}/reactions", options))
    hash
  end

  # Creates a Hash to be serialized to JSON.
  #
  # diff_entry - GitHub::Diff::Entry instance.
  # options    - Hash
  #              :repo - Optional Repository instance.
  #
  # Returns a Hash if the GitHub::Diff::Entry exists, or nil.
  def condensed_diff_entry_hash(diff_entry, options = {})
    return nil if !diff_entry

    options = Api::SerializerOptions.from(options)
    repo = repo_path(options, diff_entry)

    hash = {
      sha: diff_entry.b_blob || diff_entry.a_blob,
      filename: diff_entry.path,
      status: diff_entry.status_label,
      additions: diff_entry.additions,
      deletions: diff_entry.deletions,
      changes: diff_entry.changes,
      blob_url: diff_url(repo, diff_entry, "blob"),
      raw_url: diff_url(repo, diff_entry, "raw"),
      contents_url: diff_contents_url(repo, diff_entry),
    }

    if diff_entry.text.try(:length).to_i > 0 && !diff_entry.binary_text?
      hash[:patch] = diff_entry.unicode_text
    end

    if diff_entry.renamed?
      hash[:previous_filename] = diff_entry.a_path
    end

    hash
  end

  alias github_diff_entry_hash condensed_diff_entry_hash

  # Creates a Hash to be serialized to JSON.
  #
  # comparison - GitHub::Comparison instance.
  # options    - Hash
  #              :repo - Optional Repository instance.
  #
  # Returns a Hash if the GitHub::Comparison exists, or nil.
  def github_comparison_hash(comparison, options = {})
    return nil if !comparison

    options = Api::SerializerOptions.from(options)
    repo = repo_path(options, comparison)

    diffs = comparison.diffs
    entries = diffs.to_a

    hash = {
      url: url("/repos/#{repo}/compare/#{comparison.base}...#{comparison.head}", options),
      html_url: comparison.to_url,
      permalink_url: comparison.to_permalink_url,
      diff_url: comparison.to_diff_url,
      patch_url: comparison.to_patch_url,
      base_commit: git_commit_hash(comparison.base_commit, options),
      merge_base_commit: git_commit_hash(comparison.merge_base_commit, options),
      status: comparison.status,
      ahead_by: comparison.ahead_by,
      behind_by: comparison.behind_by,
      total_commits: comparison.total_commits,
      commits: commits(comparison: comparison, options: options),
    }

    # If we're paging the commits, we only want to return files on the first page
    if !options.page || options.page == 1
      hash[:files] = entries.map { |entry| condensed_diff_entry_hash(entry, options) }
    end

    hash
  end

  def commits(comparison:, options: {})
    options = Api::SerializerOptions.from(options)

    return commits_array(comparison.commits, options) unless options.page.present?

    commit_hashes_array(
      total_commits: comparison.total_commits,
      commits: comparison.paginated_commits(page: options.page, per_page: options.per_page),
      options: options
    )
  end

  # Hashify a community profile in preparation for JSON serialization.
  #
  # community_profile - A repository's community profile
  # options - Unused.
  #
  # Returns a hash.
  def community_profile_hash(community_profile, options = {})
    repository = community_profile.repository
    readme = repository.preferred_readme
    contributing = repository.preferred_contributing
    license = repository.license
    detected_code_of_conduct = community_profile.code_of_conduct
    issue_template = community_profile.issue_template
    pr_template = community_profile.pr_template
    hashed_code_of_conduct, hashed_code_of_conduct_file, hashed_contributing, hashed_license, hashed_readme, hashed_issue_template, hashed_pr_template = nil, nil, nil, nil, nil, nil

    if community_profile.code_of_conduct?
      preferred_coc = repository.preferred_code_of_conduct

      # TODO: Deprecate this in favor of `hashed_code_of_conduct_file`.
      # See https://github.com/github/self-organizing-communities/issues/32.
      hashed_code_of_conduct = code_of_conduct_hash(detected_code_of_conduct, options)

      hashed_code_of_conduct_file = {
        url: url("/repos/#{preferred_coc.repository.name_with_owner_for_api(use: options[:serialize_login])}/contents/#{preferred_coc.path}"),
        html_url: preferred_file_url(type: :code_of_conduct, repository: preferred_coc.repository),
      }
    end

    # Gets a contributing hash
    if community_profile.contributing?
      hashed_contributing = {
        url: url("/repos/#{repository.name_with_owner_for_api(use: options[:serialize_login])}/contents/#{contributing.path}"),
        html_url: preferred_file_url(type: :contributing, repository: contributing.repository),
      }
    end

    # Gets the license hash
    if license
      hashed_license = license_hash(license, options).except(:featured)
      hashed_license[:html_url] = preferred_file_url(type: :license, repository: repository)
    end

    # Gets a readme hash
    if community_profile.readme?
      hashed_readme = {
        url: url("/repos/#{repository.name_with_owner_for_api(use: options[:serialize_login])}/contents/#{readme.path}"),
        html_url: preferred_file_url(type: :readme, repository: repository),
      }
    end

    # Gets an issue template hash
    if !!issue_template
      hashed_issue_template = {
        url: url("/repos/#{issue_template.repository.name_with_owner_for_api(use: options[:serialize_login])}/contents/#{issue_template.path}"),
        html_url: preferred_file_url(type: :issue_template, repository: issue_template.repository),
      }
    end

    # Gets a pull request template hash
    if !!pr_template
      hashed_pr_template = {
        url: url("/repos/#{pr_template.repository.name_with_owner_for_api(use: options[:serialize_login])}/contents/#{pr_template.path}"),
        html_url: preferred_file_url(type: :pull_request_template, repository: pr_template.repository),
      }
    end

    hash = {
      health_percentage: community_profile.health_percentage(options[:current_user]),
      description: repository.description,
      documentation: community_profile.documentation_url,
      files: {
        code_of_conduct: hashed_code_of_conduct,
        code_of_conduct_file: hashed_code_of_conduct_file,
        contributing: hashed_contributing,
        issue_template: hashed_issue_template,
        pull_request_template: hashed_pr_template,
        license: hashed_license,
        readme: hashed_readme,
      },
      updated_at: time(community_profile.updated_at),
    }

    if repository.in_organization?
      hash[:content_reports_enabled] = repository.tiered_reporting_explicitly_enabled?
    end

    hash
  end

  # Hashify a repository invitation in preparation for JSON serialization.
  #
  # invitation - A repository invitation
  # options - Unused.
  #
  # Returns a hash.
  def repository_invitation_hash(invitation, options = {})
    {
      id: invitation.id,
      node_id: global_id_for(invitation, options),
      repository: simple_repository_hash(invitation.repository, content_options(options)),
      invitee: user_hash(invitation.invitee, content_options(options)),
      inviter: user_hash(invitation.inviter, content_options(options)),
      permissions: invitation.permission_string,
      created_at: time(invitation.created_at),
      url: url("/user/repository_invitations/#{invitation.id}"),
      html_url: invitation.permalink,
    }
  end

  # Hashify a repository invitation in preparation for JSON serialization.
  #
  # invitation - A repository invitation
  # options - Unused.
  #
  # Returns a hash.
  def fgp_repository_invitation_hash(invitation, options = {})
    {
      id: invitation.id,
      node_id: global_id_for(invitation, options),
      repository: simple_repository_hash(invitation.repository, options),
      invitee: user_hash(invitation.invitee, content_options(options)),
      inviter: user_hash(invitation.inviter, content_options(options)),
      permissions: invitation.permission_string,
      created_at: time(invitation.created_at),
      url: url("/user/repository_invitations/#{invitation.id}"),
      html_url: invitation.permalink,
      expired: invitation.invite_expired?,
    }
  end

  # Create a Hash of a user's permission level in preparation for JSON
  # serialization.
  #
  # permission - A String permission level (see Repository#access_level_for)
  # options - Expects a :user key mapping to a User instance.
  #
  # Returns a Hash.
  def repository_collaborator_permission(permission, options = {})
    user = options[:user]
    repo = options[:repo]

    {
      permission: permission,
      user: collaborator_hash(user, options),
      role_name: role_name(repo, user: user).to_s
    }
  end

  # Creates a Hash to be serialized to JSON.
  #
  # download - Download instance.
  # options  - Hash
  #            :repo - Optional Repository instance.
  #
  # Returns a Hash if the GitHub::Comparison exists, or nil.
  def download_hash(download, options = {})
    return nil if !download

    options = Api::SerializerOptions.from(options)
    repo = repo_path(options, download)
    {
      url: url("/repos/#{repo}/downloads/#{download.id}", options),
      id: download.id,
      html_url: download.full_url,
      name: download.name,
      description: download.description,
      created_at: time(download.timestamp),
      size: download.size * 1.kilobyte,
      download_count: download.hits,
      content_type: download.content_type,
    }
  end

  # Creates a Hash to be serialized to JSON.
  #
  # release - Release instance.
  # options - Hash or Api::SerializerOptions consisting of:
  #           :repo - Optional Repository instance.
  #           :assets - Optional Hash of Integer Release ID => ReleaseAsset.
  #
  # Returns a Hash if the Release exists, or nil.
  sig { params(release: T.nilable(Releases::IRelease), options: T.any(Hash, GitHub::Options)).returns(T.nilable(Hash)) }
  def release_hash(release, options = {})
    return nil if !release

    legacy_release = T.cast(release, Release)

    options = Api::SerializerOptions.from(options)

    repo = options[:repo_path] ||= repo_path(options, release)
    repo_api_path = "/repos/#{repo}"
    release_path = "#{repo_api_path}/releases/#{release.id}"

    asset_options = options.merge(release: release, repo_path: repo)
    assets = if all_assets = options[:assets]
      all_assets[release.id] || []
    else
      legacy_release.uploaded_assets
    end

    GitHub::PrefillAssociations.prefill_associations(assets, :release, available_records: [release]) if assets.present? && options[:assets]

    h = {
      url: url(release_path, options),
      assets_url: url("#{release_path}/assets", options),
      upload_url: "#{GitHub.api_upload_prefix}#{release_path}/assets{?name,label}",
      html_url: release.permalink,
      id: release.id,
      author: simple_user_hash(legacy_release.author, content_options(options)),
      node_id: global_id_for(release, options),
      tag_name: legacy_release.exposed_tag_name,
      target_commitish: legacy_release.target_commitish,
      name: release.name,
      draft: release.draft?,
      prerelease: release.prerelease?,
      created_at: time(release.created_at),
      published_at: time(release.published_at),
      assets: assets.map { |a| release_asset_hash(a, asset_options) },
      tarball_url: nil,
      zipball_url: nil,
    }

    h.update mime_body_hash(release, options)

    if release.published?
      h.update \
        tarball_url: url("#{repo_api_path}/tarball/#{release.tag_name}", options),
        zipball_url: url("#{repo_api_path}/zipball/#{release.tag_name}", options)
    end

    if legacy_release.discussion
      h[:discussion_url] = legacy_release.discussion&.permalink
    end

    if legacy_release.reactions_count.any?
      h[:reactions] = reactions_rollup(release, url("/repos/#{repo}/releases/#{release.id}/reactions", options))
    end

    if legacy_release.mentions_count > 0
      h[:mentions_count] = legacy_release.mentions_count
      if options[:include_mentions]
        # include user data like avatar urls and profile URLs for the Feed's release facepile
        h[:mentions] = user_avatar_hash(legacy_release.mentions)
      end
    end

    h
  end

  def repository_properties_effective_value_hash(property_values, options = {})
    property_values.map do |k, v|
      {
        property_name: k,
        value: v
      }
    end
  end

  def user_avatar_hash(users, options = {})
    # this has needs to contain the minimum requirements of the AvatarListComponent
    users.map do |u|
      {
        avatar_url: u.primary_avatar_url,
        login: u.login_for_api(use: options[:serialize_login]),
        profile_name: u.profile_name,
        profile_url: u.permalink,
        avatar_user_actor: avatar_user_actor?(u)
      }
    end
  end

  # Creates a Hash to be serialized to JSON.
  #
  # asset   - ReleaseAsset instance
  # options - Hash
  #           :repo - Optional Repository instance.
  #           :release - Optional Release instance.
  #           :object_cache - Optional object cache
  #
  # Returns a Hash if the ReleaseAsset exists, or nil.
  def release_asset_hash(asset, options = {})
    return nil if !asset

    user_cache = options[:object_cache]&.dig(:users)

    options = Api::SerializerOptions.from(options)
    repo = repo_path(options, asset.release)
    asset_path = "/repos/#{repo}/releases/assets/#{asset.id}"

    user_options = content_options(options)
    uploader = retrieve_uploader_hash(user_cache, asset.uploader, user_options)

    {
      url: url(asset_path, options),
      id: asset.id,
      node_id: global_id_for(asset, options),
      name: asset.name,
      label: asset.label,
      uploader: uploader,
      content_type: asset.downloadable_content_type,
      state: asset.state,
      size: asset.size,
      download_count: asset.downloads,
      created_at: time(asset.created_at),
      updated_at: time(asset.updated_at),
      browser_download_url: asset.permalink,
    }
  end

  # Creates a Hash to be serialized to JSON.
  #
  # name - Release notes name.
  # body - Release notes content
  # options - Hash
  #
  # Returns a Hash if the name and body exists, or nil.
  def release_notes_content_hash(release_notes_content, options = {})
    return nil if release_notes_content[:name].blank? || release_notes_content[:body].blank?

    {
      name: release_notes_content[:name],
      body: release_notes_content[:body],
    }
  end

  # Creates a Hash to be serialized to JSON.
  #
  # content - Api::RepositoryContents::ContentWrapper instance
  # options - Hash
  #           :repo - The Repository containing the content.
  #           :full - The Boolean specifying whether to include the extended
  #                   output.
  #
  # Returns a Hash if the ContentWrapper exists, or nil.
  def content_hash(content, options = {})
    options = Api::SerializerOptions.from(options)

    hash = if content.submodule?
      submodule_content_hash(content, options)
    elsif content.blob?
      blob_content_hash(content, options)
    else
      tree_content_hash(content, options)
    end

    # Backwards compatibility
    hash[:_links] = {
      self: hash[:url],
      git: hash[:git_url],
      html: hash[:html_url],
    }

    hash
  end

  # Creates a Hash to be serialized to JSON.
  #
  # autolink - Autolink reference instance.
  # options - Unused.
  #
  # Returns a Hash if the Autolink exists, or nil.
  def autolink_hash(autolink, options = {})
    return nil if !autolink
    {
      id: autolink.id,
      key_prefix: autolink.key_prefix,
      url_template: autolink.url_template,
      is_alphanumeric: autolink.is_alphanumeric,
    }
  end

  # Internal: Creates a Hash containing the elements that are common amongst all
  # JSON responses provided for "content" (i.e., trees, blobs, submodules).
  #
  # common  - Api::RepositoryContents::ContentWrapper instance representing
  # options - Hash
  #           :repo - The Repository containing the content.
  #
  # Returns a Hash if the ContentWrapper exists, or nil.
  def common_content_hash(content, options = {})
    return nil if content.nil?

    repo = options[:repo]
    repo_nwo = repo_path(options, content)

    ref = options[:ref] ||= repo.default_branch

    hash = {
      name: content.name,
      path: content.path,
      sha: content.sha,
      size: content.size,
      url: encoded_content_url("/repos/#{repo_nwo}/contents/", content.path, { ref: ref.b }),
      html_url: nil,
      git_url: nil,
      download_url: nil,
    }

    hash
  end

  # Internal: Creates a Hash to be serialized to JSON.
  #
  # tree    - Api::RepositoryContents::ContentWrapper instance representing a tree
  # options - Hash
  #           :repo - The Repository containing the content.
  #           :full - The Boolean specifying whether to include the extended
  #                   output.
  #
  # Returns a Hash if the ContentWrapper exists, or nil.
  def tree_content_hash(tree, options = {})
    return nil if tree.nil?

    hash = common_content_hash(tree, options)

    hash[:type] = "dir"

    repo = options[:repo]
    ref = options[:ref]

    hash[:html_url] = encoded_html_url("#{repo.permalink}/tree/#{ref.b}/", tree.path)

    repo_nwo = repo_path(options, tree)
    hash[:git_url] = url("/repos/#{repo_nwo}/git/trees/#{tree.sha}")

    hash
  end

  # Creates a Hash to be serialized to JSON.
  #
  # tree    - Api::RepositoryContents::ContentWrapper instance representing a tree
  # options - Hash of options for #tree_content_hash
  #
  # Returns a Hash if the ContentWrapper exists, or nil.
  def tree_object_content_hash(tree, options = {})
    return nil if tree.nil?

    _id, tree_entries, _truncated = tree.repository.tree_entries(tree.sha, "", skip_size: false)
    content_hash(tree, options).merge!(
      entries: tree_entries.map do |entry|
        entry.path_prefix = tree.path
        content_hash(entry, options.merge(full: false))
      end,
    )
  end

  # Internal: Creates a Hash to be serialized to JSON.
  #
  # blob    - A TreeEntry instance.
  # options - Hash
  #           :repo - The Repository containing the content.
  #           :full - The Boolean specifying whether to include the extended
  #                   output.
  #
  # Returns a Hash if the ContentWrapper exists, or nil.
  def blob_content_hash(blob, options = {})
    options = Api::SerializerOptions.from(options)
    return nil if blob.nil?

    hash = common_content_hash(blob, options)

    hash[:type] = blob.unresolvable_symlink? ? "symlink" : "file"

    repo = options[:repo]
    ref = options[:ref]

    hash[:html_url] = encoded_html_url("#{repo.permalink}/blob/#{ref.b}/", blob.path)
    hash[:download_url] = if blob.git_lfs?
      TreeEntryRenderHelper.lfs_blob_url(options.current_user, repo, ref, blob.path, blob.git_lfs_oid)
    else
      TreeEntryRenderHelper.raw_blob_url(options.current_user, repo, ref, blob.path)
    end

    # if the blob is an LFS pointer, blob.size is the size of the actual file, but blob.data is just the LFS
    # pointer. the pointer's data should be returned in this case, which is why git_lfs? is checked.
    has_content = blob.size < Api::RepositoryContents::RAW_OBJECT_ONLY_BLOB_SIZE || blob.git_lfs?

    repo_nwo = repo_path(options, blob)
    hash[:git_url] = url("/repos/#{repo_nwo}/git/blobs/#{blob.sha}")
    if options[:full]
      if blob.unresolvable_symlink?
        hash[:target] = blob.data.to_s
      else
        is_symlink = false
        if symlink = blob.symlink_target
          blob = symlink
          is_symlink = true
        end
        if is_symlink && blob.symlink_source && has_content && options[:sha]
          hash[:content] = encode_base64(content_at(repo, options[:sha], blob.path).data, stats_key: "git_blob")
        else
          hash[:content] = has_content ? encode_base64(blob.data.to_s, stats_key: "git_blob") : ""
        end
        hash[:size] = blob.size
        hash[:encoding] = has_content ? "base64" : "none"
      end
    end

    hash
  end

  # Internal: Creates a Hash to be serialized to JSON.
  #
  # submodule - Api::RepositoryContents::ContentWrapper instance representing a
  #             submodule
  # options   - Hash
  #             :repo - The Repository containing the content.
  #             :full - The Boolean specifying whether to include the extended
  #                     output.
  #
  # Returns a Hash if the ContentWrapper exists, or nil.
  def submodule_content_hash(submodule, options = {})
    return nil if submodule.nil?

    hash = common_content_hash(submodule, options)

    hash[:type] = "submodule"

    if submodule.submodule_hosted_on_github?
      repo_nwo = "#{submodule.submodule_user}/#{submodule.submodule_repo}"
      hash[:html_url] = html_url("/#{repo_nwo}/tree/#{submodule.sha}")
      hash[:git_url] = url("/repos/#{repo_nwo}/git/trees/#{submodule.sha}")
    end

    # When this API first shipped, we mistakenly returned the type as 'file' when providing the
    # summary info for a submodule. We are now able to fix this as a breaking change, but we need to keep
    # the old behaviour around for backwards compatability.
    use_submodule_type_changeset_active = options.changeset_active?(:return_submodule_type_for_submodules_in_directory_lists)

    if !options[:full]
      hash[:type] = "file" unless use_submodule_type_changeset_active
    end

    if options[:full]
      hash[:submodule_git_url] = submodule.submodule_git_url
    end

    hash
  end

  def page_hash(page, options = {})
    options = Api::SerializerOptions.from(options)
    repo_path = repo_path(options, page)
    hash = {
      url: url("/repos/#{repo_path}/pages", options),
      status: page.status,
      cname: page.cname,
      custom_404: page.four_oh_four,
      html_url: options[:html_url],
      build_type: page.build_type,
      source: {
        branch: page.source_branch,
        path: page.source_dir,
      },
      public: page.public
    }

    if !GitHub.enterprise?
      hash.update \
        protected_domain_state: page.protected_domain_state,
        pending_domain_unverified_at: page.domain_unverified_at
    end

    if GitHub.flipper[:pages_health_check].enabled?(page.repository)
      if page.certificate.present?
        cert = page.certificate
        domains = [page.cname]
        domains.append(cert.alt_domain) if cert.alt_domain.present?

        hash[:https_certificate] = {
              state: cert.state,
              description: cert.state_description,
              domains: domains
        }

        hash[:https_certificate][:expires_at] = cert.expires_at.strftime("%Y-%m-%d") if cert.expires_at.present?
      end
      hash[:https_enforced] = page.https_redirect?
    end

    hash
  end

  def page_build_hash(build, options = {})
    options = Api::SerializerOptions.from(options)
    repo = repo_path(options, build)
    {
      url: url("/repos/#{repo}/pages/builds/#{build.id}", options),
      status: build.status,
      error: { message: build.error },
      pusher: user_hash(build.pusher, content_options(options)),
      commit: build.commit,
      duration: build.duration.to_i,
      created_at: time(build.created_at),
      updated_at: time(build.updated_at),
    }
  end

  def pages_health_check_hash(health_check, options = {})
    return nil unless health_check
    {
      domain: domain_hash(health_check["domain"]),
      alt_domain: domain_hash(health_check["alt_domain"]),
    }
  end

  def domain_hash(domain_health_check, options = {})
    return nil unless domain_health_check
    {
      host: domain_health_check["host"],
      uri: domain_health_check["uri"],
      nameservers: domain_health_check["nameservers"],
      dns_resolves: domain_health_check["dns_resolves?"],
      is_proxied: domain_health_check["proxied?"],
      is_cloudflare_ip: domain_health_check["cloudflare_ip?"],
      is_fastly_ip: domain_health_check["fastly_ip?"],
      is_old_ip_address: domain_health_check["old_ip_address?"],
      is_a_record: domain_health_check["a_record?"],
      has_cname_record: domain_health_check["cname_record?"],
      has_mx_records_present: domain_health_check["mx_records_present?"],
      is_valid_domain: domain_health_check["valid_domain?"],
      is_apex_domain: domain_health_check["apex_domain?"],
      should_be_a_record: domain_health_check["should_be_a_record?"],
      is_cname_to_github_user_domain: domain_health_check["cname_to_github_user_domain?"],
      is_cname_to_pages_dot_github_dot_com: domain_health_check["cname_to_pages_dot_github_dot_com?"],
      is_cname_to_fastly: domain_health_check["cname_to_fastly?"],
      is_pointed_to_github_pages_ip: domain_health_check["pointed_to_github_pages_ip?"],
      is_non_github_pages_ip_present: domain_health_check["non_github_pages_ip_present?"],
      is_pages_domain: domain_health_check["pages_domain?"],
      is_served_by_pages: domain_health_check["served_by_pages?"],
      is_valid: domain_health_check["valid?"],
      reason: domain_health_check["reason"],
      responds_to_https: domain_health_check["https?"],
      enforces_https: domain_health_check["enforces_https?"],
      https_error: domain_health_check["https_error"],
      is_https_eligible: domain_health_check["https_eligible?"],
      caa_error: domain_health_check["caa_error"],
    }
  end

  # Public: Get a hash for content CRUD response
  #
  # input - hash containing :content and :commit keys
  #
  # Contains a summary of commit and content info
  #
  # Returns a Hash
  def contents_crud_hash(input, options = {})
    options = Api::SerializerOptions.from(options)

    content = input[:content]
    commit  = input[:commit]

    content_summary = if content
      content_hash(content, options.merge(ref: input[:ref]))
    end
    commit_summary  = commit_hash(commit, options)

    {
      content: content_summary,
      commit: commit_summary,
    }
  end

  # Public: Build a short hash of a branch
  #
  # input - a Ref
  #
  # Contains the name, head SHA, and location of the ref.
  #
  # Returns a hash
  def short_branch_hash(ref, options = {})
    sha        = ref.target_oid
    commit_url = url("/repos/#{ref.repository.name_with_owner_for_api(use: options[:serialize_login])}/commits/#{sha}") if sha

    {
      name: ref.name,
      commit: {
        sha: sha,
        url: commit_url,
      },
      protected: ref.protected?,
    }
  end

  # Public: Same as short_branch_hash, but includes branch protection information
  #
  # ref - A Ref (must be a branch)
  #
  # Returns a Hash
  def short_branch_with_protection_hash(ref, options = {})
    short_branch_hash(ref, options).merge({
      protection: branch_protection_hash(ref, options),
      protection_url: url(protected_branch_base_path(ref), options),
    })
  end

  # Public: Returns a hash describing what is required for the current user to push to the branch.
  #
  # Example:
  #
  # {
  #   pattern: "release-*",
  #   required_signatures: true,              # (false if user is admin and not admin-enforced)
  #   required_status_checks: ["travis-ci"],  # (empty array if user is admin and not admin-enforced)
  #   required_approving_review_count: 3,     # (0 if user is admin and not admin-enforced)
  #   required_linear_history: true,          # (false if user is admin and not admin-enforced)
  #   allow_actor: true,                      # (false if there are restrictions and user is not on list. Always true for admins, etc. True if there are no restrictions.)
  #   allow_deletions: false,                 # this has no admin override
  #   allow_force_pushes: false,              # this has no admin override
  #   block_creations: false                  # (false if user is admin and not admin-enforced)
  # }
  def branch_pushability_hash(ref, options = {})
    options = Api::SerializerOptions.from(options)
    user = options[:current_user]

    protected_branch = ref.protected_branch || unprotected_branch(ref)

    required_statuses = if protected_branch.required_status_checks_enforced_for?(actor: user)
      protected_branch.required_status_checks.map { |check| check.context }
    else
      []
    end
    review_count = if protected_branch.required_review_policy_enforced_for?(actor: user)
      protected_branch.required_approving_review_count
    else
      0
    end

    short_branch_hash(ref, options).merge(
      pattern: protected_branch.name,
      required_signatures: protected_branch.required_signatures_enforced_for?(actor: user),
      required_status_checks: required_statuses,
      required_approving_review_count: review_count,
      required_linear_history: protected_branch.required_linear_history_enforced_for?(actor: user),
      allow_actor: protected_branch.push_authorized?(user),
      allow_deletions: !protected_branch.block_deletions_enabled?,
      allow_force_pushes: !protected_branch.block_force_pushes_enabled?,
      block_creations: protected_branch.create_protected_enabled?,
    )
  end

  def unprotected_branch(ref)
    ProtectedBranch.new(repository: ref.repository).tap do |branch|
      branch.clear_blocked_deletions
      branch.clear_blocked_force_pushes
    end
  end

  def merged_upstream(result_hash, options = {})
    result_hash
  end

  def tag_protection_state_hash(tag_protection_state, options = {})
    {
      id: tag_protection_state.id,
      pattern: tag_protection_state.pattern,
      created_at: tag_protection_state.created_at,
      updated_at: tag_protection_state.updated_at,
    }
  end

  sig { params(repo: String, diff: GitHub::Diff::Entry, type: String).returns(T.nilable(String)) }
  def diff_url(repo, diff, type = "blob")
    return nil if diff.submodule?

    sha, path = diff_sha_and_path(diff)

    encoded_url = encode("#{GitHub.url}/#{repo}/#{type}/#{sha}")
    encoded_path = UrlHelper.escape_path(path)
    "#{encoded_url}/#{encoded_path}"
  end

  sig { params(repo: String, diff: GitHub::Diff::Entry).returns(String) }
  def diff_contents_url(repo, diff)
    sha, path = diff_sha_and_path(diff)

    encoded_url = encode("#{GitHub.api_url}/repos/#{repo}/contents")
    encoded_path = UrlHelper.escape_path(path)
    encoded_query = encode(query_parts(ref: sha))
    "#{encoded_url}/#{encoded_path}?#{encoded_query}"
  end

  sig { params(diff: GitHub::Diff::Entry).returns([String, String]) }
  def diff_sha_and_path(diff)
    diff.deleted? ? [diff.a_sha, diff.a_path] : [diff.b_sha, diff.b_path]
  end

  def retrieve_uploader_hash(user_cache, uploader, options)
    return simple_user_hash(uploader, options) if user_cache.nil?
    return nil unless uploader

    user_cache.getset(uploader.id) do
      simple_user_hash(uploader, options)
    end
  end

  SimpleRepositoryFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on Repository {
      id
      name
      databaseId
      networkPresent
      isPrivate
      description
      permalink(includeHost: true)
      isFork
      owner {
        login
        ...Api::Serializer::UserDependency::SimpleUserFragment
      }
      repositoryTopics(first: 100) { nodes { topic { name } } }
    }
  GRAPHQL

  RepositoryPermissionFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on Repository {
      permission: viewerPermission
    }
  GRAPHQL

  RepositoryFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on Repository {
      ...Api::Serializer::RepositoriesDependency::SimpleRepositoryFragment

      visibility

      createdAt
      updatedAt
      pushedAt
      archivedAt

      homepageUrl # homepage
      primaryLanguage {
        name
      } # language
      diskUsage # size
      defaultBranch

      hasIssuesEnabled # has_issues
      hasProjectsEnabled # has_projects
      hasWikiEnabled # has_wiki
      hasDownloads # has_downloads
      hasPages # has_pages

      squashMergeAllowed
      rebaseMergeAllowed
      mergeCommitAllowed
      autoMergeAllowed
      deleteBranchOnMerge
      forkingAllowed
      squashPrTitleUsedAsDefault

      isArchived
      isDisabled
      isTemplate

      issues(states: OPEN) {
        totalCount
      } # open_issues_count (deprecated: open_issues)
      pullRequests(states: OPEN) {
        totalCount
      } # open_issues_count (deprecated: open_issues)
      stargazers {
        totalCount # stargazers_count (deprecated: watchers, watchers_count)
      }
      forks {
        totalCount # forks_count (deprecated: forks)
      }

      cloneUrl
      mirrorUrl
      gitUrl
      sshUrl
      svnUrl

      licenseInfo {
        ...Api::Serializer::LicensesDependency::SimpleLicenseFragment
      }

      codeOfConduct {
        ...Api::Serializer::CodesOfConductDependency::PartialCodeOfConductFragment
      }

      ...Api::Serializer::RepositoriesDependency::RepositoryPermissionFragment

      hasAnonymousAccessEnabled
      tempCloneToken
    }
  GRAPHQL

  ExtendedRepositoryFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on Repository {
      ...Api::Serializer::RepositoriesDependency::RepositoryFragment

      owner {
        __typename
      }

      watchers {
        totalCount
      }

      network {
        repositories {
          totalCount
        }
      }

      templateRepository {
        ...Api::Serializer::RepositoriesDependency::RepositoryFragment
      }
    }
  GRAPHQL
end
