# typed: true
# frozen_string_literal: true

require "set"

module GitHub
  # Models a comparison between any two refs in a repository network. The base ref can
  # be thought of as the starting point: any commit reachable from the base ref
  # is excluded. That leaves unique commits reachable from the head ref. The
  # methods in this class provide views on those commits unique to the head ref
  # and its ancestors.
  class Comparison
    include LastModifiedCalculation
    include GitHub::Relay::GlobalIdentification

    DEFAULT_COMMIT_LIMIT = 1000
    COMPARE_PER_PAGE_DEFAULT = 50

    # Timeout for the entire comparison operation. That includes, finding the
    # merge-base, ahead-behind calculation, ..., and calculating the diff.
    #
    # GitHub has a hard timeout after 10sec. Within this time we need to run
    # GitRPC calls and we need to render the page. According to Datadog the
    # 99 percentile of the rendering time has a base of at least 2sec. Let's
    # grant the GitRPC calls a combined timeout of 7sec and add 1sec of wiggle
    # room.
    COMPARISON_GITRPC_TIMEOUT_SECS = 7

    class Error < StandardError; end
    class InvalidRangeError < Error; end

    attr_reader :repo, :base, :head, :limit, :pull

    # This class is going through somewhat of a transition. There are two ways of instantiating
    # this but we can only have one initialization method. To simplify the rules, please
    # avoid instantiating a Comparison directly and instead use either the `deprecated_build` or
    # `build` methods.
    #
    # USE deprecated_build IF YOU ARE UNSURE WHICH CONSTRUCTOR TO USE
    def initialize(repo: nil, base: nil, head: nil, limit: DEFAULT_COMMIT_LIMIT, pull: nil, base_repo: nil,
                   head_repo: nil, base_revision: nil, head_revision: nil, direct_compare: false)
      @repo  = repo
      @base  = base
      @head  = head
      @limit = limit
      @pull  = pull

      # Set these new ones only if they are not nil. We don't want the existing code
      # to think these are cached nils somewhere.
      @base_repo     = base_repo unless base_repo.nil?
      @head_repo     = head_repo unless head_repo.nil?
      @base_revision = base_revision unless base_revision.nil?
      @head_revision = head_revision unless head_revision.nil?

      @repo = pull ? pull.repository : base_repo if repo.nil?

      @direct_compare = direct_compare

      # TODO: This should be pulled out and be provided by the caller instead -
      # the comparison should not have to know about advisory workspaces.
      #
      # This requires some refactoring of the comparison class to no longer rely
      # on the `base` and `head` strings to specify base and head repositories.
      if @repo.advisory_workspace?
        @base_repo = @repo.parent_advisory_repository
        @head_repo = @repo
      end
    end

    # Public: The deprecated constructor.
    #
    # While this is called deprecated it is by no means out of service yet. Please
    # use this for all of your Comparison needs unless you know what you are doing.
    #
    # repo  - The Repository to which this comparison is attached. All GitRPC operations
    #         will be based on this repository.
    # base  - A String of the ref name, optionally prepended by a fork's owner's login.
    #         Eg: "forker:topic"
    # head  - Same as base but for the head ref. Eg "owner:master"
    # limit (optional) - The integer max number of commits to load for the range this comparison includes.
    # pull  (optional) - The optional pull request with which this comparison is associated.
    #                    Specifying this means its head and base repository will be used.
    # direct_compare (optional) - Boolean, see #direct_compare?
    # base_repo (optional) - The base Repository object. All GitRPC operations will be run against this repository.
    # head_repo (optional) - The head Repository object.
    def self.deprecated_build(repo, base, head, limit: DEFAULT_COMMIT_LIMIT, pull: nil, direct_compare: false, base_repo: nil, head_repo: nil)
      new(repo: repo, base: base, head: head, limit: limit, pull: pull, direct_compare: direct_compare, base_repo: base_repo, head_repo: head_repo)
    end

    # Public: The "new" instantiation method.
    #
    # Note: This is currently used exclusively by the GraphQL API. Eventually everything
    # will use this but as of this writing, a Comparison instantiated using this method
    # is internally inconsistent due to the base and head not being specified.
    # When either the GraphQL conversion needs them, or we transition another callsite
    # we can look at programmatically generating these values as the arguments
    # provided below should be sufficient.
    #
    # USE deprecated_build IF YOU ARE UNSURE WHICH CONSTRUCTOR TO USE
    #
    # base_repo     - The base Repository object. All GitRPC operations will be run against
    #                 this repository.
    # head_repo     - The head Repository object.
    # base_revision - A String which resolves to a single commit representing the base of the
    #                 comparison. Eg: "topic", "master^", "cd809d3b5dd2904eb3b966b663225410d5954be1"
    # head_revision - Same as base_revision, but resolving to the head commit of the comparison.
    # limit         - The max number of commits to load for this comparison.
    # pull          - PullRequest object.
    def self.build(base_repo:, head_repo: nil, base_revision:, head_revision:, limit: DEFAULT_COMMIT_LIMIT, pull: nil)
      raise "base repository cannot be nil" if base_repo.nil?
      raise "base revision cannot be blank" if base_revision.blank?
      raise "head revision cannot be blank" if head_revision.blank?

      # do this here instead of in the constructor to avoid affecting existing legacy logic
      # With this in place, we can assume neither repo is nil.
      head_repo = base_repo if head_repo.nil?

      new(
        base_repo:     base_repo,
        head_repo:     head_repo,
        base_revision: base_revision,
        head_revision: head_revision,
        limit:         limit,
        pull:          pull,
      )
    end

    def self.from_range(repository, range, limit: 1000)
      range = range.b
      merge_base_separator = /\.{3}|#{"…".b}/
      direct_compare = false

      # first check if we are considering a "three dot range"
      if range =~ merge_base_separator
        head, base = range.split(merge_base_separator, 2).reverse
      # since we couldn't find three dots, let's check if it's a "two dot range"
      elsif range.include?("..")
        head, base = range.split("..", 2).reverse
        direct_compare = true

      # If we couldn't find any type of range, give up!
      # For an implicit default of comparing against the base branch,
      # use `.from_range_or_ref` instead.
      else
        raise InvalidRangeError
      end

      head_repo = parse_repo(head)
      base_repo = parse_repo(base)

      deprecated_build(repository, base, head, limit: limit, direct_compare: direct_compare, base_repo: base_repo, head_repo: head_repo)
    end

    def self.parse_repo(part)
      parts = part.split(":")
      if parts.length == 3
        Repository.with_name_with_owner(parts[0], parts[1])
      else
        nil
      end
    end

    def self.from_range_or_ref(repository, range_or_ref, user:, limit: 1000)
      self.from_range(repository, range_or_ref, limit: limit)
    rescue InvalidRangeError
      head = range_or_ref
      base = repository.base_branch(head, user)

      base = repository.base_branch(head, user, include_remote_repo: true, repo_seperator: ":")
      base_repo = parse_repo(base)

      deprecated_build(repository, base.b, head.b, limit: limit, direct_compare: false, base_repo: base_repo)
    end

    def global_id
      [
        repo.id.to_i,
        base_repo.id.to_i,
        head_repo.id.to_i,
        base_revision,
        head_revision
      ].join(":")
    end

    def self.load_from_global_id(id, security_violation_behaviour:)
      components = id.split(":")
      raise "unexpected comparison component count" unless components.count == 5
      repo_id, base_repo_id, head_repo_id, base_revision, head_revision = components

      repo_ids = [repo_id, base_repo_id, head_repo_id].map(&:to_i)
      security_violation_behaviour ||= :raise
      Platform::Loaders::ActiveRecord.load_all(::Repository, repo_ids, security_violation_behaviour: security_violation_behaviour).then do |repo, base_repo, head_repo|
        next if repo.nil? || base_repo.nil? || head_repo.nil?
        new(
          repo: repo,
          base_repo: base_repo,
          head_repo: head_repo,
          base_revision: base_revision,
          head_revision: head_revision,

          # TODO: this is static until we can load the comparison by traversing the graphql schema
          # as long as comparisons continue to only need 250 commits we should be fine.
          limit:         250,
        )
      end
    end

    # Parse the revision
    # Format can either be user:ref or user:repo:ref
    def revision_parts(revision)
      revision.to_s.b.split(":", 3)
    end

    # The base commit revision. This may be a branch name, tag name, SHA1, or
    # any other valid ref value as defined by the SPECIFYING REVISIONS section
    # of git-rev-parse(1) manpage.
    def base_revision
      return @base_revision if defined?(@base_revision)
      return @base_revision = nil if base.nil?

      @base_revision = revision_parts(base).last
    end

    def display_base_revision
      scrubbed_utf8(base_revision)
    end

    # The head commit revision.
    def head_revision
      return @head_revision if defined?(@head_revision)
      return @head_revision = nil if head.nil?

      @head_revision = revision_parts(head).last
    end

    def display_head_revision
      scrubbed_utf8(head_revision)
    end

    # deprecated
    alias display_head_ref display_head_revision
    alias display_base_ref display_base_revision
    alias head_ref head_revision
    alias base_ref base_revision

    # deprecated - use async_base_oid instead.
    def base_sha
      async_base_oid.sync
    end

    # deprecated - use async_head_oid instead.
    def head_sha
      async_head_oid.sync
    end

    # Public: Is this comparison a direct comparison between the two commits (two dot)
    #         or is it between the merge base of the two and the second commit (three dot)
    #
    # Returns true if two dot, false if three
    def direct_compare?
      @direct_compare
    end

    def empty?
      if direct_compare?
        diffs.available? && diffs.empty?
      else
        !common_ancestor? || zero_commits?
      end
    end

    # SHA1 of the commit to use as the base of the comparison.
    def async_base_oid
      return @async_base_oid if defined?(@async_base_oid)
      @async_base_oid = async_base_repo.then do |base_repo|
        async_oid(base_repo, base_revision)
      end
    end

    # SHA1 of the commit to use as the head of the comparison.
    def async_head_oid
      return @async_head_oid if defined?(@async_head_oid)
      @async_head_oid = async_head_repo.then do |head_repo|
        async_oid(head_repo, head_revision)
      end
    end

    # Can a pull request be created from this comparison?
    #
    # Both the base and head must be branches that exist,
    # there must be commits between them, and they must have
    # a common ancestor.
    def pull_requestable?
      !direct_compare? &&
      valid? &&
      base_repo.heads.exist?(base_revision) &&
      head_repo.heads.exist?(head_revision) &&
      common_ancestor? &&
      commits.any?
    end

    # The Commit object to use as the base of the comparison.
    def base_commit
      @base_commit ||= base_repo.commits.find_for_sha(base_sha)
    end

    # The Commit object to use as the head of the comparison.
    def head_commit
      @head_commit ||= head_repo.commits.find_for_sha(head_sha)
    end

    # The Commit object that is the merge-base of the base and the head, if a
    # merge-base exists.
    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def merge_base_commit
      @merge_base_commit ||= (merge_base && head_repo.commits.find(merge_base))
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    # The login name of the user owning the base repository. The login name
    # is extracted from extended base ref provided during initialization. When
    # no user was specified, the repo's owner is assumed.
    def base_user_login
      if base&.include?(":")
        revision_parts(base).first
      else
        base_repo.user.display_login
      end
    end

    # The login name of the user owning the head repository.
    def head_user_login
      if head&.include?(":")
        revision_parts(head).first
      else
        head_repo&.user&.display_login
      end
    end

    # The base ref with base user login prefix, and optionally the repository name.
    def qualified_base_ref(include_repo: false)
      if include_repo
        [base_user_login, base_repo.name, base_revision].join(":")
      else
        [base_user_login, base_revision].join(":")
      end
    end

    def display_qualified_base_revision
      scrubbed_utf8(qualified_base_ref)
    end

    # The head ref with head user login prefix, and optionally the repository name.
    def qualified_head_ref(include_repo: false)
      if include_repo
        [head_user_login, head_repo.name, head_revision].join(":")
      else
        [head_user_login, head_revision].join(":")
      end
    end

    def display_qualified_head_revision
      scrubbed_utf8(qualified_head_ref)
    end

    # The User that owns the base repository.
    def base_user
      async_base_user.sync
    end

    # User that owns the head repository.
    def head_user
      async_head_user.sync
    end

    def async_base_user
      return @async_base_user if defined?(@async_base_user)
      @async_base_user = if pull
        pull.async_base_user
      else
        Platform::Loaders::ActiveRecord.load(::User, base_user_login, column: :login, case_sensitive: false)
      end
    end

    def async_head_user
      return @async_head_user if defined?(@async_head_user)
      @async_head_user = if pull
        pull.async_head_user
      else
        Platform::Loaders::ActiveRecord.load(::User, head_user_login, column: :login, case_sensitive: false)
      end
    end

    # The repository that owns the base commit.
    def base_repo
      async_base_repo.sync
    end

    def async_base_repo
      return @async_base_repo if defined?(@async_base_repo)

      @async_base_repo = if @base_repo
        Promise.resolve(@base_repo)
      elsif pull
        pull.async_base_repository
      elsif base && base.include?(":")
        async_base_user.then { |user| repo.find_fork_in_network_for_user(user) }
      else
        Promise.resolve(repo)
      end
    end

    # The repository that owns the head commit.
    def head_repo
      async_head_repo.sync
    end

    def async_head_repo
      return @async_head_repo if defined?(@async_head_repo)

      @async_head_repo = if @head_repo
        Promise.resolve(@head_repo)
      elsif pull
        pull.async_head_repository
      elsif head && head.include?(":")
        async_head_user.then { |user| repo.find_fork_in_network_for_user(user) }
      else
        Promise.resolve(repo)
      end
    end

    # The repository that git commands should be executed against.
    def compare_repository
      async_compare_repository.sync
    end

    def async_compare_repository
      return @async_compare_repository if defined?(@async_compare_repository)

      @async_compare_repository = if pull
        pull.async_compare_repository
      else
        Platform::Loaders::CompareRepository.load(
          repo,
          head_repository: head_repo,
          base_repository: base_repo,
        )
      end
    end

    # Determine if the base and head repository and refs identify actual
    # objects.
    def valid?
      !!(base_repo && head_repo && base_sha && head_sha && base_commit && head_commit && relationship)
    rescue ::GitRPC::ObjectMissing
      false
    end

    # Determine if the comparison crosses repositories. If so, the network
    # repository is used to perform diff and rev-list operations.
    def cross_repository?
      head_repo != repo || base_repo != repo
    end

    def last_modified_at
      @last_modified_at ||= last_modified_from([base_commit, head_commit])
    end

    def track_loaded_associations
    end

    def timer
      return @timer if defined?(@timer)
      @timer = GitHub::TimeoutCounter.new(COMPARISON_GITRPC_TIMEOUT_SECS)
    end

    # The best common ancestor commit between head and base to use as the base of
    # diff and log operations. See git-merge-base(1) for more information.
    #
    # Returns the commit SHA1 of the merge base commit, or nil when the two refs
    #   have no common parent.
    def merge_base
      async_merge_base.sync
    end

    def async_merge_base
      return @async_merge_base if defined?(@async_merge_base)
      @async_merge_base = Promise.all([
        async_compare_repository,
        async_base_oid,
        async_head_oid,
      ]).then do |compare_repo, base_oid, head_oid|
        timer.update do
          compare_repo.best_merge_base(base_oid, head_oid, timeout: timer.remaining)
        rescue ::GitRPC::InvalidObject
          # Temp rescue workaround when base or head shas don't exist
          nil
        end
      end
    end

    # Determine if the base and head ref have commit history in common.
    #
    # Returns true if at least one commit is shared between the two commit
    #   hierarchies, false if they're totes different histories.
    def common_ancestor?
      !merge_base.nil?
    end

    # Determine the head refs relationship with the base ref represented
    # as the number of commits unique to each line. Returns a two-tuple
    # of the form: [behind, ahead]. Each element is the integer number
    # of commits the head line is behind/ahead of the base ref.
    def relationship
      @relationship ||= begin
        if head_sha == GitHub::NULL_OID || head_sha == base_sha
          [0, 0]
        elsif base_sha == GitHub::NULL_OID
          timer.update do
            [0, compare_repository.rpc.fast_commit_count(head_sha, timeout: timer.remaining)]
          end
        else
          ahead, behind = timer.update do
            ahead_behind = compare_repository.rpc.ahead_behind(base_sha, head_sha,
              timeout: timer.remaining)
            ahead_behind[head_sha]
          end

          # It's possible that we got this far because the head commit was in a shared commits cache
          # in a public network, and it's not actually in the repo that this comparison is about.
          #
          # If ahead_behind couldn't find it, behave as if we couldn't find the head commit in the first place.
          raise ::GitRPC::ObjectMissing if [ahead, behind] == [nil, nil]

          [behind, ahead]
        end
      end
    end

    # Number of commits head is behind of base. i.e., commits were added to
    # base after the common ancestor between base and head.
    def behind_by
      relationship.first
    end

    # Number of commits head is ahead of base. i.e., commits were added to
    # head after the common ancestor between base and head.
    def ahead_by
      relationship.last
    end

    # Were commits introduced on base after the common ancestor with head?
    def behind?
      behind_by > 0
    end

    # Were commits introduced on head after the common ancestor with base?
    def ahead?
      ahead_by > 0
    end

    # Are all commits in the head line also included in the base line?
    def merged?
      !ahead?
    end

    # Were commits introduced on both head and base since the common ancestor?
    def diverged?
      behind? && ahead?
    end

    # The head commits relationship to the base commit as a string.
    def status
      case
      when diverged? ; "diverged"
      when ahead?    ; "ahead"
      when behind?   ; "behind"
      else             "identical"
      end
    end

    # Most recent commits in chronological order, not to exceed the limit.
    #
    # Deprecated - use async_commits
    def commits
      async_commits.sync
    end

    def paginated_commits(page:, per_page: COMPARE_PER_PAGE_DEFAULT)
      async_rev_list.then do |rev_list|
        skipped_commits = [(page.to_i - 1) * per_page, 0].max

        commit_oids = rev_list.drop(skipped_commits).take(per_page)
        async_load_commits(commit_oids).then do |commits|
          set_topological_dates(commits)
        end
      end.sync
    end

    def async_commits
      return @async_commits if defined? @async_commits

      @async_commits = async_commit_oids.then do |oids|
        async_load_commits(oids).then do |commits|
          set_topological_dates(commits)
        end
      end
    end

    def set_topological_dates(commits)
      return commits if commits.empty?

      commits.first.topological_date = commits.first.committed_date
      commits.each_cons(2) do |(a, b)|
        b.topological_date = [a.committed_date, b.committed_date].max
      end
      commits
    end

    # Public: load the commits for the given OIDS from either the head or base repository
    #
    # Returns the Commit objects or nil if they could not be found
    def async_load_commits(oids)
      Platform::Loaders::GitObject.load_all(repo, oids, expected_type: "commit",
        alternate_repositories: [repo, head_repo, base_repo])
    end

    # Deprecated - use async_commit_oids
    def commit_ids
      async_commit_oids.sync
    end

    # Most recent commit ids in chronological order, not to exceed the limit.
    def async_commit_oids
      return @async_commit_oids if defined? @async_commit_oids

      @async_commit_oids = async_rev_list.then do |rev_list|
        if limit
          rev_list.last(limit).freeze
        else
          rev_list
        end
      end
    end

    # Public: Checks if the given commit oid is inclusively within the bounds
    #   of this comparison from the merge base to the head commit, or is the
    #   direct parent of the initial commit.
    #
    # commit_oid: the oid of the commit in question
    #
    # Returns true if it is part of the comparison, false otherwise
    def async_covers_commit?(commit_oid)
      async_commit_oids.then do |oids|
        next false if oids.blank?
        next true if oids.include?(commit_oid)

        async_merge_base.then do |merge_base|
          next true if merge_base == commit_oid

          # Fall back to checking the parent commit of
          # the earliest commit on this pull request
          async_load_commits([oids.first]).then do |commits|
            if commit = commits.first
              commit.parent_oids.include?(commit_oid)
            end
          end
        end
      end
    end

    # The number of distinct authors and co-authors of commits in this comparison.
    #
    # NOTE: Only authors of the latest N commits are included in this count, where
    # N corresponds to the greater of the total commits or the limit for the comparison,
    # whichever is smaller.
    #
    # Returns Promise<Integer>
    def async_author_count
      return @author_count if defined?(@author_count)

      @author_count = async_commits.then do |commits|
        commits.map(&:author_emails).flatten.uniq.count
      end
    end

    def diffs_cached?
      init_diffs.entries_cached?
    end

    # A symmetric difference diff between the base and head revs.
    #
    # Use #set_diff_options to establish diff formatting options before accessing
    # this attribute.
    #
    # Returns a GitHub::Diff.
    def diffs
      diffs = init_diffs
      diffs.load_diff
      diffs
    end

    def async_diff(summary: false)
      # Try to return the summary diff whenever we can. Basically, if it has been requested
      # before this invocation we might as well use it as it contains a superset of all the
      # data in a regular diff.
      if summary || summary_diff?
        return @async_summary_diff if defined?(@async_summary_diff)
        @async_summary_diff = async_build_diff(use_summary: true)
      else
        return @async_diff if defined?(@async_diff)
        @async_diff = async_build_diff
      end
    end

    def summary_diff?
      defined?(@async_summary_diff) || (@diff_options && @diff_options["use_summary"])
    end

    def add_context_ranges(context_ranges)
      set_diff_options({ context_lines: context_ranges })
    end

    def async_build_diff(use_summary: false)
      promises = [async_compare_repository, async_head_oid]
      promises << (direct_compare? ? async_base_oid : async_merge_base)

      Promise.all(promises).then do |_compare_repo, head_oid, base_oid|
        options = @diff_options ? @diff_options : {}
        options["timeout"] = timer.min_remaining(options["timeout"])
        options["use_summary"] = use_summary

        GitHub::Diff.new(
          compare_repository,
          base_oid || GitHub::NULL_OID,
          head_oid || GitHub::NULL_OID,
          options,
        )
      end
    end

    def init_diffs
      return @diffs if defined?(@diffs)
      @diffs = async_build_diff.sync
    end

    # Set GitHub::Diff options and reset the memoized diffs object.
    #
    # options - :max_diff_size, :max_total_size, :max_files, :ignore_whitespace.
    #           See GitHub::Diff attribute docs for info on possible values.
    #
    # Returns the options provided.
    def set_diff_options(options)
      remove_instance_variable(:@diffs) if defined?(@diffs)
      @diff_options = options
    end

    def set_context_lines(value)
      remove_instance_variable(:@diffs) if defined?(@diffs)
      if defined?(@diff_options)
        @diff_options[:context_lines] = value
      else
        @diff_options = { context_lines: value }
      end
    end

    def total_commits
      async_total_commits.sync
    end

    # Total number of commits included in this comparison. This may be
    # greater than the commit limit.
    def async_total_commits
      async_rev_list.then do |list|
        list.size
      end
    end

    # Determine if the total number of commits exceeds the limit.
    def commit_limit_exceeded?
      total_commits > limit
    end

    # Determine if there's no commits in this comparison.
    def zero_commits?
      total_commits == 0
    end

    # https://github.com/technoweenie/faraday/compare/e0fa90659a82239888da41c8f7b982b755a2d32d...multipart.patch
    def to_patch_url
      "#{to_url}.patch"
    end

    def to_diff_url
      "#{to_url}.diff"
    end

    def to_path
      if pull
        "/%s/%s/pull/%d" % [
          base_user_login, base_repo.name,
          pull.number]
      else
        "/%s/compare/%s" % [
          repo.name_with_owner_for_api,
          Addressable::URI.encode_component("#{base.try(:b)}#{dots}#{head.try(:b)}", Addressable::URI::CharacterClasses::PATH),
        ]
      end
    end

    def dots
      direct_compare? ? ".." : "..."
    end

    def to_url
      "#{GitHub.url}#{to_path}"
    end

    def to_permalink_url
      "%s/%s/%s/compare/%s...%s" % [
        GitHub.url,
        base_user_login,
        base_repo.name,
        [base_user_login, base_sha[0, 7]].join(":"),
        [head_user_login, head_sha[0, 7]].join(":"),
      ]
    end

    # The list of commit SHA1s from the base to the head commit in chronological
    # order:
    #   git rev-list base..head
    #
    # This may include up to 10K commit SHA1s.
    def async_rev_list
      return @rev_list if defined?(@rev_list)

      @rev_list = Promise.all([
        async_compare_repository,
        async_base_oid,
        async_head_oid,
      ]).then do |compare_repository, base_oid, head_oid|
        if head_oid.nil? || head_oid == GitHub::NULL_OID
          []
        elsif base_oid == GitHub::NULL_OID
          compare_repository.async_rpc.then do |rpc|
            rpc.rev_list(head_oid, reverse: true)
          end
        else
          compare_repository.async_rpc.then do |rpc|
            rpc.rev_list(head_oid, exclude_oids: base_oid, reverse: true)
          end
        end
      end
    end

    def rev_list
      async_rev_list.sync
    end

    # Build and return a new PullRequest for the comparison.
    def build_pull_request(attributes = {})
      ComparisonPullRequest.build(PullRequest, self, attributes)
    end

    # Public: Find all comments associated with a commit in this Comparison.
    #
    # Deprecated - use async_visible_comments_for or, if you must, all_comments
    #
    # Note that the returned results are not filtered for spam or by capabilities.
    #
    # Returns an ActiveRecord::Scope<CommitComment>
    def comments
      return @comments if defined?(@comments)
      @comments = async_commit_oids.then { |oids| all_comments(oids).includes(:user) }.sync
    end

    # Deprecated - use async_visible_comments_for instead
    def comments_for(viewer)
      @comments_for ||= {}
      @comments_for[viewer] ||= comments.filter_spam_for(viewer)
    end

    # Public: Find all comments associated with a commit in this Comparison
    # that the viewer (User) can see. Cached by viewer.
    #
    # viewer - the User who is viewing the comments
    #
    # Returns a Promise<ActiveRecord::Scope<CommitComment>>
    def async_visible_comments_for(viewer)
      @async_comments ||= Hash.new
      @async_comments[viewer] ||= async_commit_oids.then do |oids|
        all_comments(oids).filter_spam_for(viewer).reorder("commit_comments.created_at ASC")
      end
    end

    def to_diff(full_index: false)
      timer.update do
        compare_repository.rpc.native_diff_text(base_sha, head_sha, full_index: full_index, timeout: timer.remaining)
      end
    end

    def to_patch(full_index: false)
      timer.update do
        compare_repository.rpc.native_patch_text(base_sha, head_sha, full_index: full_index, timeout: timer.remaining)
      end
    end

    # Does the user have access to the repositories being compared?
    def viewable_by?(user)
      return false unless base_repo && head_repo

      return false unless base_repo.resources.contents.readable_by?(user)
      return false unless head_repo.resources.contents.readable_by?(user)

      # If an app is performing a user-to-server request via
      # the API, we need to make sure the app has access to both
      # the base_repo and head_repo.
      #
      # See https://github.com/github/github/issues/145560
      # for more details.
      if user && user.using_auth_via_granular_actor?
        result = if GitHub.flipper[:find_grantable_from_permissions].enabled?
          viewable_by_user_using_granular_actor_candidate?(user)
        else
          viewable_by_user_using_granular_actor_control?(user)
        end

        return unless result
      end

      !base_repo.hide_from_user?(user) &&
      !head_repo.hide_from_user?(user)
    end

    def viewable_by_user_using_granular_actor_control?(user)
      base_repo_grant = ProgrammaticActor::Grant.with(user).with_target(base_repo.owner)
      return false unless base_repo.resources.contents.readable_by?(base_repo_grant)

      head_repo_grant = ProgrammaticActor::Grant.with(user).with_target(head_repo.owner)
      return false unless head_repo.resources.contents.readable_by?(head_repo_grant)

      true
    end

    def viewable_by_user_using_granular_actor_candidate?(user)
      base_repo_grant = ProgrammaticActor::Grant.with(user).with_repository(base_repo)
      return false unless base_repo.resources.contents.readable_by?(base_repo_grant)

      head_repo_grant = ProgrammaticActor::Grant.with(user).with_repository(head_repo)
      return false unless head_repo.resources.contents.readable_by?(head_repo_grant)

      true
    end

    def click_tracking_attributes
      @click_tracking_attributes ||= {
        base_repo: base_repo&.nwo,
        base_ref: display_base_revision,
        head_repo: head_repo&.nwo,
        head_ref: display_head_revision,
        number_of_commits: total_commits,
        number_of_files: diffs.changed_files,
        number_of_contributors: async_author_count.sync
      }
    rescue GitRPC::InvalidFullOid
      # don't fail if there are errors fetching git data.
      {}
    end

    #
    # INTERNAL METHODS
    #

    def scrubbed_utf8(text)
      text.nil? ? nil : text.dup.force_encoding("utf-8").scrub!
    end

    # Internal - find the oid for the revision, first by treating it as a ref, then by checking
    #            to see if it is an oid.
    def async_oid(repo, revision)
      if GitRPC::Util.valid_full_sha1?(revision)
        Promise.resolve(revision)
      elsif repo
        repo.async_ref_to_sha(revision&.b)
      else
        Promise.resolve(nil)
      end
    end

    # Internal - All comments for this comparison, no filtering for the viewer.
    def all_comments(oids)
      CommitComment.where(

        # TODO: remove repo from this list when fully graphql converted
        repository_id: [head_repo, base_repo, repo].compact.map(&:id).uniq,
        commit_id:     oids,
      ).order("created_at DESC")
    end
  end
end
