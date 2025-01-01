# typed: strict
# frozen_string_literal: true

module Users
  module IUser
    extend T::Sig
    extend T::Helpers

    include Kernel
    include GH::Auth::Actor
    include Substrate::IRepositoryOwner
    include FeatureFlag::IFeatureTarget

    abstract!

    sig { abstract.returns(T.nilable(Integer)) }
    def id; end

    sig { abstract.returns(T.nilable(String)) }
    def login; end

    sig { abstract.returns(T::Boolean) }
    def organization?; end
  end
end
