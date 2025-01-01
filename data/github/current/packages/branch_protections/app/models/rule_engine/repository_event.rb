# typed: strict
# frozen_string_literal: true

module RuleEngine
  class RepositoryEvent < RuleEvent
    extend T::Sig
    extend T::Helpers

    abstract!

    sig { override.returns(Repository) }
    attr_reader :repository

    sig { params(repository: Repository, actor: Types::Actor).void }
    def initialize(repository, actor)
      super(actor)
      @repository = repository
    end

    sig { override.returns(T.nilable(Organization)) }
    def organization
      owner = repository.owner
      owner if owner.is_a?(Organization)
    end
  end
end
