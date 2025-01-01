# typed: strict
# frozen_string_literal: true

module Users
  module IUser

    extend T::Helpers

    include Kernel
    include GH::Auth::Actor
    include Substrate::IRepositoryOwner

    abstract!

    sig { abstract.returns(T.nilable(Integer)) }
    def id; end

    sig { abstract.returns(T.nilable(String)) }
    def login; end

    sig { abstract.returns(T.nilable(String)) }
    def name_with_display_owner; end

    sig { abstract.returns(T::Boolean) }
    def user?; end

    sig { abstract.returns(T::Boolean) }
    def organization?; end

    sig { abstract.returns(T.nilable(Time)) }
    def created_at; end
  end
end
