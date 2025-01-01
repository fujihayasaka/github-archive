# typed: strict
# frozen_string_literal: true

# Controls whether we're blocking codeload raw requests for a network or repository
module RawResourceBlocking
  module Config
    extend T::Helpers

    requires_ancestor { Configurable }

    RAW_RESOURCE_BLOCKED = "git.raw_resource_blocked"

    sig { returns(T::Boolean) }
    def raw_resource_blocked?
      T.bind(self, RepositoryNetwork)

      config.enabled?(RAW_RESOURCE_BLOCKED)
    end

    sig { params(actor: User).void }
    def block_raw_resource(actor:)
      T.bind(self, RepositoryNetwork)
      config.enable(RAW_RESOURCE_BLOCKED, actor)
    end

    sig { params(actor: User).void }
    def unblock_raw_resource(actor:)
      T.bind(self, RepositoryNetwork)
      config.delete(RAW_RESOURCE_BLOCKED, actor)
    end
  end
end
