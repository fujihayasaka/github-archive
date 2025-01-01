# typed: true
# frozen_string_literal: true

# Git Commit object. This encapsulates all app-level commit related behavior.
# To read commits from underlying git storage:
#
#     repository = Repository.with_name_with_owner("github/github")
#     commit = repository.commits.find('deadbee...')
#
# The CommitsCollection (repository.commits) object includes a bunch of commit
# access and manipulation methods. Use it to lookup, search, list, and write
# commits to a repository.
class Commit
  include GitRPC::Util
  include Commits::CommitMessageable
  include GitSigning::Verifiable
  include GitHub::Relay::GlobalIdentification
  include Notifications::SubscribableThread
  include PreloadableAttributes
  include GitHub::BatchMethod

  ABBREVIATED_OID_LENGTH = 7
  NIL_PROMISE = Promise.resolve(nil)
  PATH_TEMPLATE = Addressable::Template.new("/{user}/{repo}/commit/{oid}")
  EVENT_TYPES = %w[locked unlocked]

  class Error < StandardError; end
  class UnprefilledCombinedStatus < Error; end

  # Raised when attempting to create a commit with multiple parents
  class MultipleParentsError < Error; end

  class AssociatedPullRequestSearchFailed < Error; end

  attr_preloadable :committer,
                   :git_signing_signature,
                   :has_status_check_rollup,
                   :message_body_html,
                   :on_behalf_of,
                   :path,
                   :short_message_html,
                   :status_check_rollup,
                   :verification_status

  # The Repository object this Commit is bound to.
  attr_reader :repository, :git_signing_signature

  def repository=(repository)
    check_repository_type(repository)
    @repository = repository
  end

  # allow for assigning a set of repositories.
  # For example, the head and base repos in the context of a forked repo PR.
  attr_reader :repositories

  def repositories=(repos)
    @repositories = Set.new
    Array(repos).each do |repo|
      check_repository_type(repo)
      @repositories.add(repo)
    end

    @repositories
  end

  # The base repository, if any, such as for a forked repo PR.
  attr_reader :base_repository

  def base_repository=(repo)
    @base_repository = repo
    @repositories ||= Set.new

    if repo
      check_repository_type(repo)
      @repositories.add(repo)
    end

    @base_repository
  end

  # The head repository, if any, such as for a forked repo PR.
  attr_reader :head_repository

  def head_repository=(repo)
    @head_repository = repo
    @repositories ||= Set.new

    if repo
      check_repository_type(repo)
      @repositories.add(repo)
    end

    @head_repository
  end

  # The 40 char commit oid string.
  attr_accessor :oid

  # The commit message string exactly as it exists in the commit. No tidying of
  # newlines or spaces is present in this value.
  attr_accessor :message

  # Hash of expanded shas found in the commit message.
  attr_accessor :message_shas

  # The commit's parents as an array of string commit oids.
  attr_accessor :parent_oids

  # The commit's tree oid.
  attr_accessor :tree_oid

  # Commit author information as given in the commit.
  attr_accessor :author_name, :author_email

  # Commit author and co-author information as given in the commit.
  attr_accessor :author_names, :author_emails

  # Organization name and email that the commit is made on behalf of
  attr_accessor :on_behalf_of_raw

  # Commit signed-off-by information.
  attr_accessor :sign_off_actor

  # Time object representing when the commit was first authored.
  attr_writer :authored_date

  # Committer information as given in the commit.
  attr_accessor :committer_name, :committer_email

  # Time object representing when the commit was last changed.
  attr_writer :committed_date

  # Preference to skip automatic creation of Check Suites.
  attr_accessor :skip_checks

  # Whether the commit has Co-authored-by or Signed-off-by trailers
  attr_accessor :has_authored_by_or_signed_off_trailers

  # Preference to request creation of Check Suites (when automatically off).
  attr_accessor :request_checks

  # True if we should display a "load more" button for discussion comments
  attr_accessor :can_load_more_comments
  alias_method :can_load_more_comments?, :can_load_more_comments

  # Public: Prefill Commit#comment_count association
  #
  # See CommitComment.attach_counts_to_commits
  #
  # commits    - Array of Commit objects
  # repository - Repository object
  #              (optional, defaults to repository on first passed commit)
  #
  # Returns the array of Commit objects with their comment-count values set
  # (also modifies the passed-in Commit objects)
  def self.prefill_comment_counts(commits, repository = nil)
    CommitComment.attach_counts_to_commits(commits, repository)
  end

  batch_method(:prelude_comment_count) do |commits, repository|
    comment_counts_by_oid = repository.commit_comments.where(commit_id: commits.map(&:oid)).group(:commit_id).count

    commits.index_with do |commit|
      comment_counts_by_oid[commit.oid] || 0
    end
  end

  # A CombinedStatus object associated with this Commit. This is typically
  # eager-loaded, see Commit.prefill_combined_statuses
  def combined_status
    if defined? @combined_status
      @combined_status
    else
      error = UnprefilledCombinedStatus.new("Commit<#{oid}>#combined_status was accessed, but never prefilled")
      if Rails.env.development? || Rails.env.test?
        raise error
      else
        Failbot.report(error)
        nil
      end
    end
  end
  attr_writer :combined_status

  # Public: Prefill Commit#combined_status association on an array of Commits
  #
  # commits - Array of Commits.
  # repository - The Repository to use for loading statuses.
  #
  # Returns commits input with each entry's #combined_status set
  def self.prefill_combined_statuses(commits, repository)
    return commits if commits.empty?
    combined_statuses = CombinedStatus.combined_statuses_for_shas(repository, commits.map(&:oid))
    commits.each_with_index do |commit, _index|
      commit.combined_status = combined_statuses[commit.oid]
    end

    commits
  end

  # Prefill Commit#{author,committer} based on
  # Commit#{author_email,committer_email}.
  #
  # Commits with non-UTF-8 or generic email addresses will have the
  # corresponding user attribute set to nil.
  def self.prefill_users(commits, prefill_authors: true, prefill_committers: true)
    Commit.prefill_users_async(commits, prefill_authors: prefill_authors, prefill_committers: prefill_committers).sync
  end

  def self.prefill_users_async(commits, prefill_authors: true, prefill_committers: true)
    promises = []
    commits.each do |commit|
      if prefill_authors && !commit.author_defined?
        promises << commit.author_actor.async_user.then { |author| commit.author = author }
      end

      if prefill_committers && !commit.committer_defined?
        promises << commit.async_committer.then { |committer| commit.committer = committer }
      end
    end

    if promises.empty?
      Promise.resolve(commits)
    else
      Promise.all(promises).then { commits }
    end
  end

  # Prefill Commit#short_message_html as efficiently as possible
  def self.prefill_short_messages(commits)
    Promise.all(commits.map(&:async_short_message_html)).sync
    commits
  end

  # Read signatures and signing payloads from GitRPC for a group of commits.
  #
  # repo - The Repository all the commits belong to.
  # oids - An Array of String commit OIDs.
  #
  # Returns an Array of Arrays. The first element of each array is the signature
  # and the second element is the signing payload.
  def self.parse_signing_data(repo, oids)
    repo.rpc.parse_commit_signatures(oids)
  end

  # <rev>:<path> but NOT :/<commit text matcher>
  COLON_WITH_PATH = %r{:((?!/).*)\Z}

  # Extract the path prefix from a given commit path expression
  #
  # Returns the path prefix or nil if no path prefix
  def self.extract_path_prefix_from_expression(expression)
    if match = COLON_WITH_PATH.match(expression)
      # This expression fetches a tree using the `master:path/to/subtree` syntax
      match[1]
    end
  end

  # Create a Commit object.
  #
  # repository - The Repository that owns this commit.
  # info       - Attributes to assign in gitrpc. See #assign_attributes().
  #
  # This just creates a Commit object in memory with the given attributes. The
  # repository is not changed in any way.
  #
  # NOTE Commit objects are not typically instantiated directly. Use
  # repo.commits.build or repo.commits.create (which call
  # CommitsCollection#build and CommitsCollection#create) instead.
  def initialize(repository, info = {})
    self.repository   = repository
    self.repositories = Set.new.add(repository)
    assign_attributes(info)
  end

  def global_id
    "#{repository.id}:#{oid}"
  end

  # Assign values from a gitrpc commit information hash to this object. This
  # is used when loading commit information from the git repository.
  #
  # info - A gitrpc commit info hash. Must include all required fields
  #        described in the gitrpc commit documentation.
  #
  #        {'type'              => 'commit',
  #         'oid'               => string sha1,
  #         'tree'              => string sha1,
  #         'parents'           => [oid, ...],
  #         'author'            => [name, email, time],
  #         'committer'         => [name, email, time],
  #         'message'           => string commit message,
  #         'message_truncated' => boolean,
  #         'message_shas'      => {shortsha => sha, ...}, # optional
  #         'encoding'          => string commit message encoding name,
  #         'has_signature'     => boolean }
  #
  #        See the read_commits documentation for more info:
  #        https://github.com/github/github/blob/master/vendor/gitrpc/doc/read_commits.md
  #
  # Returns self.
  def assign_attributes(info)
    @oid = info["oid"]

    if info["message"]
      source_encoding = info["encoding"] || "UTF-8"
      target_encoding = "UTF-8"

      @message = GitHub::Encoding.transcode(info["message"], source_encoding, target_encoding)
      @message = @message.dup

      if info["message_truncated"]
        @message.chomp! "\uFFFD"  # �
        @message << "…"
      end

      @message.rstrip!
    end
    @message_shas = info["message_shas"]

    @parent_oids = info["parents"] || []
    @tree_oid    = info["tree"]

    if info["author"]
      @author_name, @author_email, @authored_date_value = info["author"]
      @author_name  = @author_name.encode("UTF-8", undef: :replace, invalid: :replace)
      @author_email = @author_email.encode("UTF-8", undef: :replace, invalid: :replace)

      authors = [
        { name: @author_name, email: @author_email },
        *names_and_emails_from_git_signatures(info.dig("trailers", "co-authored-by")),
      ].uniq { |author| author[:email] }

      @author_names  = authors.map { |author| author[:name] }
      @author_emails = authors.map { |author| author[:email] }
    elsif missing_commit_feature_flag?
      @author_names = []
      @author_emails = []
    end

    if info["committer"]
      @committer_name, @committer_email, @committed_date_value = info["committer"]
      @committer_name  = @committer_name.encode("UTF-8", undef: :replace, invalid: :replace)
      @committer_email = @committer_email.encode("UTF-8", undef: :replace, invalid: :replace)
    elsif missing_commit_feature_flag?
      @committer_name = ""
      @committer_email = ""
      @committed_date_value = Time.at(0).utc.iso8601.to_s
    end

    @has_signature = info["has_signature"]
    @has_authored_by_or_signed_off_trailers = info.dig("trailers", "co-authored-by").present? || info.dig("trailers", "signed-off-by").present?
    @skip_checks    = info.dig("trailers", "skip-checks")&.first
    @request_checks = info.dig("trailers", "request-checks")&.first
    @on_behalf_of_raw = info.dig("trailers", "on-behalf-of")
    @sign_off_actor = info.dig("trailers", "signed-off-by")
    self
  end

  def target_for_conditional_access
    async_target_for_conditional_access.sync
  end

  def async_target_for_conditional_access
    async_repository.then(&:async_target_for_conditional_access)
  end

  def og_image_url
    open_graph = OpenGraph.new(self,
      cache_key_parts: [
        oid,
        repository.name,
        repository.owner_id,
      ]
    )
    open_graph.og_image_url
  end

  def async_signature
    return @async_signature if defined?(@async_signature)
    @async_signature = Platform::Loaders::GitSignature.load(self)
  end

  def async_verification_status
    @async_verification_status ||= Promise.all([async_signature, committer_actor.async_user, author_actor.async_user, async_authors]).then do |signature, committer, primary_author, authors|
      commit_actor = web_committer? ? primary_author : committer
      associated_users = Set[*authors]
      associated_users << commit_actor if commit_actor # may be nil if we can't find an associated GH account

      config_promises = associated_users.map do |u|
        Platform::Loaders::Configuration.load(u, :commit_verification_status_enabled?)
      end

      Promise.all(config_promises).then do |config_settings|
        verification_status_enabled_by_user = Hash[associated_users.zip(config_settings)]
        vigilant_associated_users = associated_users.select { |u| verification_status_enabled_by_user[u] }

        next Promise.resolve(:unsigned) if vigilant_associated_users.none? && signature.nil?

        if !signature&.verified_signature?
          :unverified
        elsif vigilant_associated_users.empty? || vigilant_associated_users.to_a == [commit_actor]
          :verified
        else
          :partially_verified
        end
      end
    end
  end

  def verification_status
    return @verification_status if defined? @verification_status

    @verification_status = async_verification_status.sync
  end

  def on_behalf_of
    return @on_behalf_of if defined? @on_behalf_of

    @on_behalf_of = async_on_behalf_of.sync
  end

  # Organization that this commit was made on behalf of
  #
  # Returns a Promise that resolves to an Organization
  def async_on_behalf_of
    return @async_on_behalf_of if defined?(@async_on_behalf_of)

    return @async_on_behalf_of = NIL_PROMISE unless on_behalf_of_raw.present?

    @async_on_behalf_of = async_signature.then do |signature|
      next unless signature && signature.verified_signature?

      # Sometimes users pass in @org_login instead of org_login and we want to ignore the @
      on_behalf_of_text = on_behalf_of_raw[0].dup
      on_behalf_of_text[0] = "" if on_behalf_of_text[0] == "@"

      on_behalf_of_values = names_and_emails_from_git_signatures([on_behalf_of_text]).first
      next unless on_behalf_of_values && on_behalf_of_values.any?
      Platform::Loaders::ActiveRecord.load(
        ::Organization, on_behalf_of_values[:name], column: :login, case_sensitive: false
      ).then do |organization|
        next unless organization

        Promise.all([author_actor.async_user, organization.async_business]).then do |author, _|
          organization.async_member?(author).then do |author_is_member|
            next unless author_is_member

            organization.async_email_eligible_domains(include_approved: false).then do |domains|
              commit_domains = [on_behalf_of_values[:email], author_email].map do |email|
                VerifiableDomain.normalize_domain(email)
              end

              verified_domains = domains.map(&:domain).to_set
              next unless commit_domains.to_set.subset?(verified_domains)
              if signed_by_github? || (committer_email == author_email)
                organization
              else
                organization.async_member?(committer).then do |committer_is_member|
                  organization if committer_is_member
                end
              end
            end
          end
        end
      end
    end
  end

  # Public: Create a commit in the underlying repository.
  #
  # files - Hash of `filename => data` pairs.
  # sign: - Boolean of whether to try to sign the commit.
  #
  # Returns the created commit when the commit was written to the repository.
  #
  # NOTE Commits are not typically created directly. Use commits.create (which
  # calls CommitsCollection#create) instead.
  def create(files, sign: false)
    raise MultipleParentsError, "Can't create a merge commit" if parent_oids.size > 1

    # Build the required metadata hash for GitRPC
    metadata = {
      "message"   => message.try(&:b),
      "committer" => {
        "name"  => committer_name.b,
        "email" => committer_email.b,
      },
    }

    if tree_oid
      metadata["tree"] = tree_oid
    end

    # Add the optional metadata for GitRPC
    if @committed_date_value
      metadata["committer"]["time"] = @committed_date_value
    end

    if author_name && author_email
      metadata["author"] = { "name" => author_name.b, "email" => author_email.b }

      if @authored_date_value
        metadata["author"]["time"] = @authored_date_value
      end
    end

    args = [first_parent_oid, metadata, files]

    oid = if web_committer? && sign
      repository.rpc.create_tree_changes(*args, &repository.method(:sign_commit))
    else
      repository.rpc.create_tree_changes(*args)
    end

    repository.commits.find(oid)
  end

  # The 40 char commit oid string.
  def to_s
    oid
  end

  def inspect
    "#<Commit oid: \"#{oid}\", created_at: \"#{created_at}\", repository_id: \"#{repository&.id}\", repository_type: \"#{repository.class.name}\">"
  end

  # Use oid for Rails URL construction.
  alias to_param oid

  # Equality is based on oid
  def ==(other)
    return false unless self.class == other.class
    repository == other.repository && oid == other.oid
  end
  alias_method :eql?, :==

  def hash
    @hash ||= [oid, repository].hash
  end

  # Public: Allow Commits to be enough like AR objects for our views
  def errors
    [].freeze
  end

  # Public: Allow Commits to be enough like AR objects for our views
  def valid?
    true
  end

  # Absolute permalink URL for the commit
  #
  # include_host - Turn off the `GitHub.url` host in the url. (default true)
  #                issue_comment.permalink(include_host: false) => `/github/github/issue/1#issuecomment-2`
  #
  def permalink(include_host: true)
    "#{@repository.permalink(include_host: include_host)}/commit/#{oid}"
  end

  # The commit's author user.
  #
  # Returns a User object, or nil when no user is associated with
  # the commit author email.
  def author
    return @author if defined?(@author)
    @author = Promise.all([author_actor.async_user, committer_actor.async_user]).then { |author, _| author }.sync
  end
  attr_writer :author

  def async_authors
    return @async_authors if defined?(@async_authors)

    @async_authors = if author_emails.empty?
      Promise.resolve([])
    else
      @repository.async_enterprise_managed_business.then do |business|
        Platform::Loaders::UserByEmail.load_all(author_emails, business: business).then { |users| users.compact.uniq }
      end
    end
  end

  # Public: Returns a filtered list of GitActors which guarantees no two actors will be
  #   associated with the same user. Also filters users who should not be visible to the
  #   viewer (spammy/blocked).
  #
  # viewer - the current viewer (User).
  #
  # Returns Promise<Array<GitActor>>
  def async_unique_visible_author_actors(viewer)
    actor_or_user_promises = author_actors.map do |actor|
      actor.async_visible_user(viewer).then { |user| user || actor }
    end

    Promise.all(actor_or_user_promises).then do |actors_and_users|
      author_actors.zip(actors_and_users).uniq { |_, user_or_actor| user_or_actor }.map(&:first)
    end
  end

  def unique_visible_author_actors(viewer)
    return @unique_visible_author_actors if defined? @unique_visible_author_actors
    @unique_visible_author_actors = async_unique_visible_author_actors(viewer).sync
  end

  def author_defined?
    defined?(@author)
  end

  def author_actor
    return @author_actor if defined?(@author_actor)
    @author_actor = GitActor.new(email: author_email, name: author_name, time: authored_date, repository: @repository)
  end

  def author_actors
    return @author_actors if defined?(@author_actors)
    @author_actors = author_names.zip(author_emails).map do |name, email|
      GitActor.new(email: email, name: name, time: authored_date, repository: @repository)
    end
  end

  def committer_actor
    return @committer_actor if defined?(@committer_actor)
    @committer_actor = GitActor.new(email: committer_email, name: committer_name, time: committed_date, repository: @repository)
  end

  def authored_by_committer
    return @authored_by_committer if defined? @authored_by_committer
    @authored_by_committer = async_authored_by_committer?.sync
  end

  # Public: Is the committer also an author?
  #
  # Returns Promise<Boolean>
  def async_authored_by_committer?
    Promise.all([
      committer_actor.async_user,
      author_actor.async_user,
      *author_actors.map(&:async_user),
    ]).then do |a_committer, _a_author, *a_authors|
      a_authors.compact!

      if a_committer.nil? || a_authors.empty?
        author_actors.map(&:email).map(&:downcase).include?(committer_email)
      else
        a_authors.include?(a_committer)
      end
    end
  end

  # Public: Was this commit created by the special web committer user?
  # This includes commits created via the web UI, including merge and squash commits.
  # A rebase & merge commit retains the original author and therefore would not have this property set as true
  #
  # Returns Boolean
  def committed_via_web?
    CommitHelper.via_github?(committer_name: committer_name, committer_email: committer_email)
  end

  # The date the commit was originally authored. This stays the same even when
  # commits are rebased or cherry-picked.
  #
  # Returns a Time object.
  def authored_date
    @authored_date ||= parse_date_value(@authored_date_value)
  end

  # The date to count this as a contribution.
  #
  # Returns a Date object.
  def contributed_on
    contributed_at = authored_date
    if contributed_at > Contribution::Calendar::TIMEZONE_AWARE_CUTOVER
      contributed_at.to_date
    else
      contributed_at.localtime.to_date
    end
  end

  # The commit's committer user.
  #
  # Returns a User object, or nil when no user is associated with
  # the commit committer email.
  def committer
    return @committer if defined?(@committer)

    @committer = async_committer.sync
  end
  attr_writer :committer

  def async_committer
    Promise.all([author_actor.async_user, committer_actor.async_user]).then { |_, committer| committer }
  end

  # Users for signature verification.
  alias_method :signer_email, :committer_email

  def committer_defined?
    defined?(@committer)
  end

  # The commit's committed date.
  #
  # Returns a Time object.
  def committed_date
    @committed_date ||= parse_date_value(@committed_date_value)
  end
  alias last_modified_at committed_date

  # Internal: Convert the gitrpc commit time value to a Time object.
  #
  # time - Either an ISO8601 string or a [unixtime, utc_offset] array.
  #
  # Returns a Time object.
  def parse_date_value(time)
    case time
    when Array
      unixtime_to_time(time, suppress_offset_errors: @repository.feature_flag_enabled_or_raise?(:suppress_offset_errors_for_commit_date)) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    when String
      Time.iso8601(time)
    end
  end

  # The abbreviated oid string. This is the first seven characters of the oid
  # and is usually enough to uniquely identify an object.
  #
  # Returns a seven char hex string.
  def abbreviated_oid
    return @abbreviated_oid if defined?(@abbreviated_oid)
    @abbreviated_oid = oid && oid[0, ABBREVIATED_OID_LENGTH]
  end

  # The GitRPC object cache key for this commit.
  #
  # Note that this does not include the GitRPC cache prefix.
  # This should be used with GitRPC#cache, not GitHub.cache.
  def gitrpc_cache_key
    @repository.rpc.object_key(oid)
  end

  # A diff for this commit. The diff data is not part of the commit. A separate
  # set of RPC calls is made to retrieve the diff when enumeration begins or
  # stat information is requested.
  #
  # Use #set_diff_options to establish diff formatting options before accessing
  # this attribute.
  #
  # Returns an enumerable GitHub::Diff object.
  def diff
    init_diff
    @diff.load_diff
    @diff
  end

  def init_diff
    @diff ||= GitHub::Diff.new(
      repository,
      first_parent_oid,
      oid,
      @diff_options || { base_repository: base_repository, head_repository: head_repository },
    )
  end

  # Set GitHub::Diff options and reset the memoized diffs object.
  #
  # options - :max_diff_size, :max_total_size, :max_files, :ignore_whitespace.
  #           See GitHub::Diff attribute docs for info on possible values.
  #
  # Returns the options provided.
  def set_diff_options(options)
    @diff = nil
    @diff_options = options.merge(base_repository: base_repository, head_repository: head_repository)
  end

  CommitStats = Struct.new(:additions, :deletions, :total)
  # A simple overview of the commit diff's modifications. Stat information is
  # not part of the commit. A separate RPC call is made to retrieve this
  # information.
  #
  # Returns an Object that responds to additions, deletions, and total where
  # each is an integer count of lines changed.
  def stats
    return nil if !diff.available?
    CommitStats.new(diff.additions, diff.deletions, diff.changes)
  end

  # Determine if the commit is a merge commit.
  #
  # Returns true when there's more than one parent.
  def merge_commit?
    parent_oids && parent_oids.size > 1
  end

  # Number of parent commits this commit has.
  def parent_count
    parent_oids && parent_oids.size
  end

  # The commit OID for this commit's first parent.
  #
  # Returns a String.
  def first_parent_oid
    parent_oids && parent_oids.first
  end

  # Internal: This is a merge commit and the given commit oid is its second parent.
  # See IssueEvent#async_revertable_by? for more information.
  #
  # Returns a Boolean
  def merged_from?(head_oid)
    # multiple parents, the second of which is the head commit.
    (merge_commit? && parent_oids[1] == head_oid)
  end

  # Internal: Is this commit revertable with respect to the given head_oid?
  # See IssueEvent#async_revertable_by? for more information.
  #
  # head_oid - the oid of the last head commit of the feature branch corresponding to this commit
  def revertable_from?(head_oid)
    merged_from?(head_oid) || (parent_count == 1 && oid != head_oid)
  end

  # Approximate AR created_at by using the committed_date on the commit.
  #
  # TODO This should really be authored_date and #updated_at should use
  # committed_date. Things sort on this though so I'm afraid to change it.
  alias created_at committed_date

  # Public: A DateTime value relative to other adjacent commits in a given list
  #         such that the values are monotonically increasing. It's a synthetic value
  #         that is optionally set when commits are fetched and should be based on
  #         committed_date. Used when sorting timeline items.
  #
  # Returns a DateTime or nil.
  attr_accessor :topological_date

  # See IssueTimeline
  def timeline_sort_by
    return [topological_date] if topological_date
    [committed_date, authored_date]
  end

  # This Commit's comments.
  #
  # Returns an array of CommitComment objects.
  def comments
    return @comments if @comments

    @comments = if repository
      repository.commit_comments.where(commit_id: oid).sort_by(&:created_at).to_a
    else
      []
    end
  end
  attr_writer :comments

  # Public: Commit comments following IssueTimeline API
  def comments_for(user, options)
    items = comments
    if since = options[:since]
      items = items.select { |item| item.created_at > since }
    end
    items.reject! { |c| c.user.nil? || c.spammy? }
    items.select! { |c| c.path == options[:path] } if options[:path].present?
    items
  end

  # Determine if this commit has any comments.
  def comments?
    comment_count > 0
  end

  # How many commit comments does this commit have?
  #
  # Returns an Integer comment count.
  def comment_count
    return @comment_count if @comment_count

    @comment_count = if repository
      repository.commit_comments.where(commit_id: oid).count
    else
      0
    end
  end
  attr_writer :comment_count

  # Get a unique list of all the users that have commented on this comment.
  #
  # Returns an Array of User records.
  def commenters
    comments.map(&:user).uniq
  end

  # Return a list of deployment objects for the sha.
  #
  # Returns an Array of Deployment records ordered by newest first.
  def deployments
    @deployments ||=
      if repository
        repository.deployments.by_sha(oid)
      else
        []
      end
  end

  # Return the most recently created deployment object
  #
  # Returns a Deployment record
  def latest_deployment
    deployments && deployments.first
  end

  # Public: Gets the NotificationSummary for this Commit
  # See Summarizable.
  #
  # Returns Newsies::Response instance.
  def get_notification_summary
    GitHub.newsies.web.find_rollup_summary_by_thread(repository, self)
  end

  # Get a unique list of all the users that commented or authored this commit.
  # Exclude users who no longer have access to this repo
  # (unless parent org has so many members that query may timeout).
  #
  # optimize_repo_access_checks - by default, #participants will check to make
  #                               sure that each user returned still has access
  #                               to the repo. If optimize_repo_access_checks is
  #                               set to true, that check will not happen if the
  #                               parent org has too many members (which may
  #                               cause the access checks to time out)
  #
  # Returns an Array of User records.
  def participants(optimize_repo_access_checks: false)
    @participants ||= begin
      users = [author, committer, *commenters].compact.uniq
      unless repository.public?
        user_ids_to_hide = repository.user_ids_to_hide_from_mentions(users, optimize_repo_access_checks: optimize_repo_access_checks)
        users.reject! { |user| user_ids_to_hide.include?(user.id) }
      end
      users
    end
  end

  # Users who should be considered commit participants, excluding any that the viewer shouldn't see
  #
  # viewer - the User who is viewing the participants (current_user)
  # optimize_repo_access_checks - if optimize_repo_access_checks is set
  #                               to true, do not perform access checks
  #                               on repos that are owned by org's with
  #                               a lot of members
  #
  # Returns an Array of Users.
  def participants_for(viewer, optimize_repo_access_checks: false)
    participants(optimize_repo_access_checks: optimize_repo_access_checks).reject { |u| u.hide_from_user?(viewer) }
  end

  # For suggestions_path helper
  alias_method :suggestion_id, :oid

  # Is this a git commit --allow-empty-message commit? Determines whether
  # there is a blank commit message.
  #
  # Returns true if the commit message is empty.
  def empty_message?
    message.blank?
  end

  # Array of issues mentioned in the commit message.
  #
  # Returns an Array of IssueReference objects
  def issue_references
    return [] if message.to_s !~ GitHub::HTML::IssueMentionFilter::MARKER
    Array message_result.issues
  end

  def async_directly_references_issue?(issue)
    return Promise.resolve(false) unless message.to_s =~ GitHub::HTML::IssueMentionFilter::MARKER

    Platform::Loaders::Cache.fetch("commit:directly_references_issue:#{oid}:#{issue.id}") do
      result = message_content.async_result.then do |result|
        output = result.output
        next false if result.issues.nil?
        result.issues.any? { |ref| ref.issue == issue }
      end
    end
  end

  # Array of commits mentioned in the commit message.
  #
  # TODO: support cross-repo references.
  #
  # Returns an Array of CommitReference objects.
  def commit_references
    return [] if message.to_s !~ /[0-9a-f]{7,40}/
    Array message_result.commits
  end

  # Users mentioned in the commit message.
  #
  # Returns the Array of User objects.
  def mentioned_users
    return [] if !message.to_s.include?("@")
    Array message_result.mentioned_users
  end

  # Returns and Array of teams mentioned.
  def mentioned_teams
    return [] if !message.to_s.include?("@")
    Array message_result.mentioned_teams
  end

  # Newsies methods
  def async_notifications_list
    async_repository
  end

  def notifications_thread
    self
  end

  def notifications_author
    author
  end

  def async_repository
    @async_repository ||= Promise.resolve(repository)
  end

  def async_readable_by?(actor)
    async_repository.then do |repository|
      next false unless repository
      repository.resources.contents.async_readable_by?(actor)
    end
  end

  def readable_by?(actor)
    async_readable_by?(actor).sync
  end

  # Public: The simple short message text without truncation. The
  # #short_message_text method should be used in most cases. This is a hold over
  # from Grit::Commit.
  def short_message
    @short_message ||= message.lstrip.split("\n", 2).first
  end

  # Public: The message without Co-authored-by/Signed-off-by trailers.
  # If there are no such trailers, the message is returned as is.
  # has_authored_by_or_signed_off_trailers is set to true when non-empty `trailers:co-authored-by/signed-off-by` objects are returned from GitRPC.
  def message_without_authored_by_or_signed_off_trailers
    return message if !@has_authored_by_or_signed_off_trailers
    message.gsub(/^(co-authored-by|signed-off-by)\:\s+(.*?)\s?\<([^\n]+)\>/i, "").strip
  end

  # The HTML Pipeline context hash used when turning commit messages into HTML.
  def message_context
    @message_context ||= super.update(current_user: context_user, expanded_shas: message_shas)
  end

  def context_user(user = nil)
    if user
      @context_user = user
      @message_context = nil
      @message_content = nil
    end

    # the given user is still the fallback behind committer and author.
    if web_committer?
      author || @context_user
    else
      committer || author || @context_user
    end
  end

  # Was this committed by the "GitHub committer"?
  #
  # Returns boolean.
  def web_committer?
    committer_name == GitHub.web_committer_name &&
      committer_email == GitHub.web_committer_email
  end

  def contribution_status
    CommitContributionStatus.new(self)
  end

  def has_status_check_rollup?
    return @has_status_check_rollup if defined? @has_status_check_rollup

    @has_status_check_rollup = async_has_status_check_rollup?.sync
  end

  def async_has_status_check_rollup?
    @async_has_status_check_rollup ||= Platform::Loaders::HasStatusCheckRollup.load(repository, oid)
  end

  def status_check_rollup
    return @status_check_rollup if defined? @status_check_rollup

    @status_check_rollup = async_status_check_rollup.sync
  end

  def async_status_check_rollup
    Platform::Objects::StatusCheckRollup.load_from_repo_and_oid(@repository, oid, true)
  end

  # Public: Find the PR that introduced this commit
  #
  # viewer - The User viewing the PullRequest. Only used for spam-checking.
  #
  # Returns nil if this commit is not in any merged PR
  # Returns a PullRequest object if at least one has been merged
  def introductory_pull_request(viewer:)
    async_introductory_pull_request(viewer: viewer).sync
  end

  # Public: Find the PR that introduced this commit
  #
  # viewer - The User viewing the PullRequest. Only used for spam-checking.
  #
  # Returns a Promise that resolves to a PullRequest, or nil if there
  # is no introductory PR, or if that PR is hidden from the viewer
  def async_introductory_pull_request(viewer:)
    pr_id, _ = introductory_pull_request_ids!
    return NIL_PROMISE unless pr_id

    Platform::Loaders::ActiveRecord.load(::PullRequest, pr_id.to_i).then do |pr|
      next unless pr

      # Resolve to PR only if the PR and its repo are not hidden
      pr.async_repository.then do |repo|
        ::Promise.all([T.must(repo).async_hide_from_user?(viewer), pr.async_hide_from_user?(viewer)]).then do |repo_hidden, pr_hidden|
          pr unless repo_hidden || pr_hidden
        end
      end
    end
  end

  # Public: Find the PR that introduced this commit on the parent repository, if any.
  #
  # viewer - The User viewing the PullRequest. Only used for spam-checking.
  #
  # Returns nil if this commit is not in any merged PR
  # Returns a PullRequest object if at least one has been merged
  def parent_introductory_pull_request(viewer:)
    async_parent_introductory_pull_request(viewer: viewer).sync
  end

  # Public: Find the PR that introduced this commit on the parent repository, if any.
  #
  # viewer - The User viewing the PullRequest. Only used for spam-checking.
  #
  # Returns a Promise that resolves to a PullRequest, or nil if there
  # is no introductory PR, or if that PR is hidden from the viewer
  def async_parent_introductory_pull_request(viewer:)
    _, parent_pr_id = introductory_pull_request_ids!
    return NIL_PROMISE unless parent_pr_id

    Platform::Loaders::ActiveRecord.load(::PullRequest, parent_pr_id.to_i).then do |parent_pr|
      next unless parent_pr

      async_repository.then do |commit_repo|
        # Verify here that the pr actually does belong to the parent repo, as
        # we couldn't do that when issuing the Elasticsearch query for PR ids.
        next unless commit_repo.parent_id == parent_pr.repository_id

        # Resolve to PR only if the PR and its repo are not hidden
        parent_pr.async_repository.then do |parent_repo|
          ::Promise.all([T.must(parent_repo).async_visible_and_readable_by?(viewer), parent_pr.async_hide_from_user?(viewer)]).then do |parent_repo_visible, parent_pr_hidden|
            next unless parent_repo_visible
            next if parent_pr_hidden
            parent_pr
          end
        end
      end
    end
  end

  def pull_requests_from_branches
    branch_names = repository.rpc.branch_contains(oid)
    default_branch = repository.default_branch
    pull_requests = T.let([], T::Array[PullRequest])

    # Don't iterate PRs if the commit is merged into the default branch
    # Otherwise the commit will be present in ALL pull requests
    unless branch_names.include?(default_branch)
      open_pulls = repository.pull_requests_as_head.open_pull_requests_by_status.where(head_ref: Git::Ref.safe_ref_name(ref_names: branch_names))

      branch_names.each do |branch|
        pull_requests += open_pulls.select { |pr| pr.head_ref_name == branch } # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end
    end

    pull_requests
  end

  def async_associated_pull_requests(order_by:, viewer:)
    pull_requests = pull_requests_from_branches

    ::Promise.all([async_introductory_pull_request(viewer: viewer), async_parent_introductory_pull_request(viewer: viewer)]).then do |intro_pr, parent_intro_pr|
      pull_requests << intro_pr if intro_pr
      pull_requests << parent_intro_pr if parent_intro_pr

      pull_promises = pull_requests.map do |pull|
        pull.async_hidden_from_or_repo_hidden_from?(viewer).then do |is_hidden|
          next if is_hidden
          pull.async_repository_metadata_readable_by?(viewer).then do |is_readable|
            next unless is_readable
            pull
          end
        end
      end

      Promise.all(pull_promises).then do |filtered_pulls|
        filtered_pulls = filtered_pulls.compact

        case order_by[:field]
        when "created_at"
          filtered_pulls.sort_by!(&:created_at)
        when "updated_at"
          filtered_pulls.sort_by!(&:updated_at)
        end

        filtered_pulls.reverse! if order_by[:direction] == "DESC"
        filtered_pulls
      end
    end
  end

  # Public: Indicate what search problem happened in finding the introductory PR, if any
  #
  # Returns a Symbol or nil
  #
  #  :failed  - couldn't connect to search, or there was a search error
  #  :timeout - the search query timed out
  #  nil      - no problem
  #
  def introductory_pull_request_search_problem
    if @introductory_pull_request_search_failed
      :failed
    elsif @introductory_pull_request_search_timed_out
      :timeout
    end
  end

  # Private: Use search to find the PR(s) that introduced this commit
  #
  # Returns a two-element array of PullRequest ids or nil values. The
  # first id, if present, corresponds to the PR on the current repository
  # that introduced the commit. The second id, if present, corresponds to
  # the PR on the parent repository that introduced this commit if the
  # current repository is a fork.
  #
  # Catches search errors and returns an empty Array.
  #
  # Returns an empty Array if this commit is not in any merged PR.
  # Returns a two-element Array of PR ids or nils.
  def introductory_pull_request_ids!
    return @introductory_pull_request_ids if defined?(@introductory_pull_request_ids)

    @introductory_pull_request_search_failed    = false
    @introductory_pull_request_search_timed_out = false
    @introductory_pull_request_ids = []

    index = Elastomer::Indexes::PullRequests.new
    res   = index.search_merged_including_commit(self, 2)
    hits  = res[:hits]

    @introductory_pull_request_search_timed_out = res[:timed_out]

    return @introductory_pull_request_ids if hits.blank?

    repo_pr_hit = hits.find { |hit| hit["_source"]["repo_id"] == repository.id }
    # That the parent-repo pr id actually belongs to the parent repo must
    # be verified via the caller.
    parent_pr_hit = hits.find { |hit| hit["_source"]["repo_id"] != repository.id }

    # Ensure we return an ordered, two-element tuple, <IdOrNil, IdOrNil>
    [repo_pr_hit, parent_pr_hit].map do |hit|
      id = hit["_id"] if hit
      @introductory_pull_request_ids.push(id)
    end

    @introductory_pull_request_ids
  rescue ElastomerClient::Client::Error, Faraday::ConnectionFailed => e
    Failbot.report_user_error(e)
    @introductory_pull_request_search_failed = true
    @introductory_pull_request_ids
    raise AssociatedPullRequestSearchFailed
  ensure
    if introductory_pull_request_search_problem
      GitHub.dogstats.increment("pull_request.commit_intro_pull_request_search_problem.#{introductory_pull_request_search_problem}")
    end
  end

  def diff_stats
    return @diff_stats if defined?(@diff_stats)
    @diff_stats = Commit::DiffStats.new(diff)
  end

  def events
    IssueEvent.where(repository_id: repository.id, issue_id: nil, commit_id: oid, event: EVENT_TYPES).order("issue_events.id ASC")
  end

  # Try to determine the time when the issue was *last* locked. If multiple lock
  # events happened during the course of the issue, take the last one.
  #
  # Returns a Time if locked directly (not archived), otherwise returns nil.
  def locked_at
    return @locked_at if @locked_at
    return nil unless locked?
    @locked_at = events.locks.last&.created_at
  end

  def locked?
    return true if repository.archived?
    return @locked if defined?(@locked)
    @locked = !!(last_event && last_event.event == "locked")
  end

  def last_event
    return @last_event if defined?(@last_event)
    @last_event = events.last
  end

  def lock_changed!
    remove_instance_variable(:@last_event) if defined?(@last_event)
    remove_instance_variable(:@locked) if defined?(@locked)
  end

  # Can the given user lock the conversation on this Issue?
  def lockable_by?(user)
    user.is_a?(User) &&
      (repository.writable_by?(user) || user.site_admin?)
  end

  def can_comment?(user)
    return true if readable_and_unlocked_for?(user)
    repository.resources.contents.writable_by?(user) && !repository.archived?
  end

  def readable_and_unlocked_for?(user)
    (user.is_a?(User) && repository.resources.contents.readable_by?(user) && !locked?)
  end

  def lock(user)
    return unless lockable_by?(user)
    GitHub.dogstats.increment("commit", tags: ["action:lock"])

    IssueEvent.transaction do
      events.create!(event: "locked", actor: user)
      lock_changed!
    end
  end

  def unlock(user)
    return unless lockable_by?(user)

    GitHub.dogstats.increment("commit", tags: ["action:unlock"])

    IssueEvent.transaction do
      events.create!(event: "unlocked", actor: user)
      lock_changed!
    end
  end

  def annotations(limit: CheckAnnotation::MAX_READ_LIMIT)
    if repository&.respond_to?(:annotations_for)
      DiffAnnotations.new(repository.annotations_for(sha: oid, limit: limit))
    else
      DiffAnnotations.new([])
    end
  end

  def path
    return @path if defined? @path

    @path = async_path.sync
  end

  def async_path
    async_repository.then do |repo|
      PATH_TEMPLATE.expand user: repo.owner_display_login, repo: repo.name, oid: oid
    end
  end

  def peel_to_commit
    # No need to peel, we already have a commit.  This is here to satisfy an
    # interface across all git object model classes.
    self
  end

  def async_user
    author_actor.async_user
  end

  def async_path_uri
    return @async_path_uri if defined?(@async_path_uri)

    @async_path_uri = async_repository.then do |repo|
      path_uri = repo.path_uri.dup
      path_uri.path += "/commit/#{oid}"
      path_uri
    end
  end

  def url
    permalink
  end

  def title
    "Commit #{oid}"
  end

  def user
    return @commit_user if defined?(@commit_user)
    @commit_user = async_user.sync
  end

  def user_display_login
    user&.display_login || User.ghost.display_login
  end

  def number
    parent_count + 1
  end

  def updated_at
    created_at
  end

  def async_hide_from_user?(viewer)
    async_repository.then { |repo| repo.async_hide_from_user?(viewer) }
  end

  # Deprecated grit interface aliases
  alias sha to_s
  alias id_abbrev abbreviated_oid
  alias date committed_date

  private

  # Private: Extracts and fixes encoding of names and emails from trailer
  #          values that match the "John Doe <john@email.com>" format.
  #
  # signatures - Array of strings (e.g., values of `Co-authored-by: ...` trailers).
  #
  # Returns a (potentially empty) Array of hashes, each having `name`
  #  and `email` keys, UTF8-encoded.
  def names_and_emails_from_git_signatures(signatures)
    return [] unless signatures
    matches = signatures.map do |signature|
      signature.encode("UTF-8", undef: :replace, invalid: :replace)
      match = signature.strip.match(GitActor::SIGNATURE_MATCHER)

      { name: match[:name].strip, email: match[:email].strip } if match
    end
    matches.compact
  end

  def check_repository_type(repo)
    if !repo.is_a?(Repository) && !repo.is_a?(Gist) && !repo.is_a?(GitHub::Unsullied::Wiki)
      raise TypeError, "expected repository to be a Repository, Gist or Wiki, but was a #{repo.class}"
    end
  end

  def missing_commit_feature_flag?
    return @missing_commit_feature_flag if defined?(@missing_commit_feature_flag)
    @missing_commit_feature_flag = FeatureFlag.vexi.enabled?(:missing_commit_data, default: false)
  end
end
