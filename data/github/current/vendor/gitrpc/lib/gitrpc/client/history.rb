# rubocop:disable Style/FrozenStringLiteralComment
module GitRPC
  class Client
    # Public: Retrieve a revision list starting at the specified commit.
    # This walks commit history but does not load any tree or blob objects
    # and has good performance characteristics as a result.
    #
    # oid - 40 char oid string identifying the starting commit.
    # options - an options hash consisting of the following optional keys:
    #             "limit"  - the maximum number of commit oids to return
    #             "offset" - an offset into the commit history for which to
    #                        start returning commit oids
    #             "path"   - a pathspec to scope commit history to
    #
    # Returns an array of oid strings in topological order, starting with the
    # oid provided as input. The array has only a single element if the commit
    # has no parents.
    def list_revision_history(oid, options = {})
      #FIXME: Symbolizing keys here is to ensure all `options` coming from
      #callers are handled properly inside GitRPC. Ultimately, all `options`
      #arguments being sent into this method should be proper keyword args, at
      #which point this symbolizing can be removed.
      #However, at the time of this commit, there may still be callsites in
      #github/github sending string keyed hashes.
      options = symbolize_keys(options)

      ensure_valid_full_oid(oid)
      convert_empty_pathspec(options)

      if options.include?(:until)
        # Options like `:until` are unlikely to be usefully cached since it's
        # a timestamp and thus a low hit rate is expected. This is currently
        # the only option like this so I'm keeping it simple for now.
        send_message(:list_revision_history, oid, **options)
      else
        cache_fetch(commit_parents_key(oid, options), backend_method: :list_revision_history) do
          send_message(:list_revision_history, oid, **options)
        end
      end
    end

    # Internal: Cache key used to store the parents list in
    # memcache.
    #
    # oid     - 40 char object id string.
    # options - an options hash consisting of the following optional keys:
    #             "limit"  - the maximum number of commit oids to return
    #             "offset" - an offset into the commit history for which to
    #                        start returning commit oids
    #             "path"   - a pathspec to scope commit history to
    #
    # Returns a key suitable for use with memcache.
    def commit_parents_key(oid, options = nil)
      key = content_cache_key(oid, "parents", "v1")

      if options && options.is_a?(Hash)
        options = stringify_keys(options)

        path = options.key?("path") ? sha256(options["path"]) : nil
        limit = options.delete("limit")
        offset = options.delete("offset")
        cache_key_parts = [key, limit, offset, path, *options.values.compact]
        key = content_cache_key(*cache_key_parts)
      end

      key
    end

    # Public: Retrieve a revision count starting at the specified commit.
    #
    # commitish        - a commit oid or ref
    # use-bitmap-index - use bitmap index
    # no_merges        - don't count merges
    # max_count        - limit count to this
    # since_time       - only count commits since this time
    # path             - a pathspec to scope commit history to
    #
    # Returns a count, or nil on failure.
    def count_revision_history(commitish, options = {})
      send_message(:count_revision_history, commitish, **options)
    end

    # Public: Retrieve a revision list starting at the specified commit(s),
    # or all the refs (i.e. "git rev-list --all").
    #
    # roots              - array of oid strings, or an empty array for --all.
    # exclude            - oids to exclude
    # findobjs           - terminate walk when any of these are found
    # skip               - skip this many commits before starting
    # max                - the maximum number of commit oids to return
    # since_time         - limit to commits newer than this
    # until_time         - limit to commits older than this
    # regexp_ignore_case - case-insensitive search
    # fixed_strings      - search for fixed strings, not regexps
    # authors            - search for these authors
    # path               - a pathspec to scope commit history to
    # timeout            - max number of seconds before giving up
    #
    # Returns an array of oid strings.
    def list_revision_history_multiple(roots, options = {})
      send_message(:list_revision_history_multiple, roots, **options)
    end

    # Public: Search commit authors, committers, or messages
    #
    # choice    - Type of search. Must be 'grep' (messages), 'author', or 'committer'.
    # query     - What to search for. This is an extended regular expression string.
    # commitish - Ref name, oid, or anything that can be resolved to a commit.
    # max - maximum number of commits to return
    #
    # Returns an array of oid strings.
    def search_revision_history(choice, query, commitish, max: nil)
      send_message(:search_revision_history, choice, query, commitish, max: max)
    end
  end
end
