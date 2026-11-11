# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # This is also defined in `models/blame.rb` - we can't directly use it because
    # GitRPC doesn't necessarily have access to Rails' models.
    IGNORE_REVS_FILE_PATH = ".git-blame-ignore-revs"

    # Public: Show what revision and author last modified each line of a file
    #
    # commit_oid - a commit
    # path       - a path
    # annotate   - array of line numbers to annotate
    #
    # Returns blame output in --porcelain format, or raises GitRPC::CommandFailed.
    def blame(commit_oid, path, options = {})
      ensure_valid_full_oid(commit_oid)

      if options[:ignore_revs_file]
        options[:ignore_revs_file] = ignore_revs_file(commit_oid)
      end

      send_message(:blame, commit_oid, path, **options)
    end

    # Public: Show what revision and author last modified each line of a file
    #
    # commit_oid - a commit
    # path       - a path
    # annotate   - array of line numbers to annotate
    #
    # Returns a promise resolving to the blame output in --porcelain format,
    # or rejects with GitRPC::CommandFailed.
    def async_blame(commit_oid, path, options = {})
      begin
        ensure_valid_full_oid(commit_oid)
      rescue GitRPC::InvalidFullOid => boom
        return Promise.new.tap { |p| p.reject(boom) }
      end

      if options[:ignore_revs_file]
        options[:ignore_revs_file] = ignore_revs_file(commit_oid)
      end

      async_send_message(:blame, commit_oid, path, **options)
    end

    private

    def ignore_revs_file(commit_oid)
      begin
        tree_entry = read_tree_entry(commit_oid, IGNORE_REVS_FILE_PATH, type: "blob", limit: 1024 * 1024)
        raise GitRPC::IgnoreRevsTooBig if tree_entry["truncated"]
        raise GitRPC::SymlinkDisallowed if tree_entry["symlink_target"]
        tree_entry["content"]
      rescue GitRPC::NoSuchPath
        nil
      end
    end
  end
end
