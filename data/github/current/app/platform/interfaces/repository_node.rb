# typed: strict
# frozen_string_literal: true

module Platform
  module Interfaces
    module RepositoryNode
      include Platform::Interfaces::Base
      description "Represents a object that belongs to a repository."

      field :repository, Objects::Repository, method: :async_repository, description: "The repository associated with this node.", null: false
    end
  end
end
