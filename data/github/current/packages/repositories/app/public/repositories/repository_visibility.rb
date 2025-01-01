# typed: strict
# frozen_string_literal: true

module Repositories
  class RepositoryVisibility < T::Enum
    enums do
      Private = new
      Public = new
      Internal = new
    end
  end
end
