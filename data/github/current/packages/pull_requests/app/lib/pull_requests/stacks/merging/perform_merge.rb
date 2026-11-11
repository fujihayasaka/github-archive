# typed: strict
# frozen_string_literal: true

module PullRequests
  module Stacks
    module Merging
      # Called from AutoMergeJob when no merge queue is configured. Merges all
      # unmerged PRs in the stack up to the triggered PR via a single base-branch
      # ref update, then runs post-merge behavior inline.
      #
      # Supports merge, squash, and rebase commit strategies. The merge method
      # is read from the auto_merge_request record (defaulting to :merge).
      #
      # Non-merge-queue counterpart to AddToMergeQueue.
      class PerformMerge
        include GitHub::Memoizer

        REBASE_TIMEOUT_SECONDS = 180

        sig do
          params(
            pull_request: PullRequest,
            actor: T.any(User, Integration),
            logger: Shared::Logger,
          ).void
        end
        def initialize(pull_request:, actor:, logger: Shared::Logger.new)
          @pull_request = pull_request
          @actor = actor
          @logger = logger
          @commit_oids = T.let({}, T::Hash[PullRequest, T.any(String, Commit)])
        end

        sig { returns(T.any(Result::Success, Result::Waiting, Result::Error, Result::Conflict, Result::NoLongerStacked)) }
        def call
          PullRequests::Observability::Git.tag(repository: @pull_request.base_repository, feature: :merge_stack) do
            with_telemetry do
              return Result::NoLongerStacked.new unless @pull_request.stacked?
              return Result::NoLongerStacked.new unless @pull_request.stack
              return Result::Error.new(message: "Error resolving repository") unless @pull_request.base_repository
              return Result::Error.new(message: "Base branch not found") unless base_branch_ref = self.base_branch_ref
              return Result::Success.new if pull_requests.empty?

              # Validate all PRs before merging any. Abort entirely if one fails to avoid partially merging a stack.
              validation_error, rule_suites = validate_pull_requests

              # update rule evaluations with stack metadata
              insights_enabled = FeatureFlag.vexi.enabled?(:pull_request_stacks_insights, repository, default: false)
              if insights_enabled
                stack_allowed = rule_suites.all?(&:action_permitted?)
                rule_suites.each do |suite|
                  if suite.action_permitted? && !stack_allowed
                    suite.result = :stack_merge_failed # If any PR in the stack is not permitted to merge, none are allowed
                  end
                  suite.evaluation_metadata[:pr_stack] = { pr_ids: pull_requests.map(&:id), stack_id: stack&.id }
                  if (stack_update = suite.ref_update).is_a?(PullRequests::Stacks::RefUpdate)
                    suite.evaluation_metadata[:pr_stack][:position] = stack_update.pull_request.stack_position
                  end
                end

                if validation_error
                  rule_suites.filter(&:should_persist?).each do |suite|
                    suite.log_evaluation
                    suite.save
                  end

                  return validation_error
                end
              else
                return validation_error if validation_error
              end

              # Always create a merge commit. This commit is used as the
              # `rule_commit` for base branch protection rule evaluation (a
              # security requirement), and is reused as the target commit for
              # the :merge strategy. If creating the merge commit detects a
              # conflict (or otherwise fails), abort early before running any
              # strategy-specific commit creation.
              rule_merge_commit = create_merge_commit # rubocop:disable GitHub/EnsureCommitAttribution
              case rule_merge_commit
              when Result::Error, Result::Conflict, Result::Waiting
                return rule_merge_commit
              when GitSystems::Commit::Created
                # Proceed; rule_merge_commit is narrowed below.
              else T.absurd(rule_merge_commit)
              end

              # Create merge commit depending on the requested type.
              commit_result = case merge_method
              when :squash
                create_squash_commits
              when :rebase
                if FeatureFlag.vexi.enabled?(:pull_request_stacks_rebase_without_merge_commit, repository, default: false)
                  create_rebase_commits
                else
                  create_rebase_commits_from_merge_commits
                end
              else
                # Reuse the commit we already had to create.
                rule_merge_commit
              end

              case commit_result
              when Result::Error, Result::Conflict, Result::Waiting
                return commit_result
              when GitSystems::Commit::Created
                target_head_oid = commit_result.sha

                begin
                  merge_commit = repository.commits.find(target_head_oid)
                  @logger.append({ target_head_oid: }, prefix: "gh.stacks")
                rescue GitRPC::ObjectMissing => find_merge_commit_exception
                end

                unless merge_commit
                  @logger.append({ target_head_oid:, merge_commit_not_found: true }, prefix: "gh.stacks")
                  return Result::Error.new(message: "Merge commit not found after creation", exception: find_merge_commit_exception)
                end
              else T.absurd(commit_result)
              end

              # Update base branch ref
              GitHub.tracer.in_span("pull_requests.stacks.perform_merge.update_base_branch_ref", kind: :internal, attributes: {
                "target_head_oid" => target_head_oid,
                "base_oid" => base_sha,
              }) do
                begin
                  base_branch_ref.update(
                    target_head_oid, @actor, reflog_data:,
                    force: false,
                    post_receive: false,
                    no_rule_suite_persist: true, # we save suites per PR
                    pull_request: @pull_request,
                    merge_method:,
                    rule_commit: rule_merge_commit.sha,
                  )
                rescue => e
                  # mark RuleSuites as failed
                  rule_suites.each do |suite|
                    suite.evaluation_metadata[:pr_stack][:final_merge_failed] = true
                    suite.result = :stack_merge_failed
                  end if insights_enabled

                  exception = GitSystems.classify_exception(e, repository:) || e
                  case exception
                  when Git::Ref::NotFastForward, Git::Ref::ComparisonMismatch
                    @logger.append_exception(exception, prefix: "gh.stacks.update_base_branch_ref")
                    return Result::Error.new(message: "Base branch was modified. Review and try the merge again.", exception:)
                  when Git::Ref::RepositoryRuleViolationError
                    @logger.append_exception(exception, prefix: "gh.stacks.update_base_branch_ref")
                    rule_suites.each do |suite|
                      suite.evaluation_metadata[:pr_stack][:final_merge_rules] = exception.rule_suite.failed_rule_types
                      suite.evaluation_metadata[:pr_stack][:final_merge_message] = exception.rule_suite.message
                    end if insights_enabled
                    return Result::Error.new(message: exception.detailed_message, exception:)
                  when Git::Ref::ProtectedBranchUpdateError
                    @logger.append_exception(exception, prefix: "gh.stacks.update_base_branch_ref")
                    rule_suites.each do |suite|
                      suite.evaluation_metadata[:pr_stack][:final_merge_rules] = exception.result.failed_rule_types
                      suite.evaluation_metadata[:pr_stack][:final_merge_message] = exception.result.message
                    end if insights_enabled
                    return Result::Waiting.new(message: exception.message)
                  when Git::Ref::UpdateError
                    @logger.append_exception(exception, prefix: "gh.stacks.update_base_branch_ref")
                    return Result::Error.new(message: "Failed to update base branch ref", exception:)
                  when GitRPC::Error
                    @logger.append_exception(exception, prefix: "gh.stacks.update_base_branch_ref")
                    return Result::Error.new(message: "Git error during ref update", exception:)
                  when GitSystems::Errors::Outage, GitSystems::Errors::Fatal, GitSystems::Errors::Timeout
                    @logger.append_exception(exception.exception, prefix: "gh.stacks.update_base_branch_ref")
                    return Result::Error.new(message: "Git error during ref update", exception: exception.exception)
                  else
                    @logger.append_exception(exception, prefix: "gh.stacks.update_base_branch_ref")
                    return Result::Error.new(message: "Unexpected error during ref update", exception:)
                  end
                ensure
                  rule_suites.filter(&:should_persist?).each do |suite|
                    suite.log_evaluation
                    suite.save
                  end if insights_enabled
                end
              end

              # Run post-merge side-effects for each PR. The push job is dispatched
              # once after all PRs have been processed (see below).
              merged_at = base_branch_ref.written_at.in_time_zone
              @logger.append({ merged_at: }, prefix: "gh.stacks")

              GitHub.tracer.in_span("pull_requests.stacks.perform_merge.post_merge", kind: :internal, attributes: {
                "pull_request_count" => pull_requests.size,
                "merge_method" => merge_method.to_s,
              }) do
                pull_requests.each do |pull_request|
                  GitHub.tracer.in_span("pull_requests.stacks.perform_merge.post_merge.pull_request", kind: :internal) do
                    commit = @commit_oids.fetch(pull_request, merge_commit)
                    commit = repository.commits.find(commit) if commit.is_a?(String)

                    # TODO: Implement per-PR rule suite finalization (see ref-update TODO above).
                    pull_request.post_merge(
                      @actor, commit, base_branch_ref, commit.oid, merged_at, merge_method, :auto_merge,
                      enqueue_push_job: false,
                    )
                  end
                end

                # Retarget the new bottom of the remaining stack to the stack's
                # base branch. This must run after post_merge marks all PRs as
                # merged (so current_base_entry returns the correct entry) and
                # before cleanup_head_ref deletes intermediate branches.
                retargeted_pull = retarget_remaining_stack_base

                pull_requests.each do |pull_request|
                  if repository.delete_branch_on_merge?
                    logger = @logger.for(pull_request.id)
                    logger.append({ cleanup_head_ref: true }, prefix: "gh.stacks.post_merge")
                    pull_request.cleanup_head_ref(@actor)
                  end
                end

                enqueue_update_all_branches(retargeted_pull) if retargeted_pull
              end

              # Single push job for the entire batch.
              GitHub.tracer.in_span("pull_requests.stacks.perform_merge.enqueue_push_job", kind: :internal) do
                base_branch_ref.enqueue_push_job(
                  base_sha, target_head_oid, @actor, merged_at, merge_method:,
                  merge_action: :auto_merge
                )

                @logger.append({ enqueued_push_job: true }, prefix: "gh.stacks.enqueue_push_job")
              end

              if (s = stack) && FeatureFlag.vexi.enabled?(:pull_request_stack_merge_hydro_events, repository, default: false)
                GlobalInstrumenter.instrument("pull_request_stack.merge", {
                  merge_action: :AUTO_MERGE,
                  merge_method: merge_method.to_s.upcase.to_sym,
                  stack_id: s.id,
                  stack_number: s.number,
                  stack_base_branch: s.base_ref,
                  repository: repository,
                  pull_requests_merged: pull_requests,
                  stack_size: s.entry_count,
                  actor: @actor,
                })
              end

              Result::Success.new
            end
          end
        end

        private

        sig { returns(T.any(GitSystems::Commit::Created, Result::Error, Result::Conflict, Result::Waiting)) }
        def create_merge_commit
          GitHub.tracer.in_span("pull_requests.stacks.perform_merge.create_merge_commit", kind: :internal) do
            # Only the topmost PR needs a merge commit; its head SHA covers all PRs below.
            command = MergeCommit::Command.new(pull_requests: [@pull_request], repository:)

            pull_request_author = @pull_request.safe_user

            commit_message = commit_message_for(@pull_request,
              default_title: @pull_request.default_merge_commit_title,
              default_message: @pull_request.default_merge_commit_message
            ).join("\n\n")

            # We're explicitly _not_ setting merge_base here as it's not necessary for normal merge commits.
            create_result = command.create_merge_commit!( # rubocop:disable GitHub/EnsureCommitAttribution
              pull_request_id: @pull_request.id,
              commit_message:,
              head_sha: @pull_request.head_sha,
              base_sha:,
              author_email: pull_request_author.git_author_email,
            )

            case create_result
            when GitSystems::Commit::Created
              @logger.append({ merge_commit_oid: create_result.sha }, prefix: "gh.stacks.create_merge_commit")
              create_result
            when GitSystems::Commit::Conflict
              @logger.append({ conflict: true, pull_request_id: @pull_request.id }, prefix: "gh.stacks.create_merge_commit")
              Result::Conflict.new(message: "Merge conflict detected")
            when GitSystems::Commit::Failed
              Result::Error.new(message: "Could not create merge commit")
            when MergeCommit::ICommand::Result::Error
              Result::Error.new(message: create_result.message)
            when MergeCommit::ICommand::Result::Timeout
              Result::Waiting.new(message: "Merge commit creation timed out")
            else
              Result::Error.new(message: "Could not create merge commit")
            end
          end
        end

        sig { returns(T.any(GitSystems::Commit::Created, Result::Error, Result::Conflict, Result::Waiting)) }
        def create_squash_commits
          GitHub.tracer.in_span("pull_requests.stacks.perform_merge.create_squash_commits", kind: :internal) do
            previous_head_before_squashing = T.let(nil, T.nilable(String))
            previous_head_after_squashing = T.let(base_sha, String)
            last_result = T.let(nil, T.nilable(GitSystems::Commit::Created))

            pull_requests.each do |pull_request|
              GitHub.tracer.in_span("pull_requests.stacks.perform_merge.create_squash_commits.pull_request", kind: :internal) do
                logger = @logger.for(pull_request.id)
                command = MergeCommit::Command.new(pull_requests: [pull_request], repository:)
                user = pull_request.safe_user

                logger.append({ head_oid: pull_request.head_sha, previous_head_before_squashing:, previous_head_after_squashing: }, prefix: "gh.stacks")

                # Step 1: Create a merge commit for this PR against the current base.
                # We must supply merge_base here because the squash step below cannot
                # accept one. Without it, squash falls back to find-best-merge-base,
                # which may resolve to a different commit—causing commits to be replayed
                # against the wrong base and triggering unexpected conflicts.
                commit_message = commit_message_for(pull_request,
                  default_title: pull_request.default_merge_commit_title,
                  default_message: pull_request.default_merge_commit_message
                ).join("\n\n")

                merge_commit = command.create_merge_commit!( # rubocop:disable GitHub/EnsureCommitAttribution
                  pull_request_id: pull_request.id,
                  commit_message:,
                  head_sha: pull_request.head_sha,
                  base_sha: previous_head_after_squashing,
                  merge_base: previous_head_before_squashing,
                  author_email: user.git_author_email,
                )

                case merge_commit
                when GitSystems::Commit::Created
                  logger.append({ merge_commit_oid: merge_commit.sha }, prefix: "gh.stacks.create_squash_commits")
                when GitSystems::Commit::Conflict
                  @logger.append({ conflict: true, pull_request_id: pull_request.id }, prefix: "gh.stacks.create_squash_commits")
                  return Result::Conflict.new(message: "Merge conflict detected")
                when GitSystems::Commit::Failed
                  return Result::Error.new(message: "Could not create merge commit")
                when MergeCommit::ICommand::Result::Error
                  return Result::Error.new(message: merge_commit.message)
                when MergeCommit::ICommand::Result::Timeout
                  return Result::Waiting.new(message: "Merge commit creation timed out")
                when GitSystems::Errors::Outage, GitSystems::Errors::Fatal, GitSystems::Errors::Timeout
                  return Result::Error.new(message: "Could not create merge commit")
                else T.absurd(merge_commit)
                end

                # Step 2: Rewrite the merge commit as a squash commit.
                require_signature = if (stack = @pull_request.stack)
                  branch_rule_evaluator&.required_signatures_enabled? && branch_rule_evaluator&.can_override_required_signatures?(actor: @actor)
                else
                  false
                end

                title, message = commit_message_for(pull_request,
                  default_title: pull_request.default_squash_commit_title,
                  default_message: pull_request.default_squash_commit_message(author: user)
                )

                squash_commit_oid = begin
                  PullRequest::SquashMerge.new(repository:, commit_oid: merge_commit.sha, require_signature:).perform(
                    author_email: user.git_author_email,
                    author_name: user.git_author_name,
                    title:,
                    message:,
                    time_zone: user.time_zone,
                  )
                rescue Repositories::Error::SignatureError => exception
                  return Result::Error.new(message: "Failed to sign squash commit", exception:)
                end

                logger.append({ squash_commit_oid: squash_commit_oid }, prefix: "gh.stacks.create_squash_commits")
                @commit_oids[pull_request] = squash_commit_oid

                last_result = GitSystems::Commit::Created.new(
                  head_sha: pull_request.head_sha,
                  base_sha: previous_head_after_squashing,
                  sha: squash_commit_oid
                )

                previous_head_before_squashing = pull_request.head_sha
                previous_head_after_squashing = squash_commit_oid
              end
            end

            last_result || Result::Error.new(message: "No PRs to squash")
          end
        end

        # Rebases each PR in the stack onto the previously-rebased commit
        # without creating an intermediate merge commit.
        #
        # For each PR N, this replays commits in the narrow range
        # `pr_{N-1}.head_sha..pr_N.head_sha` onto `rebased_pr_{N-1}` using
        # spokes' `--onto` support. This keeps the replay range limited to
        # commits introduced by PR N itself.
        #
        # The older `create_rebase_commits_from_merge_commits` first builds a
        # merge commit and then runs
        # `git replay pr_{N-1}.head_sha..merge_commit --onto rebased_pr_{N-1}`.
        # That widens the range to include already-rebased first-parent
        # ancestors, which produces spurious conflicts when multiple PRs in
        # the stack modify the same paths (see
        # PerformMergeSharedFileModificationTest for the reproduction).
        sig { returns(T.any(GitSystems::Commit::Created, Result::Error, Result::Conflict, Result::Waiting)) }
        def create_rebase_commits
          last_result = T.let(nil, T.nilable(GitSystems::Commit::Created))

          previous_head_before_rebasing = T.let(nil, T.nilable(String))
          previous_head_after_rebasing = T.let(base_sha, String)

          pull_requests.each do |pull_request|
            GitHub.tracer.in_span("pull_requests.stacks.perform_merge.create_rebase_commits", kind: :internal) do
              previous_head_before_rebasing ||= pull_request.base_sha
              user = pull_request.safe_user
              logger = @logger.for(pull_request.id)
              logger.append({ head_oid: pull_request.head_sha, previous_head_before_rebasing:, previous_head_after_rebasing: }, prefix: "gh.stacks")

              rebase_commit = GitSystems::CreateRebaseCommit.new(
                repository:,
                base_sha: previous_head_before_rebasing,
                head_sha: pull_request.head_sha,
                name: user.git_author_name,
                email: user.git_author_email,
                timestamp: user.time_zone.now,
                timeout: REBASE_TIMEOUT_SECONDS.seconds,
              ).call_spokes(onto_oid: previous_head_after_rebasing)

              case rebase_commit
              when GitSystems::Commit::Created
                last_result = rebase_commit
                previous_head_after_rebasing = rebase_commit.oid
                previous_head_before_rebasing = pull_request.head_sha
                @commit_oids[pull_request] = previous_head_after_rebasing
                logger.append({ rebase_commit_oid: previous_head_after_rebasing }, prefix: "gh.stacks.create_rebase_commits")
              when GitSystems::Commit::Conflict
                @logger.append({ conflict: true, pull_request_id: pull_request.id }, prefix: "gh.stacks.create_rebase_commits")
                return Result::Conflict.new(message: "Rebase conflict detected")
              when GitSystems::Errors::Timeout
                return Result::Waiting.new(message: "Rebase timed out")
              when GitSystems::Errors::Outage
                return Result::Error.new(message: "Git service unavailable during rebase")
              when GitSystems::Commit::Error, GitSystems::Errors::Fatal
                return Result::Error.new(message: "Failed to create rebase commit")
              else T.absurd(rebase_commit)
              end
            end
          end

          last_result || Result::Error.new(message: "No PRs to rebase")
        end

        sig { returns(T.any(GitSystems::Commit::Created, Result::Error, Result::Conflict, Result::Waiting)) }
        def create_rebase_commits_from_merge_commits
          last_result = T.let(nil, T.nilable(GitSystems::Commit::Created))

          previous_head_before_rebasing = T.let(nil, T.nilable(String))
          previous_head_after_rebasing = T.let(base_sha, String)

          pull_requests.each do |pull_request|
            GitHub.tracer.in_span("pull_requests.stacks.perform_merge.create_rebase_commits", kind: :internal) do
              command = MergeCommit::Command.new(pull_requests: [pull_request], repository:)
              user = pull_request.safe_user
              previous_head_before_rebasing ||= pull_request.base_sha
              logger = @logger.for(pull_request.id)
              logger.append({ head_oid: pull_request.head_sha, previous_head_before_rebasing:, previous_head_after_rebasing: }, prefix: "gh.stacks")

              commit_message = commit_message_for(pull_request,
                default_title: pull_request.default_merge_commit_title,
                default_message: pull_request.default_merge_commit_message
              ).join("\n\n")

              # Step 1: Create a merge commit (required as input for rebase).
              merge_commit = command.create_merge_commit!( # rubocop:disable GitHub/EnsureCommitAttribution
                pull_request_id: pull_request.id,
                head_sha: pull_request.head_sha,
                base_sha: previous_head_after_rebasing,
                merge_base: previous_head_before_rebasing,
                commit_message:,
                author_email: user.git_author_email,
              )

              case merge_commit
              when GitSystems::Commit::Created
                # Successful, continue after logging the generated commit OID.
                logger.append({ merge_commit_oid: merge_commit.sha }, prefix: "gh.stacks.create_rebase_commits")
              when GitSystems::Commit::Conflict
                @logger.append({ conflict: true, pull_request_id: pull_request.id }, prefix: "gh.stacks.create_rebase_commits")
                return Result::Conflict.new(message: "Merge conflict detected")
              when GitSystems::Commit::Failed
                return Result::Error.new(message: "Could not create merge commit")
              when MergeCommit::ICommand::Result::Error
                return Result::Error.new(message: merge_commit.message)
              when MergeCommit::ICommand::Result::Timeout
                return Result::Waiting.new(message: "Merge commit creation timed out")
              when GitSystems::Errors::Outage, GitSystems::Errors::Fatal, GitSystems::Errors::Timeout
                return Result::Error.new(message: "Could not create merge commit")
              else T.absurd(merge_commit)
              end

              # Step 2: Rebase the PR commits onto the current base.
              rebase_commit = GitSystems::CreateRebaseCommit.new(
                repository:,
                base_sha: previous_head_before_rebasing,
                head_sha: merge_commit.sha,
                name: user.git_author_name,
                email: user.git_author_email,
                timestamp: user.time_zone.now,
                timeout: REBASE_TIMEOUT_SECONDS.seconds,
              ).call_spokes(onto_oid: previous_head_after_rebasing)

              case rebase_commit
              when GitSystems::Commit::Created
                last_result = rebase_commit
                previous_head_after_rebasing = rebase_commit.oid
                previous_head_before_rebasing = pull_request.head_sha
                @commit_oids[pull_request] = previous_head_after_rebasing
                logger.append({ rebase_commit_oid: previous_head_after_rebasing }, prefix: "gh.stacks.create_rebase_commits")
              when GitSystems::Commit::Conflict
                @logger.append({ conflict: true, pull_request_number: pull_request.number }, prefix: "gh.stacks.create_rebase_commits")
                return Result::Conflict.new(message: "Rebase conflict detected")
              when GitSystems::Errors::Timeout
                return Result::Waiting.new(message: "Rebase timed out")
              when GitSystems::Errors::Outage
                return Result::Error.new(message: "Git service unavailable during rebase")
              when GitSystems::Commit::Error, GitSystems::Errors::Fatal
                return Result::Error.new(message: "Failed to create rebase commit")
              else T.absurd(rebase_commit)
              end
            end
          end

          last_result || Result::Error.new(message: "No PRs to rebase")
        end

        sig { returns([T.nilable(T.any(Result::Error, Result::Waiting, Result::Conflict)), T::Array[RuleEngine::RuleSuite]]) }
        def validate_pull_requests
          rule_suites = []
          GitHub.tracer.in_span("pull_requests.stacks.perform_merge.validate_merge_rules", kind: :internal, attributes: { "pull_request_count" => pull_requests.size }) do
            pull_requests.each do |pull_request|
              GitHub.tracer.in_span("pull_requests.stacks.perform_merge.validate_merge_rules.pull_request", kind: :internal) do
                @logger.for(pull_request.id).append({
                  is_merge_target: @pull_request == pull_request,
                }, prefix: "gh.stacks")

                validation_error, rule_suite = validate_merge_rules(pull_request)
                rule_suites << rule_suite if rule_suite
                return [validation_error, rule_suites] unless validation_error.nil?
              end
            end

            [nil, rule_suites] # All PRs are valid
          end
        end

        sig { params(pull_request: PullRequest).returns([T.nilable(T.any(Result::Error, Result::Waiting, Result::Conflict)), T.nilable(RuleEngine::RuleSuite)]) }
        def validate_merge_rules(pull_request)
          # Workaround: Validate that the given merge method is allowed.
          # Uses partial logic from PullRequests::Merge::Command#validate!
          #
          # TODO: Remove this workaround in favor of PullRequests::Merge::Command#validate!
          # after it assigns the stack's merge method correctly. See PullRequests::Merge::Rules#merge_method
          user = @actor
          result = MergeConditions::PullRequestMergeMethod.async_evaluate(pull_request, T.cast(user, User), merge_method).sync
          if result.failed?
            return [Result::Error.new(message: T.must(result.message)), nil]
          end
          # End workaround

          # For merges, run rules against an up-to-date merge commit
          if FeatureFlag.vexi.enabled?(:pull_request_stacks_insights, repository, default: false)
            pull_request.create_merge_commit(skip_rebase: true) # rubocop:disable GitHub/EnsureCommitAttribution
          end

          command = Merge::Command.new(
            pull_request:, repository:,
            actor: @actor,
            mode: Merge::Mode::StackedWait.new(strategy: Merge::Enums::Strategy.deserialize(merge_method)),
            runtime: Merge::Enums::Runtime::Evaluation,
          )

          validation = command.validate!

          case validation
          when Merge::ICommand::Result::Error
            [Result::Error.new(message: "Unknown error occurred while validating merge requirements"), nil]
          when Merge::Results::AlreadyMerged
            [Result::Error.new(message: "Pull request is already merged"), nil]
          when Merge::Results::Invalid
            case message = validation.message
            when MergeConditions::PullRequestMergeConflictState::MERGE_CONFLICT_MESSAGE,
                 MergeConditions::PullRequestMergeConflictState::REBASE_CONFLICT_MESSAGE
              [Result::Conflict.new(message:), nil]
            else
              [Result::Error.new(message:), nil]
            end
          when Merge::ICommand::Result::TerminalBranchRuleFailure
            [Result::Error.new(message: validation.messages&.join(", ") || "Terminal branch rule failure"), command.rules.rule_suite]
          when Merge::ICommand::Result::ResolvableBranchRuleFailure
            [Result::Waiting.new(message: validation.messages&.join(", ") || "Waiting for branch rule conditions to be met"), command.rules.rule_suite]
          when Merge::ICommand::Result::Success
            [nil, command.rules.rule_suite] # Validation passed
          else
            T.absurd(validation)
          end
        end

        sig { returns(T.nilable(PullRequest)) }
        def retarget_remaining_stack_base
          return unless stack = self.stack
          return unless next_base_entry = stack.current_base_entry
          return unless next_base_pull = next_base_entry.pull_request
          return if next_base_pull.base_ref == stack.base_ref

          logger = @logger.for(next_base_pull.id)
          prior_base = next_base_pull.display_base_ref_name
          target_base = stack.base_ref

          begin
            GitHub.tracer.in_span("pull_requests.stacks.perform_merge.retarget_remaining_base", kind: :internal) do
              logger.append({ retarget_to: target_base, prior_base: }, prefix: "gh.stacks.retarget_remaining_base")

              next_base_pull.change_base_branch(@actor, target_base, automatic: true)
            end

            next_base_pull
          rescue PullRequest::BaseNotChangeableError => err
            logger.append({ retarget_failed: true, error: err.error_type_key }, prefix: "gh.stacks.retarget_remaining_base")

            begin
              next_base_pull.create_issue_event(:automatic_base_change_failed,
                @actor,
                message: err.error_type_key,
                title_was: prior_base,
                title_is: stack.base_ref)
            rescue ActiveRecord::ActiveRecordError => event_err
              Failbot.report(event_err, "gh.pull_request.id": next_base_pull.id)
            end

            nil
          rescue => err
            logger.append({ retarget_failed: true, error: err.class.name }, prefix: "gh.stacks.retarget_remaining_base")
            Failbot.report(err, "gh.pull_request.id": next_base_pull.id)
            nil
          end
        end

        sig { params(start_pull_request: PullRequest).void }
        def enqueue_update_all_branches(start_pull_request)
          return unless @actor.is_a?(User)
          return unless remaining_stack = self.stack

          remaining_pulls = remaining_stack.pulls_from(start_pull_request)
          return unless remaining_pulls.any?

          expected_head_oid_by_pr_number = remaining_pulls.to_h { |pr| [pr.number.to_s, pr.head_sha] }

          GitHub.tracer.in_span("pull_requests.stacks.perform_merge.enqueue_update_all_branches", kind: :internal) do
            UpdateAllBranchesJob.perform_later(
              start_pull_request:,
              actor: @actor,
              expected_head_oid_by_pr_number:,
            )

            @logger.append({
              enqueued_update_all_branches: true,
              start_pull_request_id: start_pull_request.id,
              start_pull_request_number: start_pull_request.number
            }, prefix: "gh.stacks")
          end
        end

        sig { type_parameters(:T).params(block: T.proc.returns(T.type_parameter(:T))).returns(T.type_parameter(:T)) }
        def with_telemetry(&block)
          Failbot.push(
            repository_id: @pull_request.repository_id,
            pull_request_id: @pull_request.id,
          )

          @logger.append({
            merge_method: merge_method.to_s,
            pull_request_count: stack ? pull_requests.size : 1,
            branch_base_oid: base_sha
          }, prefix: "gh.stacks")

          @logger.append_pull_request_context(@pull_request)

          GitHub.tracer.in_span("pull_requests.stacks.perform_merge", kind: :internal) do
            GitHub.dogstats.distribution_time("pull_requests.stacks.perform_merge", &block)
          end
        end

        sig { params(pull_request: PullRequest).returns(T::Boolean) }
        def is_auto_merge_request_origin?(pull_request)
          return false unless auto_merge_request
          pull_request.id == auto_merge_request&.pull_request_id
        end

        sig { params(pull_request: PullRequest, default_title: T.nilable(String), default_message: T.nilable(String)).returns([String, String]) }
        def commit_message_for(pull_request, default_title:, default_message:)
          # Only the triggering PR has an AutoMergeRequest with commit title/message
          # overrides; other PRs in the stack fall back to their own defaults. Using
          # `@pull_request.auto_merge_request` here would apply the triggering PR's
          # overrides to every commit, producing identical messages across the stack.
          pr_auto_merge_request = pull_request.auto_merge_request

          title = pr_auto_merge_request&.commit_title.presence || default_title
          message = pr_auto_merge_request&.commit_message.presence || default_message

          [title, message]
        end

        sig { returns(Repository) }
        memoize def repository = T.must(@pull_request.base_repository)

        sig { returns(T.nilable(AutoMergeRequest)) }
        memoize def auto_merge_request = @pull_request.auto_merge_request

        sig { returns(T.nilable(PullRequests::Stack)) }
        memoize def stack = @pull_request.stack

        sig { returns(T.nilable(BranchRuleEvaluator)) }
        memoize def branch_rule_evaluator = BranchRuleEvaluator.for_repository_with_branch_name(repository, base_ref_name)

        sig { returns(Symbol) }
        memoize def merge_method = auto_merge_request&.minimal_merge_method || :merge

        sig { returns(T::Array[PullRequest]) }
        memoize def pull_requests
          if stack
            T.must(stack).unmerged_pulls_from(@pull_request)
          else
            [@pull_request]
          end
        end

        sig { returns(String) }
        memoize def base_ref_name = @pull_request.stack_or_pull_base_ref_name

        sig { returns(T.nilable(Git::Ref)) }
        memoize def base_branch_ref = repository.heads.find(base_ref_name)

        sig { returns(String) }
        memoize def base_sha = T.must(base_branch_ref).sha

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def reflog_data
          user_name, user_email = git_author_info

          {
            user_name:,
            user_email:,
            user_login:,
            user_id: @actor.id,
            server: Socket.gethostname,
            via: "stacks auto merge",
          }
        end

        sig { returns([T.nilable(String), T.nilable(String)]) }
        def git_author_info
          case @actor
          when Bot
            [@actor.git_author_name, @actor.git_author_email]
          when User
            User.git_author_info(@actor)
          when Integration
            bot = @actor.bot
            [bot&.git_author_name, bot&.git_author_email]
          else
            T.absurd(@actor)
          end
        end

        sig { returns(String) }
        def user_login
          case @actor
          when User, Bot
            @actor.display_login
          when Integration
            @actor.slug
          else
            T.absurd(@actor)
          end
        end
      end
    end
  end
end
