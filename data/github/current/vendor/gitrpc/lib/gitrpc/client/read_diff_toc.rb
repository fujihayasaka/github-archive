# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

require "gitrpc/diff"
require "gitrpc/diff/delta"

module GitRPC
  class Client
    DIFF_TOC_TIMEOUT = 8
    COMMIT_OID_MATCHER = %r{
      (?<commit_oid>[a-zA-Z0-9]{40})\x00
    }x
    TREE_MATCHER = %r{ (?<diff_entries>(#{GitRPC::Diff::DiffTreeParser::RAW_MATCHER})+)}x

    def diff_toc_cache_key(commit1, commit2, base_sha, max = nil)
      content_cache_key(commit1, commit2, base_sha, "native_read_diff_toc", max, "v6")
    end

    def native_read_diff_toc(commit1_oid, commit2_oid = nil, base_commit_oid = nil, options = {})
      ensure_valid_full_oid(commit1_oid) if commit1_oid
      ensure_valid_full_oid(commit2_oid) if commit2_oid
      ensure_valid_full_oid(base_commit_oid) if base_commit_oid

      options["timeout"] ||= DIFF_TOC_TIMEOUT
      raise GitRPC::Timeout if options["timeout"] <= 0

      max = options.delete("max")

      cache_key = diff_toc_cache_key(commit1_oid, commit2_oid, base_commit_oid, max)

      val = cache_get(cache_key, backend_method: :native_read_diff_toc_with_base)

      if val.is_a?(GitRPC::Timeout)
        raise GitRPC::Timeout
      end

      if val.nil?
        begin
          val = send_message(:native_read_diff_toc_with_base, commit1_oid, commit2_oid, base_commit_oid, options)
        rescue GitRPC::Timeout => boom
          val = boom
        end

        if val.is_a?(GitRPC::Timeout)
          # Cache the fact that we hit a timeout for 5 minutes so we can try
          # again later.
          #
          # We need to create a copy of `val` to get rid of any methods
          # defined on its singleton class.
          cache.set(cache_key, val.dup, 300)
          raise val
        else
          # Otherwise cache the toc indefinitely as it's immutable.
          cache.set(cache_key, val)
        end
      end

      # don't cache the full objects as properties such as `frozen` can be lost.
      GitRPC::Diff::DiffTreeParser.new(val).parse_deltas
    end

    # Public: List the Diff tree information for a list of commits
    #
    # commits - an array of commit SHA-1 strings
    #
    # Returns a hash of commit hash string to list of GitRPC::Diff::Delta objects
    # diff tree result format specified in https://git-scm.com/docs/git-diff-tree#_raw_output_format
    # i.e.
    # {
    #   "commit_1" => [
    #      ":100644 100644 591a8e9a16fb1492f008fefed9cef6488dc25410 3e6f862f36f66031a29ec9402ad5007b16838ead M another/foo.txt",
    #      ...
    #   ],
    #   "commit_2" => [
    #      ...
    #   ]
    # }
    def native_read_diff_toc_multi(commits = [], options = {})
      commits_to_read = []
      cache_keys = {}
      commit_trees = {}
      commits = Array(commits)

      options["timeout"] ||= DIFF_TOC_TIMEOUT
      raise GitRPC::Timeout if options["timeout"] <= 0

      max = options.delete("max")

      commits.each do |commit|
        ensure_valid_full_oid(commit)
        cache_keys[diff_toc_cache_key(nil, commit, nil, max)] = commit
      end

      vals = cache_get_multi(cache_keys.keys, backend_method: :native_read_diff_toc_multi)
      cache_keys.keys.each do |key|
        val = vals[key]
        if val.is_a?(GitRPC::Timeout)
          raise GitRPC::Timeout #Batch call should wait. cached exception should only last 5 minutes.
        elsif val.nil?
          commits_to_read << cache_keys[key]
        else
          commit_trees[cache_keys[key]] = GitRPC::Diff::DiffTreeParser.new(val).parse_deltas
        end
      end

      # May throw an exception for timeout or bad object state.
      batched_diff_trees = send_message(:native_read_diff_toc_multi, commits_to_read, options) unless commits_to_read.empty?

      if batched_diff_trees.is_a?(GitRPC::Timeout)
        raise GitRPC::Timeout
      end

      if !batched_diff_trees.nil?
        # need to parse the output which is coming in the shape of
        # commit id,                                   src,   dst,   src blob,                                dest blob,                               type, path
        # 6c892f2e631f7bf42fd865ba3af5daab181ae892\x00:100644 100644 9756ebdb41dad9c951f58b23e1af94eae28baf1c b3980a8253ead2f7ccd98a790d8bf95b0ab3d5de M\x00file.txt\x00"
        scanner = StringScanner.new(batched_diff_trees)

        while scanner.scan(COMMIT_OID_MATCHER)
          commit = scanner["commit_oid"]
          trees = scanner.scan(TREE_MATCHER)

          cache.set(diff_toc_cache_key(nil, commit, nil, max), trees)
          commit_trees[commit] = GitRPC::Diff::DiffTreeParser.new(trees).parse_deltas
        end
      end

      commit_trees
    end

    alias native_read_diff_toc_with_base native_read_diff_toc
  end
end
