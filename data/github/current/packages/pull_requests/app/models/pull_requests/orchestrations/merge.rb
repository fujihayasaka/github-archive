# typed: true
# frozen_string_literal: true

module PullRequests::Orchestrations
  class Merge < PullRequestOrchestration
    include DataAttributes
    extend GitHub::Memoizer

    DANGLING_TIME_WINDOW = 90.seconds.freeze

    # TODO: This can be a `Bot`, the override below outlines what is happening. The DSL does not support T.any.
    data :actor, User

    # Alias method chain to keep the existing behavior under a different name.
    alias actor_was actor

    # The `actor` can be both a Bot or a User.
    sig { returns(T.any(User, Bot)) }
    memoize def actor
      actor = T.let(actor_was, T.any(User, Bot))

      # In order to appropriately use a `Bot` within authorization, the installation must be loaded. This has to be
      # explicitly done in the background but will have been done already in the API call.
      if head_repository = pull_request&.head_repository
        if actor.is_a?(Bot) && !actor.installation
          actor.async_load_installation_for(head_repository).sync
        end
      end

      actor
    end

    data :method, Symbol

    # Optional commit metadata requested by caller.
    data :commit_title, String, required: false, persisted: false
    data :commit_body, String, required: false, persisted: false
    data :commit_author_email, String, required: false
    data :expected_head_sha, String, required: false

    # Metadata for logging.
    data :source, Symbol, required: false
    data :reflog_data, Hash, required: false
    data :merge_state_status, Symbol, required: false

    # Transitive orchestration state.
    data :merge_commit_sha, String, required: false
    data :merging_commit_sha, String, required: false
    data :git_error_code, Symbol, required: false

    before_validation :abandon_dangling_orchestrations, on: :create

    # Ensure we don't call `save` for each step as that adds overhead.
    def only_save_on_orchestration_end? = true

    # Override end_orchestration as the on_orchestration_end block is invoked after save is called.
    def end_orchestration(...)
      self.reflog_data = nil
      self.commit_title = nil
      self.commit_body = nil
      self.commit_author_email = nil

      super
    end

    step :set_merge_state_status do
      return unless pull_request = self.pull_request

      self.merge_state_status = pull_request.merge_state(viewer: actor).status
    end

    step :create_merge_commit do
      catching_git_exceptions do
        result = with_trace("prepare_and_validate") do
          merger.prepare_and_validate(expected_head_sha, actor:)
        end

        case result
        when PullRequest::Merge::ValidateSuccessResult
          self.merge_base_ref = result.merge_base_ref
          self.merge_commit = result.merge_commit
          self.merge_commit_sha = result.merge_commit.oid
        when PullRequest::Merge::FailResult
          return mark_as_skipped(result.fail_message, result.fail_code)
        end
      end
    end

    step :create_head_commit do
      catching_git_exceptions do
        result = with_trace("perform") do
          merger.perform
        end

        case result
        when PullRequest::Merge::PerformSuccessResult
          if sha = result.new_sha
            self.merging_commit_sha = sha
          else
            return mark_as_skipped("Could not re-write the merge commit for some reason", :rewrite)
          end
        when PullRequest::Merge::FailResult
          return mark_as_skipped(result.fail_message, result.fail_code)
        end
      end
    end

    step :execute_ref_update do
      return unless pull_request = self.pull_request

      catching_git_exceptions do
        reflog_data = pull_request.send(:pr_reflog_data, "merge").merge(self.reflog_data || {})

        merge_base_ref.update(
          merging_commit_sha,
          actor,
          pull_request:,
          reflog_data:,
          rule_commit: self.merge_commit,
          post_receive: false,
          backup: false,
          server_merge: true,
          merge_method: method
        )
      end
    end

    # TODO: This should retry in the background if it fails.
    step :perform_post_merge_updates do
      return unless pull_request = self.pull_request

      with_trace("post_merge") do
        # merge_commit shouldn't be `nil` here, the only reason why this
        # could happen is because either repository or PR are `nil` but that
        # should make the `merge_commit` method fail.
        #
        # If this is `nil` we have a big problem here.
        merger.perform_post_merge_updates(
          merge_commit,
          merge_base_ref,
          merging_commit_sha,
          merge_base_ref.written_at,
          source,
        )
      end
    end

    step :ensure_head_ref_removed do
      return unless pull_request = self.pull_request
      return unless head_repository = pull_request.head_repository
      return if head_repository.feature_enabled?(:async_cleanup_head_ref_on_merge)

      if head_repository.delete_branch_on_merge?
        cleanup_head_ref!(pull_request)
      end
    end

    step :trigger_post_merge_events do
      return unless pull_request = self.pull_request

      message_title, message, uses_defaults = pull_request.determine_merging_message(method, commit_title, commit_body)

      merger.trigger_post_merge_events(
        source,
        merge_state_status,
        message_title,
        message,
        uses_defaults,
        merging_commit_sha
      )
    end

    job_start

    step :destroy_revisions_and_conflicts do
      return unless pull_request = self.pull_request

      with_trace("destroy_revisions_and_conflicts") do
        merger.destroy_revisions_and_conflicts
      end
    end

    step :remove_head_ref_if_configured do
      return unless pull_request = self.pull_request
      return unless head_repository = pull_request.head_repository
      return unless head_repository.feature_enabled?(:async_cleanup_head_ref_on_merge)

      if head_repository.delete_branch_on_merge?
        cleanup_head_ref!(pull_request)
      end
    end

    step :record_post_merge_metrics do
      merger.record_post_merge_metrics
    end

    step :update_default_author_email_cache do
      return unless email = commit_author_email

      actor.update_default_author_email_cache(repository, email)
    end

    private

    sig { params(merge_commit: Commit).returns(Commit) }
    attr_writer :merge_commit

    # Even when validate_and_prepare will never return a `nil` merge_commit it
    # could be nil when steps run on different threads. For example when a step
    # runs on request time, but the next runs on a background job.
    #
    # That's why we memoize this and make sure that we refetch it using the
    # `merge_commit_sha` in case it is `nil`. Note that the `merge_commit_sha`
    # is stored as part of the `data` on the orchestration unlike the
    # `merge_commit` itself.
    sig { returns(T.nilable(Commit)) }
    def merge_commit
      return @merge_commit if defined?(@merge_commit)
      @merge_commit = begin
        return nil unless merge_commit_sha = self.merge_commit_sha
        return nil if merge_commit_sha.blank?

        # Using repository here rather than base_repository because of the
        # advisory database. On advisory database repository and
        # base_repository can be different unlike on a regular fork.
        pull_request&.repository&.commits.find(merge_commit_sha)
      end
    end

    sig { params(merge_base_ref: Git::Ref).returns(Git::Ref) }
    attr_writer :merge_base_ref

    sig { returns(Git::Ref) }
    def merge_base_ref
      return @merge_base_ref if defined?(@merge_base_ref)
      @merge_base_ref = pull_request&.repository&.heads&.find(pull_request&.base_ref.b)
    end

    sig { returns(PullRequest::Merge) }
    def merger
      @merger ||= PullRequest::Merge.new(
        T.must(pull_request),
        method,
        actor,
        author_email: commit_author_email,
        message_title: commit_title,
        message: commit_body
      )
    end

    sig do
      type_parameters(:T)
        .params(
          action: String,
          block: T.proc.returns(T.type_parameter(:T))
        ).returns(T.type_parameter(:T))
    end
    def with_trace(action, &block)
      GitHub.tracer.in_span("pull_request.merge.#{action}", kind: :internal, attributes: {
        "actor_id" => actor.id,
        "pull_request_id" => self.pull_request_id,
        "method" => method.to_s,
      }) { yield }
    end

    def catching_git_exceptions(&block)
      yield
    rescue Git::Ref::ProtectedBranchUpdateError => e
      mark_as_skipped(e.result.message, :protected_branch)
    rescue Git::Ref::WorkflowUpdatePolicyError => e
      mark_as_skipped(e.message, :workflow_policy_update_error)
    rescue Git::Ref::RepositoryRuleViolationError => e
      mark_as_skipped(e.detailed_message, :repository_rule_violation)
    rescue Git::Ref::ComparisonMismatch
      mark_as_skipped("Base branch was modified. Review and try the merge again.", :parent_mismatch)
    end

    sig { params(message: String, code: Symbol).returns([Symbol, String]) }
    def mark_as_skipped(message, code)
      self.git_error_code = code
      [:skipped, message]
    end

    sig { returns(String) }
    def duplicate_orchestration_error_message
      "Merge already in progress"
    end

    sig { params(pull: PullRequest).void }
    def cleanup_head_ref!(pull)
      pull.cleanup_head_ref(actor)
    rescue Git::Ref::ProtectedBranchUpdateError => error
      log_error("could not remove head ref due to branch rules")
    end

    def abandon_dangling_orchestrations
      if pull_request&.repository&.feature_enabled?(:mark_dangling_orchestrations_as_abandoned)
        dangling_orchestrations = self.class.where(
          repository_id: repository_id,
          pull_request_id: pull_request_id,
          state: [:created, :started],
          updated_at: ..DANGLING_TIME_WINDOW.ago,
          # include all steps before job_start
          step_name: self.class.all_steps.take_while { |step| step.name != :job_start }.map(&:name),
        ).limit(100)

        if dangling_orchestrations.any?
          GitHub.logger.info(
            "marking dangling merge orchestrations as abandoned",
            "code.namespace": "PullRequests::Orchestrations::Merge",
            "gh.repository.id": repository_id,
            "gh.pull_request.id": pull_request_id,
          )
        end

        dangling_orchestrations.each do |orchestration|
          orchestration.end_orchestration(:abandoned, "orchestration failed to execute within dangling time window")
        end
      end
    end
  end
end
