# typed: strict
# frozen_string_literal: true

module Authz
  module IUserRole
    extend T::Helpers

    abstract!

    sig { abstract.returns(T.nilable(Integer)) }
    def id; end
  end
end
