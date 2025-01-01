# typed: strict
# frozen_string_literal: true

module RuleEngine
  class RepositoryEvent < RuleEvent
    extend T::Helpers

    abstract!

    sig { returns(Repository) }
    attr_reader :repository

    sig { params(repository: Repository, actor: Types::Actor).void }
    def initialize(repository, actor)
      super(actor)
      @repository = repository
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def evaluation_log_data
      {
        "gh.repo.id" => repository.id,
        "gh.org.id" => repository.owner&.id,
      }
    end
  end
end
