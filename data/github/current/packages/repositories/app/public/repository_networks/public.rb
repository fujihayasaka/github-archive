# typed: strict
# frozen_string_literal: true

module RepositoryNetworks
  module Public
    extend self

    include Kernel

    sig { params(id: T.nilable(Integer)).returns(T.nilable(::Business)) }
    def resolve_tenant(id:)
      ::RepositoryNetwork.find_by(id: id)&.resolve_tenant
    end

    extend GitHub::DomainIsolation::PackageBoundary
  end
end
