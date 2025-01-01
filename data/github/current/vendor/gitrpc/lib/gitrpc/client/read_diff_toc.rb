# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

require "gitrpc/diff"
require "gitrpc/diff/delta"

module GitRPC
  class Client
    DIFF_TOC_TIMEOUT = 8
    COMMIT_OID_MATCHER = %r{
      (?<commit_oid>#{GitRPC::Util::FULL_OID_REGEXP})\x00
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

    alias native_read_diff_toc_with_base native_read_diff_toc
  end
end
