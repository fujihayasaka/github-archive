# typed: true
# frozen_string_literal: true

# Repository methods related to reading, listing, searching, and writing
# Commit objects through a Repository object. This object is exposed at
# Repository#commits and is typically accessed like this:
#
#   repo = Repository.with_name_with_owner("github/github")
#   repo.commits.find('deadbee...')
#
class CommitsCollection
  include Scientist

  # Used when there is an error creating a merge commit
  class MergeError < StandardError
  end

  # Used when there is an error creating a revert commit
  class RevertError < StandardError
  end

  class CurrentUserValidationError < StandardError; end

  class PaginatedCommitCollection < WillPaginate::Collection
    attr_accessor :filters
  end

  # The Repository object whose commits we're operating on.
  attr_reader :repository

  # Create a CommitsCollection.
  #
  # repository - A Repository like object. This must respond to #rpc
  #              and return object compatible with the Repository versions of
  #              those methods. Gist currently emulates this interface.
  #
  # NOTE CommitsCollection objects are not typically instantiated directly. Use
  # Repository#commits or Gist#commits instead.
  def initialize(repository)
    @repository = repository
  end

  # Internal: Available git access interfaces.
  delegate :rpc,    to: :repository

  # Build a new Commit object with the given information.
  #
  # info - See Commit#initialize for supported attributes.
  #
  # Returns a new Commit object with the given attributes.
  def build(info = {})
    Commit.new(repository, info.stringify_keys)
  end

  # Public: Create a new commit in the underlying repository.
  #
  # Use Ref#create_commit or Ref#append_commit instead. The is only meant for internal usages.
  #
  # metadata         - The commit metadata hash. See the extended documentation for
  #                    details on this data structure.
  # parent           - The 40 character SHA1 oid of the parent commit, or nil to create a
  #                    new tree.
  # sign:            - Boolean of whether to try to sign the commit.
  # target_ref_name  - (Optional) The proposed ref that will point to the commit.
  # skip_rule_evaluation - (Optional) Indicates whether rule evaluation should be skipped. This is only
  #                        necessary for creating temporary commits and should otherwise be avoided.
  #
  # You can add file changes to the commit in one of two ways: 1) passing a block
  # or 2) fetching from an existing tree oid.
  #
  # When passing a block, it should accept one argument, which will be an
  # empty CommitsCollection::Files object (see the CommitsCollection::Files
  # documentation at the bottom of this file). The commit's files should be
  # built up in that object.
  #
  # When fetching files from an existing tree, include the tree oid
  # in the metadata.
  #
  # Examples:
  #
  #   * Passing a block:
  #
  #     head_oid = "3572d83ba062076f6a740379463d0f3f770d7fc5"
  #     repository.commits.create({message: "foo"}, head_oid) do |files|
  #       files.add("my_new_file.txt", "check this out!\n")
  #     end
  #
  #   * Fetching from tree:
  #
  #     head_oid = "3572d83ba062076f6a740379463d0f3f770d7fc5"
  #     tree_oid = "d9d67f971d948d0b43f1d91ead123e0b969556fe"
  #     repository.commits.create({message: "foo", tree: tree_oid}, head_oid)
  #
  # The metadata argument is for specifying commit metadata. The expected keys
  # for the hash are:
  #
  # :message        - (Required) String commit message.
  # :committer      - (Optional) User who created the commit. This can either be
  #                   a User object or a hash with :name and :email keys.
  # :committed_date - (Optional) ISO8601-formatted string representing when the
  #                   commit was created. Time.zone.now will be used if none is
  #                   specified.
  # :author         - (Optional) User who authored the commit. :author has the
  #                   same format as :committer, and :committer will be used if
  #                   no author is specified.
  # :authored_date  - (Optional) ISO8601-formatted string representing when the
  #                   commit was authored. :committed_time will be used if
  #                   there is no :authored_time specified, and Time.zone.now will
  #                   be used if neither is specified.
  # :tree           - (Optional) The 40 character SHA1 oid of an existing tree.
  #                   When included, builds files from the given tree. Do not
  #                   include :tree if passing a block, because this will raise
  #                   an ArgumentError.
  # :current_user   - (Optional) User who is responsible for this operation used for attributing
  #                  pre-receive rule evaluation
  #
  # Returns a new Commit object.
  # Raises Commit::InvalidError if the commit is invalid.
  def create(metadata, parent = nil, sign: false, target_ref_name: nil, skip_rule_evaluation: false)
    tree = metadata[:tree]

    if tree.present? && block_given?
      raise ArgumentError, "Block not allowed when tree is passed"
    end

    if !block_given? && tree.blank?
      raise ArgumentError, "Files block or tree must be passed"
    end

    committer = metadata[:committer]
    author = metadata[:author]

    if author.nil? && committer.nil?
      raise ArgumentError, "committer or author must be specified"
    end

    # The author params are passed into the build method via the info hash
    author ||= committer
    author_name, author_email = User.git_author_info(author)

    if metadata[:author_email]
      author_email = metadata[:author_email]
      unless GitHub.choose_commit_email_enabled? && author.emails.verified.pluck(:email).include?(author_email)
        raise ArgumentError, "invalid email for web commit"
      end

      # Set this as the default web commit email
      author.update_default_author_email_cache(repository, author_email)
    end

    committer_name, committer_email = if committer.nil?
      [GitHub.web_committer_name, GitHub.web_committer_email]
    else
      User.git_author_info(committer)
    end

    committed_date = metadata[:committed_date] || metadata[:authored_date] || Time.zone.now.iso8601
    authored_date = metadata[:authored_date] || committed_date

    info = {
      "type"      => "commit",
      "parents"   => [parent],
      "message"   => metadata[:message],
      "committer" => [committer_name, committer_email, committed_date],
      "author"    => [author_name, author_email, authored_date],
    }
    info["tree"] = tree if tree.present?

    files = Files.new(repository, parent)
    yield(files) if block_given?

    files_hash = files.to_hash

    rule_suite = check_pre_receive_rules(metadata[:message], author, author_email, committer_email, files_hash, parent, target_ref_name:, current_user: metadata[:current_user]) unless skip_rule_evaluation

    commit = build(info).create(files_hash, sign: sign)

    if commit && rule_suite&.persisted?
      rule_suite.after_oid = commit.oid
      rule_suite.save!
    end

    publish_commit_created_event(repository: repository, created_sha: commit.oid) if commit
    commit
  end

  # Find a single or multiple commits from the underying git repository. This is
  # main commit reading chokepoint. Commit metadata should not be read without
  # going through this method.
  #
  # commit_oids        - Either a single string oid or an array of oids.
  # check_reachability - check if the commits are reachable (from branches or tags)
  #                      non-reachable commits will be treated as if they don't exist
  #                      (optional, default: false)
  #
  # Returns a single Commit object in the single commit form, or an array of
  # Commit objects in the multiple commit form. Returns nil or an empty array for
  # a nil argument or if any other GitRPC errors are raised.
  #
  # Raises ArgumentError when commit_oids includes malformed oids.
  # Raises GitRPC::ObjectMissing when any of the requested commits does not exist.
  # Raises GitRPC::InvalidObject when an object was found but is not a commit.
  def find(commit_oids, check_reachability: false)
    return if commit_oids.nil?

    oids = downcase_oids(commit_oids)
    objects = repository.objects.read(oids, "commit")

    return objects unless check_reachability

    repository.rpc.commits_visible(Array(oids)).each do |oid, visible|
      raise GitRPC::ObjectMissing.new("commit not reachable", oid) unless visible
    end

    objects
  rescue GitRPC::Failure => boom
    if boom.original.class == Rugged::InvalidError
      raise ArgumentError, boom.original.message
    elsif commit_oids.is_a?(Array)
      []
    else
      nil
    end
  end

  # Public: Check if an object exists and is a commit object.
  #
  # commit_oids        - Either a single string oid or an array of oids.
  # check_reachability - check if the commits are reachable (from branches or tags)
  #                      non-reachable commits will be treated as if they don't exist
  #                      (optional, default: false)
  #
  # Returns true when all commit oids provided have an associated commit object
  # available in the object store.
  def exist?(commit_oids, check_reachability: false)
    result = repository.objects.exist?(commit_oids, "commit")
    return result unless result && check_reachability

    repository.rpc.commits_visible(Array(commit_oids)).values.uniq == [true]
  end

  # Public: List commit history starting at the given commit and walking the
  # given number of maximum versions.
  #
  # commit_oid - The string oid of a commit to start from. This must be a full
  #              oid, not a ref or abbreviated sha1.
  # max        - Maximum number of revisions to include in result list.
  # skip       - Number of commits to skip before listing.
  # path       - Optional path to tree entry to filter history on.
  #
  # Returns an array of Commit objects.
  # Raises GitRPC::ObjectMissing, GitRPC::InvalidObject
  def history(commit_oid, max = nil, skip = 0, path = nil)
    oids = repository.revision_list(commit_oid, max, skip, path)
    find(oids)
  end

  # Public: List commit history starting at a given commit with support for
  # pagination.
  #
  # start_sha - The commit to start at as a full oid.
  # page      - The page we're on. Default: 1
  # per_page  - How many commits per page. Default: 30
  # path      - A string path to the tree entry to limit history to.
  #
  # Returns a WillPaginate::Collection of commits.
  def paged_history(commit_oid, page = 1, per_page = 30, path = nil, ignore_merge_commits = false)
    page = 1 if page.blank? || page.to_i < 1
    page = (page || 1).to_i
    path = nil if path.blank?
    skip = (page - 1) * per_page

    oids = repository.revision_list(commit_oid, per_page + 1, skip, path, ignore_merge_commits)
    commits = find(oids.to_a)
    collection = PaginatedCommitCollection.new(page, per_page, skip + commits.length)
    collection.replace commits.take(per_page).compact
  end

  # Public: Load all commits reachable from a given set of commit oids
  # excluding commits reachable from another set of commit oids.
  #
  # heads   - Array of commit oids to start walking from.
  # exclude - Array of commit oids which cause traversing to stop.
  # max     - The maximum number of commits to return.
  #
  # Returns an array of Commit objects.
  def except(heads = [], exclude = [], max = nil)
    oids = rpc.list_revision_history_multiple(heads, exclude: exclude, max: max)
    find(oids)
  end

  # Public: Search commit authors, committers, or messages
  #
  # choice    - Type of search. Must be 'grep' (messages), 'author', or 'committer'.
  # query     - What to search for. This is an extended regular expression string.
  # commitish - Ref name, oid, or anything that can be resolved to a commit.
  #
  # Returns an array of Commit objects that match the query.
  def search(choice, query, commitish = "master")
    if %w( author committer ).include?(choice) && user = User.find_by_login(query)
      query += "|#{user.emails.map(&:email).join("|")}"
    end

    oids = rpc.search_revision_history(choice, query, commitish, max: 100)
    find(oids)
  end

  # Public: Finds a commit given a SHA
  #
  # This is different from `find` because a full OID is not needed
  #
  # sha                - a string commit SHA
  # check_reachability - check if the commit is reachable (from branches or tags)
  #                      non-reachable commits will be treated as if they don't exist
  #                      (optional, default: false)
  #
  # Returns a Commit object if found, or nil otherwise.
  def find_for_sha(sha, check_reachability: false)
    repository.objects.verify_sha_format(sha)

    if sha.length == 40
      oid = sha
    else
      begin
        oid = repository.spokes_api.resolve_object(object_name: sha)
      rescue GitRPC::Failure => boom # e.g. ambiguous SHA1 prefix
        raise unless boom.original.class == Rugged::OdbError
        return
      end
      return if oid.blank?
      return unless oid.starts_with?(sha)
    end

    find(oid, check_reachability: check_reachability)
  rescue GitRPC::InvalidObject, GitRPC::ObjectMissing
    nil
  end

  # Public: Loads the most recent commit for a given path and ref. Attempts to
  # find it in memcache, falls back to fileservers if it cannot be found.
  #
  # ref  - The ref name (branch, tag, commit) that you're browsing at
  # path - The path as a String.
  #
  # Returns a Commit.
  def last_touched(ref, path = "")
    commit_oid = repository.ref_to_sha(ref)
    return nil unless commit_oid

    # If we're at the root of the directory structure, ref is the latest commit
    if path.blank?
      begin
        return find(commit_oid)
      rescue GitRPC::ObjectMissing
        return nil
      end
    end

    # Create a TreeHistory object to find the last commit that touched path.
    parts = path.split("/")
    basename = parts.pop
    dirname = parts.join("/")
    tree_history = repository.directory(commit_oid, dirname).tree_history
    tree_history.load_or_calculate_single_entry(basename)
  end

  # Create a merge commit.
  #
  # If you just want to perform a merge, use the Ref#merge method instead. This just
  # creates a lone merge commit from the two parents without updating the base
  # ref. Used internally by Ref#merge as well as by the PullRequest model.
  #
  # author  - The User who will be the author of the merge commit
  # base    - a String ref or commit OID
  # head    - a String ref or commit OID
  # options - a Hash of options (default: {})
  #           :commit_message - Optional String to use as the commit message for the merge commit
  #           :commit_time - Optional Time to use as the commit date for the merge commit
  #
  # Returns a tuple of [Commit, error], only one of which will be present.
  #
  # Possible errors:
  #   :merge_conflict - if the merge failed due to a conflict
  #   :already_merged - if there was nothing to merge
  #   :error          - a situation we couldn't handle. Usually a busted repo.
  def create_merge_commit(author, base, head, options = {})
    message = options[:commit_message] || "Merge #{head} into #{base}"
    time = options[:commit_time] || Time.current
    author_name, author_email = User.git_author_info(author)
    author_email = options[:author_email] || author_email

    author_sig = {
      name: author_name,
      email: author_email,
      time: time,
    }

    committer_sig = web_committer_signature(time)

    rule_suite = check_pre_receive_rules(message, author, author_email, author_email, options[:resolve_conflicts], current_user: author) unless options[:resolve_conflicts].blank?

    result, error, details = repository.create_merge_commit(
      base,
      head,
      author_sig,
      message,
      check_tree_with_diff: FeatureFlag.vexi.enabled_or_raise?(:create_merge_commit_check_tree_with_diff, repository), # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      committer: committer_sig,
      resolve_conflicts: options[:resolve_conflicts],
      record_conflicts: true,
      more_conflict_info: true,
      &repository.method(:sign_commit)
    )

    if result && rule_suite&.persisted?
      rule_suite.after_oid = result
      rule_suite.save!
    end

    case error
    when nil
      commit = find(result)
      publish_commit_created_event(repository: repository, created_sha: commit.oid) if commit
      [commit, nil]
    when "merge_conflict"
      [nil, :merge_conflict, details]
    when "already_merged"
      [nil, :already_merged]
    when "error"
      boom = MergeError.new("GitRPC create_merge_commit failed")
      boom.set_backtrace(caller)
      Failbot.report(boom, {
        "gh.repo.id": repository.id,
        "git.commit.author.name": author.git_author_name,
        "git.commit.author.email": author_email,
        "git.commit.result": result,
      })
      [nil, :error]
    end
  rescue GitRPC::ObjectMissing
    GitHub.dogstats.increment("commits", tags: ["action:create_merge", "error:object_not_found"])
    [nil, :error]
  end

  # Rebase commits.
  #
  # This rebases the commits specified via `head` onto `base` without updating the
  # refs. Used internally by Ref#merge as well as by the PullRequest model.
  #
  # head    - a String ref or commit OID
  # base    - a String ref or commit OID
  # options - a Hash of options (default: {})
  #           :commit_time - Optional Time to use as the commit date for the rebased commits
  #
  # Returns a tuple of [Commit, error], only one of which will be present.
  #
  # Possible errors:
  #   :merge_conflict - if the merge failed due to a conflict
  #   :error          - a situation we couldn't handle. Usually a busted repo.
  def rebase(head, base, options = {})
    time = options[:commit_time] || Time.current
    committer_sig = web_committer_signature(time)

    extra_options = {
      use_tmp_objdir_mode: "migrate-on-success"
    }

    if FeatureFlag.vexi.enabled_or_raise?(:tmp_objdir_experiment, repository) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      extra_options[:use_tmp_objdir_mode] = "pack-and-migrate-on-success" if FeatureFlag.vexi.enabled_or_raise?(:tmp_objdir_experiment_pack, repository) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      result, dogstats = repository.rpc.rebase_tmp_objdir_experiment(
        head,
        base,
        committer_sig,
        **extra_options,
        &repository.method(:sign_commit)
      )
      dogstats.each { |args| GitHub.dogstats.count(*args) }
    else
      result = repository.rpc.rebase(
        head,
        base,
        committer_sig,
        **extra_options,
        &repository.method(:sign_commit)
      )
    end

    return [nil, :merge_conflict] if result.nil?
    commit = find(result)
    publish_commit_created_event(repository: repository, created_sha: commit.oid) if commit
    [commit, nil]
  rescue GitRPC::ObjectMissing
    GitHub.dogstats.increment("commits", tags: ["action:rebase", "error:object_not_found"])
    [nil, :error]
  end

  # Create a revert commit
  #
  # author          - the User responsible for the revert commit
  # head_commit_oid - the OID of the head commit to build the revert on top of
  # commit_oid      - the OID of the commit to revert
  # Options:
  #   :message  - message to use for the commit
  #   :mainline - if reverting a merge commit, the parent number
  #               to be used as the "mainline"
  #
  # Returns a tuple of [Commit, error], only one of which will be present.
  #
  # Possible errors:
  #   :merge_conflict - if the revert failed due to a conflict
  #   :error          - a situation we couldn't handle. Usually a busted repo.
  def create_revert_commit(author, head, revert, options = {})
    commit_message = options[:commit_message] || "Revert #{revert}"

    author_name, author_email = User.git_author_info(author)
    author_sig = {
      name: author_name,
      email: author_email,
      time: Time.current,
    }

    committer_sig = web_committer_signature
    args = [revert, head, author_sig, committer_sig, commit_message, options[:mainline]]

    result, error = repository.rpc.create_revert_commit(*args, &repository.method(:sign_commit))

    case error
    when nil
      commit = find(result)
      publish_commit_created_event(repository: repository, created_sha: commit.oid) if commit
      [commit, nil]
    when "merge_conflict"
      [nil, :merge_conflict]
    when "error"
      boom = RevertError.new("GitRPC create_revert_commit failed")
      boom.set_backtrace(caller)
      Failbot.report(boom, {
        "gh.repo.id": repository.id,
        "git.commit.author.name": author.git_author_name,
        "git.commit.author.email": author.git_author_email,
        "git.commit.result": result,
      })
      [nil, :error]
    end
  rescue GitRPC::ObjectMissing
    GitHub.dogstats.increment("commits", tags: ["action:create_revert", "error:object_not_found"])
    [nil, :error]
  end

  # Public: Create revert commits for all commits between `range_start_commit` and
  # `range_end_commit`.
  #
  # Note: The list of reverted commits will not include `range_start_commit`.
  #
  # author             - the User responsible for the revert commit
  # head_commit_oid    - the OID of the head commit to build the revert on top of
  # range_start_commit - the OID of the start of the commit range. This commit
  #                      will not be reverted.
  # range_end_commit   - the OID of the end of the commit range. This commit
  #                      will be reverted.
  #
  # Options:
  #   :timeout      - maximum amount of time to spend on reverting the commits.
  #
  # Returns a tuple of [Commit, error], only one of which will be present.
  #
  # Possible errors:
  #   :merge_conflict - if the revert failed due to a conflict.
  #   :timeout        - if the revert took longer than the given timeout value.
  #   :error          - a situation we couldn't handle. Usually a busted repo.
  def create_revert_commits_for_range(author, head_commit_oid, range_start_commit, range_end_commit, timeout: nil)
    author_name, author_email = User.git_author_info(author)
    author_sig = {
      name: author_name,
      email: author_email,
      time: Time.current,
    }

    committer_sig = web_committer_signature

    result, error = repository.rpc.create_revert_commits_for_range(
      range_start_commit,
      range_end_commit,
      head_commit_oid,
      author_sig,
      committer_sig,
      timeout: timeout,
    )

    case error
    when nil
      commit = find(result)
      publish_commit_created_event(repository: repository, created_sha: commit.oid) if commit
      [commit, nil]
    when "timeout"
      [nil, :timeout]
    when "merge_conflict"
      [nil, :merge_conflict]
    when "error"
      boom = RevertError.new("GitRPC create_revert_commits_for_range failed")
      boom.set_backtrace(caller)
      Failbot.report(boom, {
        "gh.repo.head_oid": head_commit_oid,
        "gh.repo.range_start_commit": range_start_commit,
        "gh.repo.range_end_commit": range_end_commit,
        "gh.repo.id": repository.id,
        "git.commit.author.name": author.git_author_name,
        "git.commit.author.email": author.git_author_email,
        "git.commit.result": result,
      })
      [nil, :error]
    end
  rescue GitRPC::ObjectMissing
    GitHub.dogstats.increment("commits", tags: ["action:create_revert_for_range", "error:object_not_found"])
    [nil, :error]
  end

  private

  # Internal: downcase an Array or a String of a single oid.
  #
  # commit_oids - an Array or String oid.
  #
  # Returns an Array or a String oid.
  def downcase_oids(commit_oids)
    if commit_oids.is_a?(Array)
      commit_oids.map(&:downcase)
    else
      commit_oids.downcase
    end
  end

  # Committer signature to use for commits created through the web ui.
  #
  # time - The time to include in the signature (optional).
  #
  # Returns a Hash.
  def web_committer_signature(time = Time.current)
    {
      name: GitHub.web_committer_name,
      email: GitHub.web_committer_email,
      time: time,
    }
  end

  # XXX this method is basically duplicated in Ref
  def git_user_env(person, time)
    name, email = User.git_author_info(person)
    now = time.to_formatted_s(:git)

    {
      "GIT_AUTHOR_NAME"     => name,
      "GIT_AUTHOR_EMAIL"    => email,
      "GIT_AUTHOR_DATE"     => now,
      "GIT_COMMITTER_NAME"  => name,
      "GIT_COMMITTER_EMAIL" => email,
      "GIT_COMMITTER_DATE"  => now,
      "TZ"                  => Time.zone.tzinfo.name,
    }
  end

  # Internal: Evaluates the pre-receive rules for the repository.
  #
  # message - The commit message
  # author - The User who pushed the commit or a Hash including name and/or email
  # author_email - The email address of the author
  # committer_email - The email address of the committer
  # files - Hash of file paths to file contents
  # parent - The parent commit OID
  # target_ref_name - The target ref that will point to the commit
  # current_user - The User who is responsible for the operation
  #
  sig do
    params(
      message: T.nilable(String),
      author: T.any(User, T::Hash[String, String]),
      author_email: String,
      committer_email: String,
      files: T::Hash[String, T.any(T.nilable(String), T::Hash[String, String])],
      parent: T.nilable(String),
      target_ref_name: T.nilable(String),
      current_user: T.nilable(User),
    )
    .returns(T.nilable(RuleEngine::RuleSuite))
  end
  def check_pre_receive_rules(message, author, author_email, committer_email, files, parent = nil, target_ref_name: nil, current_user: nil)
    return unless repository.is_a?(Repository)

    actor = if current_user.is_a?(User)
      current_user
    else
      User.ghost
    end

    files = files.map do |path, payload|
      content = if payload.is_a?(Hash)
        payload["data"]
      else
        payload
      end

      [path, content]
    end.to_h

    rule_suite = RuleEngine::Evaluator.evaluate_pre_commit_rules(
      repository,
      parent,
      actor,
      {
        message:,
        author_email:,
        committer_email:,
        blobs: files,
      },
      target_ref_name:
    )

    raise Git::Ref::RepositoryRuleViolationError.new(rule_suite) unless rule_suite.action_permitted?

    rule_suite
  end

  sig do
    params(
      repository: T.any(::Repository, ::Gist, GitHub::Unsullied::Wiki),
      created_sha: String,
    ).void
  end
  def publish_commit_created_event(repository:, created_sha:)
    # We only publish events for commits in a repository - not Gists or Wikis.
    return unless repository.is_a?(::Repository)
    GitHub.aqueduct_fallback_hydro_publisher.publish(
      {
        repository_id: repository.id,
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        created_at: Time.now,
        commit_shas: [created_sha],
        enabled_flags: Repositories::HydroPushJobFlags.enabled_for_repo(repository)
      },
      schema: "github.repositories.v1.CommitsCreated",
      partition_key: repository.id
    )
  end

  # Internal: Class for keeping track of what files the user wants to add,
  # remove, and move in a commit.
  #
  # Example usage:
  #
  # files = CommitsCollection::Files.new(repo)
  # files.to_hash
  # => {}
  # files.add('README.md', 'My data here!')
  # files.remove('path/to/file.rb')
  # files.move('some/thing.rb', 'different/thing.rb', 'More data!')
  # files.to_hash
  # => {
  #      'README.md' => 'My data here!',
  #      'path/to/file.rb' => nil,
  #      'some/thing.rb' => nil
  #      'different/thing.rb' => 'More data!'
  #    }
  class Files
    def initialize(repo, parent = nil)
      @repo   = repo
      @parent = parent
      @files  = {}
    end

    # Public: Add a file to be included in the commit.
    #
    # filename - Name of the file to be added (can include subdirs)
    # data     - Data that the file should contain
    # mode     - the mode for the file to set its permissions, as an integer; leave nil to keep
    #            default mode; e.g., 0100644
    #
    # Returns nothing.
    def add(filename, data, mode: nil)
      raise ArgumentError, "Can't add a file with no content" unless data
      @files[filename] = if mode
        { "mode" => mode, "data" => data }
      else
        data
      end
    end

    # Public: Add a file to be deleted in the commit. This call can only be made
    # if a parent commit was included.
    #
    # filename - Name of the file to be deleted (can include subdirs)
    #
    # Returns nothing.
    def remove(filename)
      @files[filename] = nil
    end

    # Public: Move a file to a new location in the repository. This call can
    # only be made if a parent commit was included.
    #
    # old_filename - Name of the file currently
    # new_filename - Where the file should be moved to
    # data         - Data that the file should contain after being moved.
    #
    # Returns nothing.
    def move(old_filename, new_filename, data)
      raise ArgumentError, "Can't add a file with no content" unless data
      @files[new_filename] = { "source" => old_filename, "data" => data }
    end

    # Public: Convert this to a hash that's ready to be passed to
    # create_tree_changes.
    #
    # Returns a Hash.
    def to_hash
      @files.dup
    end
  end
end
