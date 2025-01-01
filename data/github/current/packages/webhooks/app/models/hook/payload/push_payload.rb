# typed: true
# frozen_string_literal: true

class Hook::Payload::PushPayload < Hook::Payload
  # Helper methods that require the module to respond to
  # repository, before, after and ref
  include Pushes::CommitsHelper
  include Repositories::CustomProperties::CustomPropertiesHelper
  include GitHub::Memoizer

  # https://github.com/github/github/blob/a8c4775e92a50dcfa30814c3749584f16e6de4fd/vendor/gitrpc/lib/gitrpc/backend/read_refs.rb#L17
  REFS_FILTER_ARGS = ["refs/heads/**", "refs/tags/**", "refs/guest/**", "refs/notes/**"].freeze

  delegate :pusher, :repository, :before, :after, :ref, to: :hook_event

  def to_payload_hash
    {
       ref: ref,
       before: before,
       after: after,
       repository: repo_hash,
       pusher: user_hash(pusher),
     }.tap { |payload| payload.merge!(git_only) }
  end

  def git_only
    return {} unless @include_git_data

    ActiveRecord::Base.connected_to(role: :reading) do
      {
        created: created?,
        deleted: deleted?,
        forced: non_fast_forward?,
        base_ref: base_ref,
        compare: compare_url,
        commits: commits_hashes_array(commits_pushed_limited),
        head_commit: commit_hash(head_commit),
      }
    end
  end

  def initialize(hook_event, include_git_data: true, merge: false)
    @include_git_data = include_git_data
    @merge = merge
    super(hook_event)
  end

  # Builds an array of commit hashes.
  #
  # commits - The commits to build hashes for.
  #
  # Returns an Array of Hashes.
  def commits_hashes_array(commits)
    Commit.prefill_users(commits).map do |commit|
      commit_hash(commit)
    end
  end

  # Builds the payload representation for the given commit.
  #
  # commit - A Commit instance.
  #
  # Returns a Hash.
  def commit_hash(commit)
    return unless commit

    diff = commit_file_stats_hash(commit)
    hash = {
      id: commit.oid,
      tree_id: commit.tree_oid,
      distinct: distinct?(commit),
      message: commit.message,
      timestamp: commit.committed_date.xmlschema,
      url: commit_url(commit),
      author: {
        name: commit.author_name,
        email: commit.author_email,
      },
      committer: {
        name: commit.committer_name,
        email: commit.committer_email,
      },
      added: diff["added"],
      removed: diff["removed"],
      modified: diff["modified"],
    }
    if user = commit.author
      hash[:author][:username] = user.display_login
    end
    if user = commit.committer
      hash[:committer][:username] = user.display_login
    end
    hash
  end

  # Builds the diff stats payload representation for the given commit.
  #
  # commit - A Commit instance.
  #
  # Returns a Hash.
  def commit_file_stats_hash(commit)
    hash = {
      "removed" => [],
      "added" => [],
      "modified" => [],
    }

    begin
      deltas = commit.init_diff.deltas
    rescue GitRPC::Timeout
      GitHub.dogstats.increment("commit_file_stats_hash.rpc_timeout")
      deltas = []
    end

    deltas.each do |delta|
      case delta.status
      when "A"
        hash["added"] << delta.new_file.path
      when "D"
        hash["removed"] << delta.old_file.path
      when "R"
        hash["added"] << delta.new_file.path
        hash["removed"] << delta.old_file.path
      else
        hash["modified"] << delta.new_file.path
      end
    end

    hash["removed"].sort!
    hash["added"].sort!
    hash["modified"].sort!

    hash
  end

  # Builds the payload representation for the Repository.
  #
  # Returns a Hash.
  def repo_hash
    serialized_repo = api_serialize(:repository_hash, repository)

    serialized_owner =
      user_hash(repository.owner).merge(serialized_repo[:owner].to_h)

    serialized_repo = serialized_repo.
      merge(legacy_repo_hash(repository)).
      merge(owner: serialized_owner)

    # NOTE: In order to ensure backwards compatibility, we need to make sure that the repo
    # pushed_at and created_at timestamps are sent at unix timestamps
    # NOTE: We prefer the pushed_at timestamp from the hook event, because the repo's timestamp is not updated
    # until later in push processing, so it may be stale depending if it is running before
    # us (PostPushEventToHookshotJob)
    serialized_repo[:pushed_at] = hook_event&.pushed_at&.to_i || serialized_repo[:pushed_at].to_i
    serialized_repo[:created_at] = serialized_repo[:created_at].to_i

    if repository.owner&.organization?
      serialized_repo[:custom_properties] = repo_custom_properties_hash(repository)
    end

    serialized_repo
  end

  # Builds the payload representation for the User
  #
  # Returns a Hash.
  def user_hash(user)
    if user
      {
        name: user.display_login,
        email: user.outbound_email,
      }
    else
      {
        name: "none",
      }
    end
  end

  # Builds the absolute URL for the given commit.
  #
  # commit - A Commit instance.
  #
  # Returns a String URL.
  def commit_url(commit)
    "#{repo_url}/commit/#{commit.oid}"
  end

  # Builds the absolute URL for the current Repository.
  #
  # Returns a String URL.
  def repo_url
    @repo_url ||= "%s/%s/%s" % [GitHub.url, repository.owner.display_login, repository.to_s]
  end

  def base_ref
    return @base_ref if defined?(@base_ref)
    return unless created? || (distinct_commits && distinct_commits.empty?)

    # If the after sha is distinct, by definition it is *only* referenced by the current ref.
    # In that case we can return nil early instead of letting the filtering out of the ref at the end make the result nil.
    # distinct_commits is hard coded to nil for creations, so we fallback to checking commits_pushed in that case.
    # For a creation, distinct_commits_pushed and commits_pushed are the same, so we can use either.
    if distinct_commits&.include?(after) || (created? && commits_pushed.any? { |commit| commit.oid == after })
      @base_ref = nil
      return
    end

    @base_ref = if FeatureFlag.vexi.enabled?(:push_hook_base_ref_with_points_at, repository, default: false)
      load_base_ref
    else
      Scientist.run "push_hook_base_ref_with_points_at" do |e|
        e.context({ repository_id: repository.id, ref: ref, before: before, after: after })
        e.use do
          # hash of 'oid' => [Ref, ...] for all tags/branches
          GitHub.dogstats.increment("push_payload.base_ref.repository_refs")
          target_map = repository.refs.group_by(&:target_oid)

          # first, try the new sha being pushed
          matches = target_map[after]

          if matches
            GitHub.dogstats.increment("push_payload.base_ref.repository_refs.after")
            if matches.size == 1 && matches.first.qualified_name == ref
              GitHub.dogstats.increment("push_payload.base_ref.repository_refs.after.only_ref")
            end
          end

          # then search the pushed commits for one we recognize
          matches ||=
            if base_commit = commits_pushed.find { |commit| target_map.key?(commit.oid) }
              target_map[base_commit.oid]
            end

          # and fallback to the previous sha value
          matches ||= target_map[before] || []

          matches = matches.map(&:qualified_name)
          matches.delete(ref)
          matches.first
        end
        e.try do
          load_base_ref
        end
      end
    end
  end

  def load_base_ref
    GitHub.dogstats.increment("push_payload.base_ref.list_references")

    references = load_references(points_at: [after])

    # The previous logic used target_map = repository.refs.group_by(&:target_oid)
    # which for annotated tag refs, the target_oid points to the git tag object
    # and won't match target_map[after], since after is the commit oid
    # to match the behavior, we will exclude these cases
    references = references.reject { |ref_obj| ref_obj.target_id.id != after }
    references = references.map(&:reference).map(&:name)

    if references.any?
      GitHub.dogstats.increment("push_payload.base_ref.list_references.after")
      if references.size == 1 && references.first == ref
        GitHub.dogstats.increment("push_payload.base_ref.list_references.after.only_ref")
      end
      return get_base_ref(references)
    end

    # If we didn't find any references pointing at the 'after' sha, we need to
    # look through the commits that were pushed to see if any of them are pointed
    # to by any references in the repository.
    # In this case, we will load all references in the repository that point to
    # any of the commits that were pushed, or the 'before' sha.
    # This is potentially expensive, but should be rare. And it is still better
    # than loading all references in the repository.

    points_at = commits_pushed.map(&:oid)
    points_at << before unless before == GitHub::NULL_OID
    points_at.uniq!

    # Spokes API ListReferences points_at only supports up to 25 items
    references = points_at.each_slice(25).flat_map do |slice|
      load_references(points_at: slice)
    end

    reference_map = references.reduce({}) do |acc, ref_obj|
      if !acc.key?(ref_obj.target_id.id)
        acc[ref_obj.target_id.id] = []
      end
      acc[ref_obj.target_id.id] << ref_obj.reference.name
      acc
    end

    if base_commit = commits_pushed.find { |commit| reference_map.key?(commit.oid) }
      return get_base_ref(reference_map[base_commit.oid])
    end

    return get_base_ref(reference_map[before]) if reference_map.key?(before)

    nil
  end

  def get_base_ref(references)
    # To match the control behavior, I will delete the current ref right before returning.
    # We couldn't decide if this is the expected behavior or a bug in the control code.
    # Given it has existed for a long time seems people are happy with the current behavior,
    # and it also avoid multiple calls to Spokes API, so we keep it.
    references.delete(ref)
    return nil if references.empty?
    BranchSorter.new(references).to_a.first
  end

  def load_references(points_at:)
    list_references_response = repository.spokes_api.list_references_with_details(include_globs: REFS_FILTER_ARGS, points_at: points_at)

    return [] if list_references_response.refs.empty?
    all_refs = list_references_response.refs.to_a

    if list_references_response.next_cursor.present?
      cursor = list_references_response.next_cursor
      while cursor.present?
        list_references_response = repository.spokes_api.list_references_with_details(include_globs: REFS_FILTER_ARGS, points_at: points_at, cursor: cursor)
        all_refs.concat(list_references_response.refs.to_a)
        cursor = list_references_response.next_cursor
      end
    end

    all_refs
  end

  # `head_commit` is the commit object that `after` is or points to, or nil if
  # `after` isn't or doesn't point to a commit.
  #
  #  - For a branch ref update, this is always just the after commit or nil if the
  #    push is a deletion.
  #  - For a ref update outside the `refs/heads` namespace, `after` could refer
  #    to any object type.  If `after` refers to a tree or blob then this field
  #    has no meaning and will be nil.  But if it refers to a tag object then
  #    we need to attempt to peel it to obtain the indirectly referenced commit
  #    (if one exists; the tag could point to anything as well)
  #
  #   The implicit case statement described above has been hoisted into the
  #   `peel_to_commit` methods in each git object class (Commit, Blob, Tag,
  #   Tree)
  #
  memoize def head_commit
    return if deleted?
    repository.objects.read(after).peel_to_commit
  rescue GitRPC::ObjectMissing
    nil
  end

  # Checks if the given Commit is being pushed to the Repository for the
  # first time.
  #
  # commit - A Commit instance.
  #
  # Returns true if the commit is distinct, or false.
  def distinct?(commit)
    # In a PR merge by definition any commits that are not the merge commit will not be distinct,
    #  and the merge (head) commit will be distinct.
    # In this case we can just return true for the merge commit and false for all others,
    #  and avoid a race condition between distinct commit lookup and automatic ref deletion for PRs.
    # https://github.com/github/repos/issues/9614
    if @merge
      return commit.oid == head_commit&.oid
    end

    distinct_commits.nil? || distinct_commits.include?(commit.oid)
  end

  # A Set of all the distinct commits that from the current push.
  #
  # Returns a Set of String commit SHAs, or nil when all commits are distinct.
  def distinct_commits
    if created? || deleted? || non_fast_forward?
      nil
    else
      @distinct_commits ||= Set.new(distinct_commits_pushed.map { |c| c.sha })
    end
  end

  def compare_url
    @compare_url ||= if !created?
      "#{repo_url}/compare/#{before[0, 12]}...#{after[0, 12]}"
    elsif commits_pushed.length > 1
      "#{repo_url}/compare/#{commits_pushed.first.oid[0, 12]}^...#{commits_pushed.last.oid[0, 12]}"
    elsif commits_pushed.length == 1
      "#{repo_url}/commit/#{commits_pushed.first.oid[0, 12]}"
    else
      "#{repo_url}/compare/#{branch_name}"
    end
  end

  def commits_pushed
    super # Pushes::CommitsHelper
  end

  def distinct_commits_pushed
    super # Pushes::CommitsHelper
  end

  private

  def legacy_repo_hash(repo)
    {
      id: repo.id,
      name: repo.name,
      html_url: repo.permalink,
      description: repo.description,
      homepage: repo.homepage,
      watchers: repo.stargazer_count,
      stargazers: repo.stargazer_count,
      forks: repo.forks_count,
      fork: repo.fork?,
      size: repo.disk_usage.to_i,
      owner: repo.owner.display_login,
      private: repo.private?,
      open_issues: repo.open_issues_count,
      has_issues: repo.has_issues?,
      has_downloads: repo.has_downloads?,
      has_wiki: repo.has_wiki?,
      language: repo.primary_language_name,
      created_at: repo.created_at,
      pushed_at: repo.pushed_at,
      master_branch: repo.default_branch,
      default_branch: repo.default_branch,
      organization: repo.organization&.display_login,
    }.compact
  end
end
