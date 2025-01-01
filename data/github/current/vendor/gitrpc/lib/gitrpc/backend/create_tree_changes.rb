# rubocop:disable Style/FrozenStringLiteralComment
require "uri"

module GitRPC
  class Backend

    rpc_writer :create_tree_changes
    def create_tree_changes(*args)
      options = create_tree_changes_options(*args)
      create_commit(options, prettify: false)
    end

    rpc_reader :stage_signed_tree_changes
    def stage_signed_tree_changes(*args)
      options = create_tree_changes_options(*args)
      [create_commit(options, true, prettify: false), options[:tree]]
    end

    rpc_writer :persist_signed_tree_changes
    def persist_signed_tree_changes(base_data, signature, *args)
      # ensure that any blobs/trees are created on all replicas.
      create_tree_changes_options(*args)

      create_commit_with_signature_raw(base_data, signature)
    end

    rpc_writer :create_tree
    def create_tree(files, base_tree_oid = nil)
      # Check if the base tree exists and is a tree
      if base_tree_oid
        res = spawn_git("cat-file", ["-t", base_tree_oid])
        if !res["ok"]
          raise GitRPC::InvalidObject, "Invalid tree oid #{base_tree_oid}"
        elsif res["out"].chomp != "tree"
          raise GitRPC::InvalidObject, "Invalid object type, expected tree but was #{res["out"].chomp}"
        end
      end
      process_files(files, base_tree_oid)
    end

    def format_tree_entry(mode:, oid:, path:)
      "#{mode} #{oid}\t#{path}"
    end

    # Internal: Given a Hash of files that will be used to create or modify a
    # new tree, write new blobs to the repository for any files that have
    # content specified in the file data. Update the file data hashes in place
    # with the OID of the new blob.
    #
    # files - Hash of filename => file data hash pairs, some of which may
    #         specify content to write as new blobs.
    #
    # Returns nothing.
    def create_and_insert_blobs(files)
      # Deduplicate blobs by creating a mapping of blob content to the list of
      # file data hashes that specify that content.
      to_write = files.each_with_object({}) do |(_, data), files_by_content|
        if data && data["data"]
          key = data["data"]
          files_by_content[key] ||= []
          files_by_content[key] << data
        end
      end.to_a

      # Write each unique blob, get the list of OIDs for each new blob
      oids = if !to_write.empty?
        res = checked_spawn_git!("hash-object", ["-w", "--batch", "--strict"],
          to_write.map { |content, _| "blob #{content.bytesize}\n#{content}\n" }.join)
        res["out"].split("\n")
      else
        []
      end

      # Remap the OIDs back to the file data hashes
      to_write.zip(oids).each do |(_, files_by_content), oid|
        files_by_content.each { |data| data["oid"] = oid }
      end
    end

    # Internal: Given a file data entry, determine whether that file needs to be
    # looked up in the base tree. If must_exist is true, only return true if
    # the file *must* exist in the base tree and we should fail to write a new
    # tree otherwise; if must_exist is false, additionally return true if the
    # file *may* exist in the base tree and we should look it up if it does.
    #
    # data             - Hash containing file data. May be nil, which indicates
    #                    a file to be removed.
    # must_exist       - Boolean indicating whether to return 'true' only for
    #                    files that must exist in the base tree, or also for
    #                    those that we want to look up but may be missing.
    #
    # Returns a Boolean
    def want_tree_lookup?(data, must_exist: false)
      data.nil? || data["source"] || !data["oid"] || (!must_exist && !data["mode"])
    end

    # Internal: Based on the contents of the associated file hash, either wrap
    # the input err in a GitRPC::BadObjectState or return the input error
    # directly. The main purpose of this function is maintaining parity with the
    # legacy Rugged implementation of create_tree/create_tree_changes.
    #
    # data - Hash containing file data. May be nil, which indicates a file to be
    #        removed.
    # err  - Error instance that may or may not need to be wrapped in a
    #        BadObjectState.
    #
    # Returns the error to raise.
    def wrap_missing_file_error(data, err)
      data.nil? || !data["source"] ? GitRPC::BadObjectState.new("failed to write the requested tree", err) : err
    end

    # Internal: Given a Hash of files that will be used to create or modify a
    # new tree, look up files in the base tree to check for their existence
    # and/or populate the OID and mode from the looked up tree entry.
    #
    # files     - Hash of filename => file data hash pairs, some of which may
    #             specify content to write as new blobs.
    # base_tree - String object ID of the base tree in which we should look up
    #             the files. May be nil, in which case files are not looked up
    #             and an error is raised if any entry in `files` indicates that
    #             a file must exist in the base tree.
    #
    # Returns nothing.
    def populate_metadata_from_tree(files, base_tree)
      if base_tree
        # Identify files that need information from base_tree, deduplicate
        # by filename.
        to_read = files.each_with_object({}) do |(filename, data), files_by_filename|
          if want_tree_lookup?(data)
            key = data && data["source"] ? data["source"] : filename
            files_by_filename[key] ||= []
            files_by_filename[key] << data
          end
        end.to_a

        sources = if !to_read.empty?
          res = checked_spawn_git!("show-paths",
            ["-z", "--format=%(objectname) %(objectmode)" "--end-of-options", base_tree],
            to_read.map(&:first).join("\0"))
          res["out"].split("\0").map do |line|
            if line =~ /.* missing/
              nil
            else
              oid, mode = line.split(" ", 2)
              [oid, mode.to_i(8)]
            end
          end
        else
          []
        end

        to_read.zip(sources).each do |(filename, files_by_filename), source|
          files_by_filename.each do |data|
            raise wrap_missing_file_error(data, ArgumentError.new("#{filename} does not exist in tree #{base_tree}")) if source.nil? && want_tree_lookup?(data, must_exist: true)
            if data && !source.nil?
              data["oid"] ||= source[0]
              data["mode"] ||= source[1]
            end
          end
        end
      else
        files.each do |_, data|
          raise wrap_missing_file_error(data, ArgumentError.new("cannot read from nil base_tree")) if want_tree_lookup?(data, must_exist: true)
        end
      end
    end

    def process_files(files, base_tree)
      ensure_valid_full_oid(base_tree) if base_tree

      # Validate filenames & normalize data hashes
      files.update(files) do |file, data|
        raise ArgumentError, "filename contains null byte" if file.include?("\0")
        if data.nil?
          nil
        elsif data.is_a?(Hash)
          raise ArgumentError, "filename contains null byte" if data["source"] && data["source"].include?("\0")
          ensure_valid_full_oid(data["oid"]) if data["oid"]
          data
        else
          { "data" => data }
        end
      end

      create_and_insert_blobs(files)
      populate_metadata_from_tree(files, base_tree)

      entries = []
      files.sort_by(&:first).each do |file, data| # sort by filename so trees are written before the entries in them
        if data.nil?
          entries.append(format_tree_entry(mode: NULL_MODE, oid: NULL_OID, path: file))
        else
          entries.append(format_tree_entry(mode: NULL_MODE, oid: NULL_OID, path: data["source"])) if data["source"]

          mode = (data["mode"] ||= 0100644)
          oid = data["oid"] || raise(GitRPC::BadObjectState, "failed to write the requested tree")

          entries.append(format_tree_entry(mode: mode.to_s(8), oid: oid, path: file))
        end
      end

      mktree_args = ["-z", "--fsck", "--end-of-options"]
      mktree_args << base_tree if base_tree
      res = spawn_git("mktree", mktree_args, entries.join("\0"), {}, nil, nil,
                      ["-c", "fsck.gitattributesSymlink=error",
                       "-c", "fsck.largePathname=ignore"])
      if res["ok"]
        res["out"].chomp
      else
        # Parse the error
        if res["err"].include?(NOT_GIT_REPO)
          raise GitRPC::InvalidRepository, "path is not a repository: #{@path}"
        elsif res["err"] =~ /object [0-9a-f]+ is a [a-z]+ but specified type was \([a-z]+\)/
          raise GitRPC::BadObjectState, "failed to write the requested tree"
        elsif res["err"] =~ /(gitattributes|gitmodules)Symlink: .*/
          raise GitRPC::SymlinkDisallowed.new(".#{$1} is not allowed to be a symlink")
        elsif res["err"] =~ /gitmodules([A-Za-z]+): (.*)/
          msg_type, git_msg = $1, $2
          err_msg = if msg_type == "Name"
            ".gitmodules contains an invalid submodule name"
          elsif %w[Url Path].include?(msg_type)
            if git_msg =~ /disallowed submodule (?:url|path): (.*)/
              ensure_valid_submodule_url($1)
            end
            # Fall back on generic error if the more specific checks in
            # ensure_valid_submodule_url don't raise anything
            ".gitmodules contains an invalid submodule url"
          else
            git_msg
          end
          raise GitRPC::BadGitmodules.new(err_msg)
        elsif res["err"] =~ /gitattributes[A-Za-z]+: (.*)/
          raise GitRPC::BadGitattributes.new($1)
        else
          # NEEDSWORK: Git is so unhappy with .gitmodules or .gitattributes as
          # symlinks that 'git mktree' doesn't even get past the initial path
          # validation before failing. Unfortunately, the path validation error
          # doesn't make any specific mention of the issue being that the path
          # is a symlink.
          #
          # The hack here is to take an "educated guess" at whether the error
          # was due to a disallowed symlink. If the error is "invalid path" and
          # all of the following are true:
          #
          # 1. The path basename is .gitmodules or .gitattributes
          # 2. The file is in the input file list
          # 3. The mode specified for the input is 0120000
          #
          # Then we raise a SymlinkDisallowed. This doesn't catch all possible
          # bad symlink cases (for example, if the base tree has a pre-existing
          # bad .gitmodules), but those cases should be exceedingly rare *and*
          # will still raise an error, albeit the wrong class.
          if res["err"] =~ /invalid path '(.*)'/
            bad_path = $1
            if bad_path =~ /^(.*\/)?(\.gitmodules|\.gitattributes)$/ && files[bad_path] && files[bad_path]["mode"] == 0120000
              raise GitRPC::SymlinkDisallowed.new("#{bad_path} is not allowed to be a symlink")
            end
          end
          raise GitRPC::Failure.new(GitRPC::CommandFailed.new(res))
        end
      end
    rescue GitRPC::Failure => e
      raise GitRPC::BadObjectState.new("failed to write the requested tree", e)
    end

    def ensure_valid_submodule_url(value)
      # Always perform the newline check, since this isn't allowed in
      # either absolute or relative URLs.
      decoded = URI::DEFAULT_PARSER.unescape(value)
      if decoded.include?("\n")
        raise GitRPC::BadGitmodules.new(".gitmodules contains a URL with newlines")
      end

      # Split into whether we're in the relative or newline case.
      if /\A\.{1,2}[\\\/]/ =~ value
        # Check if the URL escapes past the root and has a
        # potentially-empty path component.
        #
        # Note: finding '../' in the middle of the string is not
        # required since Git's submodule relative resolver doesn't
        # bother.
        if /\A(?:\.[\\\/])*\.\.[\\\/]/ =~ value
          if /[\\\/]{2}/ =~ value
            raise GitRPC::BadGitmodules.new(".gitmodules contains potential empty hostname")
          end
          if /[\\\/]:/ =~ value
            raise GitRPC::BadGitmodules.new(".gitmodules contains potential scheme rewrite")
          end
        end
      else
        url = if /\A(?:http|ftp)s?::(.*)\z/ =~ value
          $1
        elsif /\A(?:http|ftp)s?:\/\// =~ value
          value
        else
          # Do nothing, since Git's 'skip_remote_curl_protocol_prefix()'
          # allows this URL to bypass further checks.
          nil
        end

        if url
          if url.start_with?("://")
            raise GitRPC::BadGitmodules.new(".gitmodules contains a protocol-relative URL")
          end

          begin
            uri = URI(url)
          rescue URI::Error
            raise GitRPC::BadGitmodules.new(".gitmodules contains an invalid URL")
          end

          if !uri.scheme || uri.scheme.empty?
            raise GitRPC::BadGitmodules.new(".gitmodules contains a URL without a protocol")
          end
          if !uri.host || uri.host.empty?
            raise GitRPC::BadGitmodules.new(".gitmodules contains a URL without a host")
          end
        end
      end
    end

    def create_tree_changes_options(parents, info, files = nil)
      message   = info["message"]
      committer = symbolize_keys(info["committer"])
      author    = symbolize_keys(info["author"] || committer.dup)
      tree      = info["tree"]

      parents = Array(parents)
      parent = parents.first

      [author, committer].each do |person|
        person[:time] =
          case person[:time]
          when nil
            raise ArgumentError, "Time field is required"
          when String
            iso8601(person[:time])
          when Array
            unixtime_to_time(person[:time])
          else
            raise ArgumentError, "Invalid time value: #{person[:time]}"
          end
      end

      options = {
        :message    => message,
        :committer  => committer,
        :author     => author,
        :parents    => [],
      }

      options[:parents] = parents

      reuse_tree = valid_full_oid?(tree) && object_exists?(tree, "tree")
      options[:tree] = if reuse_tree
        # `git mktree` will validate files in the tree
        process_files({}, tree)
      elsif files
        if parent
          res = checked_spawn_git!("cat-file", ["-t", parent])
          parent_type = res["out"].chomp
          raise ArgumentError, "Invalid parent, expected commit but was #{parent_type}" if parent_type != "commit"
        end
        process_files(files, parent)
      else
        raise ArgumentError, "You must specify either 'tree' in the info hash, or an array of files"
      end

      options
    end

  end
end
