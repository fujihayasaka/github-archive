# typed: true
# frozen_string_literal: true

class PullRequest
  class Update
    def initialize(pull:, actor:, author_email: nil, expected_head_oid: pull.head_sha, exclude_synchronize: false)
      @pull = pull
      @actor = actor
      @author_email = author_email
      @expected_head_oid = expected_head_oid
      @exclude_synchronize = exclude_synchronize
    end

    def merge(base_oid: nil, conflict_resolutions: nil)
      merge_commit_sha = generate_merge_commit(base_oid:, conflict_resolutions:)
      persist_merge_commit(merge_commit_sha:, has_resolved_conflicts: conflict_resolutions.present?)
    end

    def generate_merge_commit(base_oid:, conflict_resolutions:)
      check_push_permissions
      check_head_ref_position

      unless (merge_commit_sha = pull.create_merge_commit(skip_rebase: true))
        if !conflict_resolutions
          raise MergeConflictError, "merge conflict between base and head"
        end

        mergeable, merge_commit_sha = Prepare.new(pull: pull, base_oid: base_oid, skip_rebase: true).perform(conflict_resolutions: conflict_resolutions)
        if !mergeable
          raise MergeConflictError, "merge conflict not fully resolved"
        end
      end

      merge_commit_sha
    end

    def persist_merge_commit(merge_commit_sha:, has_resolved_conflicts: false)
      check_head_ref_position

      fetch_commit_from_base_repository_into_head_repository(merge_commit_sha)

      merge_commit = head_repository.commits.find(merge_commit_sha)
      _, merge_head_sha = merge_commit.parent_oids

      if merge_head_sha != expected_head_oid
        raise RefMismatch, "expected head oid value didn't match merge commit parent"
      end

      rewritten_merge_commit_sha = rewrite_merge_commit(merge_commit, has_resolved_conflicts)
      begin
        update_head_ref_to(rewritten_merge_commit_sha)
      rescue Git::Ref::ComparisonMismatch
        raise RefMismatch, "expected head oid value didn't match current head ref"
      end
      instrument_hydro_event(before: expected_head_oid, after: rewritten_merge_commit_sha)
      rewritten_merge_commit_sha
    end

    private

    attr_reader :pull, :actor, :author_email, :expected_head_oid, :exclude_synchronize

    def check_push_permissions
      unless pull.head_ref_pushable_by?(actor)
        if !pull.head_repository
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

      if pull.repository&.feature_flag_enabled_or_raise?(:skip_branch_update_if_no_commits) && !pull.behind_base? # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        GitHub.dogstats.increment("pull_requests.update_skipped", tags: ["type:merge"])
        raise BaseBranchNotBehindError, "There are no new commits on the base branch"
      end
    end

    def fetch_commit_from_base_repository_into_head_repository(commit_id)
      return if base_repository == head_repository
      GitHub.dogstats.time("pull_request",
          tags: ["action:fetch_commit_from_base_repository_into_head_repository"]) do
        head_repository.rpc.fetch_commits(base_repository.shard_path, commit_id)
      end
    end

    def rewrite_merge_commit(merge_commit, has_resolved_conflicts)
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
        "message"   => merge_commit_message(has_resolved_conflicts, author),
        "committer" => committer,
        "author"    => author,
        "tree"      => merge_commit.tree_oid,
      }

      merge_base_sha, merge_head_sha = merge_commit.parent_oids
      Repositories.domain.commits.create_tree_changes(
        repository: head_repository,
        parent_oids: [merge_head_sha, merge_base_sha],
        info: info,
        files: nil,
        sign_commit: true
      )
    end

    def merge_commit_message(has_resolved_conflicts, author)
      message = "Merge branch '#{pull.base_ref_name}' into #{head_ref.name}"
      # We only want to append DCO sign-off when there was a conflict resolution and not a clean merge
      message += "\n\n#{DcoSignoffHelper::dco_signoff_text(author.symbolize_keys)}" if pull.dco_signoff_enabled? && has_resolved_conflicts
      message
    end

    def update_head_ref_to(commit_id, forced: false)
      previous_commit_id = head_ref.target_oid

      # TODO: Make PullRequest#pr_reflog_data non-private
      options = { reflog_data: pull.send(:pr_reflog_data, "merge base into head") }
      options[:excluded_pull_ids] = [pull.id] if exclude_synchronize

      head_ref.update(commit_id, actor, options)
      pull.update_mergeable_attribute(nil)
    end

    def head_ref
      return @head_ref if defined?(@head_ref)
      @head_ref = head_repository.heads.find(pull.head_ref)
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
            update_method: "merge_commit",
          }
        }
      )
    end
  end
end
