# typed: strict
# frozen_string_literal: true

module PullRequests
  # Validates the new `PullRequests::GitSystems::CreateSquashCommit` service
  # path against the legacy `PullRequest::SquashMerge` path by re-running the
  # new path inside a Scientist experiment and comparing its commit *tree*
  # OID against the tree OID of the squash commit that the legacy path
  # already produced.
  #
  # Enqueued from `MergeQueues::Ref#create_squash_commit` after the legacy
  # path successfully produces a squash commit, behind the
  # `:merge_queue_squash_commit_experiment` flag. Mismatches surface in the
  # Scientist dashboard under the experiment name
  # `merge_queue_squash_from_merge_commit` so we can validate equivalence
  # before flipping the rollout flag of the same name.
  class VerifySquashCommitJob < ApplicationJob
    include Scientist
    include GitHub::Memoizer

    EXPERIMENT_NAME = "merge_queue_squash_from_merge_commit"

    queue_as :merge_queue_squash_verification

    retry_on_dirty_exit
    discard_on(ActiveRecord::RecordNotFound)
    retry_on(SpokesAPI::ResourceExhausted, wait: :polynomially_longer)

    resolve_tenant_context do |repository_id:, **|
      repository = Repository.find_by(id: repository_id)
      Business.find_by(id: repository.tenant_id) if repository
    end

    sig do
      params(
        repository_id: Integer,
        pull_request_id: Integer,
        merge_queue_entry_id: Integer,
        merge_commit_oid: String,
        squash_commit_oid: String,
        base_sha: String,
        head_sha: String,
        timestamp_iso8601: String,
        sign: T::Boolean,
      ).void
    end
    def perform(repository_id:, pull_request_id:, merge_queue_entry_id:, merge_commit_oid:, squash_commit_oid:, base_sha:, head_sha:, timestamp_iso8601:, sign:)
      logger.append({
        namespace: self.class.name,
        function: "perform",
      }, prefix: "code")

      logger.append({
        repository_id:,
        id: pull_request_id,
        merge_queue_entry_id:,
        merge_commit_oid:,
        squash_commit_oid:,
        base_sha:,
        head_sha:,
        sign:,
      }, prefix: "gh.pull_request")

      control_tree_oid = T.let(nil, T.nilable(String))
      candidate_tree_oid = T.let(nil, T.nilable(String))

      repository = Repositories::Public.get_active_or_deleted!(repository_id)
      pull_request = PullRequest.find(pull_request_id)
      logger.append_repository_context(repository)
      logger.append_pull_request_context(pull_request)

      if repository.feature_flag_enabled?(:merge_queue_squash_commit_experiment_shut_off, default: false)
        logger.append_outcome("experiment_shut_off")
        return
      end

      unless repository.feature_flag_enabled?(:merge_queue_squash_commit_experiment, default: false)
        logger.append_outcome("skipped_flag_disabled")
        return
      end

      merge_commit = begin
        repository.commits.find(merge_commit_oid)
      rescue GitRPC::ObjectMissing
        nil
      end
      unless merge_commit
        GitHub.dogstats.increment("merge_queue.squash_verify.skipped", tags: ["reason:missing_merge_commit"])
        logger.append_outcome("skipped_missing_merge_commit")
        return
      end

      timestamp = Time.iso8601(timestamp_iso8601)
      author = pull_request.user || User.ghost
      title = pull_request.default_squash_commit_title
      message = pull_request.default_squash_commit_message(author:)
      author_email = author.default_author_email(repository, pull_request.head_sha) || author.git_author_email
      merge_commit_tree_oid = merge_commit.tree_oid

      PullRequests::Observability::Git.tag(repository:, feature: :merge_queue_squash_verify) do
        science EXPERIMENT_NAME do |e|
          e.context(
            repository_id: repository.id,
            pull_request_id: pull_request.id,
            merge_queue_entry_id:,
            base_sha:,
            head_sha:,
            merge_commit_oid:,
          )

          # Compare on *tree* OIDs rather than commit OIDs. Commit OIDs include
          # committer time and signature bytes which can legitimately diverge
          # between the two paths even when the produced content is identical.
          e.use do
            control_tree_oid = repository.commits.find(squash_commit_oid)&.tree_oid
          end

          e.try do
            result = PullRequests::GitSystems::CreateSquashCommit.new(
              repository:,
              parent: base_sha,
              original_head_oid: head_sha,
              sign:,
              tree_oid: merge_commit_tree_oid,
              author: {
                name: author.git_author_name,
                email: author_email,
                time: timestamp.in_time_zone(author.time_zone).iso8601,
              },
              committer: {
                name: GitHub.web_committer_name,
                email: GitHub.web_committer_email,
                time: timestamp.iso8601,
              },
              message: "#{title}\n\n#{message}".chomp(""),
            ).call

            tree_oid = case result
            when PullRequests::GitSystems::Commit::Created
              repository.commits.find(result.sha)&.tree_oid
            when PullRequests::GitSystems::Commit::Failed
              raise "CreateSquashCommit failed: #{result.code}"
            when PullRequests::GitSystems::Commit::Error
              raise result.exception
            else
              T.absurd(result)
            end
            candidate_tree_oid = tree_oid
          end

          # Tolerate identical-class errors from both paths; only flag the
          # mismatch when one raises and the other doesn't, or they raise
          # different classes.
          e.compare_errors { |control, candidate| control.class == candidate.class }
        end
      end

      logger.append({ control_tree_oid:, candidate_tree_oid: })

      if control_tree_oid && candidate_tree_oid && control_tree_oid != candidate_tree_oid
        begin
          diff = repository.rpc.read_tree_diff(control_tree_oid, candidate_tree_oid, diff_trees: true)

          logger.append({
            diff_entries_count: diff.size,
            diff_statuses: diff.map { _1["status"] }.tally.to_json,
            diff_paths: diff.first(10).map { _1.dig("new_file", "path") || _1.dig("old_file", "path") }.join(","),
          })
        rescue => exception
          case error = PullRequests::GitSystems.classify_exception(exception, repository:)
          when nil
            # capture generic exception information, but ignore it
            logger.append({
              exception_class: exception.class.to_s,
              exception_message: exception.message,
            }, prefix: "gh.pull_request.diff_error")
          else
            # append it to the logs
            logger.append({
              error_class: error.class.to_s,
              **error.serialize,
            }, prefix: "gh.pull_request.diff_error")
          end
        end

        logger.append_outcome("mismatch")
      elsif control_tree_oid && control_tree_oid == candidate_tree_oid
        logger.append_outcome("match")
      else
        logger.append_outcome("missing_tree_oid")
      end
    rescue => exception
      logger.append_exception(exception)
      case error = PullRequests::GitSystems.classify_exception(exception)
      when nil
        # unclassified; no additional tagging
      else
        logger.append({ git_systems_error_class: error.class.name.to_s.demodulize.underscore })
      end
      logger.append_outcome("error")
      raise
    ensure
      logger.flush
    end

    private

    sig { returns(PullRequests::Shared::Logger) }
    memoize def logger
      PullRequests::Shared::Logger.new(
        default_prefix: "gh.pull_requests.merge_queue_squash_verify",
        feature: "merge_queue_squash_verify",
      )
    end
  end
end
