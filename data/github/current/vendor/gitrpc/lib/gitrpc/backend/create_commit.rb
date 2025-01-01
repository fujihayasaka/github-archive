# frozen_string_literal: true
# typed: true

module GitRPC
  class Backend

    # Internal: Construct a commit object from the given options.
    #
    # opts      - Hash of options configuring the content of the commit.
    # to_string - Boolean indicating what to do with the created commit content.
    #             If true, the formatting commit object content is returned
    #             without, and the commit is not written to the repository. If
    #             false, the commit is written to the repository and the object
    #             ID of the commit is returned.
    # prettify  - Boolean indicating whether to prettify the commit message. If
    #             true (default), clean up the provided message with
    #             '--cleanup=whitespace' (passed to 'git commit-tree'). If
    #             false, use the provided message verbatim by specifying
    #             '--cleanup=verbatim'.
    #
    # The structure of the 'opts' hash is expected to be:
    #
    # {
    #   :tree => String,
    #   :parents => [String],
    #   :message => String,
    #   :author => {
    #     :name => String,
    #     :email => String,
    #     :time => Time,
    #   },
    #   :committer => {
    #     :name => String,
    #     :email => String,
    #     :time => Time,
    #   },
    # }
    #
    # Where the "tree" is a valid tree object name (like a tree OID or
    # "<tree-ish>^{tree}") and "parents" are valid commit name (like a commit
    # OID or "<commit-ish>^{commit}"). The given object names are _not_ peeled
    # by 'commit-tree', so they must refer directly to the appropriate object
    # type.
    #
    # Returns the String content specified by 'to_string' (object ID if 'false',
    # commit object content if 'true').
    def create_commit(opts, to_string = false, prettify: true)
      raise TypeError, "invalid message string" unless opts[:message].is_a?(String)
      parent_args = opts[:parents].compact.map { |commit| ["-p", commit.is_a?(String) ? commit : commit.oid] }.flatten
      string_args = to_string ? ["--print-object-contents"] : []
      res = checked_spawn_git!(
        "commit-tree",
        [
          *parent_args,
          *string_args,
          "--cleanup=#{prettify ? "whitespace" : "verbatim"}",
          opts[:tree],
        ],
        opts[:message],
        {
          "GIT_AUTHOR_NAME"     => opts[:author][:name],
          "GIT_AUTHOR_EMAIL"    => opts[:author][:email],
          "GIT_AUTHOR_DATE"     => clamp_git_time(opts[:author][:time]).iso8601,
          "GIT_COMMITTER_NAME"  => opts[:committer][:name],
          "GIT_COMMITTER_EMAIL" => opts[:committer][:email],
          "GIT_COMMITTER_DATE"  => clamp_git_time(opts[:committer][:time]).iso8601,
        }
      )
      to_string ? res["out"] : res["out"].rstrip
    end

    # Internal: Like 'create_commit', but signs the commit before writing it to
    # the repository.
    #
    # opts      - Hash of options configuring the content of the commit (see
    #             'create_commit').
    # signature - String containing the GPG signature to use for signing the
    #             commit.
    # prettify  - Boolean indicating whether to prettify the commit message. If
    #             true (default), clean up the provided message with
    #             '--cleanup=whitespace' (passed to 'git commit-tree'). If
    #             false, use the provided message verbatim by specifying
    #             '--cleanup=verbatim'.
    #
    # Returns the object ID of the created commit.
    def create_commit_with_signature(opts, signature, prettify: true)
      raise TypeError, "invalid message string" if !opts[:message].is_a?(String)
      parent_args = opts[:parents].compact.map { |commit| ["-p", commit.is_a?(String) ? commit : commit.oid] }.flatten
      res = checked_spawn_git!(
        "commit-tree",
        [
          *parent_args,
          "-S",
          "--cleanup=#{prettify ? "whitespace" : "verbatim"}",
          opts[:tree],
        ],
        opts[:message],
        {
          "GIT_AUTHOR_NAME"     => opts[:author][:name],
          "GIT_AUTHOR_EMAIL"    => opts[:author][:email],
          "GIT_AUTHOR_DATE"     => opts[:author][:time].iso8601,
          "GIT_COMMITTER_NAME"  => opts[:committer][:name],
          "GIT_COMMITTER_EMAIL" => opts[:committer][:email],
          "GIT_COMMITTER_DATE"  => opts[:committer][:time].iso8601,
          "GPG_SIGNATURE"       => signature,
        },
        nil,
        nil,
        [
          "-c",
          "gpg.program=git-fake-signature",
        ],
      )
      res["out"].rstrip
    end

    # Internal: Rather than using 'git commit-tree' to create a commit object,
    # insert the signature directly into the raw commit content and write the
    # manually-updated object to the object database. The commit's format, as
    # well as the existence & type of its referenced objects (tree, parents) are
    # validated before being written to the object database.
    #
    # Based on git_commit_create_with_signature() in libgit2.
    #
    # base_data - String containing the raw commit content.
    # signature - String containing the GPG signature to use for signing the commit.
    #
    # Returns the object ID of the created commit.
    def create_commit_with_signature_raw(base_data, signature)
      signed_base_data = if signature.nil?
        base_data
      else
        # Determine where to insert the signature
        header_end = base_data.index("\n\n")
        raise GitRPC::Error, "invalid commit data" unless header_end

        # Format the signature (format continuations properly)
        formatted_signature = "gpgsig " + signature.gsub("\n", "\n ") + "\n"

        # Create the new commit contents
        base_data[0..header_end] + formatted_signature + base_data[(header_end + 1)..-1]
      end

      res = spawn_git("hash-object", ["-t", "commit", "--strict", "-w", "--stdin"], signed_base_data)
      if res["ok"]
        res["out"].rstrip
      elsif res["err"] =~ /([0-9a-f]+) is not a valid object/
        raise GitRPC::ObjectMissing.new("no such object: #{$1}")
      elsif res["err"] =~ /([0-9a-f]+) is not a valid '(commit|tree)' object/
        raise GitRPC::InvalidObject.new("invalid #{$2} oid #{$1}")
      else
        raise GitRPC::Failure.new(GitRPC::CommandFailed.new(res))
      end
    end
  end
end
