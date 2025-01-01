# typed: strict
# frozen_string_literal: true

module Orgs
  module IOrganization
    extend T::Sig
    extend T::Helpers

    include Kernel
    include Substrate::IRepositoryOwner
    include FeatureFlag::IFeatureTarget

    abstract!

    sig { abstract.returns(T.nilable(Integer)) }
    def id; end

    sig { abstract.returns(T::Boolean) }
    def organization?; end

    sig { abstract.returns(T::Boolean) }
    def active?; end
  end
end
