# typed: strict
# frozen_string_literal: true

module Repositories
  class RepositoryPrivacy < T::Enum
    extend T::Sig

    enums do
      Private = new
      Public = new
    end

    sig { returns(T::Boolean) }
    def to_bool
      serialize == "public" ? true : false
    end
  end
end
