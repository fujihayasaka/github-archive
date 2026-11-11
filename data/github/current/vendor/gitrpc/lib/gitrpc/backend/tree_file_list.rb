# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    rpc_reader :tree_file_list
    def tree_file_list(oid, list_directories, list_submodules, skip_directories, override_skipdirs_using_gitattributes = false, return_separate_lists = false)
      if override_skipdirs_using_gitattributes
        skip_directories = reject_allowlisted_skipdirs_raw(tree_oid: oid, skip_directories:)
      end

      file_list = []
      directory_list = []
      submodule_list = []

      # Walk the tree recursively using raw git commands
      # git ls-tree can handle commit/tag OIDs directly and will resolve them to trees
      walk_tree_recursive(oid, skip_directories, list_directories, list_submodules, return_separate_lists, file_list, directory_list, submodule_list)

      if return_separate_lists
        { files: file_list, directories: directory_list, submodules: submodule_list }
      else
        file_list
      end
    rescue => boom
      if boom.message.include?("Not a valid object") || boom.message.include?("bad object") || boom.message.include?("missing")
        raise GitRPC::ObjectMissing.new(boom, oid)
      end
      raise
    end

    private

    # Walk a tree using a single recursive ls-tree call
    def walk_tree_recursive(tree_oid, skip_directories, list_directories, list_submodules, return_separate_lists, file_list, directory_list, submodule_list)
      # Build ls-tree arguments
      # -z: use NUL as line terminator to handle paths with special characters
      # -r: recurse into subtrees
      # -t: show tree entries even when going to recurse into them
      #
      # Use #{tree_oid}^{tree} to explicitly dereference the object as a tree.
      # This allows distinguishing between:
      # - ObjectMissing: object does not exist ("Not a valid object name")
      # - InvalidObject: object exists but is wrong type ("expected tree type, but the object dereferences to * type")
      args = ["-z", "-r", "-t", "#{tree_oid}^{tree}"]

      # Four patterns per directory to fully exclude directories and their contents:
      # 1. Directory entry at root level (dir/ - trailing slash matches directory only)
      # 2. Files inside directory at root level (dir/**)
      # 3. Directory entry when nested (**/dir/)
      # 4. Files inside nested directories (**/dir/**)
      if skip_directories.any?
        args << "--"
        skip_directories.each do |dir|
          args << ":(exclude)#{dir}/"
          args << ":(exclude)#{dir}/**"
          args << ":(exclude)**/#{dir}/"
          args << ":(exclude)**/#{dir}/**"
        end
      end

      # Pass empty string for GIT_LITERAL_PATHSPECS to enable pathspec magic (:(exclude) patterns)
      res = spawn_git("ls-tree", args, nil, { "GIT_LITERAL_PATHSPECS" => "" })
      unless res["ok"]
        raise_tree_error(res["err"] || "", tree_oid)
      end

      output = res["out"]
      output = output.b

      # Split on NUL characters (output is NUL-terminated with -z)
      output.split("\0".b).each do |entry|
        # Parse git ls-tree output: <mode> SP <type> SP <object> TAB <file>
        # Example: "100644 blob abc123\tfilename"

        _mode, type, _object, full_name = parse_ls_tree_line(entry)
        next unless full_name

        case type
        when "tree"
          if return_separate_lists && list_directories
            directory_list << full_name
          else
            file_list << full_name if list_directories
          end

        when "commit"
          if list_directories && list_submodules && return_separate_lists
            submodule_list << full_name
          else
            file_list << full_name if list_directories && list_submodules
          end

        else
          # Regular file (blob)
          file_list << full_name
        end
      end
    end

    # Parse a line from git ls-tree output
    def parse_ls_tree_line(line)
      # Format: <mode> SP <type> SP <object> TAB <file>
      parts = line.split("\t".b, 2)
      return [nil, nil, nil, nil] if parts.length != 2

      meta = parts[0].split(" ".b, 3)
      return [nil, nil, nil, nil] if meta.length != 3

      mode = meta[0].force_encoding("UTF-8")
      type = meta[1].force_encoding("UTF-8")
      object = meta[2].force_encoding("UTF-8")
      # Force name to UTF-8 encoding to match Rugged's behavior.
      # Rugged returns file paths with UTF-8 encoding.
      name = parts[1].force_encoding("UTF-8")

      [mode, type, object, name]
    end

    # Raise the appropriate error based on git ls-tree stderr output.
    # When using the ^{tree} dereference syntax, we can distinguish between:
    # - ObjectMissing: object does not exist (e.g., "Not a valid object name abc123^{tree}")
    # - InvalidObject: object exists but is wrong type (e.g., "expected tree type, but the object dereferences to blob type")
    def raise_tree_error(stderr, oid)
      # Check for type mismatch error pattern:
      # "expected <type> type, but the object dereferences to <type> type"
      if stderr =~ /expected \w+ type, but the object dereferences to (\w+) type/
        actual_type = $1
        raise GitRPC::InvalidObject, "Invalid object type, expected tree but was #{actual_type}"
      else
        # Object doesn't exist or other error
        raise GitRPC::ObjectMissing.new(stderr, oid)
      end
    end

    # Alternative version of reject_allowlisted_skipdirs using raw git
    def reject_allowlisted_skipdirs_raw(tree_oid:, skip_directories:)
      glob_matching_files = skip_directories.map { |dir| random_path(dir) }
      attributes = read_attributes(tree_oid, glob_matching_files, %w(linguist-generated linguist-vendored))
      dirs_with_attrs = skip_directories.zip(attributes).to_h
      dirs_with_attrs.delete_if do |_, attrs|
        attrs.slice("linguist-generated", "linguist-vendored").values.any? { |v| false == v || "false" == v }
      end
      dirs_with_attrs.keys
    end

    # `tree_file_list` ignores a hardcoded list of directories known to
    # commonly include vendored or generated files
    # (see gh/gh Repository::GitDependency::JUNK_DIRS).
    # Some users would prefer to instead include files in those directories,
    # which we allow them to do by defining a `.gitattributes` entry which
    # recursively sets all files under these dirs as `-linguist-generated`
    # or `-linguist-vendored` (NB that the minus indicates *not*
    # generated/vendored). Specifically, the file might look like:
    #
    #   build/** -linguist-generated
    #   vendor/** -linguist-vendored
    #
    def reject_allowlisted_skipdirs(tree:, skip_directories:)
      unless tree.get_entry(".gitattributes")
        # nothing to do
        return skip_directories
      end

      glob_matching_files = skip_directories.map { |dir| random_path(dir) }
      attributes = read_attributes(tree.oid, glob_matching_files, %w(linguist-generated linguist-vendored))
      dirs_with_attrs = skip_directories.zip(attributes).to_h
      dirs_with_attrs.delete_if do |_, attrs|
        # this is interesting, rugged treats `-attribute` (false) and
        # `attribute=false` ("false") differently even though they are supposed
        # to be equivalent AFAIK 🤷
        attrs.slice("linguist-generated", "linguist-vendored").values.any? { |v| false == v || "false" == v }
      end
      dirs_with_attrs.keys
    end

    # Rugged doesn't expose the parsed gitattributes directly so to determine
    # whether the `dir/**` gitattribute is in use we generate a random path two
    # levels deep and check its gitattributes.
    def random_path(dir)
      File.join(dir, random_pathsafe_string, random_pathsafe_string)
    end

    def random_pathsafe_string(bytes: 50)
      SecureRandom.random_bytes(bytes).tr("\0", "0")
    end
  end
end
