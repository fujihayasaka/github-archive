# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: perform a backup with the new 'gitbackups' mechanism.
    #
    # wiki - whether we want to backup this repository's wiki rather than the
    # repository itself.
    # parent - the parent repository ID, if any
    #
    # Returns the command's information.
    def gitbackups_perform(wiki, parent = nil)
      send_message(:gitbackups_perform, wiki, parent)
    end

    # Public: restore a repository via 'gitbackups'
    #
    # spec - specification for what to restore, e.g. 123/123.git, 123/123.wiki.git or gist/abcdefg.git
    # target - the directory in which to create the repository
    #
    # Returns the command's result
    def gitbackups_restore(spec, target)
      send_message(:gitbackups_restore, spec, target)
    end
  end
end
