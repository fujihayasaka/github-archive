# typed: true
# frozen_string_literal: true

module GitRepository
  class LegacyArchiveCommand < ArchiveCommand
    def codeload_type
      "legacy.#{@type}"
    end

    def filename
      @filename ||= "%s-%s-%s.%s" % [@git_repo.owner.display_login, @git_repo, tag, @type]
    end

    def prefix
      oid = @git_repo.public? ? commitish_oid[0, 7] : commitish_oid
      @prefix ||= "%s-%s-%s" % [@git_repo.owner.display_login, @git_repo, oid]
    end

    def tag
      @tag ||= begin
        s = recent_tag_name || fallback_tag_name
        s = s.gsub /[^a-z0-9\-\_\.]/i, "-"
        s = s.gsub /-{2,}/, "-"
        s
      end
    end

    # Uses `git describe` to get a file name for the given commit.  Works for
    # branches or tags.
    #
    # Returns a String result from `git describe` or nil.
    def recent_tag_name
      len = @git_repo.public? ? 7 : 40
      begin
        @git_repo.rpc.describe(@commitish, len)
      rescue GitRPC::ObjectMissing, GitRPC::Timeout
        nil
      end
    end

    # Implements some approximation of whatever Grit used to do to deref
    # a tag. This logic makes no sense to me, but it needs to match the original
    # behavior or the checksums of the archive will change.
    #
    # Returns a String Commit oid.
    def legacy_tag_deref(commitish)
      oid = begin
              @git_repo.rpc.rev_parse(@commitish)
            rescue GitRPC::BadRepositoryState, GitRPC::Failure
              # just 404 if the revision string is bad (Rugged::InvalidError, Rugged::OSError)
              nil
            end
      return nil if oid.nil?
      obj = @git_repo.rpc.read_objects([oid]).first
      if obj["target_type"] == "tag"
        obj["target_oid"]
      else
        obj["oid"]
      end
    end

    # Public: Gets the oid resolved from the commitish.  This is usually a Commit,
    # but could be an annotated Tag.
    #
    # Returns a String oid.
    def commitish_oid
      @commitish_oid ||= (legacy_tag_deref(@commitish) || commit_oid).to_s
    end

    # Creates a unique name for the given commitish value by combining it with
    # the sha that it references.
    #
    # Returns a String like "#{commitish}-#{sha}"
    def fallback_tag_name
      len = @git_repo.public? ? 7 : 40
      "#{@commitish}-#{commit_oid[0...len]}"
    end
  end
end
