# typed: true
# frozen_string_literal: true

class PullRequest
  class Rebase
    attr_reader :pull, :actor, :author_email, :expected_head_oid, :exclude_synchronize

    def initialize(pull:, actor:, author_email: nil, expected_head_oid: pull.head_sha, exclude_synchronize: false)
      @pull = pull
      @actor = actor
      @author_email = author_email
      @expected_head_oid = expected_head_oid
      @exclude_synchronize = exclude_synchronize
    end

    def check_rebase_prepared
      return if pull.rebase_prepared? && pull.rebase_safe?

      if GitHub.flipper[:pull_request_generate_rebase_sync].enabled?(pull.repository)
        previous_mergeable = pull.conflict.nil?
        previously_unknown = pull.mergeable_unknown?
        mergeable, merge_commit_sha = Prepare.new(pull: pull, priority: :high, skip_rebase: false).perform
        pull.update_mergability(mergeable, merge_commit_sha, previous_mergeable, previously_unknown)
        # reset memoized rebase_state
        pull.reload
      end

      unless pull.rebase_prepared?
        if pull.rebase_conflicts?
          raise RebaseConflictError, "rebase conflict between base and head"
        else
          raise RebaseConflictError, "rebase not prepared"
        end
      end

      unless pull.rebase_safe?
        raise RebaseConflictError, "base changed"
      end
    end

    def rebase
      check_push_permissions
      check_head_ref_position
      check_pull_permissions
      check_rebase_prepared

      merge_commit = pull.repository.commits.find(pull.merge_commit_sha)
      rebase_commit = pull.repository.internal_refs.find(pull.rebase_ref).target

      fetch_commit_from_base_repository_into_head_repository(merge_commit.oid)
      fetch_commit_from_base_repository_into_head_repository(rebase_commit.oid)

      rewritten_rebased_commit = rewrite_commits(rebase_commit.oid, merge_commit.first_parent_oid)
      update_head_ref_to(rewritten_rebased_commit, force: true)

      instrument_hydro_event(before: expected_head_oid, after: rewritten_rebased_commit)
      rewritten_rebased_commit
    end

    private

    def check_pull_permissions
      # RebaseConflictError is not going to display a very informative error to the user
      # This is replicating the behaviour that updating via merge commit shows to users
      raise RebaseConflictError, "pull request merged" if pull.merged_at?
      raise RebaseConflictError, "pull request closed" if pull.closed?
      raise RebaseConflictError, "base ref does not exist" unless pull.base_ref_exist?
    end

    def check_push_permissions
      unless pull.head_ref_pushable_by?(actor)
        if !pull.head_repository
          # PermissionError displays an error saying the user does not have permission to update the base repository
          # This is replicating the behaviour that updating via merge commit shows to users
          raise PermissionError, "head repository does not exist"
        else
          raise PermissionError, "user doesn't have permission to update head repository"
        end
      end
    end

    def check_head_ref_position
      unless head_ref
        raise HeadMissing, "head ref does not exist"
      end

      unless head_ref.target_oid == expected_head_oid
        raise RefMismatch, "expected head oid value didn't match current head ref"
      end
    end

    def fetch_commit_from_base_repository_into_head_repository(commit_id)
      return if base_repository == head_repository
      GitHub.dogstats.time("pull_request",
          tags: ["action:fetch_commit_from_base_repository_into_head_repository"]) do
        head_repository.rpc.fetch_commits(base_repository.shard_path, commit_id)
      end
    end

    def rewrite_commits(start_commit, end_commit)
      head_repository.rpc.update_committer_info(start_commit, end_commit, {
        "email" => author_email || actor.git_author_email,
        "name"  => actor.git_author_name,
        "time"  => actor.time_zone.now.iso8601,
      })
    end

    def update_head_ref_to(commit_id, force: false)
      options = {
        reflog_data: pull.send(:pr_reflog_data, "rebase head onto base"),
        force: force
      }
      options[:excluded_pull_ids] = [pull.id] if exclude_synchronize

      head_ref.update(commit_id, actor, options)

      pull.update_mergeable_attribute(nil)
    end

    def head_ref
      @head_ref ||= head_repository.heads.find(pull.head_ref)
    end

    def head_repository
      pull.head_repository
    end

    def base_repository
      pull.base_repository
    end

    def instrument_hydro_event(before:, after:)
      GlobalInstrumenter.instrument("pull_request.user_action",
        {
          user_id: actor.id,
          pull_request_id: pull.id,
          category: "update_branch",
          action: "performed",
          data: {
            before: before,
            after: after,
            update_method: "rebase",
          }
        }
      )
    end
  end
end
