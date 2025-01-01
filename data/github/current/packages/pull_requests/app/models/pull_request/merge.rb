# typed: true
# frozen_string_literal: true

class PullRequest
  # Merge is a Service Object that handles all operations that are required to
  # prepare and perform the merge of a Pull Request.
  class Merge
    class ValidateSuccessResult
      sig { returns(Commit) }
      attr_reader :merge_commit
      attr_reader :merge_base_ref

      def initialize(merge_commit, merge_base_ref)
        @merge_commit = merge_commit
        @merge_base_ref = merge_base_ref
      end

      def success
        true
      end
    end

    class PerformSuccessResult
      sig { returns(T.nilable(String)) }
      attr_reader :new_sha

      def initialize(new_sha)
        @new_sha = new_sha
      end

      def success
        true
      end
    end

    class FailResult
      attr_reader :fail_message, :fail_code

      VALID_FAIL_CODES = [
        :base_missing,
        :denied,
        :draft,
        :head_mismatch,
        :invalid_email,
        :merge_commit_blocked,
        :not_mergeable,
        :protected_branch,
        :rebase,
        :rebase_merge_blocked,
        :squash_merge_blocked,
        :repository_rule_violation,
      ]

      def initialize(fail_message, fail_code = nil)
        raise ArgumentError.new(
          "Invalid fail_code: #{fail_code}"
        ) unless VALID_FAIL_CODES.include?(fail_code)

        @fail_message = fail_message
        @fail_code = fail_code
      end

      # Enable duck typing to Success.
      def new_sha = nil

      def success
        false
      end
    end

    PerformResult = T.type_alias { T.any(PullRequest::Merge::PerformSuccessResult, PullRequest::Merge::FailResult) }
    ValidateResult = T.type_alias { T.any(PullRequest::Merge::ValidateSuccessResult, PullRequest::Merge::FailResult) }

    # pull - The PullRequest to merge.
    # method - Symbol that specifies the merge method to perform. Can be one of
    #          :merge, :squash or :rebase. (optional, defaults to :merge).
    # actor   - User object of the GitHub user initiating the merge
    #           (optional, defaults to PR creator).
    # author_email - Custom email the user has chosen for this merge commit
    #                 (optional, if user doesn't make a selection will default to git email)
    # message_title - String commit message title to prefix the merge message
    #                 (optional, defaults to the default
    #                 "Merge pull request #N from repo/branch" text).
    # message - String commit message to append to the merge message
    #           (optional, defaults to PR title).
    # merge_commit - A previously prepared merge commit.
    #                (optional, if not provided prepare_and_validate must be called prior to perform)
    sig do
      params(
        pull: PullRequest,
        method: Symbol,
        actor: User,
        author_email: T.nilable(String),
        message_title: T.nilable(String),
        message: T.untyped,
        merge_commit: T.untyped
      ).void
    end
    def initialize(pull, method, actor, author_email: nil, message_title: nil, message: nil, merge_commit: nil)
      raise ArgumentError, "Unknown merge method" unless %i[merge squash rebase].include? method

      unless pull.repository&.feature_enabled?(:better_merge_email_validation)
        if author_email
          # author_emails is only verified emails
          emails = GitHub.email_verification_enabled? ? actor.author_emails : actor.emails.visible.pluck(:email)
          raise ArgumentError, "Invalid email for web commit" unless emails.include?(author_email)
        end
      end

      @pull = pull
      @method = method
      @actor = actor
      @author_email = author_email
      @message_title = message_title
      @message = message
      @merge_commit = merge_commit
    end

    attr_reader :pull

    def merge_base_sha
      fail NO_MERGE_COMMIT_MSG if merge_commit.nil?

      merge_commit.parent_oids.first
    end

    # Public: Perform the merge described by a PullRequest.
    #
    # Requires that the merge was previously prepared by calling `#prepare`
    # (e.g. from a background job), or that a previously prepared
    # merge commit was passed to #initialize.
    #
    sig { returns(PerformResult) }
    def perform
      GitHub.dogstats.time("pullrequest.merge.perform") do
        fail NO_MERGE_COMMIT_MSG if merge_commit.nil?

        # FIXME: Use verification support of `dgit-update` to check
        # that `pull.base_ref` still points to
        # `merge_commit.parent_oids[0]` and `"refs/pull/:number/head"`
        # points to `merge_commit.parent_oids[1]`.
        #
        # If they do not, we can fail early.
        if method == :rebase
          perform_rebase(actor, merge_commit)
        elsif method == :squash
          perform_squash(actor, author_email, merge_commit, message_title, message)
        else
          perform_merge(actor, author_email, merge_commit, message_title, message)
        end
      end
    end

    # Prepare and validate the PR's merge state prior to #perform.
    #
    # Creates merge commit when necessary.
    #
    sig { params(expected_head: T.nilable(String), actor: T.untyped).returns(ValidateResult) }
    def prepare_and_validate(expected_head = nil, actor: nil)
      content_authorization = ContentAuthorizer.authorize(actor, :pull_request, :merge,
                                                          issue: pull.issue,
                                                          repo: repository)
      unless content_authorization.authorized?
        return FailResult.new(content_authorization.first_error.message, :denied)
      end

      if pull.repository&.feature_enabled?(:better_merge_email_validation)
        if author_email
          emails = actor.emails.visible
          # we don't use the .verified scope because it excludes stealth
          # email addresses which we want to allow to be used if specified to merge the PR.
          emails = emails.where(state: "verified") if GitHub.email_verification_enabled?

          return FailResult.new("Invalid email address", :invalid_email) unless emails.pluck(:email).include?(author_email)
        end
      end

      if pull.draft?
        return FailResult.new("Pull Request is still a draft", :draft)
      end

      pull.maintain_tracking_ref(actor)

      # some old PRs got mergeable and merge_commit_sha out of sync.
      # we need to try creating the merge commit again. (#9675, github/enterprise-support#353)
      merge_commit_out_of_sync = pull.mergeable == true && pull.merge_commit_missing?

      if merge_commit_out_of_sync || pull.mergeable.nil?
        GitHub.dogstats.increment("merge.prepare_and_validate.create_new_merge_commit")
        skip_rebase = method != :rebase
        pull.create_merge_commit(skip_rebase: skip_rebase)
      end

      return FailResult.new("Pull Request is not mergeable", :not_mergeable) if pull.mergeable != true

      merge_base_ref = pull.base_repository.heads.find(pull.base_ref.b)
      return FailResult.new("Base branch no longer exists", :base_missing) if merge_base_ref.nil?

      if expected_head.present? && expected_head != pull.head_sha
        return FailResult.new("Head branch was modified. Review and try the merge again.", :head_mismatch)
      end

      if pull.branch_locked_for_merge_queue?
        return FailResult.new("Base branch is the protected head branch of a queued pull request.", :not_mergeable)
      end

      if pull.in_merge_queue?
        return FailResult.new("Pull Request is in the merge queue.", :not_mergeable)
      end

      if pull.base_repository
        if method == :merge && !pull.merge_commit_allowed?(actor:)
          return FailResult.new("Merge commits are not allowed on this repository.", :merge_commit_blocked)
        end

        if method == :squash && !pull.squash_merge_allowed?(actor:)
          return FailResult.new("Squash merges are not allowed on this repository.", :squash_merge_blocked)
        end

        if method == :rebase && !pull.rebase_merge_allowed?(actor:)
          return FailResult.new("Rebase merges are not allowed on this repository.", :rebase_merge_blocked)
        end
      end

      # grab the merge commit from PR repo
      merge_commit = repository.commits.find(pull.merge_commit_sha)
      merge_base_sha, merge_head_sha = merge_commit.parent_oids

      # make sure that the parents of the merge commit are up to date
      if merge_base_sha != merge_base_ref.target_oid || merge_head_sha != pull.mergeable_head_sha
        GitHub.dogstats.increment("merge.prepare_and_validate.merge_commit_out_of_date")
        pull.update_mergeable_attribute(nil)
        raise Git::Ref::ComparisonMismatch
      end

      if GitHub.flipper[:validate_repo_sha_when_merging].enabled?(pull.repository)
        head_reference = pull.head_repository&.heads&.find(pull.head_ref.b)
        unless head_reference && head_reference.target_oid == pull.head_sha
          GitHub.dogstats.increment("merge.prepare_and_validate.head_sha_out_of_date")

          if GitHub.flipper[:fail_on_head_repo_mismatch].enabled?(pull.repository)
            pull.update_mergeable_attribute(nil)
            return FailResult.new("Head branch is out of date. Review and try the merge again.", :head_mismatch)
          end
        end
      end

      @merge_commit = merge_commit

      ValidateSuccessResult.new(merge_commit, merge_base_ref)
    end

    def post_merge(
      merge_commit,
      merge_base_ref,
      new_sha,
      merged_at,
      merge_action,
      merge_state_status: nil,
      enqueue_push_job: true,
      merge_commit_title: nil,
      merge_commit_message: nil,
      default_merge_commit_message_and_title: true)

      perform_post_merge_updates(merge_commit, merge_base_ref, new_sha, merged_at, merge_action, enqueue_push_job: enqueue_push_job)
      trigger_post_merge_events(merge_action, merge_state_status, merge_commit_title, merge_commit_message, default_merge_commit_message_and_title, new_sha)
      record_post_merge_metrics
    end

    def perform_post_merge_updates(merge_commit, merge_base_ref, new_sha, merged_at, merge_action, enqueue_push_job: true)
      merge_base_sha, _ = merge_commit.parent_oids

      # Ensure that we don't leave merges in a half finished state (e.g. closing referenced
      # issues when the pull fails to be marked as merged). Also makes sure side effects tied to
      # after_commit hooks are not fired until all relevant records are committed to database.
      PullRequest.transaction do
        pull.reload
        pull.mark_as_merged(actor, new_sha, merge_base_sha, merge_action)
        pull.save!
      end

      PullRequestCloseReferencedIssuesJob.perform_later(pull_request: pull, actor: actor)

      merge_base_ref.enqueue_push_job(merge_base_sha, new_sha, actor, merged_at, merge_method: method) if enqueue_push_job
    end

    def destroy_revisions_and_conflicts
      # once the pull request is merged, clean up the review markers to save space
      pull.last_seen_pull_request_revisions.destroy_all
      # also cleanup the conflict metadata if there is any
      pull.destroy_conflict_metadata
    end

    def mark_issue_referenced_from_commit(new_sha)
      pull.issue.reference_from_commit(actor, new_sha, repository)
    end

    def trigger_post_merge_events(merge_action, merge_state_status, merge_commit_title, merge_commit_message, default_merge_commit_message_and_title, new_sha)
      GlobalInstrumenter.instrument("pull_request.merge", {
        pull_request: pull,
        actor: actor,
        author: pull.user,
        protected_branch: pull.base_branch_rule_evaluator&.original_protected_branch,
        merge_method: method,
        merge_action: merge_action,
        merge_state_status: merge_state_status,
        merge_commit_title: merge_commit_title,
        merge_commit_message: merge_commit_message,
        default_merge_commit_message_and_title: default_merge_commit_message_and_title,
        merge_commit_sha: new_sha
      })
      pull.instrument(:merge, actor: actor)
    end

    def record_post_merge_metrics
      GitHub.dogstats.increment("pull_request", tags: ["action:merged", "result:#{method}"])

      combined_status = pull.combined_status
      if !combined_status.any?
        GitHub.dogstats.increment("status", tags: ["action:merged", "result:none"])
      else
        GitHub.dogstats.increment("pull_request", tags: ["action:merged", "result:#{combined_status.state}"])
        if combined_status.count == 1
          GitHub.dogstats.increment("status", tags: ["action:merged", "result:single"])
        else
          GitHub.dogstats.histogram("status", combined_status.count, tags: ["action:merged", "result:more", "type:combined_count"])
        end
      end
    end

    private

    attr_reader :method, :actor, :author_email, :merge_commit, :message_title, :message

    NO_MERGE_COMMIT_MSG = "No merge commit. Either provide one in initialize or call validate_and_prepare before perform.".freeze

    def repository
      pull.repository
    end

    # Does the base branch have a required signatures that cannot be
    # overridden by the actor?
    #
    # Returns boolean.
    def signature_required?(actor:)
      pull.base_branch_rule_evaluator&.required_signatures_enabled? &&
        !pull.base_branch_rule_evaluator.can_override_required_signatures?(actor: actor)
    end

    def perform_rebase(actor, merge_commit)
      GitHub.dogstats.time("pullrequest.merge.perform_rebase") do
        ref = repository.refs.read(pull.rebase_ref)
        unless ref.exist?
          return FailResult.new("This branch can't be rebased", :rebase)
        end

        unless ref.target.tree_oid == merge_commit.tree_oid
          return FailResult.new("Base branch was modified. Review and try the merge again.", :rebase)
        end

        if signature_required?(actor: actor)
          return FailResult.new("Base branch requires signed commits. Rebase merges cannot be automatically signed by #{GitHub.flavor}", :protected_branch)
        end

        new_sha = Repositories.domain.commits.update_committer_info(
          repository: repository,
          start_commit_oid: ref.target.oid,
          end_commit_oid: merge_commit.parent_oids[0],
          email: actor.git_author_email,
          name: actor.git_author_name,
          time: actor.time_zone.now.iso8601
        )

        begin
          repository.batch_write_refs(actor, [[pull.rebase_ref, nil, new_sha]])
        rescue Git::Ref::ComparisonMismatch
          return FailResult.new("Base branch was modified. Review and try the merge again.", :rebase)
        end

        PerformSuccessResult.new(new_sha)
      end
    end

    def perform_merge(actor, author_email, merge_commit, message_title, message)
      GitHub.dogstats.time("pullrequest.merge.perform_merge") do
        if pull.draft?
          return FailResult.new("Pull Request is still a draft", :draft)
        end

        # generate a commit message
        title = message_title.presence || pull.default_merge_commit_title
        body = message || pull.default_merge_commit_message
        commit_message = "#{title}\n\n#{body}"

        author = {
          "email" => author_email || actor.git_author_email,
          "name"  => actor.git_author_name,
          "time"  => actor.time_zone.now.iso8601,
        }

        committer = {
          "email" => GitHub.web_committer_email,
          "name"  => GitHub.web_committer_name,
          "time"  => author["time"],
        }

        info = {
          "committer" => committer,
          "author" => author,
          "message" => commit_message,
        }

        args = [merge_commit.oid, info, false]

        begin
          new_sha = Repositories.domain.commits.rewrite_merge_commit(
            repository: repository,
            commit_oid: merge_commit.oid,
            info: info,
            squash: false,
            require_signature: signature_required?(actor: actor)
          )
          return PerformSuccessResult.new(new_sha)
        rescue Repositories::Error::SignatureError
          return FailResult.new("The base branch requires that commits be signed and we failed to sign your merge commit. Please try again.", :protected_branch)
        end
      end
    end

    def perform_squash(actor, author_email, merge_commit, message_title, message)
      GitHub.dogstats.time("pullrequest.merge.perform_squash") do
        author = pull.user || actor

        squash_commit_author_email =
          # Only the pull request author is allowed to override the email for the squash commit.
          if actor == pull.user && author_email
            author_email
          else
            pull.squash_commit_author_email(actor)
          end

        begin
          squash_merge = PullRequest::SquashMerge.new(
            repository: repository,
            commit_oid: merge_commit.oid,
            require_signature: signature_required?(actor: actor)
          )
          new_sha = squash_merge.perform(
            author_email: squash_commit_author_email,
            author_name: author.git_author_name,
            time_zone: author.time_zone,
            title: message_title.presence || pull.default_squash_commit_title,
            message: message || pull.default_squash_commit_message(author: author),
          )

          return PerformSuccessResult.new(new_sha)
        rescue Repositories::Error::SignatureError
          return FailResult.new("The base branch requires that commits be signed and we failed to sign your squash commit. Please try again.", :protected_branch)
        rescue StandardError => error # rubocop:todo Lint/GenericRescue
          Failbot.report(error, "gh.repo.id": repository.id, "gh.pull_request.id": pull.id)
          raise error
        end
      end
    end
  end
end
