# typed: strict
# frozen_string_literal: true

module Admin
  module IBusiness
    extend T::Sig
    extend T::Helpers

    include Kernel

    abstract!

    sig { abstract.returns(T.nilable(Integer)) }
    def id; end
  end
end
