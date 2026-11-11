# typed: strict
# frozen_string_literal: true

module Repositories
  class RepositoryType < T::Enum
    enums do
      Public = new("public")
      Private = new("private")
      Source = new("source")
      Fork = new("fork")
      Mirror = new("mirror")
      Template = new("template")
      Archived = new("archived")
      Sponsorable = new("sponsorable")
    end
  end
end
