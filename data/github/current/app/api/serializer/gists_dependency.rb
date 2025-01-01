# typed: false
# frozen_string_literal: true

module Api::Serializer::GistsDependency
  include GitHub::UTF8
  # Creates a Hash to be serialized to JSON.
  #
  # gist - Gist instance.
  # options - Hash
  #           :full    - Boolean specifying we want the extended output.
  #           :files   - Boolean specifying we want files included in the output.
  #           :version - String specifying the revision of the gist to serialize.
  #
  # Returns a Hash if the Gist exists, or nil.
  def gist_hash(gist, options = {})
    return nil if !gist

    options = Api::SerializerOptions.from(options)

    files = {}
    all_files = []
    if options[:full] || options[:files]
      all_files = gist.files(options[:version])
      Gist.limit_files(all_files).each do |f|
        files[f.name] = {
          filename: f.name,
          type: f.mime_type,
          language: f.language.try(:name),
          raw_url: gist.raw_url_for(f),
          size: f.size,
        }

        next unless options[:full]

        files[f.name].update truncated: f.truncated?

        params = options[:mime_params] || []

        if params.include?(:base64) || f.binary?
          files[f.name].update \
            content: encode_base64(f.data, stats_key: "gist"),
            encoding: "base64"
        else
          files[f.name].update \
            content: utf8(f.data),
            encoding: "utf-8"
        end
      end
    end

    full_url = if options[:version] && options[:version] != gist.default_branch
      "/gists/#{gist.gist_id}/#{options[:version]}"
    else
      "/gists/#{gist.gist_id}"
    end

    hash = {
      url: url(full_url, options),
      forks_url: url("/gists/#{gist.gist_id}/forks", options),
      commits_url: url("/gists/#{gist.gist_id}/commits", options),
      id: gist.repo_name,
      node_id: global_id_for(gist, options),
      git_pull_url: gist.clone_url,
      git_push_url: gist.push_url,
      #:git_url     => "", # SMART HTTP, not supported
      html_url: gist.permalink,
      files: files,
      public: gist.public,
      created_at: time(gist.created_at),
      updated_at: time(gist.updated_at),
      description: gist.description,
      comments: gist.comment_count,
      user: nil,
      comments_enabled: gist.comments_enabled,
    }

    hash[:comments_url] = url("/gists/#{gist.gist_id}/comments", options)

    if options.wants_beta_media_type? && !options.changeset_active?(:deprecate_beta_media_type)
      hash[:user] = user_hash(gist.owner, content_options(options)) if gist.owner
    else
      hash[:owner] = user_hash(gist.owner, content_options(options)) if gist.owner
    end

    if options[:full]
      hash[:fork_of] = gist_hash(gist.parent, content_options(options)) if gist.fork?

      # DEPRECATED: Will be removed in API v4. Will be replaced with a separate
      # API call to get the forks for a gist.
      hash[:forks] = gist_forks(gist, options)

      # DEPRECATED: Will be removed in API v4. Will be replaced with a separate
      # API call to get the history for a gist.
      hash[:history] = gist_history(gist, options)
    end

    if options[:full] || options[:files]
      hash[:truncated] = (all_files.count > files.keys.count)
    end

    hash.delete(:forks) if options.changeset_active?(:remove_forks_history_from_base_gist)
    hash.delete(:history) if options.changeset_active?(:remove_forks_history_from_base_gist)

    hash
  end

  def gist_forks(gist, options = nil)
    return nil if !gist
    options = Api::SerializerOptions.from(options)

    gist.visible_forks.preload(:user).map do |f|
      {
        url: url("/gists/#{f.gist_id}", options),
        user: user_hash(f.owner, options),
        id: f.repo_name,
        created_at: time(f.created_at),
        updated_at: time(f.updated_at),
      }
    end
  end

  def gist_history(gist, options = nil)
    return nil if !gist
    options = Api::SerializerOptions.from(options)

    Failbot.push("gh.gist.id": gist.id)

    stats = {}
    begin
      stats = commit_stats(gist)
    rescue GitRPC::CommandFailed, Repository::CommandFailed => boom
      Failbot.push app: "github-user"
      Failbot.report boom
    end

    version = options[:version] || gist.master_oid
    oid = gist.ref_to_sha(version)

    commits = if options.page
      gist.commits.paged_history(oid, options.page, options.per_page)
    else
      # Return a sample of the history
      # The rest of the history is available at gist/:gist_id/commits
      max_revisions = 30

      gist.commits.history(oid, max_revisions)
    end

    hash_commits = commits.map do |commit|
      change_status = {}
      if s = stats[commit.oid]
        change_status = s
      end
      {
        user: (commit.author && user_hash(commit.author, content_options(options))),
        version: commit.oid,
        committed_at: time(commit.authored_date),
        change_status: change_status,
        url: url("/gists/#{gist.gist_id}/#{commit.oid}", options),
      }
    end

    commits.replace hash_commits
  end

  # Creates a Hash to be serialized to JSON.
  #
  # comment - Gist comment instance.
  # options - Hash
  #
  # Returns a Hash if the Gist comment exists, or nil.
  def gist_comment_hash(comment, options = {})
    options = Api::SerializerOptions.from(options)

    {
      url: url("/gists/#{comment.gist.gist_id}/comments/#{comment.id}", options),
      id: comment.id,
      node_id: global_id_for(comment, options),
      user: user_hash(comment.user, content_options(options)),
      author_association: comment.author_association(options[:current_user]).to_s,
      created_at: time(comment.created_at),
      updated_at: time(comment.updated_at),
    }.update(mime_body_hash(comment, options))
  end

  def commit_stats(gist)
    # git log --max-count=10 --skip=0 --shortstat --pretty=format:%H --no-merges -z HEAD
    stats = gist.rpc.commit_stats_log(gist.default_branch)

    stats.each_with_object({}) do |commit, hash|
      oid, shortstat = commit.split("\n")

      deletions = if shortstat =~ /(\d+) deletions?/
        $1.to_i
      else
        0
      end

      additions = if shortstat =~ /(\d+) insertions?/
        $1.to_i
      else
        0
      end

      hash[oid] = {
        total: additions + deletions,
        additions: additions,
        deletions: deletions,
      }
    end
  end

  def disabled_gist_hash(gist, options = {})
    return nil if !gist

    if gist.access.disabled?
      reason    = gist.access.disabling_reason
      timestamp = gist.access.disabled_at
    end

    valid_reasons = GitRepositoryAccess::REASONS - ["broken"]
    reason = "unavailable" unless valid_reasons.include?(reason)

    url = if GitHub.enterprise?
      "#{GitHub.enterprise_admin_help_url}/guides/installation/troubleshooting/"
    elsif reason == "dmca"
      gist.access.dmca_url
    else
      "#{GitHub.scheme}://#{GitHub.host_name}/tos"
    end

    response = {
                  message: "Gist access blocked",
                  block: {
                    reason: reason,
                    created_at: timestamp,
                    html_url: url,
                  },
               }

    response
  end
end
