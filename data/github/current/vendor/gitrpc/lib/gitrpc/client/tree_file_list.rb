# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: return a list of all the filenames inside a given tree and all its
    # subtrees. The result includes the full path to all the entries in the tree.
    #
    # oid - sha1 of the tree or commit to enumerate
    # list_directories - if false, actual directory paths will not be returned
    # in the filename list, but the files under the directories will
    # list_submodules - if false, submodule paths will not be returned in the
    # filename list
    # skip_directories - array of directory names that should not be descended into
    # when enumerating
    # return_separate_lists - if true, return file and directory lists separately: {files: [], directories: [], submodules: []}
    #
    # Returns an array of String
    def tree_file_list(oid, list_directories: false, list_submodules: false, skip_directories: [], override_skipdirs_using_gitattributes: false, return_separate_lists: false)
      ensure_valid_full_oid(oid)

      hash_key = tree_file_list_key(
        oid,
        list_directories,
        list_submodules,
        skip_directories,
        override_skipdirs_using_gitattributes,
        return_separate_lists
      )

      cache_fetch(hash_key, backend_method: :tree_file_list) do
        if return_separate_lists
          send_message(:tree_file_list, oid, list_directories, list_submodules, skip_directories, override_skipdirs_using_gitattributes, true)
        elsif override_skipdirs_using_gitattributes
          send_message(:tree_file_list, oid, list_directories, list_submodules, skip_directories, true)
        else # preserve legacy arity for deploy safety
          send_message(:tree_file_list, oid, list_directories, list_submodules, skip_directories)
        end
      end
    end

    protected
    def tree_file_list_key(oid, list_d, list_s, skip, override, separate_lists)
      list_d = list_d.to_s
      list_s = list_s.to_s
      override = override.to_s
      separate_lists = separate_lists.to_s
      skip = sha256(skip)

      content_cache_key("tree_file_list", oid, list_d, list_s, skip, override, separate_lists)
    end
  end
end
