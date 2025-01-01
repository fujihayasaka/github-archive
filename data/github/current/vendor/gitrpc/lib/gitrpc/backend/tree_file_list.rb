# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    rpc_reader :tree_file_list
    def tree_file_list(oid, list_directories, list_submodules, skip_directories, override_skipdirs_using_gitattributes = false, return_separate_lists = false)
      tree = case object = rugged.lookup(oid)
      when Rugged::Commit
        object.tree
      when Rugged::Tree
        object
      else
        raise(GitRPC::InvalidObject, "Invalid object type, expected tree but was #{object.type}")
      end

      if override_skipdirs_using_gitattributes
        skip_directories = reject_allowlisted_skipdirs(tree:, skip_directories:)
      end

      file_list = []
      directory_list = []
      submodule_list = []

      tree.walk(:preorder) do |root, entry|
        name = entry[:name]
        name = File.join(root, name) unless root.empty?

        case entry[:type]
        when :tree
          next false if skip_directories.include?(entry[:name])
          if return_separate_lists && list_directories
            directory_list << name
          else
            file_list << name if list_directories
          end

        when :commit
          if list_directories && list_submodules && return_separate_lists
            submodule_list << name
          else
            file_list << name if list_directories && list_submodules
          end

        else
          file_list << name
        end

        true
      end

      if return_separate_lists
        { files: file_list, directories: directory_list, submodules: submodule_list }
      else
        file_list
      end
    rescue Rugged::TreeError, Rugged::OdbError => boom
      raise GitRPC::ObjectMissing.new(boom, oid)
    end

    private

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
