# typed: strict
# frozen_string_literal: true

module MergeQueues
  # Class responsible for creating the temporary refs used to run CI on
  # behalf of Merge Queue.
  class Ref
    include GitHub::Memoizer

    class ErrorCode < T::Enum
      enums do
        AlreadyMerged = new(:already_merged)
        NoSuchHead = new(:no_such_head)
        MergeConflict = new(:merge_conflict)
        FailedMerge = new(:failed_merge)
        BadBase = new(:bad_base)
        RefAlreadyExists = new(:ref_already_exists)
        SignatureError = new(:signature_error)
        RebaseTimeout = new(:rebase_timeout)
        RebaseConflict = new(:rebase_conflict)
        BranchProtectionError = new(:branch_protection_error)
        InvalidMergeCommit = new(:invalid_merge_commit)
        NotFoundAfterCreation = new(:not_found_after_creation)
        GitSystemsOutage = new(:git_systems_outage)
        Unknown = new(:unknown)
      end

      sig { returns(String) }
      def to_s
        serialize.to_s
      end
    end

    module Result
      extend T::Helpers

      requires_ancestor { Object }

      sealed!

      class Error < T::Struct
        include Result
        const :error, ErrorCode
        const :error_details, T.nilable(T::Hash[Symbol, T.untyped]), default: nil
        const :name, T.nilable(String), default: nil
        const :exception, T.nilable(Exception), default: nil

        sig { returns(String) }
        def message
          case e = exception
          when Git::Ref::RepositoryRuleViolationError
            e.detailed_message
          when Exception
            e.message
          else
            error.to_s
          end
        end
      end

      class Success < T::Struct
        include Result
        const :head_ref, String
        const :head_oid, String
      end
    end

    ProtectedBranchExceptions = T.let([
      Git::Ref::ProtectedBranchUpdateError,
      Git::Ref::WorkflowUpdatePolicyError,
      Git::Ref::RepositoryRuleViolationError,
    ], T::Array[T.class_of(Git::Ref::UpdateError)])

    # Double the rebase timeout because we're in a background job.
    sig { returns(ActiveSupport::Duration) }
    def self.rebase_timeout
      T.let(PullRequest::Prepare.rebase_timeout.seconds * 2, ActiveSupport::Duration)
    end

    sig do
      params(
        entry: MergeQueueEntry,
        base_sha: String,
        merge_method: IConfiguration::MergeMethod,
        timestamp: Time,
        enqueuer: T.nilable(User),
        pull_request: PullRequest,
        repository: Repository,
        queue: MergeQueues::Command::QueueDependency,
        head_sha: T.nilable(String),
      ).void
    end
    def initialize(entry:, base_sha:, merge_method:, timestamp:, enqueuer:, pull_request:, repository:, queue:, head_sha: nil)
      @entry = entry
      @base_sha = base_sha
      @head_sha = head_sha
      @merge_method = merge_method
      @timestamp = timestamp
      @enqueuer = enqueuer
      @pull_request = pull_request
      @repository = repository
      @queue = queue
    end

    sig { returns(Result) }
    def create
      if error = delete_existing_ref
        return error
      end

      case result = create_merge_commit
      when Commit
        commit = merge_commit = result
      when Result::Error
        return result
      else
        T.absurd(result)
      end

      if @merge_method == IConfiguration::MergeMethod::Squash
        case result = create_squash_commit(commit)
        when Commit
          commit = result
        when Result::Error
          return result
        else
          T.absurd(result)
        end
      end

      if @merge_method == IConfiguration::MergeMethod::Rebase
        result = if @repository.feature_enabled?(:merge_queue_rebase_service_object)
          create_rebase_commit_from_service(commit)
        else
          create_rebase_commit(commit)
        end

        case result
        when Commit
          commit = result
        when Result::Error
          return result
        else
          T.absurd(result)
        end
      end

      error = check_final_commit_diffsame!(commit, merge_commit)
      return error if error

      case result = create_ref(commit)
      when Git::Ref
        ref = result
      when Result::Error
        return result
      else
        T.absurd(result)
      end

      unless @queue.uses_queue_refs?
        find_or_create_locked_ref(ref)
      end

      Result::Success.new(
        head_ref: refname,
        head_oid: commit.oid
      )
    end

    sig { returns(String) }
    memoize def refname
      "#{@queue.branch}/pr-#{@pull_request.number}-#{@base_sha}"
    end

    protected

    # Avoid "ref already exists" errors by deleting any existing ref before
    # attempting to create it.
    #
    # Refs are unique to the queue, PR number, and base_oid, so the only
    # reason we would be in this situation is if a previous attempt for this
    # PR had failed, e.g. if the ref was created but the subsequent DB write
    # failed.
    sig { returns(T.nilable(Result::Error)) }
    def delete_existing_ref
      ref = T.let(@queue.queue_ref_collection.read(refname), Git::Ref)

      return unless ref.exists?

      GitHub.logger.info(
        "Deleting stale Merge Queue ref",
        "gh.merge_queue.ref_name_suffix": "pr-#{@pull_request.number}-#{@base_sha}",
        "gh.merge_queue.ref_sha": ref.target_oid,
      )

      begin
        ref.delete(MergeQueues.system_actor)
        nil
      rescue Git::Ref::NotFound
        nil
      rescue *ProtectedBranchExceptions => exception
        Result::Error.new(error: ErrorCode::BranchProtectionError, exception:)
      end
    end

    sig { returns(T.any(::Commit, Result::Error)) }
    def create_merge_commit
      GitHub.logger.with_named_tags({ "code.namespace": "MergeQueues::Ref", "code.function": "create_merge_commit" }) do
        head_sha = @head_sha
        if head_sha.nil?
          GitHub.logger.error(
            "gh.merge_queue.failure" => "GIT_TREE_INVALID",
            "exception.message" => "No head_sha on PR record",
          )
          return Result::Error.new(error: ErrorCode::NoSuchHead)
        end

        unless head_commit = find_commit(head_sha)
          GitHub.logger.error(
            "gh.merge_queue.failure" => "GIT_TREE_INVALID",
            "exception.message" => "PR head_sha does not exist",
            "gh.commit.oid" => head_sha,
          )
          return Result::Error.new(error: ErrorCode::NoSuchHead)
        end

        title = @pull_request.default_merge_commit_title
        message = @pull_request.default_merge_commit_message
        commit_message = "#{title}\n\n#{message}".chomp("")

        commit, error, error_details = @repository.commits.create_merge_commit(enqueuer, @base_sha, head_commit.oid, {
          commit_message:,
          commit_time: @timestamp,
        })

        if commit
          commit
        else
          case error
          when :already_merged
            Result::Error.new(error: ErrorCode::AlreadyMerged)
          when :merge_conflict
            GlobalInstrumenter.instrument("pull_request.merge_conflict",
              conflicts: error_details,
              pull: @pull_request,
              base_commit_oid: @base_sha,
              head_commit_oid: @pull_request.head_sha,
              queued: true
            )

            Result::Error.new(error: ErrorCode::MergeConflict, error_details:)
          else
            GitHub.logger.error(
              "gh.merge_queue.failure" => "GIT_TREE_INVALID",
              "exception.message" => "Merge failed with #{error_details}",
            )

            Result::Error.new(error: ErrorCode::FailedMerge)
          end
        end
      end
    rescue GitRPC::InvalidFullOid, GitRPC::ObjectMissing
      Result::Error.new(error: ErrorCode::BadBase)
    end

    sig { params(commit: Commit).returns(T.any(Commit, Result::Error)) }
    def create_squash_commit(commit)
      GitHub.dogstats.time("merge_queue.squash_merge_commit") do
        squash_merge = PullRequest::SquashMerge.new(
          repository: @repository,
          commit_oid: commit.oid,
          require_signature: require_signature_for_squash?,
        )

        sha = squash_merge.perform(
          author_email: git_email(pull_request_author),
          author_name: pull_request_author.git_author_name,
          time_zone: pull_request_author.time_zone,
          title: @pull_request.default_squash_commit_title,
          message: @pull_request.default_squash_commit_message(author: pull_request_author),
          commit_time: @timestamp,
        )

        if squash_commit = find_commit(sha)
          squash_commit
        else
          Result::Error.new(error: ErrorCode::Unknown)
        end
      end
    rescue Repositories::Error::SignatureError
      Result::Error.new(error: ErrorCode::SignatureError)
    end

    # Prepare a rebase for the given merge commit.
    # Returns the final oid for the sequence of commits that have been rebased, or an error if there was an issue.
    sig { params(commit: Commit).returns(T.any(Commit, Result::Error)) }
    def create_rebase_commit_from_service(commit)
      GitHub.dogstats.time("merge_queue.prepare_rebase") do
        exception = T.let(nil, T.nilable(Exception))
        error = T.let(ErrorCode::Unknown, ErrorCode)

        base_sha, head_sha = commit.parent_oids

        result = PullRequests::GitSystems::CreateRebaseCommit.new(
          repository: @repository,
          base_sha: base_sha.to_s,
          head_sha: head_sha.to_s,
          name: enqueuer.git_author_name,
          email: git_email(enqueuer),
          timestamp: @timestamp,
          timeout: Ref.rebase_timeout,
        ).call

        case result
        when PullRequests::GitSystems::Commit::Created
          if result.sha == result.base_sha
            error = ErrorCode::AlreadyMerged
          elsif rebase_commit = find_commit(result.sha)
            return rebase_commit
          else
            error = ErrorCode::NotFoundAfterCreation
          end
        when PullRequests::GitSystems::Commit::Conflict
          error = ErrorCode::RebaseConflict
        when PullRequests::GitSystems::Errors::Timeout
          exception = result.exception
          error = ErrorCode::RebaseTimeout
        when PullRequests::GitSystems::Errors::Outage
          exception = result.exception
          error = ErrorCode::GitSystemsOutage
        when PullRequests::GitSystems::Commit::Error, PullRequests::GitSystems::Errors::Fatal
          exception = result.exception
        else T.absurd(result)
        end

        Result::Error.new(error:, exception:, name: refname)
      end
    end

    # FIXME: Copied/pasted/slightly-modified from PullRequest::Prepare
    # Prepare a rebase for the given merge commit.
    # Returns the final oid for the sequence of commits that have been rebased, or an error if there was an issue.
    sig { params(commit: Commit).returns(T.any(Commit, Result::Error)) }
    def create_rebase_commit(commit)
      GitHub.dogstats.time("merge_queue.prepare_rebase") do
        base_sha, head_sha = commit.parent_oids

        committer = {
          name: enqueuer.git_author_name,
          email: git_email(enqueuer),
          time: @timestamp,
        }

        timeout = false
        exception = nil

        rebase_oid = begin
          GitHub.logger.with_named_tags({ "code.function": "rebase" }) do
            extra_options = {
              use_tmp_objdir_mode: "migrate-on-success"
            }

            if GitHub.flipper[:tmp_objdir_experiment].enabled?(@repository)
              extra_options[:use_tmp_objdir_mode] = "pack-and-migrate-on-success" if GitHub.flipper[:tmp_objdir_experiment_pack].enabled?(@repository)
              result, dogstats = @repository.rpc.rebase_tmp_objdir_experiment(head_sha, base_sha, committer, timeout: Ref.rebase_timeout, **extra_options)
              dogstats.each { |args| GitHub.dogstats.count(*args) }
              result
            else
              @repository.rpc.rebase(head_sha, base_sha, committer, timeout: Ref.rebase_timeout, **extra_options)
            end
          end
        rescue GitRPC::Backend::RebaseTimeout, GitRPC::GitmonClient::AbortError, GitRPC::NetworkError, GitRPC::NoDataError => e
          exception = e
          timeout = true
          nil
        rescue GitRPC::Protocol::DGit::ResponseError => e
          exception = e

          # Treat split timeouts--some nodes timed out, others succeeded--as
          # equivalent to a unanimous timeout, rather than propagating a
          # messy ResponseError.
          if e.errors.all? do |route, error|
            error.is_a?(GitRPC::Backend::RebaseTimeout) ||
              error.is_a?(GitRPC::GitmonClient::AbortError) ||
              error.is_a?(GitRPC::Timeout) ||
              error.is_a?(GitRPC::NoDataError) ||
              error.is_a?(BERTRPC::ProtocolError) ||
              !route.voting?
          end
            GitHub.dogstats.increment("merge_queue", tags: ["action:merge_queue_prepare_rebase_timeout"])
            timeout = true
            nil
          else
            raise
          end
        end

        if timeout
          Result::Error.new(
            error: ErrorCode::RebaseTimeout,
            name: refname,
            exception:
          )
        elsif rebase_oid.nil?
          Result::Error.new(
            error: ErrorCode::RebaseConflict,
            name: refname,
            exception:
          )
        elsif rebase_commit = find_commit(rebase_oid)
          rebase_commit
        else
          Result::Error.new(error: ErrorCode::Unknown, name: refname, exception:)
        end
      end
    end

    sig { params(commit: Commit).returns(T.any(Git::Ref, Result::Error)) }
    def create_ref(commit)
      @queue.queue_ref_collection.create(
        refname,
        commit.oid,
        MergeQueues.system_actor,
        post_receive: true
      )
    rescue *ProtectedBranchExceptions => e
      Result::Error.new(error: ErrorCode::BranchProtectionError, exception: e)
    end

    sig { params(git_ref: Git::Ref).void }
    def find_or_create_locked_ref(git_ref)
      repository_id = @repository.id
      ref = git_ref.qualified_name.sub(%r[\Arefs/heads/], "")

      MergeQueueLockedRef.retry_on_find_or_create_error do
        MergeQueueLockedRef.where(repository_id:, queue: @queue, ref:).exists? ||
          MergeQueueLockedRef.create!(repository_id:, queue: @queue, ref:)
      end
    end

    private

    sig { returns(User) }
    def pull_request_author
      @pull_request.user || User.ghost
    end

    sig { returns(User) }
    def enqueuer
      @enqueuer || User.ghost
    end

    sig { params(user: User).returns(String) }
    def git_email(user)
      user.default_author_email(@repository, @pull_request.head_sha) || user.git_author_email
    end

    # Returns the pull request's head commit if it exits, otherwise `nil`.
    sig { params(sha: String).returns(T.nilable(::Commit)) }
    def find_commit(sha)
      return nil unless GitRPC::Util.valid_full_oid?(sha)
      @repository.commits.find(sha)
    end

    sig { returns(T::Boolean) }
    def require_signature_for_squash?
      evaluator = @queue.branch_rule_evaluator
      evaluator.present? &&
        evaluator.required_signatures_enabled? &&
        !evaluator.can_override_required_signatures?(actor: enqueuer)
    end

    # Check to make sure that the changes in the "merge queue commit" built on top of @target_sha are diffsame to the
    # changes in the pull request at the moment it was added to the merge queue. Changes can differ when PRs earlier in
    # the queue interact with later PRs in ways which move the merge base or otherwise add/remove changes to the final
    # merge queue commit (which might be a merge, rebase or squash).
    sig { params(commit: Commit, merge_commit: Commit).returns(T.nilable(Result::Error)) }
    def check_final_commit_diffsame!(commit, merge_commit)
      GitHub.dogstats.time("merge_queue_ref_check_final_commit_diffsame") do
        begin
          # This code needs some explanation. We need to figure out what the "best merge base" was at the moment this PR
          # entered the merge queue. @pull_request has the head_sha, but the base_sha is not always updated. In some
          # cases it points to a commit which would give us the wrong merge base. That would allow exactly the types of
          # commit-smuggling attacks we're trying to prevent. See https://github.com/github/pull-requests/issues/8059,
          # https://github.com/github/repos/issues/5876, etc.

          # What we need to do is get the actual system merge at the moment the PR was enqueued. This is the same commit
          # we use to evaluate policies when the PR tries to enter the queue -- see `branch_protections_fulfilled` in the
          # MergeQueueEntry class. It will always be a two-parent merge, with the PR's base branch HEAD as parent 1 and
          # feature branch HEAD as parent 2.

          enqueued_merge_commit_sha = @pull_request.merge_commit_sha
          enqueued_merge_commit = @repository.commits.find(enqueued_merge_commit_sha)

          enqueued_base_sha, enqueued_head_sha = enqueued_merge_commit.parent_oids

          enqueued_merge_base_sha = @repository.rpc.best_merge_base(enqueued_base_sha, enqueued_head_sha)
          enqueued_merge_base_commit = @repository.commits.find(enqueued_merge_base_sha)

          # The best merge base at the time the PR was enqueued must be tree-equal to the best merge base between the
          # feature branch HEAD and the current HEAD of the queue (@target_sha). If not, fail the diff-same check.

          comparison_merge_base_sha = @repository.rpc.best_merge_base(@base_sha, enqueued_head_sha)
          comparison_merge_base_commit = @repository.commits.find(comparison_merge_base_sha)

          unless enqueued_merge_base_commit.tree_oid == comparison_merge_base_commit.tree_oid
            return Result::Error.new(error: ErrorCode::InvalidMergeCommit)
          end

          # Merge the head branch as it existed when the PR was enqueued with @target_sha. The result must be tree-equal to
          # the proposed final commit being added to the queue. If not, fail the diff-same check because something changed.

          comparison_merge_commit =
            # Because we lock the head branch of a PR in the queue, the parents used to create merge_commit should be the
            # ones we expect (@target_sha and enqueued_head_sha). However, if the locking isn't race-proof or if any of
            # the logic in `create_ref` ever changes, this might not stay true. If that happens, create the correct merge.

            if merge_commit.parent_oids == [@base_sha, enqueued_head_sha]
              merge_commit
            else
              GitHub.dogstats.increment("pull_requests.create_merge_commit", tags: ["location:merge_queue_ref", "unreachable:true"])
              @repository.commits.create_merge_commit(
                @pull_request.safe_user,
                @base_sha,
                enqueued_head_sha
              ).first
            end

          unless comparison_merge_commit && commit.tree_oid == comparison_merge_commit.tree_oid
            return Result::Error.new(error: ErrorCode::InvalidMergeCommit)
          end
        rescue GitRPC::Timeout, GitRPC::ObjectMissing, GitRPC::InvalidObject, GitRPC::InvalidOid, GitRPC::InvalidFullOid,
          RepositoryObjectsCollection::InvalidObjectId => exception

          GitHub.logger.error(
            "gh.merge_queue.failure" => "GIT_TREE_INVALID",
            "code.namespace" => "MergeQueues::Ref",
            "code.function" => "check_final_commit_diffsame!",
            "exception.class" => exception.class.name,
            "exception.message" => exception.message,
          )

          return Result::Error.new(error: ErrorCode::FailedMerge, exception:)
        end
      end
    end
  end
end
