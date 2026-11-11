# typed: strict
# frozen_string_literal: true

module Repositories
  class RepositoryAffiliation < T::Enum
    enums do
      Owned = new(:owned)
      Direct = new(:direct)
      Indirect = new(:indirect)
    end
  end
end
