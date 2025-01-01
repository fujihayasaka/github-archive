# typed: true
# frozen_string_literal: true

module Conduit
  class RepositoryMembership
    extend T::Sig

    attr_reader :repository, :member

    delegate :id, to: :member

    sig { params(repository: Repository, member: User).void }
    def initialize(repository:, member:)
      @repository = repository
      @member = member
    end

    sig { returns(User) }
    def target_for_conditional_access
      @repository.target_for_conditional_access
    end
  end
end
