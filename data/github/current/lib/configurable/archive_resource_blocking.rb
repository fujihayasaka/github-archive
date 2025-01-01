# typed: strict
# frozen_string_literal: true

# Controls whether we're blocking access to the archives for a network or repository
module Configurable
  module ArchiveResourceBlocking
    extend T::Helpers
    requires_ancestor { Configurable }

    ARCHIVE_RESOURCE_BLOCKED = "git.archive_resource_blocked"

    sig { returns(T::Boolean) }
    def archive_resource_blocked?
      T.bind(self, T.any(Repository, Gist, RepositoryNetwork))

      config.enabled?(ARCHIVE_RESOURCE_BLOCKED)
    end

    sig { params(actor: User).void }
    def block_archive_resource(actor:)
      T.bind(self, T.any(Repository, Gist, RepositoryNetwork))
      config.enable(ARCHIVE_RESOURCE_BLOCKED, actor)
    end

    sig { params(actor: User).void }
    def unblock_archive_resource(actor:)
      T.bind(self, T.any(Repository, Gist, RepositoryNetwork))
      config.delete(ARCHIVE_RESOURCE_BLOCKED, actor)
    end
  end
end
