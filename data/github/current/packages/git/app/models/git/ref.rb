# typed: true
# frozen_string_literal: true

# An individual ref in a git repository.
#
# Synopsis:
#
#   >> ref = repository.refs.find('master')
#   => #<Ref['refs/heads/master' => 'deadbee...']>
#   >> ref.name
#   => 'master'
#   >> ref.qualified_name
#   => 'refs/heads/master'
#   >> ref.target
#   => #<Commit:@oid='deadbee...'>
#   >> ref.update('decafba...', current_user)
#   >> ref.delete(current_user)
#   >> ref.exist?
#
# Refs are the mechanism by which git objects like Commits and Tags are given
# names in a git repository. They are the basis for branches and tags and are
# also used to keep track of auxiliary information like git notes, pull request
# tracking info, and GitHub's subversion bridge mapping data.
#
# Each Ref object has a name and target git object. All ref names share a single
# namespace and are organized into hierarchies. It's probably easiest to grasp
# this by looking at a dump of all refs in a repository:
#
#     $ git show-ref
#     be4017422c98fb3e00e6815261c7ac8fb6a8b62f refs/heads/master
#     9a474c5dd9c3d37ff441cfcfe65932fd795acb7a refs/heads/encodings
#     c22d7c4ba78d25507fafb2443ae64f1465850b87 refs/tags/v1.0
#     120a9db424f1ed960a53927ada8d518168393f14 refs/tags/v1.2
#     8c0cc8650c9f27cdf00cc3a44e86d0772aae3eaf refs/pull/1/head
#     fbbefc4c9a5e41212065e64388718e14c762d408 refs/pull/1/merge
#     982b64f45d7dddb586bf94033b43098e70baea8f refs/pull/2/head
#     c5e18b4ecdc54698f1805e1f7e38d0ff76540d11 refs/pull/2/merge
#
# The first column is the oid of the git object the ref points to and the second
# column is the fully qualified name of the ref. The #target_oid, #target, and
# #qualified_name accessors expose this information.
#
# Ref objects are often operated on within the scope of a certain hierarchy.
# For instance, the Repository#heads and Repository#tags collections give access
# to Ref objects whose qualified name falls within those hierarchies only.
# Callers almost never care about the hierarchy part of the ref name in these
# cases, so the Ref#name attribute is designed to only return the short name /
# suffix portion (like "master" or "v1.0") of fully qualified ref name.
#
# All ref modifications like creating/updating/deleting branches and tags must
# go through the Ref model. The #create, #update, and #delete methods ensure that
# all ref modifications are performed using a CAS operation, and raise a
# Ref::ComparisonFailed exception when the ref was modified by a different
# process. See the ref writing methods for more information.
#
# See the following Pro Git chapter for more background on how git refs work:
#
# <https://git-scm.com/book/en/Git-Internals-Git-References>
module Git
  class Ref
    include GitHub::Relay::GlobalIdentification
    include GitHub::BatchMethod
    include GitHub::UTF8

    # The Repository this ref belongs to.
    attr_reader :repository

    # A ref's Entity is its Repository
    alias_method :entity, :repository

    def async_entity
      Promise.resolve(entity)
    end

    # The ref's name minus the ref namespace prefix. Use #qualified_name to get
    # the full name of the ref including namespace.
    attr_reader :name

    # The ref's prefix. "refs/heads/", "refs/tags/", etc.
    attr_reader :prefix

    # The string oid (SHA1) of the object this ref points to. This is always a
    # commit object for branches but may be any other object type for other refs.
    # Tag refs often point to tag objects instead of commits and may even point to
    # blobs and trees.
    #
    # The target is never set unless the target oid value was read from the
    # underlying ref in the repository. Ref objects that don't exist yet have a
    # nil target and target_oid.
    attr_reader :target_oid

    # Base error for any ref update error.
    class UpdateError < StandardError
    end

    # Raised when updating or deleting a ref that doesn't exist.
    class NotFound < UpdateError
    end

    # Raised when updating a ref and the CAS operation mismatches.
    class ComparisonMismatch < UpdateError
      def failbot_context
        { app: "github-ref-errors" }
      end
    end

    class ReferenceExistsError < ComparisonMismatch
    end

    # Raised when creating a ref that already exists.
    class ExistsError < UpdateError
    end

    # Raised when ref update is rejected.
    class RejectedError < UpdateError
    end

    # Raised when a ref update cannot be performed because of a merge conflict
    class MergeConflictError < UpdateError
    end

    # Raised when a fetch-and-merge has failed and we have additional
    # information we want to tell the user
    class FetchAndMergeFailure < StandardError
      include GitHub::UIError

      def initialize(ui_message)
        @ui_message = ui_message
        super
      end

      def ui_message
        @ui_message
      end
    end

    # Raised from the #commit method when following the ref's target through Tag
    # objects does not eventually reach a Commit.
    class UnresolveableCommit < StandardError
    end

    # Raised when attempting to create a ref with an invalid name
    class InvalidName < UpdateError
    end

    # Raised when a ref update fails for a reason we aren't expecting
    class UpdateFailed < UpdateError
    end

    # Raised when a ref update fails for a reason we aren't expecting.
    # Used instead of UpdateFailed when the exception may contain
    # sensitive content.
    class UpdateFailedSensitive < UpdateFailed
      def needs_redacting?
        true
      end
    end

    # Raised when a custom pre-receive hook fails
    class HookFailed < UpdateError
    end

    # Raised when a branch ref update that cannot be fast forwarded has
    # been requested with force=false.
    class NotFastForward < UpdateError
    end

    # Raised when attempt to update a ref that fails the workflow scope check
    class WorkflowUpdatePolicyError < UpdateError
      # Internal: Initialize a WorkflowUpdatePolicyError.
      #
      # message - Generic String message
      def initialize(message)
        super(message)
      end
    end

    # Raised when attempting to update a ref that violates repository rules
    class RepositoryRuleViolationError < UpdateError
      sig { returns(RuleEngine::RuleSuite) }
      attr_reader :rule_suite
      sig { returns(T::Array[RuleEngine::RuleRun]) }
      attr_reader :failed_runs
      attr_reader :detailed_message

      sig { params(rule_suite: RuleEngine::RuleSuite).void }
      def initialize(rule_suite)
        message = "Repository rule violations found"

        @rule_suite = rule_suite
        @failed_runs = rule_suite.rule_runs.filter(&:failed?)
        @detailed_message = generate_detailed_message(message, rule_suite)

        super(message)
      end

      private

      def generate_detailed_message(default_message, rule_suite)
        messages = rule_suite.failure_messages(prefix: nil, exclude_violations: true)

        return default_message if messages.empty?

        "#{default_message}\n\n#{messages.join("\n\n")}\n\n"
      end
    end

    # Raised when attempt to update a ref that fails a protected branch check
    class ProtectedBranchUpdateError < UpdateError
      include GitHub::UIError

      # Ref that was attempted to be updated.
      attr_reader :ref

      # An unsuccessful PolicySuite::PolicySuite.
      attr_reader :result

      # Internal: Initialize a ProtectedBranchUpdateError.
      #
      # ref - Ref that was attempted to be updated
      # result - An unsuccessful RuleEngine::PolicySuite instance
      # message - Generic String message
      def initialize(ref, result, message)
        @ref = ref
        @result = result
        super(message)
      end

      def failbot_context
        { app: "github-user" }
      end

      def ui_message
        "Couldn't update \"#{ref.name}\": #{result.message}"
      end
    end

    # Take a ref name or Array of ref names in either the format of "master"
    # or "refs/heads/master", and return ["master", "refs/heads/master"].
    def self.permutations(names)
      Array(names).flat_map do |name|
        if name.starts_with?("refs/heads/")
          [name.delete_prefix("refs/heads/"), name]
        else
          [name, "refs/heads/#{name}"]
        end
      end
    end

    COMMON_PREFIXES = ["refs/heads/", "refs/tags/"].freeze

    # Take a ref name or Array of ref names in either the format of "master"
    # or "refs/heads/master", and returns safe_ref_name

    def self.safe_ref_name(ref_names:)
      Array(ref_names).flat_map do |name|
        name.delete_prefix("refs/heads/")
      end
    end

    # Public: Create a Ref for the given repository and ref.
    #
    # repository - Repository that the branch lives on
    # name       - The ref's short name string, or fully qualified name when no
    #              prefix is given.
    # target     - Optional target object. Commit, Tag, Tree, or Blob. This may
    #              also be a string oid when the target object has not been
    #              loaded.
    # prefix     - The ref's namespace prefix string.
    #
    # NOTE Ref objects are not typically instantiated directly. Use the
    # Repository#refs, Repository#heads, and Repository#tags collections to find,
    # create, and update Ref objects. See the Git::Ref::Collection model for all
    # available collection methods.
    def initialize(repository, name, target = nil, prefix = nil)
      unless repository && name
        raise ArgumentError, "repository and name are required"
      end

      @repository = repository
      @name       = name
      @prefix     = prefix

      # search for common prefixes when none given
      if @prefix.nil?
        COMMON_PREFIXES.each do |prefix|
          if @name.start_with?(prefix)
            @prefix = prefix
            @name = @name[@prefix.size, @name.length]
            break
          end
        end
      elsif @name.start_with?(@prefix)
        @name = @name[@prefix.size, @name.length]
      end

      set_target_object(target)
    end

    # Public: The fully qualified name of the ref. "refs/heads/master",
    # "refs/tags/v1.0", etc.
    def qualified_name
      "#{@prefix}#{@name}"
    end

    # Public: Returns the value tagged as UTF-8 and scrubbed. Used in name_for_display
    # and qualified_name_for_display methods, and available to callers that have ref
    # name values
    def self.value_for_display(value)
      value.dup.force_encoding("UTF-8").scrub!
    end

    # Public: Returns `qualified_name` but tagged as UTF-8 and scrubbed. This method
    # should be used when displaying the ref qualified name on a web page.
    def qualified_name_for_display
      self.class.value_for_display(qualified_name)
    end

    # Public: Returns `name` but tagged as UTF-8 and scrubbed.  This method
    # should be used when displaying the ref name on a web page.
    def name_for_display
      self.class.value_for_display(name)
    end

    # Internal: An unencoded string used to generate a global identifier for use
    # with GraphQL and Relay. See #global_relay_id below.
    def global_id
      "#{self.repository.id}:#{self.qualified_name}"
    end

    # Public: check if the ref exists in the repository. This is based entirely on
    # whether a target object or oid have been set on the Ref.
    #
    # Returns true when the ref's target is set.
    def exist?
      !target_oid.nil?
    end

    # Public: The git object pointed to by the ref. This is typically a Commit or
    # Tag but may be any object type in non-branch hierarchies. Always nil for
    # refs that do not yet exist.
    #
    # Returns a Commit, Tag, Blob, or Tree. May also return nil when the object
    # does not exist or the target_oid is not set.
    # Raises GitRPC::ObjectMissing when the target oid is set but the object can
    # not be loaded from the repository.
    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def target
      @target ||= (target_oid && @repository.objects.read(target_oid))
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    # Public: Set the model instance this ref points to. Must be a Commit, Tag,
    # Blob, or Tree. This method is provided so that target objects may be loaded
    # in batch and mass assigned instead of making N+1 RPC calls.
    def set_target_object(object)
      @commit = nil
      if object.respond_to?(:oid)
        @target_oid = object.oid
        @target = object
      elsif object.nil? || object == GitHub::NULL_OID
        @target_oid = nil
        @target = nil
      elsif object.is_a?(String) && object.size == 40
        @target_oid = object
        @target = nil
      else
        raise TypeError, "Bad target object: #{object.inspect}"
      end
    end

    # Internal: Check whether the target object has been set, either via call to
    # set_target_object or by lazy loading on first access. This does not attempt
    # to load the object.
    def target_acquired?
      !@target.nil?
    end

    # Public: Inspect the ref object.
    #
    # Returns a string.
    def inspect
      "#<Ref[#{qualified_name.inspect} => #{target_oid.inspect}]>"
    end

    # Public: Check if a commit can be resolved by walking target objects until a
    # commit is found.
    #
    # Returns true when the ref eventually points to a commit, false when the ref
    # points to a tree, blob, or tag that points to a tree or blob.
    def commit?
      !commit.nil?
    rescue UnresolveableCommit
      false
    end

    # Public: Resolve the reference down to a Commit, possibly traversing
    # intermediate Tag objects.
    #
    # Returns the Commit object this ref eventually points to.
    # Raises UnresolveableCommit when no commit is reachable from this ref.
    def commit
      @commit ||= resolve_commit(target)
    end

    # Internal: Follow the objects target chain until a Commit is reached.
    def resolve_commit(object)
      if object.is_a?(::Commit)
        object
      elsif object.is_a?(::Tag)
        resolve_commit(object.target)
      else
        raise UnresolveableCommit
      end
    end

    # Internal: The latest 3PC commit time for writing to this Ref.
    #
    # If this in-memory Git::Ref object has had #write_ref called on it,
    # the #written_at property will hold the Spokes three-phase commit time
    # for the Git ref update.
    #
    # This data is ephemeral and will not be preserved once the object is
    # garbage collected.
    #
    # Returns a DateTime or nil.
    def written_at
      @written_at
    end

    # Public: Determines whether the ref name is well formed according to
    # the git-check-ref-format(1) command.
    #
    # See the Ref.normalize method, which follows git-check-ref-format rules
    # (for the most part)
    #
    # Returns Boolean
    def well_formed?
      name.present? &&
      name == self.class.normalize(name)
    end

    def self.well_formed?(name)
      name == normalize(name)
    end

    # Public: Create a new ref in the underlying repository. The ref's name must
    # not already exist.
    #
    # target  - The new target object. Must be a Commit, Tag, Blob, or Tree. May
    #           also be the string oid of the target object.
    # author  - The User or { :name, :email } Hash that is creating the branch.
    # options - Optional Hash of additional options. See #write_ref.
    #
    # Returns self when the ref was written to the repository.
    # Raises Ref::ExistsError when the ref already exists in the repository.
    def create(target, author, options = {})
      raise ExistsError, qualified_name if target_oid || exist?

      if qualified_name =~ GitHub::SHA_LIKE_REF_NAME
        raise InvalidName, "Sorry, branch or tag names consisting of 40 hex characters are not allowed."
      elsif qualified_name =~ GitHub::REFS_PREFIX_REF_NAME && (target.respond_to?(:oid) ? target.oid != GitHub::NULL_OID : target != GitHub::NULL_OID)
        raise InvalidName, "Sorry, branch or tag names starting with 'refs/' are not allowed."
      elsif qualified_name.length > GitHub::MAX_REF_LENGTH
        raise InvalidName, "Sorry, refs longer than #{GitHub::MAX_REF_LENGTH} bytes are not allowed."
      elsif branch? && qualified_name == "refs/heads/HEAD"
        raise InvalidName, "Sorry, branches named 'HEAD' are not allowed."
      end

      update(target, author, options)
    rescue Ref::ComparisonMismatch
      # ref was found to exist on the server
      raise ExistsError, qualified_name
    end

    # Public: Update an existing ref in the underlying repository or create a
    # new ref when an existing ref doesn't exist.
    #
    # proposed_target - The new target object. Must be a Commit, Tag, Blob, or Tree. May
    #                   also be the string oid of the target object.
    # author          - The User or { :name, :email } Hash that is updating the branch.
    # options         - Optional Hash of additional options. See #write_ref.
    #   :rule_commit  - Reference commit for policy checks
    #   :force        - Whether branch ref updates that are not fast-forwardable
    #                   should be allowed (true by default)
    #   :no_rule_suite_persist - Do not write RuleSuite results to the database.
    #                            Failing runs will still return RuleSuite in exception.
    #   :never_bypass - in #check_rules, never use bypass even if it's available
    #
    # Returns self when the ref was written to the repository.
    # Raises Ref::ComparisonMismatch when the ref has moved since the last known
    #   value (Ref#target_oid).
    # Raises Ref::NotFastForward when the ref is a branch, options[:force] is
    #   false and proposed_target is not a descendant of the current target.
    def update(proposed_target, author, options = {})
      ref_update = build_ref_update(proposed_target, options)

      check_rules(repository, ref_update, author, options[:server_merge] == true, options[:fetch_and_merge] == true,
        options[:no_rule_suite_persist] == true, options[:never_bypass] == true)

      write_ref(proposed_target, author, options[:reflog_data] || {}, options)
      self
    end

    # Public: Delete the ref from the underlying git repository.
    #
    # author  - The User or { :name, :email } Hash who is responsible for deleting the branch.
    # options - Optional Hash of additional options. See #write_ref.
    #
    # Returns true on success; false when the ref could not be deleted because the
    #   old value has changed.
    # Raises Ref::NotFound when the ref's existing target oid is not known.
    # Raises Ref::ComparisonMismatch when the ref has moved since the last known
    #   value (Ref#target_oid).
    def delete(author, options = {})
      raise NotFound, qualified_name if target_oid.nil?
      update(GitHub::NULL_OID, author, options).tap do
        repository.reset_memoized_attributes
      end
    end

    # Public: Creates a new commit based on the changes provided and updates this ref to point to it.
    #
    # changes - an array of changes each of the form
    #
    # {
    #   path: "file/path",       # required
    #   content: "content",      # required if content is changing
    #   deletion: false,         # optional - defaults to false
    #   new_path: "file/path2"   # optional - used for renaming/moving. file at `path` will be deleted. Content
    # }
    #
    # rename example:
    # {
    #   path: "lib/sample1",
    #   new_path: "lib/sample2"
    # }
    #
    # modification:
    #
    # {
    #   path: "lib/file",
    #   content: "stuff in file"
    # }
    #
    # deletion:
    #
    # {
    #   path: "docs/delete-me",
    #   deletion: true
    # }
    #
    # rename and modification:
    #
    # {
    #   path: "start/path",
    #   content: "new content",
    #   new_path: "end/path"
    # }
    #
    # author - the user authoring the commit
    # headline - commit headline
    # body - the optional body of the commit message
    #
    # Returns a Ref object pointing to the resulting commit.
    def create_commit(changes:, author:, headline:, body: nil)
      fail Git::Ref::UpdateFailed, "Cannot write to repository." unless repository.pushable_by?(author)

      message = [headline, body].compact.join("\n\n")

      append_commit({ author: author, message: message }, author) do |files|
        changes.each { |change| add_change(change: change, files: files) }
      end
    end

    # Public: Update this ref by appending a commit to the tip
    #
    # This is a convenience method, where
    #
    #     ref.append_commit(metadata, user, options) do |files|
    #       files.add(path, content)
    #     end
    #
    # is equivalent to
    #
    #     commit = ref.repository.commits.create(metadata, ref.target_oid) do |files|
    #       files.add(path, content)
    #     end
    #     ref.update(commit, user, options)
    #
    # See CommitsCollection#create and Ref#update for details
    #
    # Returns the newly-created Commit.
    #
    # Note: This method DOES NOT perform authentication / authorization checks.
    # Ensure that callers of this method handle any required authentication
    # prior to invoking this function.
    def append_commit(metadata, author, options = {})
      sign = options.delete(:sign)
      proposed_target_oid = options.delete(:target_oid) || target_oid

      metadata[:current_user] = author

      commit = if block_given? || metadata[:tree].blank?
        repository.commits.create(metadata, proposed_target_oid, sign: sign, target_ref_name: qualified_name) do |files|
          yield files if block_given?
        end
      else
        repository.commits.create(metadata, proposed_target_oid, sign: sign, target_ref_name: qualified_name)
      end

      update(commit, author, options)
      commit
    end

    # Internal: Low level interface on git-update-ref(1). Used to create, update,
    # or delete the current ref in the underlying git repository. The receiver's
    # target attribute is also updated to reflect the change and the shared refs
    # collection is modified
    #
    # target     - The target object or string oid to write to the ref, or the
    #              special null oid value to delete the ref.
    # author     - The User or { :name, :email } Hash that is responsible for updating the ref.
    # reflog     - Optional Hash of arbitrary data to write to the reflog.
    # options    - Optional Hash of extra options.
    #   :post_receive    - Boolean specifying whether to trigger a post-receive. Default true.
    #   :backup          - Boolean specifying whether to trigger a backup job when
    #                      :post_receive is false. Default true.
    #   :clear_ref_cache - Boolean specifying whether to clear the ref cache. Default true.
    #   :priority        - The priority to provide to DGit's 3PC ref update client.
    #
    # Returns the target object provided when the ref was written successfully.
    # Raises ComparisonMismatch
    def write_ref(target, author, reflog, options = {}, attempts_remaining = 10)
      raise TypeError, "target must not be nil" if target.nil?
      new_oid = target.respond_to?(:oid) ? target.oid : target
      old_oid = target_oid || GitHub::NULL_OID
      priority = options.delete(:priority) || :high

      # guard against writing to refs outside of the refs/ namespace
      # like HEAD and root repository files
      if !qualified_name.start_with?("refs/")
        fail "Refusing to write ref outside the refs/ namespace"
      end

      # guard against writing to invalid branch names
      if GitHub::SHA_LIKE_REF_NAME.match?(qualified_name) && new_oid != GitHub::NULL_OID
        raise InvalidName, "Sorry, branch or tag names consisting of 40 hex characters are not allowed."
      elsif GitHub::REFS_PREFIX_REF_NAME.match?(qualified_name) && new_oid != GitHub::NULL_OID
        raise InvalidName, "Sorry, branch or tag names starting with 'refs/' are not allowed."
      elsif qualified_name.length > GitHub::MAX_REF_LENGTH && new_oid != GitHub::NULL_OID
        raise InvalidName, "Sorry, refs longer than #{GitHub::MAX_REF_LENGTH} bytes are not allowed."
      end

      raise TypeError, "author must not be nil" if author.nil?

      @written_at = @repository.batch_write_refs(author, [[qualified_name, old_oid, new_oid]],
                                   reflog: reflog,
                                   priority: priority,
                                   attempts_remaining: attempts_remaining,
                                   clear_ref_cache: options.fetch(:clear_ref_cache, true),
                                   no_custom_hooks: options[:no_custom_hooks])
      set_target_object(target)
      process_update_options(old_oid, new_oid, author, written_at, priority, options)
      target
    end

    # Internal: Perform post ref update operations based on the given options.
    # This enqueues a push job.
    def process_update_options(old_oid, new_oid, author, pushed_at, priority, options = {})
      if options[:post_receive] != false
        enqueue_push_job(old_oid, new_oid, author, pushed_at, excluded_pull_ids: options[:excluded_pull_ids])
      elsif options[:backup] != false
        GitHub.dogstats.increment("backup", tags: ["action:hidden-update"])
        repository.update_pushed_at
        if priority == :low
          repository.async_backup_delayed(opts: { pushed_at: pushed_at })
        else
          repository.async_backup(opts: { pushed_at: pushed_at })
        end
      end
    end

    # Public: Trigger push processing to run in the background.
    #
    # excluded_pull_ids - A array which, if provided, indicates PRs that have
    #   been eagerly synchronized and can be skipped by
    #   `synchronize_requests_for_ref`.
    # merge_method - The merge method, if provided, indicates the push resulted from a programmatic PR merge.
    #   Could be :merge, :squash, or :rebase.
    # merge_action - Symbol that we use to log which type of action was taken that resulted in the merge.
    #                One of :indirect_merge, :direct_merge, :admin_override_merge, :auto_merge, :merge_queue_merge, or :api_merge_queue_merge
    def enqueue_push_job(old_oid, new_oid, author, pushed_at, excluded_pull_ids: nil, merge_method: nil, merge_action: nil)
      ref_update = Git::Ref::Update.new(repository: repository, refname: qualified_name,
                                        before_oid: old_oid || GitHub::NULL_OID,
                                        after_oid: new_oid)

      if repository&.feature_enabled?(:push_event_pusher_id)
        RepositoryPushJobTrigger.new(
          repository,
          author.is_a?(User) ? author : nil,
          [ref_update],
          pushed_at,
          excluded_pull_ids: excluded_pull_ids,
          merge_method:,
          merge_action:,
          pusher_id: author.is_a?(User) ? author.id : nil,
        ).enqueue
      else
        RepositoryPushJobTrigger.new(repository, author.is_a?(User) ? author : nil, [ref_update], pushed_at, excluded_pull_ids: excluded_pull_ids, merge_method:, merge_action:).enqueue
      end
    end

    # Internal: Build a hash with environment variables needed when invoking git
    # commands that require commit information.
    #
    # person - The person whose git author info we want. Can either be a User
    #          object or a hash with :name and :email keys.
    #
    # Returns a Hash.
    def self.git_committer_env(person)
      name, email = User.git_author_info(person)
      { "GIT_COMMITTER_NAME" => name, "GIT_COMMITTER_EMAIL" => email, "TZ" => Time.zone.tzinfo.name }
    end

    alias ref name       # deprecated
    alias sha target_oid # deprecated
    alias valid?  exist? # deprecated
    alias exists? exist? # deprecated

    # Notify websocket subscribers of ref updates.
    # Should be called by PostReceive
    def notify_socket_subscribers(data)
      action = case data[:action]
      when :create
        "created"
      when :push
        "pushed"
      when :delete
        "deleted"
      else
        raise "unknown action: #{data[:action].inspect}"
      end

      data = data.merge(reason: "branch '#{name}' was #{action}")
      channel = GitHub::WebSocket::Channels.branch(repository, utf8(name))
      GitHub::WebSocket.notify_repository_channel(repository, channel, data)
    end

    # Revert a commit on this ref.
    #
    # author     - the User responsible for the revert
    # commit_oid - the OID of the commit to revert
    # Options:
    #   :reflog_data - Hash of metadata to be written to the reflog
    #   see CommitsCollection#create_revert_commit for the rest.
    #
    # Returns a tuple of [Commit, error], only one of which will be present.
    #
    # See CommitsCollection#create_revert_commit for possible errors
    def revert_commit(author, commit_oid, options = {})
      retrying do
        revert_commit, error = @repository.commits.create_revert_commit(
          author,
          target_oid,
          commit_oid,
          options,
        )

        return [nil, error] if error

        update(revert_commit.oid, author, options.slice(:reflog_data))
        [revert_commit, nil]
      end
    end

    # Public: Merge one thing into another, like git-merge
    #
    # author  - The User who will be the author/committer of the merge
    # head    - a String branch name or commit oid to be merged into the base
    # options - a Hash of options (default: {})
    #           :commit_message - Optional String to use as the commit message for the merge commit
    #           :reflog_data    - Optional Hash of arbitrary data to write to the reflog as JSON.
    #           :post_receive   - Boolean specifying whether to trigger a post-receive. Default true.
    #
    # Returns a tuple of [Commit, error, error_message, additional_details]. If there was an error,
    # Commit will be nil and error/error_message will be set
    #
    # See CommitsCollection#create_merge_commit for possible errors
    def merge(author, head, options = {})
      options[:commit_message] ||= "Merge #{head} into #{name}"
      options[:server_merge] = true

      if sha = repository.ref_to_sha(head)
        if repository.rpc.object_exists?(sha, "commit")
          commit = repository.commits.find(sha)
        end
      end

      if commit.nil?
        return [nil, :no_such_head, "Head does not exist"]
      end

      retrying do
        base = target_oid || options[:target_oid]
        merge_commit, error, details = repository.commits.create_merge_commit(author, base, head, options)

        case error
        when :already_merged
          return [nil, error, "Already merged"]
        when :merge_conflict
          return [nil, error, "Merge conflict", details]
        when nil
          # no error, attempt ref update
          begin
            update(merge_commit, author, options)
            [merge_commit, nil, nil]
          rescue Ref::ProtectedBranchUpdateError => e
            return [nil, :protected_branch_update_error, e.message]
          rescue Ref::WorkflowUpdatePolicyError => e
            return [nil, :workflow_policy_update_error, e.message]
          rescue Ref::RepositoryRuleViolationError => e
            return [nil, :repository_rule_violation, e.detailed_message]
          end
        else
          return [nil, error, "There was a problem performing the merge"]
        end
      end
    end

    # Public: Check if ref can be deleted.
    #
    # - A ref must exist
    # - Can't be the default branch, most likely "master"
    # - Can't be covered by a protected branch that prohibits branch deletion (the default)
    # - Can't be covered by a protected branch that is locked (depends on if it applies to non-admins or everyone)
    # - Can't be in the process of being renamed
    #
    # Returns boolean.
    def deleteable?(deleter: nil)
      return false unless deleteable_to_complete_rename?
      return false if self.policy_evaluator&.blocks_deletes_for?(deleter)
      !repository.branch_being_renamed?(name.b)
    end

    # Public: Check if this ref could be deleted as part of finishing a branch rename process.
    #
    # - A ref must exist
    # - Can't be the default branch, most likely "master"
    # - Branch renames are allowed to bypass the "deletion" branch protection policy
    #
    # Returns a Boolean.
    def deleteable_to_complete_rename?
      return false if !exist?
      return false if default_branch?
      return false if !repository.writable?

      true
    end

    # Public: Check if ref is the repository's default branch.
    #
    # This is "master" by default, but can be changed by the user.
    #
    # Returns boolean.
    def default_branch?
      name.b == repository.default_branch.b
    end

    def branch?
      prefix == "refs/heads/"
    end

    def tag?
      prefix == "refs/tags/"
    end

    # Public: Check if ref is "Locked".
    #
    # Returns Boolean.
    def locked?
      protected_branch&.lock_branch_enabled? ? true : false
    end

    # Public: Check if ref is "Protected".
    #
    # Depending on branch protection settings, non-fast-forward updates and branch deletion may be prohibited.
    #
    # Returns Boolean.
    sig { returns(T::Boolean) }
    def protected?
      protected_by_protected_branch? || protected_by_ruleset?
    end

    # Public: Check if ref is "Protected" by a protected branch.
    #
    # Returns Boolean.
    def protected_by_protected_branch?
      policy_evaluator.present? && policy_evaluator&.protected_branch.present?
    end

    # Public: Check if ref is "Protected" by a ruleset.
    #
    # Returns Boolean.
    def protected_by_ruleset?
      ref_rulesets.any?
    end

    # Public: Check if ref is "Protected" by an org-ruleset.
    #
    # Returns Boolean.
    sig { returns(T::Boolean) }
    def protected_by_org_ruleset?
      ref_rulesets.any? { |ruleset| ruleset.source&.is_a?(Organization) }
    end

    # Public: Check if this ref is protected via a protection rule that
    #         matches this ref's short name.
    def protected_by_exact_rule?
      protected? && !protected_branch.wildcard_rule?
    end

    # Public: Find the PolicyEvaluator for this branch, with support for
    # preloading via Prelude
    #
    # Returns a BranchRuleEvaluator or nil
    batch_method(:policy_evaluator, T.nilable(BranchRuleEvaluator)) do |refs|
      branches_by_repo_and_name = {}
      # BranchRuleEvaluator uses the organization to load org-wide policies. Preload now for performance.
      if GitHub.flipper[:use_billing_locked_rather_than_disabled].enabled?
        GitHub::PrefillAssociations.prefill_associations(refs.map(&:repository).uniq, [:organization, { owner: [:customer_accounts, :customer] }])
      else
        GitHub::PrefillAssociations.prefill_associations(refs.map(&:repository).uniq, [:organization, :owner])
      end

      refs.group_by(&:repository).each do |repo, repo_refs|
        branch_names = repo_refs.select(&:branch?).map(&:name)

        BranchRuleEvaluator.for_repository_with_branch_names(repo, branch_names).each do |branch_name, protected_branch|
          branches_by_repo_and_name[[repo, branch_name]] = protected_branch
        end
      end

      refs.index_with do |ref|
        branches_by_repo_and_name[[ref.repository, ref.name]]
      end
    end

    # Public: Find the ProtectedBranch for this branch, with support for
    # preloading via Prelude
    #
    # Returns a ProtectedBranch or nil
    batch_method(:protected_branch) do |refs|
      branches_by_repo_and_name = {}

      refs.group_by(&:repository).each do |repo, repo_refs|
        branch_names = repo_refs.select(&:branch?).map(&:name)

        ProtectedBranch.for_repository_with_branch_names(repo, branch_names).each do |branch_name, protected_branch|
          branches_by_repo_and_name[[repo, branch_name]] = protected_branch
        end
      end

      refs.index_with do |ref|
        branches_by_repo_and_name[[ref.repository, ref.name]]
      end
    end

    # Public: Set the ProtectedBranch object for this ref. Can only be used for branches
    #
    # protected_branch - A ProtectedBranch
    #
    # Returns ProtectedBranch
    def protected_branch=(protected_branch)
      unless branch?
        raise TypeError, "cannot set a ProtectedBranch for non-branch ref"
      end

      unsafe_preload_batch_method_value(:protected_branch, protected_branch)
      clear_preloaded_batch_method_value(:policy_evaluator)
    end

    # Public: normalize the ref name to something acceptable
    # Get rid of things like spaces, consecutive slashes, dots, &c, and
    # convert them to dashes
    #
    # cf git-check-ref-format(1)
    #
    # name - String name to check/normalize
    #
    # Returns a String
    # Returns nil when name is normalized to empty string
    def self.normalize(name)
      return nil if name.blank?

      result = name.dup

      # Ref name encodings are not reliable: names returned by GitRPC are
      # always marked as ASCII-8BIT regardless of the bytes they contain.
      # In order to match against a regexp containing UTF-8 byte sequences,
      # we need to have a UTF-8 string, therefore we temporarily change the
      # encoding, but only strip the control characters if the string makes
      # sense as UTF-8.
      result.force_encoding("UTF-8")
      if result.valid_encoding?
        result.gsub!(/[\u0080-\u00A0]/, "")      # Remove Unicode C1 control characters
      end
      result.force_encoding(name.encoding)

      result.gsub!(/[~^:?*\[\\]+/, "")           # Remove ~, ^, :, ?, *, [, and \ characters
      result.gsub!(/[\0-\037\177]+/, "")         # Remove any ASCII control characters
      result.gsub!(/\s+/, "-")                   # Replace spaces with hyphens

      begin
        old_result = result.dup
        result.gsub!(/\.lock(\/|$)/, "/")        # No slash-separated part can end with .lock
        result.gsub!(/(^|\/)\./, "/")            # No slash-separated part can start with a period
        result.gsub!(/@{/, "")                   # Cannot contain the @{ sequence
        result.gsub!(/\/{2,}/, "/")              # Make all consecutive / characters into a single one
        result.gsub!(/\.{2,}/, ".")              # Make all consecutive . characters into a single one
        # Remove any leftover hyphens and slashes at the beginning or end
        ["-", "/"].each do |char|
          result.delete_prefix!(char)
          result.delete_suffix!(char)
        end
        # Remove any trailing dots
        result.delete_suffix!(".")
      end until result == old_result # rubocop:disable Lint/Loop

      return nil if result.blank?

      result
    end

    # Public: Same as Git::Ref#normalize, but also removes characters that could
    # allow the ref name to be exploited for 'pastejacking' if copy/pasted into
    # terminal. See https://github.com/github/github/issues/154877 for more info.
    #
    # For use when displaying the sanitized ref name in copyable terminal content
    # (for example, the rename branch dialog).
    #
    # name - String name to check/normalize
    #
    # Returns a String
    # Returns nil when name is normalized to empty string
    def self.paste_safe_normalize(name)
      result = normalize(name)
      return nil if result.blank?

      result.delete!("`$")
      return nil if result.blank?
      result
    end

    # For caching.  Delegate to the last_modified_at for the target commit.
    def last_modified_at
      if commit?
        commit.last_modified_at
      else
        repository.last_modified_at
      end
    end

    # On success, returns a hash with the following keys:
    # {
    #   message: success message,
    #   merge_type: merge / fast-forward / none,
    #   base_branch: base branch name in the form owner:branch-name
    # }
    def fetch_and_merge(actor:, discard_changes: false)
      old_ref_commit = self.sha

      raise RejectedError unless repository.fork?
      unless repository.parent.resources.contents.readable_by?(actor)
        GitHub.dogstats.increment("branch.fetch_and_merge_error", tags: ["reason:cant_read_parent"])
        raise FetchAndMergeFailure, "You can't read the parent repository."
      end
      unless repository.resources.contents.writable_by?(actor)
        GitHub.dogstats.increment("branch.fetch_and_merge_error", tags: ["reason:cant_write_repo"])
        raise FetchAndMergeFailure, "You can't write to this branch."
      end

      unless repository.writable?
        GitHub.dogstats.increment("branch.fetch_and_merge_error", tags: ["reason:repository_inactive"])
        raise FetchAndMergeFailure, "This repository is not writable"
      end

      # These conditions are NOT expected, but let's play safe
      base_branch = repository.base_branch(self.name, actor)
      raise RejectedError unless base_branch.include?(":")
      parent_commit = repository.parent.refs.find(base_branch.split(":").last)&.sha
      raise RejectedError unless parent_commit

      repository.rpc.fetch_commits(repository.parent.shard_path, parent_commit)

      # If we are ahead, we need to create a merge commit, otherwise we can just
      # "fast forward" (i.e., update the branch to the fetched commit)
      # But if we're not behind, we don't need to do anything!
      ff_check_comparison = GitHub::Comparison.deprecated_build(repository, parent_commit, self.qualified_name)
      push_time = actor.time_zone.now
      if !ff_check_comparison.behind?
        return {
          message: "This branch is not behind the upstream #{base_branch}.",
          merge_type: "none",
          base_branch: base_branch
        }
      elsif ff_check_comparison.ahead? && !discard_changes
        author = {
          "email" => actor.git_author_email,
          "name"  => actor.git_author_name,
          "time"  => push_time,
        }
        committer = {
          "email" => GitHub.web_committer_email,
          "name"  => GitHub.web_committer_name,
          "time"  => push_time,
        }
        message = "Merge branch '#{base_branch}' into #{self.name}"
        target_commit, error, details = repository.create_merge_commit(
          old_ref_commit, parent_commit, author, message, {
            committer: committer,
            check_tree_with_diff: GitHub.flipper[:create_merge_commit_check_tree_with_diff].enabled?(repository),
          }, &repository.method(:sign_commit))
      else
        target_commit = parent_commit
        error = nil
      end

      if error.nil?
        begin
          # Evaluate rules and commit
          update(target_commit, actor, { fetch_and_merge: true })

          action = ff_check_comparison.ahead? && !discard_changes ? "merged" : "fast-forwarded"
          merge_type = ff_check_comparison.ahead? && !discard_changes ? "merge" : "fast-forward"
          GitHub.dogstats.increment("branch.fetch_and_merge", tags: ["strategy:#{action}", "discard_changes:#{discard_changes}"])
          {
            message: if discard_changes
                       "Successfully discarded changes and synchronized branch to match upstream #{base_branch}."
                     else
                       "Successfully fetched and #{action} from upstream #{base_branch}."
                     end,
            merge_type: merge_type,
            base_branch: base_branch
          }
        rescue ProtectedBranchUpdateError, RepositoryRuleViolationError => e
          GitHub.dogstats.increment("branch.fetch_and_merge_error", tags: ["reason:rule_violation"])
          raise FetchAndMergeFailure, e.message
        rescue WorkflowUpdatePolicyError => e
          GitHub.dogstats.increment("branch.fetch_and_merge_error", tags: ["reason:workflow_update"])
          raise FetchAndMergeFailure, e.message
        rescue UpdateError
          GitHub.dogstats.increment("branch.fetch_and_merge_error", tags: ["reason:error_branch_update"])
          raise FetchAndMergeFailure, "There was a problem updating the branch"
        end
      elsif error == "merge_conflict"
        GitHub.dogstats.increment("branch.fetch_and_merge_error", tags: ["reason:merge_conflict"])
        raise MergeConflictError
      else
        GitHub.dogstats.increment("branch.fetch_and_merge_error", tags: ["reason:error_merge_commit"])
        raise FetchAndMergeFailure, "There was a problem creating the merge commit"
      end
    end

    private

    sig { returns(T::Array[RepositoryRuleset]) }
    def ref_rulesets
      policy_evaluator&.ref_rulesets || []
    end

    # A helper for #update that accepts a proposed target and builds an
    # Update object describing the change.
    def build_ref_update(proposed_target, options)
      before_oid = target_oid || GitHub::NULL_OID
      after_oid = proposed_target.respond_to?(:oid) ? proposed_target.oid : proposed_target

      rule_commit = options.delete(:rule_commit)
      force = options.delete(:force) { true }
      allow_deletion_policy_bypass = options.delete(:allow_deletion_policy_bypass)

      pull_request = options.delete(:pull_request)
      merge_method = options.delete(:merge_method)

      if branch?
        policy_commit_oid = rule_commit.respond_to?(:oid) ? rule_commit.oid : rule_commit

        Git::Branch::Update.new(repository: repository, refname: qualified_name,
                                before_oid: before_oid, after_oid: after_oid,
                                policy_commit_oid: policy_commit_oid, force: force,
                                allow_deletion_policy_bypass: allow_deletion_policy_bypass,
                                pull_request: pull_request, merge_method: merge_method)
      else
        Git::Ref::Update.new(repository: repository, refname: qualified_name,
                             before_oid: before_oid, after_oid: after_oid)
      end
    end

    # This helper method can be used for cases where the ref may
    # move before we attempt to update it, but we don't actually care
    # where it is and just want to try the operation again.

    # It makes sense for merging and reverting, where the new
    # commit needs to be built on top of the current one, but
    # what the current one is is really irrelevant as far as the
    # update goes.
    #
    # See #merge and #revert_commit for practical usage example.
    def retrying(max = 10)
      1.upto(max).each do |attempt|
        begin
          return yield
        rescue ComparisonMismatch => e
          raise e if attempt == max
          repository.reload
          set_target_object(repository.spokes_api.resolve_object(object_name: qualified_name))
        end
      end
    end

    # Internal: add a change to the files object for the new commit.
    def add_change(change:, files:)
      return files.remove(change[:path]) if change[:deletion]
      return if change[:content].nil? && change[:new_path].nil?

      path = change[:path]

      content = if change[:content]
        repository.normalize_line_endings(change[:content], target_oid, path)
      else
        repository.blob(target_oid, path).data
      end

      files.add(change[:new_path] || path, content)
      files.remove(path) if change[:new_path]
    end

    def check_rules(repository, ref_update, author, server_merge, fetch_and_merge, no_rule_suite_persist, never_bypass)
      # Rules are only supported by actual Repository objects, not by Gists or Wikis
      return unless repository.is_a?(Repository)

      rule_suite = RuleEngine::Evaluator.evaluate_rules_one(
        repository,
        ref_update,
        author,
        phase: RuleEngine::Types::Phase::PostReceive,
        dry_run: no_rule_suite_persist,
        options: {
          server_merge: server_merge,
          fetch_and_merge: fetch_and_merge
        }
      )

      # Telemetry to see how often github-merge-queue[bot] is interacting with policies
      if rule_suite.rule_runs.any? && author.type == "Bot" && GitHub.merge_queue_bot && (author.id == GitHub.merge_queue_bot.id)
        if rule_suite.rules_fulfilled?
          GitHub.dogstats.increment("Git::Ref::check_rules:merge-queue-bot", tags: ["result:passed"])
        elsif !rule_suite.bypassed?
          GitHub.dogstats.increment("Git::Ref::check_rules:merge-queue-bot", tags: ["result:blocked"])
        else
          GitHub.dogstats.increment("Git::Ref::check_rules:merge-queue-bot", tags: ["result:bypassed"])

          GitHub.logger.info(
            "Git::Ref::check_rules:merge-queue-bot bypass",
            "gh.repo.id": repository.id,
            "gh.repo.name": repository.name,
            "gh.repo.owner_id": repository.owner&.id,
            "gh.repo.owner_name": repository.owner&.name,
            "gh.ref_update.refname": ref_update.refname,
          )
        end
      end

      if never_bypass
        return if rule_suite.rules_fulfilled?
      else
        return if rule_suite.action_permitted?
      end

      if (failed_runs = rule_suite.rule_runs.filter(&:failed?)).any? && failed_runs.all? { |run| run.rule_type == "workflow_updates" }
        workflow_run = failed_runs.filter(&:failed?).find { |run| run.rule_type == "workflow_updates" }
        raise WorkflowUpdatePolicyError.new(workflow_run&.message)
      elsif rule_suite.rule_runs.any? { |run| run.failed? && !run.legacy_rule_provider? }
        raise RepositoryRuleViolationError.new(rule_suite)
      else
        raise ProtectedBranchUpdateError.new(self, rule_suite,
          "protected #{branch? ? 'branch' : 'tag'} '#{name}' check failed:\n  #{rule_suite.message}")
      end
    end
  end
end
