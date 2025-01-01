# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    DIFF_SUMMARY_TIMEOUT = 8
    DIFF_SUMMARY_DEFAULT_ALGORITHM = "vanilla".freeze

    def diff_summary_cached?(commit1_oid, commit2_oid, base_commit_oid, algorithm: DIFF_SUMMARY_DEFAULT_ALGORITHM)
      key = diff_summary_cache_key(commit1_oid, commit2_oid, base_commit_oid, algorithm)
      cache.exist?(key)
    end

    def read_diff_summary(commit1_oid, commit2_oid, base_commit_oid, timeout: DIFF_SUMMARY_TIMEOUT, algorithm: DIFF_SUMMARY_DEFAULT_ALGORITHM)
      ensure_valid_full_oid(commit1_oid) if commit1_oid
      ensure_valid_full_oid(commit2_oid)

      GitRPC::Diff.ensure_valid_algorithm(algorithm)

      timeout ||= DIFF_SUMMARY_TIMEOUT
      return GitRPC::Diff::Summary.unavailable(reason: "timeout", error: nil) if timeout <= 0

      timeout_key = diff_summary_timeout_cache_key(commit1_oid, commit2_oid, base_commit_oid, algorithm)
      previous_timeout = cache.get(timeout_key)

      if previous_timeout && timeout <= previous_timeout
        return GitRPC::Diff::Summary.unavailable(reason: "timeout", error: nil)
      end

      begin
        key = diff_summary_cache_key(commit1_oid, commit2_oid, base_commit_oid, algorithm)
        output = cache_fetch(key, backend_method: :read_diff_summary_with_base) do
          options = { "algorithm" => algorithm, "timeout" => timeout }
          send_message(:read_diff_summary_with_base, commit1_oid, commit2_oid, base_commit_oid, options)
        end

        # don't cache the full objects as properties such as `frozen` can be lost.
        GitRPC::Diff::Summary.parse(output)
      rescue GitRPC::CommandBusy => boom
        GitRPC::Diff::Summary.unavailable(reason: "too busy", error: boom)
      rescue GitRPC::ObjectMissing => boom
        GitRPC::Diff::Summary.unavailable(reason: "missing commits", error: boom)
      rescue GitRPC::InvalidRepository => boom
        GitRPC::Diff::Summary.unavailable(reason: "corrupt", error: boom)
      rescue GitRPC::Timeout => boom
        cache.set(timeout_key, timeout)
        GitRPC::Diff::Summary.unavailable(reason: "timeout", error: boom)
      rescue GitRPC::Error => boom
        GitRPC::Diff::Summary.unavailable(reason: "corrupt", error: boom)
      end
    end

    private

    def diff_summary_cache_key(commit1_oid, commit2_oid, base_commit_oid, algorithm)
      content_cache_key("diff_summary", commit1_oid, commit2_oid, base_commit_oid, algorithm, "v4")
    end

    def diff_summary_timeout_cache_key(commit_oid1, commit2_oid, base_commit_oid, algorithm)
      content_cache_key("diff_summary", commit_oid1, commit2_oid, base_commit_oid, algorithm, "v4", "timed_out")
    end
  end
end
