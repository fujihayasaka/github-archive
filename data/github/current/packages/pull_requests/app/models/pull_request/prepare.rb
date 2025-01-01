# typed: true
# frozen_string_literal: true

class PullRequest
  class Prepare
    KILOBYTE = 1_024

    # Maximum time that we want to spend on preparing a rebase.
    def self.rebase_timeout
      ENV["REBASE_TIMEOUT_SECONDS"]&.to_f&.seconds ||
        (GitHub.flipper[:rebase_timeout_1sec].enabled? ? 1.second : 7.seconds)
    end

    def initialize(pull:, base_oid: pull.mergeable_base_sha, priority: :high, skip_rebase: false)
      @pull = pull
      @base_oid = base_oid
      @priority = priority
      @skip_rebase = skip_rebase
    end

    # Public: Run all operations that are required before this PR can be merged.
    #
    # This will prepare a preliminary merge commit and rebase commit. It will
    # also update the externally readable `merge` ref and the hidden rebase ref.
    #
    # A rebase will only be prepared if the merge commit creation was successful.
    #
    # Returns a 2-element array. The first element corresponds to the
    # `mergeability` flag. `true` signals the preparation was successful and the
    # PR can be merged and `false` means we encountered a merge conflict
    # or another error that prevented merge commit creation.
    # The second element is the merge commit sha, if the preparation was
    # successful, and `nil` otherwise.
    def perform(conflict_resolutions: nil)
      GitHub.dogstats.time("pullrequest.merge.prepare") do
        track_exceptions("perform") do
          merge_commit = track_exceptions("prepare_merge") do
            prepare_merge(conflict_resolutions:)
          end

          if merge_commit
            rebase_commit_oid = nil

            if @skip_rebase
              track_commit_outcome(:rebase, :skipped)
            else
              rebase_commit_oid = track_exceptions("prepare_rebase") do
                prepare_rebase(merge_commit)
              end
            end

            track_exceptions("prepare_refs") do
              prepare_refs(merge_commit.oid, rebase_commit_oid)
            end

            record_rebase_metrics(merge_commit, rebase_commit_oid)
          else
            track_commit_outcome(:rebase, :missed)
          end

          return !!merge_commit, merge_commit.try(:oid)
        end
      end
    end

    private

    attr_reader :pull, :base_oid, :priority

    sig { returns(Repository) }
    def repository
      pull.repository
    end

    def record_rebase_metrics(merge_commit, rebase_commit_oid)
      return if merge_commit.nil? || rebase_commit_oid.nil?

      rebased_commit = repository.commits.find(rebase_commit_oid)
      return if rebased_commit.nil?

      if rebased_commit.tree_oid != merge_commit.tree_oid
        GitHub.dogstats.increment("pull_request", tags: ["action:merge_prepare_rebase_unsafe"])
      end
    rescue GitRPC::Error
    end

    def prepare_refs(merge_commit_oid, rebase_commit_oid)
      GitHub.logger.with_named_tags("code.function": "batch_write_refs") do
        with_distribution_repo_size_logging("batch_write_refs") do
          repository.batch_write_refs(pull.safe_user, [
            [pull.merge_ref, nil, merge_commit_oid],
            [pull.rebase_ref, nil, rebase_commit_oid || GitHub::NULL_OID]
          ], priority: priority, no_custom_hooks: true)
        end
      end
    end

    # Prepare a merge by creating a preliminary merge commit
    def prepare_merge(conflict_resolutions: nil)
      base_commit_oid = base_oid
      head_commit_oid = pull.mergeable_head_sha
      GitHub.dogstats.time("pullrequest.merge.prepare_merge") do
        merge_commit, error, details = GitHub.dogstats.time("pull_request", tags: ["action:merge_commit_creation"]) do
          GitHub.logger.with_named_tags("code.function": "create_merge_commit") do
            with_distribution_repo_size_logging("create_merge_commit") do
              GitHub.dogstats.increment("pull_requests.create_merge_commit", tags: ["location:pull_request_prepare", "unreachable:false"])
              repository.commits.create_merge_commit(
                pull.safe_user,
                base_commit_oid,
                head_commit_oid,
                resolve_conflicts: conflict_resolutions
              )
            end
          end
        end

        if error == :merge_conflict
          track_commit_outcome(:merge, :conflict)
        elsif error || merge_commit.nil?
          track_commit_outcome(:merge, :failed)
        else
          track_commit_outcome(:merge, :success)
        end

        if details
          if error == :merge_conflict
            pull.store_conflicts(details)
            GlobalInstrumenter.instrument("pull_request.merge_conflict",
              conflicts: details,
              pull:,
              base_commit_oid:,
              head_commit_oid:,
              queued: false
            )
          end
        end

        merge_commit
      end
    end

    # Prepare a rebase for the given merge commit.
    # Returns the final oid for the sequence of commits that have been rebased, or nil if there was an issue.
    def prepare_rebase(merge_commit)
      pull.clear_rebase_conflicts

      GitHub.dogstats.time("pullrequest.merge.prepare_rebase") do
        safe_user = pull.safe_user

        committer = {
          name: safe_user.git_author_name,
          email: safe_user.git_author_email,
          time: safe_user.time_zone.now,
        }

        merge_base_sha, merge_head_sha = merge_commit.parent_oids

        timeout = false
        rebase_commit_oid =
          begin
            GitHub.logger.with_named_tags("code.function": "rebase") do
              extra_options = {
                use_tmp_objdir_mode: "migrate-on-success"
              }

              if GitHub.flipper[:tmp_objdir_experiment].enabled?(repository)
                extra_options[:use_tmp_objdir_mode] = "pack-and-migrate-on-success" if GitHub.flipper[:tmp_objdir_experiment_pack].enabled?(repository)
                with_distribution_repo_size_logging("rebase_tmp_objdir_experiment") do
                  result, dogstats = repository.rpc.rebase_tmp_objdir_experiment(merge_head_sha, merge_base_sha, committer, timeout: Prepare.rebase_timeout, **extra_options)
                  dogstats.each { |args| GitHub.dogstats.count(*args) }
                  result
                end
              else
                with_distribution_repo_size_logging("rebase") do
                  repository.rpc.rebase(merge_head_sha, merge_base_sha, committer, timeout: Prepare.rebase_timeout, **extra_options)
                end
              end
            end
          rescue GitRPC::Backend::RebaseTimeout, GitRPC::GitmonClient::AbortError, GitRPC::NetworkError, GitRPC::NoDataError
            GitHub.dogstats.increment("pull_request", tags: ["action:merge_prepare_rebase_timeout"])
            timeout = true
            nil
          rescue GitRPC::Protocol::DGit::ResponseError => e

            # Treat split timeouts--some nodes timed out, others succeeded--as
            # equivalent to a unanimous timeout, rather than propagating a
            # messy ResponseError.
            if e.errors.all? do |route, error|
              if GitHub.flipper[:treat_data_error_as_timeout].enabled?(repository)
                error.is_a?(GitRPC::Backend::RebaseTimeout) ||
                  error.is_a?(GitRPC::GitmonClient::AbortError) ||
                  error.is_a?(GitRPC::Timeout) ||
                  error.is_a?(GitRPC::NoDataError) ||
                  error.is_a?(BERTRPC::ProtocolError) ||
                  !route.voting?
              else
                error.is_a?(GitRPC::Backend::RebaseTimeout) ||
                  error.is_a?(GitRPC::GitmonClient::AbortError) ||
                  error.is_a?(GitRPC::Timeout) ||
                  error.is_a?(BERTRPC::ProtocolError) ||
                  !route.voting?
              end
            end
              GitHub.dogstats.increment("pull_request", tags: ["action:merge_prepare_rebase_timeout"])
              timeout = true
              nil
            else
              track_commit_outcome(:rebase, :failure)
              raise
            end
          end

        if !rebase_commit_oid && !timeout
          pull.store_rebase_conflicts
        end

        if rebase_commit_oid
          track_commit_outcome(:rebase, :success)
        elsif timeout
          track_commit_outcome(:rebase, :timeout)
        else
          track_commit_outcome(:rebase, :conflict)
        end

        rebase_commit_oid
      end
    end

    def track_commit_outcome(type, outcome)
      GitHub.dogstats.increment("pull_request.prepare.commits.#{type}", tags: ["result:#{outcome}}"])
    end

    # Execute the block and track exceptions in Datadog.
    def track_exceptions(key)
      yield
    rescue => exception # rubocop:todo Lint/GenericRescue
      Failbot.push("gh.pull_request.prepare": key)
      raise
    ensure
      GitHub.dogstats.increment("pull_request.prepare.#{key}", tags: ["result:#{exception ? :exception : :success}}"])
    end

    def with_distribution_repo_size_logging(log_name, &block)
      return yield unless repository.feature_enabled?(:pull_request_prepare_repo_size_tags)

      GitHub.dogstats.distribution_time("pullrequest.merge.#{log_name}", tags: ["repo_size:#{repository_size_tag}"]) do
        yield
      end
    end

    def repository_size_tag
      @repository_size_tag ||= begin
        disk = repository.disk_usage.to_i * KILOBYTE
        case
        when disk >= 5.gigabyte
          "massive"
        when disk >= 1.gigabyte
          "large"
        when disk >= 1.megabyte
          "medium"
        when disk >= 1.kilobyte
          "small"
        else
          "unknown"
        end
      end
    end
  end
end
