# typed: strict
# frozen_string_literal: true

module Marketplace
  class Domain
    extend T::Sig

    include GitHub::Memoizer

    sig { params(caller_service: Symbol, domain_actor: T.nilable(GH::Auth::Actor)).void }
    def initialize(caller_service, domain_actor: nil)
      @caller_service = caller_service
      @domain_actor = domain_actor
    end

    sig { returns(RepositorySettings) }
    memoize def repository_settings
      RepositorySettings.new(caller_service, actor: domain_actor)
    end

    private

    sig { returns(Symbol) }
    attr_reader :caller_service

    sig { returns(T.nilable(GH::Auth::Actor)) }
    attr_reader :domain_actor
  end
end
