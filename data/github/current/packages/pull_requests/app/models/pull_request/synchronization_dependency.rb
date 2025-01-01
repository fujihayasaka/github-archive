# typed: true
# frozen_string_literal: true

class PullRequest
  module SynchronizationDependency
    extend ActiveSupport::Concern
    extend T::Helpers

    requires_ancestor { PullRequest }

    module ClassMethods
      extend T::Helpers
      requires_ancestor { T.class_of(PullRequest) }
      # Update pull requests on the given repository that are based on the given
      # ref in response to an update (such as a Git push, applying suggested
      # changes, creating a commit from the web, or creating a deployment). The
      # pull request is closed when the head is merged into the base.
      #
      # NOTE Because moving through all pull requests can take some time and other
      # push events can trigger merges behind our back, each pull request is
      # loaded immediately before being synchronized to minimize the window where a
      # merge can be detected by two separate workers processing two separate pushes.
      # See the following issue for more info:
      #
      # https://github.com/github/github/issues/5827
      #
      # repository - Repository in which the initiating activity (push, commit,
      #   deployment etc) took place.
      # ref - The ref that was updated or deployed.
      # pusher - User responsible for pushing, committing or deploying.
      # forced - `true` if the ref was updated in a non-fast-forward manner.
      # before - The SHA before the ref was updated (does not apply to
      #   deployments).
      # after - The SHA after the ref was updated (does not apply to
      #   deployments).
      # push_options - Currently unused, but may be used in the future to
      #   request additional actions at push time using commands such as `git
      #   push -o pull.ready`.
      # excluded_pull_ids - Optional array of pull request ids that should not
      #   be updated; used by callers that want to synchronize a specific PR
      #   synchronously (for example, after applying suggested changes) before
      #   calling this method.
      def synchronize_requests_for_ref(
        repository,
        ref,
        pusher,
        forced: false,
        before: nil,
        after: nil,
        push_options: nil,
        excluded_pull_ids: nil,
        pushed_at: nil
      )
        if pusher && pusher.is_a?(Bot)
          pusher.installation = T.unsafe(pusher.integration).installations.with_repository(repository).first
        end

        ref_update = PullRequest::RefUpdate.new(
          repository:,
          pusher:,
          qualified_refname: ref,
          before_oid: before,
          after_oid: after
        )

        compliant_pr_ids = PullRequest.find_compliant_pull_request_ids(ref_update)

        if !GitHub.fan_out_synchronize_pull_request_jobs?
          preload_qualified_refs = []
          # This could be optimized. (1) It's only looking at ref names but in a fork network, some of these refs are in a different
          # repo. We wouldn't end up using the preloaded values. (2) Why are we preloadinging tags? We don't have PRs to / from tags.
          ref_update.refnames_from_affected_pulls.each do |ref|
            next if ref.nil?
            preload_qualified_refs << "refs/heads/#{ref}"
            preload_qualified_refs << "refs/tags/#{ref}"
          end
          repository.heads.find_all(preload_qualified_refs)
        end

        excluded_pull_ids = excluded_pull_ids&.to_set || Set.new
        pulls_to_retry = []
        process_compliant_prs_now = false
        ref_name = ref.delete_prefix("refs/heads/")

        synchronizable_pulls = ref_update.synchronizable_pulls
          .filter { |syncable_pr| !excluded_pull_ids.member?(syncable_pr.pull_request_id) }
        GitHub.dogstats.histogram("pull_request", synchronizable_pulls.count, tags: ["action:synchronize_number_of_pulls"])

        batch_is_merged = BatchIsPullRequestMerged.call(ref_update:)

        if compliant_pr_ids.present?
          # The first PR marked as "merged" which has a commit in its ancestry becomes the "pull request of record"
          # for that commit. See this method:
          #   Elastomer::Indexes::PullRequests.search_merged_including_commit()
          #
          # This is not ideal, but we have to work with it. We partition the list of PRs so that compliant pull requests
          # can be processed before non-compliant pull requests, and synchronously. This ensures that their merged_at
          # timestamp is set earlier than any non-compliant pull request's.

          (compliant_prs, non_compliant_prs) = synchronizable_pulls
            .partition { |syncable_pr| compliant_pr_ids.member?(syncable_pr.pull_request_id) }

          if compliant_prs.any? && non_compliant_prs.any?
            # We only care about what order these get synced when there is a mix of both compliant and non-compliant PRs
            synchronizable_pulls = compliant_prs + non_compliant_prs
            process_compliant_prs_now = true
            GitHub.dogstats.increment("pull_request.sync.process_compliant_pulls_inline")
          end
        end

        skipped_pull_request_ids = []
        synchronizable_pulls.each do |syncable_pr|
          pull_id = syncable_pr.pull_request_id
          base_oid = syncable_pr.base_oid
          head_oid = syncable_pr.head_oid

          # If this PR's commits are now part of base, the event in the timeline should say "closed" not "merged",
          # because policies were not met.
          non_compliant_merge = compliant_pr_ids.present? && !compliant_pr_ids.member?(pull_id)

          perform_later = GitHub.fan_out_synchronize_pull_request_jobs? &&
            # If there is a policy-compliant PR and a bunch of non-compliant PRs to sync, do the compliant PR(s) first:
            (!process_compliant_prs_now || non_compliant_merge)

          # Retrieve precomputed merge status for this PR, and also the OID's which were used to precompute it
          should_mark_merged = batch_is_merged.fetch(base_oid:, head_oid:)
          precomputed_merge_oids = [base_oid.to_s, head_oid.to_s] unless should_mark_merged == BatchIsPullRequestMerged::NotPrecomputed

          if syncable_pr.base_ref == ref_name && should_mark_merged == false && !forced
            GitHub.dogstats.increment("pull_request.sync.skipped_base_ref_sync")
            skipped_pull_request_ids.push(pull_id)
            next
          end

          if perform_later
            SynchronizePullRequestJob.perform_later(
              pull_request_id: pull_id,
              user: pusher,
              installation: pusher.try(:installation),
              repo: repository,
              forced:,
              ref: ref_name,
              before:,
              after:,
              should_mark_merged:,
              precomputed_merge_oids:,
              push_options:,
              non_compliant_merge:,
              pushed_at:,
            )
          else
            begin
              pull = includes(:issue).find(pull_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
              pull.synchronize!(user: pusher,
                                repo: repository,
                                forced:,
                                ref: ref_name,
                                before:,
                                after:,
                                should_mark_merged:,
                                precomputed_merge_oids:,
                                lock_options: { strict: true, timeout: 1 },
                                push_options:,
                                non_compliant_merge:,
                                pushed_at:)
            rescue LockAcquisitionError
              pulls_to_retry.push(pull)
            rescue => boom # rubocop:todo Lint/RescueException
              # don't let exceptions stop us from processing other open requests
              Failbot.report(boom,
                             "gh.repo.id": repository.id,
                             "gh.owner.id": repository.owner.id,
                             "gh.actor.id": pusher && pusher.id,
                             "gh.pull_request.force_pushed": forced,
                             "gh.pull_request.id": pull_id,
                            )
            end
          end
        end

        sync_prs_by_id = synchronizable_pulls.to_h { |syncable_pr| [syncable_pr.pull_request_id, syncable_pr] } if pulls_to_retry.any?
        pulls_to_retry.each do |pull|
          # If this PR's commits are now part of base, the event in the timeline should say "closed" not "merged",
          # because policies were not met.
          non_compliant_merge = compliant_pr_ids && !compliant_pr_ids.member?(pull.id)

          # Note: No need to use the partitioned and sorted list here since we're just retrying random errors
          syncable_pr = sync_prs_by_id&.fetch(pull.id)
          base_oid = syncable_pr&.base_oid
          head_oid = syncable_pr&.head_oid

          # Retrieve precomputed merge status for this PR, and also the OID's which were used to precompute it
          should_mark_merged = batch_is_merged.fetch(base_oid:, head_oid:)
          precomputed_merge_oids = [base_oid, head_oid] unless should_mark_merged == BatchIsPullRequestMerged::NotPrecomputed

          begin
            pull.synchronize!(
              user: pusher,
              repo: repository,
              forced:,
              ref: ref_name,
              before:,
              after:,
              should_mark_merged:,
              precomputed_merge_oids:,
              lock_options: { strict: false, timeout: 1 },
              push_options:,
              non_compliant_merge:,
              pushed_at:)
          rescue => boom # rubocop:todo Lint/RescueException
            Failbot.report(boom,
                            "gh.repo.id": repository.id,
                            "gh.owner.id": repository.owner.id,
                            "gh.actor.id": pusher && pusher.id,
                            "gh.pull_request.force_pushed": forced,
                            "gh.pull_request.id": pull.id,
                          )
          end
        end

        if FeatureFlag.vexi.enabled?(:pull_requests_reduced_merge_commits, repository, default: false)
          GitHub.logger.info(
            "skipping batch writing mergeable: nil",
            "gh.repo.id" => repository.id,
            "gh.pull_requests.skipped_pull_request_ids" => skipped_pull_request_ids
          )
        else
          skipped_pull_request_ids.each_slice(500) do |batch|
            PullRequest.where(id: batch).update_all(mergeable: nil)
          end
        end
      end

      def find_compliant_pull_request_ids(ref_update)
        compliant_pr_ids = T.let(nil, T.nilable(Set))

        # Look to see which pull requests complied with rules during ref update
        rule_suite = RuleEngine::RuleSuite
          .order(created_at: :desc)
          .find_by(
            repository: ref_update.repository,
            ref_name: ref_update.qualified_refname,
            before_oid: ref_update.before_oid,
            after_oid: ref_update.after_oid
          )
        pull_request_rule_runs = rule_suite&.runs_by_rule_type("pull_request")

        if pull_request_rule_runs&.any?
          pull_request_rule_runs.each do |run|
            compliant_for_run = run.evaluation_metadata&.[]("compliant_pr_ids")
            next unless compliant_for_run # PR's merged by merge queue don't (yet) include this info

            # A pull request is compliant only if it is compliant for all rule runs which protect the updated ref.
            if compliant_pr_ids.nil?
              compliant_pr_ids = Set[*compliant_for_run]
            else
              compliant_pr_ids &= [*compliant_for_run]
            end
          end
        end

        compliant_pr_ids
      end
    end

    mixes_in_class_methods(ClassMethods)

    class LockAcquisitionError < ::PullRequest::Error; end

    # Updates the state of a `PullRequest` and related records in response to
    # activities such as pushes (to the base or head ref), switching the base
    # ref, applying suggestions, and resolving conflicts.  Side-effects may
    # include publishing issue events, dismissing stale reviews, requesting new
    # reviews, closing pull requests, and more.
    #
    # user - The user responsible for the activity and who should be attributed
    #   in any created issue events. Beware that the `user` may sometimes be
    #   based on a heuristic (for example, when called from `catch_up`, it's the
    #   owner of the base repo).
    # repo - The Repository (head or base repository) where the activity took
    #   place. Some exceptions to this exist, such as switching the base branch,
    #   re-opening a closed PR, or using the `catch_up` functionality from staff
    #   tools (these always pass the base repository).
    # forced - Whether the ref was updated in a non-fast-forward manner; note
    #   this does not necessarily mean that the PR's head branch was
    #   force-pushed (force-pushing the base branch will also cause `forced` to
    #   be `true` for PRs that target that branch).
    # ref - The ref that was updated. Some synchronization triggers omit this
    #   (e.g. when advisory pull requests are updated, when a closed PR is
    #   reopened, when merge conflict resolution commits are created by
    #   `CreatePullRequestResolvedMergeConflictJob`).
    # before - The SHA before the ref was updated: only passed in response to a
    #   push or push-like (applying suggested changes, committing from the
    #   web) event.
    # after - The SHA after the ref was updated: only passed when triggered by a
    #   push or switching the base ref.
    # should_mark_merged - precomputed value of `is_head_merged_into_base?`.
    #   Note: defaults to a sentinel here for deploy safety. A future deploy
    #   will make it a required argument.
    # changing_base - Indicates that the supplied `ref` should be used as the
    #   new `base_ref`; only `true` when called from
    #   `PullRequest#change_base_branch`.
    # reopened - Indicates a closed PR is being reopened and should therefore
    #   recalculate its base SHA in order to ensure the correct diff is shown.
    # automatic_base_retarget - Indicates that `synchronize!` is being
    #   called while automatically updating dependent PRs after merging a
    #   branch or otherwise cleaning up another PR.
    # lock_options - Customizes `:timeout` and `:strict` behavior for lock
    #   acquisition; when `:strict` is `false`, a best effort is made to obtain
    #   the lock, but execution proceeds anyway; when `:strict` is `true`,
    #   failure to obtain the lock raises a `LockAcquisitionError`.
    # push_options - Currently unused, but may be used in the future to request
    #   additional actions at push time using commands such as `git push -o
    #   pull.ready`.
    # non_compliant_merge - this means that one or more pull request rule
    #   applied to this ref update, and this pull request did not comply with
    #   at least one of them. A pull request might be "merged" in the sense that
    #   all its commits are now in the base branch, but the PR was not compliant.
    #   For example, it might not have enough approvals, or the right approvals,
    #   or a last-push approval, etc.
    #
    #   Note that this flag does NOT mean that the PR is actually merged, it just
    #   means if it's merged, it was a non-compliant merge.
    #
    # Returns true when the pull request was modified, falsey otherwise.
    sig do params(
      user: T.nilable(User),
      repo: Repository,
      forced: T::Boolean,
      ref: T.nilable(String),
      before: T.nilable(String),
      after: T.nilable(String),
      should_mark_merged: BatchIsPullRequestMerged::PrecomputedResultType,
      precomputed_merge_oids: T.nilable(T::Array[String]),
      changing_base: T::Boolean,
      reopened: T::Boolean,
      automatic_base_retarget: T::Boolean,
      lock_options: T::Hash[Symbol, T.untyped],
      push_options: T.untyped,
      promote_reviews: T::Boolean,
      non_compliant_merge: T::Boolean,
      pushed_at: T.nilable(Time)
    ).void
    end
    def synchronize!(
      user:,
      repo:,
      forced: false,
      ref: nil,
      before: nil,
      after: nil,
      should_mark_merged: BatchIsPullRequestMerged::NotPrecomputed,
      precomputed_merge_oids: [],
      changing_base: false,
      reopened: false,
      automatic_base_retarget: false,
      lock_options: {},
      push_options: {},
      promote_reviews: false,
      non_compliant_merge: false,
      pushed_at: nil
    )

      is_changing_base = T.let(changing_base, T::Boolean)

      positioner = PullRequests::CommentPosition::Synchronization.new(pull_request: T.unsafe(self), repository: repo)

      is_reducing_merge_commits = FeatureFlag.vexi.enabled?(:pull_requests_reduced_merge_commits, repo, default: false)

      # Validations on Issues, such as label limits, shouldn't prevent syncing here if not relevant.
      T.must(issue).skip_validation_for_pr_sync = true # domain-isolation-query-violation:ignore:packages/issues (SELECT)

      GitHub.dogstats.time("pull_request", tags: ["action:synchronize"]) do
        with_synchronize_lock(lock_options) do
          # Track before approval state if a ref update is happening and
          # code owner review is required. Used to move project cards
          # when code owner required reviews are added/removed.
          if ref && base_branch_rule_evaluator&.require_code_owner_review? && issue&.project_workflow_review_triggers?
            approved_before = approved_with_no_changes_requested?
          end

          # Previously we always clear the mergeable attribute. This forces CPRMC to run, so in an effort to reduce this, we'll
          # decide this further along after we've determine commit points.
          unless is_reducing_merge_commits
            update_mergeable_attribute(nil)
          end

          # These things can happen outside of the transaction because
          # they merely set attributes on the model or do git stuff,
          # and don't write to the database.

          saved_base_sha = base_sha
          saved_head_sha = head_sha

          old_base_ref = self.base_ref
          old_display_base_ref_name = self.display_base_ref_name
          if is_changing_base
            if ref != self.base_ref
              self.base_ref = ref
              @comparison = nil
              remove_instance_variable(:@async_build_comparison) if defined?(@async_build_comparison)
              remove_instance_variable(:@async_changed_commits) if defined?(@async_changed_commits)
              clear_preloaded_batch_method_value(:base_branch_rule_evaluator)
            else
              is_changing_base = false
            end
          end

          begin
            commit_points_changed = GitHub.dogstats.time("pull_request", tags: ["action:record_concrete_commit_points"]) do
              record_concrete_commit_points(forced || changing_base || reopened)
            end
          rescue ActiveRecord::RecordNotFound
            # Keep noise from soft-deleted repos out of Sentry:
            # https://github.com/github/pull-requests/issues/7081
            return
          end

          if commit_points_changed
            if positioner.enabled?
              positioner.reposition!(
                from: [saved_base_sha, saved_head_sha],
                to: [base_sha, head_sha],
                threads: review_threads.to_a # These are the relations called during save_thread_positions!
              )
            else
              recalculate_all_positions
            end
          end

          pushed_to_base = repo == base_repository

          # if a ref was specified, meaning that this call to #synchronize! came from a push,
          # then verify that the push was to the base ref.
          if pushed_to_base && ref
            base_ref_name = Git::Ref.safe_ref_name(ref_names: base_ref)
            pushed_to_base = base_ref_name.include?(ref)
          end
          head_ref_name = Git::Ref.safe_ref_name(ref_names: head_ref)
          pushed_to_head = head_ref_name.include?(ref) && repo == head_repository

          if (pushed_to_head && after) || promote_reviews
            promote_reviews_to_latest_head(head_sha)
          end

          precompute_usable = "not_precomputed"
          sync_called_spokes = T.let(false, T::Boolean)
          throttled_by_spokes = T.let(false, T::Boolean)

          current_head_oid = head_repository&.heads&.find(head_ref)&.target_oid
          if !current_head_oid
            # The head ref or perhaps the whole head repo was deleted
            precompute_usable = "head_not_found"

            should_mark_merged =
              if closed? && merged?
                # This PR was closed and merged, so it's still merged
                true
              elsif !head_sha || head_sha == GitHub::NULL_OID
                # There's no current ref, and we have no head_sha to base a historical comparison on
                false
              else
                # Use this PR's head_sha to determine if it's merged. Setting NotPreComputed causes us to call spokes below.
                current_head_oid = head_sha
                BatchIsPullRequestMerged::NotPrecomputed
              end
          else
            # If a precomputed merge status is available, check if it's still valid
            if should_mark_merged != BatchIsPullRequestMerged::NotPrecomputed
              if [current_base_oid, current_head_oid] == precomputed_merge_oids
                # The branches still point to the same commits used during precomputation
                precompute_usable = "usable"
              else
                # Throw away the precomputed merged value, it has become stale
                precompute_usable = "stale"
                should_mark_merged = BatchIsPullRequestMerged::NotPrecomputed
              end
            end
          end

          # If we don't know the merged status, compute it
          if should_mark_merged == BatchIsPullRequestMerged::NotPrecomputed
            sync_called_spokes = true
            GitHub.dogstats.distribution_time("pull_request.sync.compute_is_merged_with_spokes") do
              should_mark_merged = T.must(base_repository).spokes_api
                .ahead_behind_contains(base: current_base_oid, tips: [current_head_oid])
                .include?(current_head_oid)
            end
          end

          # Was this synchronize! caused by a ref update?
          is_ref_update = ref.present? && before.present? && after.present?

          tags = ["precompute_usable:#{precompute_usable}", "is_ref_update:#{is_ref_update}", "sync_called_spokes:#{sync_called_spokes}"]

          GitHub.dogstats.increment("pull_request.sync.batched_is_merged.usability", tags:)

          # changed_commits is expensive to calculate (~20ms) and only used when the base branch is being changed. Telemetry
          # shows we use it less than 1 time in 5,000. Only calculate it if we need it.
          if automatic_base_retarget || changing_base
            has_changed_commits = changed_commits.any?
          end

          merged = user && pushed_to_base && merged_at.nil? && should_mark_merged

          if repository&.feature_flag_enabled_or_raise?(:pushed_ref_stats) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            if pushed_to_base
              GitHub.dogstats.increment("pull_request.sync.pushed_ref", tags: ["action:base", "forced:#{forced}", "should_mark_merged:#{should_mark_merged}"])
            elsif pushed_to_head
              GitHub.dogstats.increment("pull_request.sync.pushed_ref", tags: ["action:head"])
            else
              GitHub.dogstats.increment("pull_request.sync.pushed_ref", tags: ["action:unknown"])
            end
          end

          inferred_merge_sha = T.let(nil, T.nilable(String))

          if merged
            # If a merge commit is available in the history, persist it for revertability.
            GitHub.dogstats.time("pull_request", tags: ["action:determine_merge_sha"]) do
              inferred_merge_sha = determine_merge_sha
            end
          end

          # XXX force pushes just break pr history so let's just truncate the review
          # history in that case for now
          LastSeenPullRequestRevision.clear(self) if forced || changing_base || reopened

          force_push_event =
            if forced && ref && before && after
              if pushed_to_base
                if !repo.rpc.descendant_of?(after, saved_base_sha)
                  :base_ref_force_pushed
                end
              else
                :head_ref_force_pushed
              end
            end

          if repository&.feature_flag_enabled_or_raise?(:update_last_reviewable_push_from_sync_job) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            if is_changing_base || pushed_to_head || reopened
              # This returns quickly unless a "last push policy" is enforced on the base branch
              GitHub.dogstats.time("pull_request", tags: ["action:find_last_reviewable_push"]) do
                find_and_update_last_reviewable_push
              end
            end
          end

          disable_auto_merge_if_non_writer_pushed_or_changed_base(before: T.unsafe(saved_head_sha), after: T.unsafe(head_sha), user: user, changing_base: is_changing_base)

          # stuff we need below, but don't want to cause slowing of the transaction.
          diff_may_have_changed = forced || is_changing_base || pushed_to_head || reopened

          no_common_ancestor = !in_advisory_workspace? && !common_ancestor?
          should_dismiss_stale_reviews = dismiss_stale_reviews?(
            changing_base: is_changing_base,
            base_changed_manually: (is_changing_base && !automatic_base_retarget))
          should_dismiss_file_reviews = dismiss_file_reviews?(
            before: saved_head_sha, after: head_sha, base_changed_manually: (is_changing_base && !automatic_base_retarget))
          has_potential_codeowners = codeowners!.any?
          duplicate_exists = (automatic_base_retarget || is_changing_base) ? find_existing : nil

          missing_reviewer_summaries = if ready_for_review? && diff_may_have_changed && !closed?
            self.find_missing_required_review_summaries
          end

          in_timed_otel_span("pull_request.synchronize_transaction") do
            # DON'T PUT ANYTHING UNNECESSARY INSIDE OF THIS TRANSACTION
            #
            # This transaction has a history of being slow and causing problems
            # for the pull requests table. Any calculations, calls to git or external
            # services etc, should take place outside of the transaction. Ideally anything
            # in here will be limited strictly to database operations.
            transaction do
              if commit_points_changed
                if positioner.enabled?
                  in_timed_otel_span("pull_request.synchronize_transaction.save_review_thread_positions") do
                    positioner.save_threads!
                  end
                else
                  save_review_thread_positions
                end
              end

              if automatic_base_retarget
                raise RefPairingAlreadyExistsError.new(T.unsafe(self), ref) if duplicate_exists

                # If we're automatically changing base and there are no changed
                # commits, then the pull request will be marked as merged.
                #
                # Reset the base sha here so that the PR's comparison page will
                # show the diff at the time of merge before the base update.
                self.base_sha = saved_base_sha unless has_changed_commits

                create_issue_event(:automatic_base_change_succeeded,
                                  user,
                                  title_was: old_display_base_ref_name,
                                  title_is: display_base_ref_name)
              elsif is_changing_base
                raise RefPairingAlreadyExistsError.new(T.unsafe(self), ref) if duplicate_exists
                raise ComparisonWouldBeEmptyError.new(T.unsafe(self), ref) unless has_changed_commits
                create_issue_event(:base_ref_changed,
                                  user,
                                  title_was: old_display_base_ref_name,
                                  title_is: display_base_ref_name)
              end

              if merged
                in_timed_otel_span("pull_request.synchronize_transaction.mark_as_merged") do

                  if non_compliant_merge
                    # This PR was not compliant w/ policies, but its commits were merged via some other, compliant PR
                    mark_as_merged(user, after, nil, :merged_indirectly)
                  else
                    mark_as_merged(user, inferred_merge_sha)
                  end

                  GlobalInstrumenter.instrument("pull_request.merge", {
                    pull_request: self,
                    actor: user,
                    author: user,
                    protected_branch: self.base_branch_rule_evaluator&.original_protected_branch,
                    merge_action: :indirect_merge
                  })
                  instrument(:indirect_merge, {
                    actor: user,
                    before: saved_head_sha,
                    after: head_sha
                  })
                end
              elsif !pushed_to_base && should_mark_merged
                close(user)
              elsif no_common_ancestor
                GitHub.dogstats.increment("pull_request", tags: ["action:closed_no_common_ancestor"])
                close(user)
              elsif cross_repo_violation?
                GitHub.dogstats.increment("pull_request", tags: ["action:cross_repo_violation"])
                # Don't let the SHA leak across repos
                write_attribute :head_sha, saved_head_sha
                close(user)
              end

              if should_dismiss_stale_reviews
                in_timed_otel_span("pull_request.synchronize_transaction.dismiss_stale_reviews") do
                  dismiss_stale_reviews(
                    actor: user,
                    changing_base: is_changing_base,
                    base_changed_manually: (is_changing_base && !automatic_base_retarget))
                end
              end

              if should_dismiss_file_reviews
                in_timed_otel_span("pull_request.synchronize_transaction.dismiss_file_reviews") do
                  dismiss_file_reviews(before: saved_head_sha, after: head_sha, actor: user)
                end
              end

              should_request_codeowner_reviews =
                ready_for_review? && has_potential_codeowners && diff_may_have_changed

              if should_request_codeowner_reviews
                in_timed_otel_span("pull_request.synchronize_transaction.request_code_owners") do
                  request_review_from_codeowners(user)
                end
              end

              if missing_reviewer_summaries.present?
                in_timed_otel_span("pull_request.synchronize_transaction.add_required_review_requests") do
                  add_missing_required_review_requests(missing_reviewer_summaries:)
                end
              end

              if force_push_event
                create_issue_event(force_push_event,
                                   user,
                                   commit_repository_id: repo.id,
                                   before_commit_oid: before,
                                   after_commit_oid: after,
                                   ref: ref)
              end

              if commit_points_changed || merged || is_changing_base || reopened
                update_mergeable_attribute(nil)
                save! # domain-isolation-query-violation:ignore:packages/issues (UPDATE)
              end
            end

            if is_changing_base
              instrument(:change_base, {
                actor: user,
                issue: issue,
                before_base_ref: old_base_ref,
                before_base_sha: saved_base_sha,
                after_base_ref: ref,
                after_base_sha: after,
                spammy: T.must(user).spammy?,
                allowed: allowed?,
              })
            end

            if merged
              PullRequestCloseReferencedIssuesJob.perform_later(pull_request: self, actor: user)

              if head_repository&.delete_branch_on_merge?
                if repository&.feature_flag_enabled_or_raise?(:async_delete_branch_on_merge) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
                  PullRequests::CleanupHeadRefJob.perform_later(pull_request: T.unsafe(self), actor: user)
                else
                  cleanup_head_ref(user)
                end
              end
            end

            # we don't track events on spammy pull requests
            return true if self.user&.spammy? && !allowed?

            head_sha_changed = head_sha != saved_head_sha

            if !merged && head_sha_changed
              unless approved_before.nil?
                # Reset codeowners to get an accurate new review state
                @codeowners = nil
                approved_after = approved_with_no_changes_requested?
              end
              payload = {
                before: saved_head_sha,
                after: head_sha,
                issue: issue,
                approved_before: approved_before,
                approved_after: approved_after,
              }
              if user.present?
                payload[:actor]   = user
                payload[:spammy]  = user.spammy?
                payload[:allowed] = allowed?
              end

              instrument(:synchronize, payload)
              GlobalInstrumenter.instrument("pull_request.synchronize", {
                actor: payload[:actor],
                repository: repo,
                pull_request: self,
                issue: payload[:issue],
                protected_branch: self.base_branch_rule_evaluator&.original_protected_branch,
                ref: ref,
                before: payload[:before],
                after: payload[:after],
              })

              if repository&.feature_flag_enabled_or_raise?(:pull_request_synchronization_event_logging) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
                # Adding this as we currently have many issues open for pull request synchronization events not
                # being emitted. Thus far we've been unable to corroborate job failures with a lack of events but can
                # confirm that the events are not showing up in our web event tooling in stafftools. This is wrapped
                # in a feature flag so we don't overwhelm splunk with possible logs
                GitHub.logger.info(
                  "pull request synchronize event instrumented",
                  "gh.pull_request.id" => id,
                  "gh.pull_request.head_repo.id" => head_repository_id,
                  "gh.pull_request.base_repo.id" => base_repository_id,
                  "gh.pull_request.ref" => ref,
                  "gh.pull_request.head_sha.before" => saved_head_sha,
                  "gh.pull_request.head_sha.after" => head_sha,
                  "gh.pull_request.head_sha.approved_before" => approved_before,
                  "gh.pull_request.head_sha.approved_after" => approved_after,
                  "gh.pull_request.user.spammy" => user&.spammy?,
                  "gh.pull_request.allowed" => allowed?
                )
              end
            end

            if pushed_at
              if DateTime.parse(pushed_at.to_s) < 1.minute.ago
                GitHub.logger.info(
                  "delayed pushed_at",
                  "code.function" => "synchronize!.pushed_at",
                  "gh.pull_request.id" => id,
                  "gh.pull_request.head_repo.id" => head_repository_id,
                  "gh.pull_request.base_repo.id" => base_repository_id,
                  "gh.pull_request.pushed_at" => pushed_at
                )
              end

              if pushed_to_head
                GitHub.dogstats.distribution_timing_since("pullrequest.sync.time_since_head_ref_update", pushed_at, tags: ["head_sha_changed:#{head_sha_changed}"])

                if !head_sha_changed
                  GitHub.logger.info(
                    "head sha didn't change",
                    "code.function" => "synchronize!.pushed_at",
                    "gh.pull_request.id" => id,
                    "gh.pull_request.pushed_at" => pushed_at,
                    "gh.pull_request.before" => before,
                    "gh.pull_request.after" => after,
                    "gh.pull_request.ref" => ref,
                    "gh.pull_request.head_repo.id" => head_repository_id,
                    "gh.pull_request.base_repo.id" => base_repository_id,
                  )
                end
              else
                GitHub.dogstats.distribution_timing_since("pullrequest.sync.time_since_base_ref_update", pushed_at)
              end
            else
              GitHub.dogstats.increment("pullrequest.sync.push_record_not_found")
            end

            true
          end
        end
      end
    end

    # In the event that we missed a push (dropped job perhaps), try to
    # catch the PR up to the current state of the branches involved.
    # We might attribute some things to the wrong user or miss out on
    # some details about pushes we missed. This could get better if we
    # end up using the reflog someday.
    #
    # This is only ever used from stafftools and rarely so.
    def catch_up
      synchronize!(user: T.unsafe(base_repository).owner, repo: T.must(base_repository), lock_options: { strict: true })
    rescue LockAcquisitionError
      synchronize!(user: T.unsafe(base_repository).owner, repo: T.must(base_repository), lock_options: { strict: false })
    end

    # recalculate `position`s and `blob_position`s for all associated review comments.
    def recalculate_all_positions
      update_outdated_flag_for_file_threads
      in_timed_otel_span("pull_request.recalculate_review_comment_relative_positions") do
        recalculate_review_comment_diff_positions
      end
      in_timed_otel_span("pull_request.recalculate_review_comment_absolute_positions") do
        recalculate_review_comment_blob_positions
      end
    end

    def recalculate_review_comment_diff_positions
      return if line_review_threads.empty?
      diff = current_threads_diff

      if repository&.feature_flag_enabled_or_raise?(:comment_outside_the_diff) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        # get a mapping of former paths to target paths in case of renames
        target_paths = {}
        line_review_threads.each do |thread|
          thread.path && target_paths[thread.path] ||= thread.async_target_path(diff).sync
        end

        # these are the positions we'll want to inject
        adjusted_diff_positions = line_review_threads.map do |thread|
          Promise.all([
            Promise.resolve(target_paths[thread.path]),
            thread.has_positioning_data? ? thread.async_adjusted_blob_position(diff) : nil,
            thread.start_position_offset || 0]
          ).sync
        end

        # removing positions that are now outdated
        adjusted_diff_positions.reject! { |_path, position| position.nil? }

        @additional_context_line_ranges = Hash.new { |h, k| h[k] = [] }
        adjusted_diff_positions.each do |path, position, offset|
          next unless position
          context_range = Range.new(
            position - offset - (PullRequestReviewThread::OUTSIDE_DIFF_CONTEXT_MARGIN + 1),
            position + (PullRequestReviewThread::OUTSIDE_DIFF_CONTEXT_MARGIN) + 1
          )
          @additional_context_line_ranges[path] << context_range
        end

        # generate a new diff with context injected
        # then pass it into async_reposition_from_blob_position
        reset_current_threads_diff!
        diff = current_threads_diff
      end

      adjustment_promises = line_review_threads.map do |thread|
        next nil unless thread.has_positioning_data?
        thread.async_reposition_from_blob_position(diff)
      end.compact

      GitHub.dogstats.distribution("pull_request.sync.relative_threads_repositioned", adjustment_promises.size)

      Promise.all(adjustment_promises).sync
    end

    def recalculate_review_comment_blob_positions
      line_review_threads.select(&:needs_position_update?).each(&:update_position_data).tap do
        # Send the number of threads that were actually repositioned.
        GitHub.dogstats.distribution("pull_request.sync.absolute_threads_repositioned", _1.size)
      end
    end

    def update_outdated_flag_for_file_threads
      diff = current_threads_diff
      file_review_threads.each do |thread|
        thread.outdated = thread.file_level_thread_outdated_as_of_diff?(diff: diff)
      end
    end

    # We save the review threads separately, so the recalculating
    # can be done outside of the transaction.
    def save_review_thread_positions
      in_timed_otel_span("pull_request.synchronize_transaction.save_review_thread_positions") do
        line_review_threads.group_by(&:changed_attribute_names_to_save).each do |fields, records|
          if fields == ["commit_id"]
            # For many PR syncs we only need to update the `commit_id`.
            # These changes are the same for all review threads, and because
            # there can be a lot of them it's more efficient to do this as a
            # bulk update.

            records.in_groups_of(100, false) do |batch|
              line_review_threads.where(id: batch.map(&:id)).update_all(
                commit_id: head_sha,
                updated_at: current_time_from_proper_timezone,
              )
              batch.each(&:changes_applied)
            end
          else
            # For more complex updates, where we're actually changing
            # thread-specific data, we should actually save each record
            # individually.

            records.each(&:save_positions)
          end
        end

        file_review_threads.each(&:save)
      end
    end

    DEFAULT_LOCK_TIMEOUT_SECONDS = 5

    def name_for_synchronize_lock
      if self.id
        "PullRequest#synchronize!:#{self.id}"
      end
    end

    def with_synchronize_lock(lock_options = {}, &block)
      timeout = lock_options.fetch(:timeout, DEFAULT_LOCK_TIMEOUT_SECONDS)
      name = name_for_synchronize_lock
      mutex = GitHub::Redis::Mutex.new(name, { wait: timeout })

      begin
        mutex.lock do
          GitHub.dogstats.increment("pull_request", tags: ["action:synchronize_lock_acquired"])
          block.call
        end
      rescue GitHub::Redis::Mutex::LockError
        GitHub.dogstats.increment("pull_request", tags: ["action:synchronize_lock_timed_out"])
        if use_strict_locking?(lock_options)
          raise LockAcquisitionError, "failed to acquire lock `#{name}`"
        else
          block.call
        end
      end
    end

    def use_strict_locking?(lock_options = {})
      !!lock_options.fetch(:strict, false)
    end

    def cross_repo_violation?
      return false unless head_repository = self.head_repository
      return false unless base_repository = self.base_repository

      head_repository.network_id != base_repository.network_id && !in_advisory_workspace?
    end

    def async_cross_repo_violation?
      Promise.all([
        async_base_repository,
        async_head_repository,
        async_in_advisory_workspace?
      ]).then do |base_repo, head_repo, in_advisory_workspace|
        next false unless base_repo
        next false unless head_repo

        base_repo.network_id != head_repo.network_id && !in_advisory_workspace
      end
    end

    private

    def in_timed_otel_span(name)
      GitHub.dogstats.distribution_time(name) do
        GitHub.tracer.in_span(name, kind: :internal) do
          yield
        end
      end
    end
  end
end
