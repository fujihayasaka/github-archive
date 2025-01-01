
# typed: true
# frozen_string_literal: true

module Events
  # ParentAsActor is used as a proxy for any organization or repository
  # that needs to be featureflag based on its database ID.
  class ParentAsActor
    include GitHub::FlipperActor
    include GitHub::VexiActor

    # Public: Given an organization id, creates a ParentAsActor scoped to organization
    sig { params(id: T.nilable(Integer)).returns(T.nilable(ParentAsActor)) }
    def self.org_actor(id)
      new("organization-#{id}")
    end

    # Public: Given a repository_id, creates a ParentAsActor scoped to repository
    sig { params(id: T.nilable(Integer)).returns(T.nilable(ParentAsActor)) }
    def self.repo_actor(id)
      new("repository-#{id}")
    end

    sig { params(id: String).returns(ParentAsActor) }
    def self.find_by_id(id) # rubocop:disable GitHub/FindByDef
      new(id)
    end

    sig { params(index_key: String).void }
    def initialize(index_key)
      @index_key = index_key
    end

    sig { override.returns(String) }
    def vexi_id
      flipper_id
    end

    sig { returns(String) }
    def id
      @index_key
    end
  end
end
